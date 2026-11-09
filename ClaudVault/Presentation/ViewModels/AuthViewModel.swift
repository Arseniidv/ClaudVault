
import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import GoogleSignIn
import FirebaseAuth

@MainActor
final class AuthViewModel: ObservableObject {
    private let signInUseCase: SignInUseCase
    private let signUpUseCase: SignUpUseCase
    private let signOutUseCase: SignOutUseCase
    private let resetPasswordUseCase: ResetPasswordUseCase
    private let getCurrentUserUseCase: GetCurrentUserUseCase
    private let authRepository: AuthRepository
    private let otpService: OTPService
    private let passwordResetService: PasswordResetService
    /// Координирует изоляцию данных при смене пользователя.
    /// nil в тестах/превью — тогда контекст не переключается.
    private let sessionCoordinator: UserSessionCoordinator?

    // MARK: - Published Properties
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    /// Показывать ли ввод OTP-кода (после отправки письма).
    @Published var isOTPEntryPresented = false
    /// Код сброса пароля отправлен — ResetPasswordView показывает шаг 2.
    @Published var isResetCodeSent = false
    // MARK: - Auth State
    private var authStateTask: Task<Void, Never>?
    // MARK: - Initializer
    init(
        signInUseCase: SignInUseCase,
        signUpUseCase: SignUpUseCase,
        signOutUseCase: SignOutUseCase,
        resetPasswordUseCase: ResetPasswordUseCase,
        getCurrentUserUseCase: GetCurrentUserUseCase,
        authRepository: AuthRepository,
        otpService: OTPService,
        passwordResetService: PasswordResetService,
        sessionCoordinator: UserSessionCoordinator? = nil
    ) {
        self.signInUseCase = signInUseCase
        self.signUpUseCase = signUpUseCase
        self.signOutUseCase = signOutUseCase
        self.resetPasswordUseCase = resetPasswordUseCase
        self.getCurrentUserUseCase = getCurrentUserUseCase
        self.authRepository = authRepository
        self.otpService = otpService
        self.passwordResetService = passwordResetService
        self.sessionCoordinator = sessionCoordinator
    }
    // MARK: - Observe Authentication
    func observeAuthState() {
        guard authStateTask == nil else { return }
        // Последний обработанный владелец данных — для детекции
        // реальной смены пользователя, а не каждого emission
        // (обновления профиля приходят с тем же id).
        var lastOwnerID: String? = nil
        authStateTask = Task {
            for await user in getCurrentUserUseCase.observeAuthState() {
                let newOwnerID = user?.id.uuidString
                if newOwnerID != lastOwnerID {
                    await sessionCoordinator?.handleUserChange(
                        from: lastOwnerID,
                        to: newOwnerID
                    )
                    lastOwnerID = newOwnerID
                }
                self.currentUser = user
                if user == nil {
                    // Сессия завершена — стираем снимок из App Group,
                    // чтобы виджет не показывал чужие email/usage.
                    WidgetDataPublisher.publish(accounts: [])
                }
            }
        }
    }
    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        guard validateEmail(email), !password.isEmpty else {
            errorMessage = "Введите корректный email и пароль."
            return
        }
        await performAuthAction {
            let user = try await signInUseCase.execute(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            currentUser = user
            successMessage = nil
        }
        
    }
    @MainActor
    func signInWithGoogle() async {
        // Повторный вызов во время активного входа запрещён:
        // параллельный GIDSignIn-флоу перезапишет continuation
        // и «съест» результат, оставив вечный спиннер.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        defer {
            isLoading = false
        }

