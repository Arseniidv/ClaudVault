import Foundation
import GoogleSignIn

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
        }
    }
}

// MARK: - Google OAuth Manager

@MainActor
final class GoogleOAuthManager {

    static let driveScope = "https://www.googleapis.com/auth/drive.file"

    private(set) var isConfigured = false

    /// Сессия, восстановленная через QR-перенос с другого устройства.
    /// `GIDSignIn` не умеет принимать чужие токены, поэтому
    /// refresh token хранится отдельно и обменивается на
    /// access token напрямую через OAuth2 endpoint Google.
    private let keychainStorageService = KeychainStorageService.makeDefault()
    private let restoredSessionStore = GoogleSessionStore()

    // MARK: - Configuration

    init() {
        // GIDClientID — документированный способ конфигурации GoogleSignIn.
        if let clientID = Bundle.main.object(
            forInfoDictionaryKey: "GIDClientID"
        ) as? String,
           !clientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: clientID
            )
            isConfigured = true
        }
    }

    var isSignedIn: Bool {
        GIDSignIn.sharedInstance.currentUser != nil
            || restoredSessionStore.load() != nil
    }

    // MARK: - Connect

    func connect() async throws -> GoogleAccount {
        try ensureConfigured()

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
        try ensureConfigured()

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            let account = try makeAccount(from: user)
            await persistSession(user: user, email: account.email)
            return account
        } catch let error as NSError {
            // Исправлено: заменено GIDSignInErrorCode на GIDSignInError
            if error.domain == kGIDSignInErrorDomain,
               error.code == GIDSignInError.hasNoAuthInKeychain.rawValue {
                // Локальной сессии GIDSignIn нет — проверяем
                // сессию, восстановленную через QR-перенос.
                return restoredAccount()
            }

            throw Self.mapSignInError(error)
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        restoredSessionStore.delete()
        Task { try? await keychainStorageService.deleteSessions(for: .googleDrive) }
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
            // Fallback: сессия, восстановленная через QR-перенос.
            guard let session = restoredSessionStore.load() else {
                throw GoogleOAuthError.notSignedIn
            }
            return try await restoredAccessToken(session: session)
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
                return GoogleOAuthError.missingAccount // Или ваша кастомная ошибка отмены
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

    /// Аккаунт из сессии, восстановленной через QR-перенос.
    /// Возвращает nil, если сессии нет или в ней нет scope Drive.
    private func restoredAccount() -> GoogleAccount? {
        guard let session = restoredSessionStore.load(),
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
        session: GoogleRestoredSession
    ) async throws -> String {
        if let cached = session.accessToken,
           let expiresAt = session.accessTokenExpiresAt,
           expiresAt.timeIntervalSinceNow > 60 {
            await persistRestoredSession(session: session, accessToken: cached)
            return cached
        }

        var request = URLRequest(
            url: URL(string: "https://oauth2.googleapis.com/token")!
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        var fields: [String: String] = [
            "client_id": session.clientID,
            "refresh_token": session.refreshToken,
            "grant_type": "refresh_token"
        ]
        if !session.grantedScopes.isEmpty {
            fields["scope"] = session.grantedScopes.joined(separator: " ")
        }
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
            let error: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
                case error
            }
        }

        let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)

        guard (200..<300).contains(http.statusCode),
              let accessToken = decoded?.accessToken else {
            if decoded?.error == "invalid_grant" {
                // Refresh token отозван/протух — сессию нужно переподключить.
                restoredSessionStore.delete()
                throw GoogleOAuthError.notSignedIn
            }
            throw GoogleOAuthError.tokenExchangeFailed
        }

        var updated = session
        updated.accessToken = accessToken
        // 60 секунд запаса до реального истечения.
        updated.accessTokenExpiresAt = Date().addingTimeInterval(
            (decoded?.expiresIn ?? 3600) - 60
        )
        restoredSessionStore.save(updated)
        await persistRestoredSession(session: updated, accessToken: accessToken)

        return accessToken
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
            expiresAt: nil
        ))
    }

    /// Зеркалирует QR-восстановленную сессию в `CloudAccountSession`,
    /// чтобы `listAllSessions()` видел её наравне с обычным входом.
    private func persistRestoredSession(
        session: GoogleRestoredSession,
        accessToken: String
    ) async {
        await saveSessionMirror(CloudAccountSession(
            provider: .googleDrive,
            userEmail: session.email,
            accessToken: accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.accessTokenExpiresAt
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
}
