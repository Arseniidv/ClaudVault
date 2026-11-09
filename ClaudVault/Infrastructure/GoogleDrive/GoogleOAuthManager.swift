import Foundation
import OSLog
import GoogleSignIn
import ClaudVaultDomain

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Google Account

struct GoogleAccount: Equatable {
    let userID: String
    let email: String
    let name: String?

    // Access token намеренно НЕ хранится в аккаунте:
    // он короткоживущий и запрашивается через GoogleOAuthManager
    // перед каждым обращением к Google API.
}

// MARK: - Errors

enum GoogleOAuthError: LocalizedError {
    case missingClientID
    case notConfigured
    case notSignedIn
    case missingAccount
    case missingEmail
    case noPresentingWindow
    case scopeDenied
    case tokenExchangeFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingClientID, .notConfigured:
            return "Не найден Google OAuth Client ID (GIDClientID в Info.plist)."
        case .notSignedIn:
            return "Аккаунт Google не подключён."
        case .missingAccount:
            return "Не удалось получить данные Google-аккаунта."
        case .missingEmail:
            return "Google не вернул email пользователя."
        case .noPresentingWindow:
            return "Не удалось найти окно для показа авторизации."
        case .scopeDenied:
            return "Не выдан доступ к Google Drive."
        case .tokenExchangeFailed:
            return "Не удалось обновить токен Google Drive. Подключите аккаунт заново."
        case .cancelled:
            return "Вход в Google отменён."
        }
    }
}

// MARK: - Google OAuth Manager

@MainActor
final class GoogleOAuthManager {

    static let driveScope = "https://www.googleapis.com/auth/drive.file"

    private static let logger = Logger(
        subsystem: "ClaudVault",
        category: "google-oauth"
    )

    private(set) var isConfigured = false

    /// Результат обмена refresh token на access token
    /// у `https://oauth2.googleapis.com/token`.
    enum RestoredTokenExchange {
        case success(
            accessToken: String,
            expiresIn: Double?,
            refreshToken: String?
        )
        /// Refresh token отозван/протух — сессию нужно переподключить.
        case invalidGrant
    }

    /// Сетевой обмен refresh token'а. Вынесен в замыкание,
    /// чтобы тесты могли подменить token endpoint.
    private let exchangeRestoredToken: (GoogleRestoredSession) async throws -> RestoredTokenExchange

    /// Single-flight восстановленных refresh-запросов по ownerID:
    /// `tokenProvider` вызывается на каждый API-запрос, и без
    /// дедупликации параллельные вызовы делали бы дублирующие
    /// POST на token endpoint.
    private var restoredRefreshTasks: [String: Task<String, Error>] = [:]

    /// Хвост очереди OAuth-флоу GIDSignIn. SDK — синглтон с
    /// единственным слотом continuation'а: параллельные
    /// `signIn`/`restorePreviousSignIn` перезаписывают внутренние
    /// options и «съедают» чужой completion, из-за чего async-вызов
    /// может не завершиться никогда. Все флоу выполняем строго
    /// последовательно.
    private var gidFlowTail: Task<Void, Never>?

    /// Сессия, восстановленная через QR-перенос с другого устройства.
    /// `GIDSignIn` не умеет принимать чужие токены, поэтому
    /// refresh token хранится отдельно и обменивается на
    /// access token напрямую через OAuth2 endpoint Google.
    private let keychainStorageService = KeychainStorageService.makeDefault()
    private let restoredSessionStore = GoogleSessionStore()

    // MARK: - Configuration

