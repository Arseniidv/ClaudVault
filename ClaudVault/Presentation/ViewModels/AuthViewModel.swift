
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

    // MARK: - Published Properties
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    /// Показывать ли ввод OTP-кода (после отправки письма).
    @Published var isOTPEntryPresented = false
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
        otpService: OTPService
    ) {
        self.signInUseCase = signInUseCase
        self.signUpUseCase = signUpUseCase
        self.signOutUseCase = signOutUseCase
        self.resetPasswordUseCase = resetPasswordUseCase
        self.getCurrentUserUseCase = getCurrentUserUseCase
        self.authRepository = authRepository
        self.otpService = otpService
    }
    // MARK: - Observe Authentication
    func observeAuthState() {
        guard authStateTask == nil else { return }
        authStateTask = Task {
            for await user in getCurrentUserUseCase.observeAuthState() {
                self.currentUser = user
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
            guard let presentingWindow = NSApp.keyWindow ?? NSApp.windows.first else {
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
            let authResult = try await Auth.auth().signIn(
                with: credential
            )
            successMessage = "Вы успешно вошли через Google"
            print("Google Sign-In successful")
            print("User ID: \(authResult.user.uid)")
        } catch {
            errorMessage = error.localizedDescription
            print("Google Sign-In error: \(error.localizedDescription)")
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
        guard password.count >= 6 else {
            errorMessage = "Пароль должен содержать минимум 6 символов."
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

    private func performAuthAction(
        operation: () async throws -> Void
    ) async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        defer {
            isLoading = false
        }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    @MainActor
    func senfPasswordReset(email:String) async{
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        defer{
            isLoading = false
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else{
            errorMessage = "Введите адрес электронной почты"
            return
        }
        guard trimmedEmail.contains("G"),trimmedEmail.contains(".") else{
            errorMessage = "Введите корректный email"
            return
        }
        do{
            try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
            successMessage = "Письмо для восстановления пароля отправлено"
        } catch {
            errorMessage = error.localizedDescription
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