        do {
            let result: GIDSignInResult
            #if os(iOS)
            guard let presentingViewController = UIApplication.shared
                .connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?
                .rootViewController else {
                throw NSError(
                    domain: "GoogleSignIn",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось открыть окно авторизации"
                    ]
                )
            }
            result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController
            )
            #elseif os(macOS)
            // presentingWindow — якорь ASWebAuthenticationSession.
            // Предпочитаем видимое окно: `NSApp.windows.first`
            // может вернуть скрытую панель, и тогда сессия
            // не сможет корректно завершиться.
            guard let presentingWindow = NSApp.keyWindow
                ?? NSApp.windows.first(where: { $0.isVisible })
                ?? NSApp.windows.first else {
                throw NSError(
                    domain: "GoogleSignIn",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось открыть окно авторизации"
                    ]
                )
            }
            result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingWindow
            )
            #endif

            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(
                    domain: "GoogleSignIn",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось получить Google ID Token"
                    ]
                )
            }
            let accessToken = result.user.accessToken.tokenString

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )
            _ = try await Auth.auth().signIn(
                with: credential
            )
            successMessage = "Вы успешно вошли через Google"
        } catch {
            // GIDSignIn-сессия — лишь источник credential'ов для
            // Firebase. Если вход в Firebase не состоялся,
            // оставлять «авторизованную» Google-сессию нельзя:
            // она противоречила бы состоянию Firebase Auth
            // (вход успешен в Google, но нет пользователя
            // CloudVault). CloudVault-сессии Google Drive
            // хранятся отдельно (GoogleSessionStore/Keychain)
            // и от этого не страдают.
            GIDSignIn.sharedInstance.signOut()
            errorMessage = Self.mapGoogleSignInError(error)
        }
    }

    /// Человекочитаемые сообщения для ошибок GIDSignIn вместо
    /// сырых `com.google.GIDSignIn error -N`.
    private static func mapGoogleSignInError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == kGIDSignInErrorDomain else {
            return error.localizedDescription
        }
        switch nsError.code {
        case GIDSignInError.canceled.rawValue:
            return "Вход через Google отменён."
        case GIDSignInError.keychain.rawValue:
            return "Не удалось сохранить сессию Google (Keychain)."
        case GIDSignInError.hasNoAuthInKeychain.rawValue:
            return "Сессия Google не найдена. Войдите заново."
        case GIDSignInError.refreshTokenExpired.rawValue:
            return "Сессия Google истекла. Войдите заново."
        case GIDSignInError.scopesAlreadyGranted.rawValue:
            return "Запрошенные доступы уже выданы."
        default:
            return error.localizedDescription
        }
    }
    func signUp(
        name: String,
        email: String,
        password: String,
        confirmPassword: String
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Введите ваше имя."
            return
        }
        guard validateEmail(trimmedEmail) else {
            errorMessage = "Введите корректный email."
            return
        }
        guard password.count >= 12 else {
            errorMessage = "Пароль должен содержать минимум 12 символов."
            return
        }
        guard password.count <= 128 else {
            errorMessage = "Пароль не должен превышать 128 символов."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Пароли не совпадают."
            return
        }
        await performAuthAction {
            let user = try await signUpUseCase.execute(
                name: trimmedName,
                email: trimmedEmail,
                password: password
            )
            currentUser = user
            successMessage = nil
        }
    }
    func resetPassword(email:String) async{
        let trimmedEmail = email.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard validateEmail(trimmedEmail) else{
            errorMessage = "Введите корректный адрес"
            return
        }
        await performAuthAction {
            try await resetPasswordUseCase.execute(email: trimmedEmail)
            successMessage = "Письмо для сброса пароля отправлено."
        }
    }
    func sendEmailVerificationLink() async {
        guard let email = currentUser?.email,
              !email.isEmpty else {
            errorMessage = "Нет email для отправки ссылки."
            return
        }
        await performAuthAction {
            try await authRepository.sendEmailSignInLink(email: email)
            successMessage = "Ссылка для подтверждения отправлена на \(email)."
        }
    }
    
    func handleIncomingURL(_ url: URL) {
        guard authRepository.isEmailSignInLink(url) else { return }
        let pendingEmail = UserDefaults.standard.string(
            forKey: FirebaseAuthRepository.pendingEmailLinkKey
        ) ?? currentUser?.email
        guard let email = pendingEmail, !email.isEmpty else {
            errorMessage = "Не удалось определить email для ссылки. Войдите заново и повторите."
            return
        }
        Task {
            do {
                let user = try await authRepository.completeEmailSignIn(
                    email: email,
                    link: url
                )
                UserDefaults.standard.removeObject(
                    forKey: FirebaseAuthRepository.pendingEmailLinkKey
                )
                currentUser = user
                successMessage = user.emailVerified
                    ? "Email подтверждён."
                    : "Вход по ссылке выполнен."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Password Reset (Gmail)

    /// Шаг 1 «Забыли пароль»: отправляет 6-значный код на email
    /// через Gmail (Cloud Functions + SMTP).
    func requestPasswordResetCode(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateEmail(trimmed) else {
            errorMessage = "Введите корректный email."
            return
        }
        await performAuthAction {
            try await passwordResetService.requestCode(email: trimmed)
            isResetCodeSent = true
            successMessage = "Если аккаунт существует, код отправлен на \(trimmed)."
        }
    }

    /// Шаг 2: проверяет код и устанавливает новый пароль.
    func confirmPasswordReset(
        email: String,
        code: String,
        newPassword: String
    ) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        guard validateEmail(trimmedEmail) else {
            errorMessage = "Введите корректный email."
            return
        }
        guard trimmedCode.count == 6 else {
            errorMessage = "Код должен содержать 6 цифр."
            return
        }
        guard newPassword.count >= 12 else {
            errorMessage = "Пароль должен содержать минимум 12 символов."
            return
        }
        guard newPassword.count <= 128 else {
            errorMessage = "Пароль не должен превышать 128 символов."
            return
        }
        await performAuthAction {
            try await passwordResetService.confirmReset(
                email: trimmedEmail,
                code: trimmedCode,
                newPassword: newPassword
            )
            isResetCodeSent = false
            successMessage = "Пароль обновлён. Войдите с новым паролем."
        }
    }

    // MARK: - Two-Factor (OTP)

    /// Включение 2FA: запрашивает код на email и показывает поле ввода.
    func enableTwoFactor() async {
        await performAuthAction {
            try await otpService.requestCode()
            isOTPEntryPresented = true
        }
    }

    /// Проверяет введённый код и включает 2FA при успехе.
    func confirmTwoFactorCode(_ code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 6 else {
            errorMessage = "Код должен содержать 6 цифр."
            return
        }
        await performAuthAction {
            try await otpService.verifyCode(trimmed)
            otpService.isTwoFactorEnabled = true
            isOTPEntryPresented = false
            successMessage = "Двухфакторная защита включена."
        }
    }

    func disableTwoFactor() {
        otpService.isTwoFactorEnabled = false
    }

    // MARK: - Profile

    @discardableResult
    func updateProfile(name: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Введите имя."
            return false
        }

        return await performAuthAction {
            currentUser = try await authRepository.updateProfile(name: trimmedName)
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        await performAuthAction {
            try await signOutUseCase.execute()
            currentUser = nil
        }
    }

    // MARK: - Helpers

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    @discardableResult
    private func performAuthAction(
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isLoading else { return false }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        defer {
            isLoading = false
        }

        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func validateEmail(_ email: String) -> Bool {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)

        return email.range(
            of: #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#,
            options: .regularExpression
        ) != nil
    }
}