    init(
        clientID: String? = nil,
        exchangeRestoredToken: ((GoogleRestoredSession) async throws -> RestoredTokenExchange)? = nil
    ) {
        let resolvedClientID = clientID ?? (Bundle.main.object(
            forInfoDictionaryKey: "GIDClientID"
        ) as? String)
        // GIDClientID — документированный способ конфигурации GoogleSignIn.
        if let resolvedClientID, !resolvedClientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: resolvedClientID
            )
            isConfigured = true
        }
        self.exchangeRestoredToken = exchangeRestoredToken ?? Self.defaultTokenExchange
    }

    var isSignedIn: Bool {
        if GIDSignIn.sharedInstance.currentUser != nil {
            return true
        }
        guard let ownerID = currentOwnerID else { return false }
        // Эвристика для UI: ошибка чтения трактуется как «сессии
        // нет» — реальную ошибку покажет restoreConnection.
        return (try? restoredSessionStore.load(ownerID: ownerID)) != nil
    }

    /// Текущий пользователь CloudVault; nil — сеанса нет,
    /// работать с Google-сессиями нельзя.
    private var currentOwnerID: String? {
        CurrentUserContext.shared.ownerID
    }

    // MARK: - Connect

    func connect() async throws -> GoogleAccount {
        try await serializedGIDFlow(performConnect)
    }

    private func performConnect() async throws -> GoogleAccount {
        try ensureConfigured()

        // Если в GIDSignIn осталась чужая сессия (например, от
        // предыдущего пользователя CloudVault), сбрасываем её —
        // connect всегда запускает вход заново.
        if GIDSignIn.sharedInstance.currentUser != nil,
           !(await currentGIDUserIsOwned()) {
            GIDSignIn.sharedInstance.signOut()
        }

        if GIDSignIn.sharedInstance.currentUser == nil {
            do {
                #if os(iOS)
                let presenter = try presentingViewController()
                _ = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: [Self.driveScope]
                )
                #elseif os(macOS)
                let presenter = try presentingWindow()
                _ = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: [Self.driveScope]
                )
                #endif
            } catch let error as NSError {
                throw Self.mapSignInError(error)
            }
        }

        try await ensureDriveScope()

        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleOAuthError.missingAccount
        }

        let account = try makeAccount(from: user)
        await persistSession(user: user, email: account.email)
        return account
    }

    // MARK: - Restore Session

    func restorePreviousSignIn() async throws -> GoogleAccount? {
        // Без владельца CloudVault Google-сессия не может быть
        // «своей»: silent-флоу GIDSignIn не запускаем вообще.
        // Он бы не только зря трогал keychain, но и перезаписал
        // continuation возможного интерактивного входа через
        // Google на экране логина (общий слот в GIDSignIn).
        guard currentOwnerID != nil else { return nil }
        return try await serializedGIDFlow(performRestorePreviousSignIn)
    }

    private func performRestorePreviousSignIn() async throws -> GoogleAccount? {
        try ensureConfigured()

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            let account = try makeAccount(from: user)

            // Восстановленная GIDSignIn-сессия может принадлежать
            // другому аккаунту Google (данные до изоляции или
            // остатки чужого входа). Принимаем её только если
            // Google-аккаунт записан за текущим пользователем.
            guard await currentGIDUserIsOwned() else {
                GIDSignIn.sharedInstance.signOut()
                return try restoredAccount()
            }

            await persistSession(user: user, email: account.email)
            return account
        } catch let error as NSError {
            // Исправлено: заменено GIDSignInErrorCode на GIDSignInError
            if error.domain == kGIDSignInErrorDomain,
               error.code == GIDSignInError.hasNoAuthInKeychain.rawValue {
                // Локальной сессии GIDSignIn нет — проверяем
                // сессию, восстановленную через QR-перенос.
                return try restoredAccount()
            }

            throw Self.mapSignInError(error)
        }
    }

    /// Выполняет OAuth-операцию GIDSignIn строго после всех
    /// ранее поставленных в очередь. См. комментарий у
    /// `gidFlowTail`.
    private func serializedGIDFlow<T>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let previous = gidFlowTail
        let task = Task { @MainActor in
            _ = await previous?.value
            return try await operation()
        }
        gidFlowTail = Task { _ = try? await task.value }
        return try await task.value
    }

    /// Отключение Google Drive текущим пользователем:
    /// удаляет GIDSignIn-сессию и все scoped-записи этого
    /// пользователя. Сессии других пользователей не затрагиваются.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        guard let ownerID = currentOwnerID else { return }
        do {
            try restoredSessionStore.delete(ownerID: ownerID)
        } catch {
            Self.logger.error(
                "Failed to delete restored Google session: \(error.localizedDescription)"
            )
        }
        Task {
            try? await keychainStorageService.deleteSessions(
                for: .googleDrive,
                ownerID: ownerID
            )
        }
    }

    /// Сброс сессии GIDSignIn при смене пользователя CloudVault.
    /// Scoped-записи в Keychain сохраняются — они принадлежат
    /// конкретному ownerID.
    /// ВНИМАНИЕ: `GIDSignIn.signOut()` — не «только in-memory»:
    /// он также удаляет credentials из Keychain, поэтому вызывать
    /// его на переходе nil → user (восстановление сессии при
    /// холодном старте) нельзя — это уничтожит персистентную
    /// сессию до того, как `restorePreviousSignIn` её прочитает.
    /// Вызывать ПОСЛЕ `exportSessionForOwner`, иначе refresh
    /// token текущей GIDSignIn-сессии будет потерян.
    func disconnectInMemory() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// Сохраняет текущую GIDSignIn-сессию в scoped-хранилище
    /// `GoogleSessionStore` от имени указанного пользователя.
    /// Нужно при смене аккаунта: GIDSignIn — синглтон и не умеет
    /// держать сессии двух пользователей, поэтому перед сбросом
    /// экспортируем refresh token, чтобы прежний пользователь
    /// мог восстановить подключение при повторном входе.
    func exportSessionForOwner(_ ownerID: String) {
        guard !ownerID.isEmpty,
              let user = GIDSignIn.sharedInstance.currentUser,
              !user.refreshToken.tokenString.isEmpty,
              let clientID = GIDSignIn.sharedInstance.configuration?.clientID,
              let email = user.profile?.email else {
            return
        }
        do {
            try restoredSessionStore.save(GoogleRestoredSession(
                refreshToken: user.refreshToken.tokenString,
                clientID: clientID,
                userID: user.userID ?? "",
                email: email,
                displayName: user.profile?.name,
                grantedScopes: user.grantedScopes ?? [],
                accessToken: nil,
                accessTokenExpiresAt: nil
            ), ownerID: ownerID)
        } catch {
            // Экспорт best-effort: при неудачной записи прежний
            // пользователь при повторном входе просто
            // переподключит Google Drive.
            Self.logger.error(
                "Failed to export Google session: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - URL Handling

    @discardableResult
    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Access Token

    func freshAccessToken() async throws -> String {
        try ensureConfigured()

        guard let user = GIDSignIn.sharedInstance.currentUser else {
            // Fallback: сессия, восстановленная через QR-перенос
            // или экспортированная при смене пользователя.
            guard let ownerID = currentOwnerID,
                  let session = try restoredSessionStore.load(ownerID: ownerID) else {
                throw GoogleOAuthError.notSignedIn
            }
            return try await restoredAccessToken(session: session, ownerID: ownerID)
        }

        // Чужая GIDSignIn-сессия не должна отдавать токены
        // текущему пользователю CloudVault.
        guard await currentGIDUserIsOwned() else {
            GIDSignIn.sharedInstance.signOut()
            throw GoogleOAuthError.notSignedIn
        }

        _ = try await user.refreshTokensIfNeeded()

        guard let refreshed = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleOAuthError.notSignedIn
        }

        return refreshed.accessToken.tokenString
    }

    // MARK: - Scopes

    private func ensureDriveScope() async throws {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleOAuthError.notSignedIn
        }

        let granted = user.grantedScopes ?? []
        guard !granted.contains(Self.driveScope) else { return }
        do {
            #if os(iOS)
            let presenter = try presentingViewController()
            _ = try await user.addScopes(
                [Self.driveScope],
                presenting: presenter
            )
            #elseif os(macOS)
            let presenter = try presentingWindow()
            _ = try await user.addScopes(
                [Self.driveScope],
                presenting: presenter
            )
            #endif
        } catch let error as NSError {
            throw Self.mapSignInError(error)
        }

        let updated = GIDSignIn.sharedInstance.currentUser ?? user
        let grantedAfter = updated.grantedScopes ?? []

        guard grantedAfter.contains(Self.driveScope) else {
            throw GoogleOAuthError.scopeDenied
        }
    }

    /// Маппит ошибки SDK в доменные ошибки хранилища.
    private static func mapSignInError(_ error: NSError) -> Error {
        if error.domain == kGIDSignInErrorDomain {
            if error.code == GIDSignInError.canceled.rawValue {
                return GoogleOAuthError.cancelled
            }

            if error.code == GIDSignInError.hasNoAuthInKeychain.rawValue {
                return GoogleOAuthError.notSignedIn
            }
        }
        return error
    }

    // MARK: - Presenting

    private func ensureConfigured() throws {
        guard isConfigured,
              GIDSignIn.sharedInstance.configuration != nil else {
            throw GoogleOAuthError.notConfigured
        }
    }

    #if os(iOS)

    private func presentingViewController() throws -> UIViewController {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        let window = windows.first { $0.isKeyWindow } ?? windows.first

        var presenter = window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }

        guard let presenter else {
            throw GoogleOAuthError.noPresentingWindow
        }

        return presenter
    }

    #elseif os(macOS)

    private func presentingWindow() throws -> NSWindow {
        let application = NSApplication.shared

        if let keyWindow = application.keyWindow {
            return keyWindow
        }

        guard let window = application.windows.first else {
            throw GoogleOAuthError.noPresentingWindow
        }

        return window
    }

    #endif

    // MARK: - Restored Session (QR transfer)

    /// Аккаунт из сессии, восстановленной через QR-перенос
    /// или экспортированной при смене пользователя.
    /// Возвращает nil, если сессии нет или в ней нет scope Drive.
    /// Ошибки Keychain/декодирования пробрасываются — битая запись
    /// не должна маскироваться под «сессии нет».
    private func restoredAccount() throws -> GoogleAccount? {
        guard let ownerID = currentOwnerID,
              let session = try restoredSessionStore.load(ownerID: ownerID),
              session.grantedScopes.contains(Self.driveScope) else {
            return nil
        }
        return GoogleAccount(
            userID: session.userID,
            email: session.email,
            name: session.displayName
        )
    }

    /// Access token для восстановленной сессии: из кэша,
    /// если не истёк, иначе — обмен refresh token'а
    /// на `https://oauth2.googleapis.com/token`.
    private func restoredAccessToken(
        session: GoogleRestoredSession,
        ownerID: String
    ) async throws -> String {
        if let cached = session.accessToken,
           let expiresAt = session.accessTokenExpiresAt,
           expiresAt.timeIntervalSinceNow > 60 {
            return cached
        }

        // Single-flight: `tokenProvider` вызывается на каждый
        // API-запрос — параллельные вызовы делят один обмен
        // refresh token'а, иначе каждый слал бы свой POST
        // и перезаписывал сессию в Keychain.
        if let inFlight = restoredRefreshTasks[ownerID] {
            return try await inFlight.value
        }
        let task = Task<String, Error> {
            try await self.performRestoredTokenRefresh(
                session: session,
                ownerID: ownerID
            )
        }
        restoredRefreshTasks[ownerID] = task
        do {
            let token = try await task.value
            restoredRefreshTasks[ownerID] = nil
            return token
        } catch {
            restoredRefreshTasks[ownerID] = nil
            throw error
        }
    }

    /// Собственно обмен refresh token'а и запись результата.
    /// Отделён от single-flight обёртки для читаемости.
    private func performRestoredTokenRefresh(
        session: GoogleRestoredSession,
        ownerID: String
    ) async throws -> String {
        let accessToken: String
        let expiresIn: Double?
        let rotatedRefreshToken: String?
        switch try await exchangeRestoredToken(session) {
        case .invalidGrant:
            // Refresh token отозван/протух — сессию нужно
            // переподключить. Запись принадлежит ownerID,
            // удаление безопасно даже при смене владельца.
            do {
                try restoredSessionStore.delete(ownerID: ownerID)
            } catch {
                Self.logger.error(
                    "Failed to delete revoked Google session: \(error.localizedDescription)"
                )
            }
            throw GoogleOAuthError.notSignedIn
        case .success(let token, let ttl, let rotated):
            accessToken = token
            expiresIn = ttl
            rotatedRefreshToken = rotated
        }

        // Владелец мог выйти или смениться, пока шёл сетевой
        // запрос: поздний результат не должен попасть в чужую
        // сессию или воскресить запись, удалённую signOut.
        guard currentOwnerID == ownerID else {
            throw CancellationError()
        }

        var updated = session
        updated.accessToken = accessToken
        // 60 секунд запаса до реального истечения.
        updated.accessTokenExpiresAt = Date().addingTimeInterval(
            (expiresIn ?? 3600) - 60
        )
        // Новый refresh_token сохраняем, только если сервер
        // его прислал и он не пуст — иначе оставляем прежний.
        if let rotatedRefreshToken, !rotatedRefreshToken.isEmpty {
            updated.refreshToken = rotatedRefreshToken
        }
        try restoredSessionStore.save(updated, ownerID: ownerID)
        await persistRestoredSession(
            session: updated,
            accessToken: accessToken,
            ownerID: ownerID
        )

        return accessToken
    }

    /// Реализация обмена refresh token → access token
    /// через `https://oauth2.googleapis.com/token`.
    /// Параметр `scope` в refresh-запросе не передаётся:
    /// grant `refresh_token` его не принимает — scopes
    /// привязаны к refresh token'у при выдаче.
    private static func defaultTokenExchange(
        _ session: GoogleRestoredSession
    ) async throws -> RestoredTokenExchange {
        var request = URLRequest(
            url: URL(string: "https://oauth2.googleapis.com/token")!
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        let fields: [String: String] = [
            "client_id": session.clientID,
            "refresh_token": session.refreshToken,
            "grant_type": "refresh_token"
        ]
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = (components.percentEncodedQuery ?? "")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleOAuthError.tokenExchangeFailed
        }

        struct TokenResponse: Decodable {
            let accessToken: String?
            let expiresIn: Double?
            let refreshToken: String?
            let error: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
                case refreshToken = "refresh_token"
                case error
            }
        }

        let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)

        guard (200..<300).contains(http.statusCode),
              let accessToken = decoded?.accessToken else {
            if decoded?.error == "invalid_grant" {
                return .invalidGrant
            }
            throw GoogleOAuthError.tokenExchangeFailed
        }

        return .success(
            accessToken: accessToken,
            expiresIn: decoded?.expiresIn,
            refreshToken: decoded?.refreshToken
        )
    }

    // MARK: - Account Mapping

    /// Дублирует активную Google-сессию в нормализованную
    /// `CloudAccountSession`-запись единого Keychain-хранилища.
    /// Сырые токены остаются под управлением GIDSignIn —
    /// это индекс для `listAllSessions()` и QR-переноса.
    private func persistSession(user: GIDGoogleUser, email: String) async {
        let refreshToken = user.refreshToken.tokenString
        await saveSessionMirror(CloudAccountSession(
            provider: .googleDrive,
            userEmail: email,
            accessToken: user.accessToken.tokenString,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            // GIDSignIn не экспонирует срок жизни access token'а.
            expiresAt: nil,
            ownerID: currentOwnerID ?? ""
        ))
    }

    /// Зеркалирует QR-восстановленную сессию в `CloudAccountSession`,
    /// чтобы `listAllSessions()` видел её наравне с обычным входом.
    private func persistRestoredSession(
        session: GoogleRestoredSession,
        accessToken: String,
        ownerID: String
    ) async {
        await saveSessionMirror(CloudAccountSession(
            provider: .googleDrive,
            userEmail: session.email,
            accessToken: accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.accessTokenExpiresAt,
            ownerID: ownerID
        ))
    }

    private func saveSessionMirror(_ session: CloudAccountSession) async {
        do {
            try await keychainStorageService.saveSession(session)
        } catch {
            #if DEBUG
            print("[Google] Failed to mirror session to Keychain: \(error)")
            #endif
        }
    }

    private func makeAccount(from user: GIDGoogleUser) throws -> GoogleAccount {
        guard let email = user.profile?.email else {
            throw GoogleOAuthError.missingEmail
        }

        // Исправлена опечатка в имени структуры: GoogleAccount вместо GoleAccount
        return GoogleAccount(
            userID: user.userID ?? "",
            email: email,
            name: user.profile?.name
        )
    }

    // MARK: - Ownership

    /// Проверяет, что активная GIDSignIn-сессия принадлежит
    /// текущему пользователю CloudVault. Признак владения —
    /// scoped `CloudAccountSession`-зеркало или scoped
    /// восстановленная сессия с тем же email. Без активного
    /// пользователя CloudVault возвращает false.
    private func currentGIDUserIsOwned() async -> Bool {
        guard let ownerID = currentOwnerID,
              let user = GIDSignIn.sharedInstance.currentUser,
              let email = user.profile?.email else {
            return false
        }

        if await keychainStorageService.loadSession(
            for: .googleDrive,
            email: email,
            ownerID: ownerID
        ) != nil {
            return true
        }

        do {
            if try restoredSessionStore.load(ownerID: ownerID)?.email == email {
                return true
            }
        } catch {
            // Битая запись не должна влиять на проверку владения
            // GIDSignIn-сессией — mirror уже проверен выше.
        }
        return false
    }
}
