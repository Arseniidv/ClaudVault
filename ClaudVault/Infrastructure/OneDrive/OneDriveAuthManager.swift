import AuthenticationServices
import CryptoKit
import Foundation
import Security
import ClaudVaultDomain
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Управляет OAuth-флоу OneDrive через Microsoft identity platform
/// (v2.0 endpoint) с PKCE — без внешних зависимостей.
///
/// Перед использованием нужно зарегистрировать приложение в
/// Azure Portal (Azure Active Directory → App registrations):
///   - Platforms: iOS / macOS
///   - Redirect URI: `msauth.<bundleID>://auth`
///   - API permissions: Files.ReadWrite, offline_access, User.Read
/// Client ID прописывается в Info.plist под ключом `OneDriveClientID`.
@MainActor
final class OneDriveAuthManager {

    /// Client ID из Info.plist (`OneDriveClientID`). nil — не настроено.
    static var clientID: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "OneDriveClientID"
        ) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Redirect URI вида `msauth.<bundleID>://auth` — должен совпадать
    /// с URI, зарегистрированным в Azure Portal.
    static var redirectURI: String {
        "msauth.\(AppConfiguration.bundleIdentifier)://auth"
    }

    private static var redirectScheme: String {
        URL(string: redirectURI)?.scheme ?? "msauth"
    }

    private static let scopes = "Files.ReadWrite offline_access User.Read"
    private static let authorizeURL =
        "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    private static let tokenURL =
        "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    private static let graphMeURL =
        "https://graph.microsoft.com/v1.0/me"

    private let tokenStore = OneDriveTokenStore()
    /// Единое Keychain-хранилище нормализованных сессий облаков.
    private let keychainStorage = KeychainStorageService.makeDefault()
    private let session: URLSession
    private var webAuthSession: ASWebAuthenticationSession?
    private let presentationContext = OneDrivePresentationContext()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Connect / Restore / SignOut

    /// Подключает OneDrive: при живой сессии возвращает аккаунт,
    /// иначе запускает OAuth-флоу в системном браузере.
    func connect() async throws -> CloudStorageAccount {
        guard Self.clientID != nil else {
            throw CloudStorageError.notConfigured
        }

        if tokenStore.load() != nil {
            do {
                _ = try await freshAccessToken()
                let account = try await currentAccount()
                await persistSession(account: account)
                return account
            } catch {
                tokenStore.delete()
            }
        }

        try await authorize()
        let account = try await currentAccount()
        await persistSession(account: account)
        return account
    }

    /// Возвращает аккаунт при сохранённой сессии, иначе nil.
    func restoreConnection() async throws -> CloudStorageAccount? {
        guard tokenStore.load() != nil else { return nil }

        do {
            _ = try await freshAccessToken()
            let account = try await currentAccount()
            await persistSession(account: account)
            return account
        } catch {
            tokenStore.delete()
            return nil
        }
    }

    /// Текущий пользователь CloudVault; nil — сеанса нет.
    private var currentOwnerID: String? {
        CurrentUserContext.shared.ownerID
    }

    func signOut() {
        tokenStore.delete()
        guard let ownerID = currentOwnerID else { return }
        Task {
            try? await keychainStorage.deleteSessions(
                for: .oneDrive,
                ownerID: ownerID
            )
        }
    }

    /// Свежий access token: из Keychain, если не истёк,
    /// иначе через refresh_token.
    func freshAccessToken() async throws -> String {
        guard let tokens = tokenStore.load() else {
            throw CloudStorageError.notConnected
        }

        if tokens.expiresAt.timeIntervalSinceNow > 60 {
            return tokens.accessToken
        }

        return try await refresh(tokens: tokens)
    }

    // MARK: - OAuth flow

    private func authorize() async throws {
        guard let clientID = Self.clientID else {
            throw CloudStorageError.notConfigured
        }

        let verifier = try Self.randomURLSafeString(byteCount: 32)
        let challenge = Self.codeChallenge(from: verifier)

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let authURL = components.url else {
            throw CloudStorageError.invalidResponse
        }

        let callbackURL = try await authenticate(url: authURL)
        let callbackItems = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        )?.queryItems
        guard let code = callbackItems?.first(where: { $0.name == "code" })?.value else {
            let errorParam = callbackItems?
                .first(where: { $0.name == "error" })?.value ?? "missing_code"
            if errorParam == "access_denied" {
                throw CloudStorageError.cancelled
            }
            throw CloudStorageError.operationFailed(
                "OneDrive OAuth: \(errorParam)"
            )
        }

        let tokens = try await exchangeCode(code: code, verifier: verifier)
        tokenStore.save(tokens)
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.redirectScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor [weak self] in
                    self?.webAuthSession = nil
                    if let error {
                        if let sessionError = error as? ASWebAuthenticationSessionError,
                           sessionError.code == .canceledLogin {
                            continuation.resume(throwing: CloudStorageError.cancelled)
                        } else {
                            continuation.resume(
                                throwing: CloudStorageError.network(error.localizedDescription)
                            )
                        }
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: CloudStorageError.cancelled)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
            }

            session.presentationContextProvider = presentationContext
            session.prefersEphemeralWebBrowserSession = false

            webAuthSession = session
            if !session.start() {
                webAuthSession = nil
                continuation.resume(
                    throwing: CloudStorageError.operationFailed(
                        "Не удалось открыть окно авторизации OneDrive."
                    )
                )
            }
        }
    }

    // MARK: - Token endpoints

    private func exchangeCode(code: String, verifier: String) async throws -> OneDriveTokenStore.StoredTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formBody([
            "client_id": Self.clientID ?? "",
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
            "scope": Self.scopes
        ])

        return try await performTokenRequest(request)
    }

    private func refresh(
        tokens: OneDriveTokenStore.StoredTokens
    ) async throws -> String {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formBody([
            "client_id": Self.clientID ?? "",
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "scope": Self.scopes
        ])

        let refreshed = try await performTokenRequest(request)
        tokenStore.save(refreshed)
        await mirrorTokenRefresh(refreshed)
        return refreshed.accessToken
    }

    private func performTokenRequest(
        _ request: URLRequest
    ) async throws -> OneDriveTokenStore.StoredTokens {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CloudStorageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidResponse
        }

        struct TokenResponse: Decodable {
            let accessToken: String?
            let refreshToken: String?
            let expiresIn: Double?
            let error: String?
            let errorDescription: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case error
                case errorDescription = "error_description"
            }
        }

        let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)

        guard (200..<300).contains(http.statusCode) else {
            let message = decoded?.errorDescription
                ?? decoded?.error
                ?? "HTTP \(http.statusCode)"
            if decoded?.error == "invalid_grant" {
                return try await handleInvalidGrant(message: message)
            }
            throw CloudStorageError.requestFailed(
                statusCode: http.statusCode,
                message: message
            )
        }

        guard let accessToken = decoded?.accessToken,
              let refreshToken = decoded?.refreshToken ?? tokenStore.load()?.refreshToken else {
            throw CloudStorageError.invalidResponse
        }

        let expiresIn = decoded?.expiresIn ?? 3600
        return OneDriveTokenStore.StoredTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            // 60 секунд запаса до реального истечения.
            expiresAt: Date().addingTimeInterval(expiresIn - 60)
        )
    }

    private func handleInvalidGrant(message: String) async throws -> OneDriveTokenStore.StoredTokens {
        tokenStore.delete()
        if let ownerID = currentOwnerID {
            try? await keychainStorage.deleteSessions(
                for: .oneDrive,
                ownerID: ownerID
            )
        }
        throw CloudStorageError.unauthorized
    }

    // MARK: - Session mirror

    /// Дублирует активную OneDrive-сессию в нормализованную
    /// `CloudAccountSession`-запись единого Keychain-хранилища.
    private func persistSession(account: CloudStorageAccount) async {
        guard let tokens = tokenStore.load(),
              let ownerID = currentOwnerID else { return }
        await saveSessionMirror(CloudAccountSession(
            provider: .oneDrive,
            userEmail: account.email,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            ownerID: ownerID
        ))
    }

    /// Обновляет access token/expiry в зеркальной записи после refresh,
    /// чтобы `listAllSessions()` не возвращал протухший токен.
    private func mirrorTokenRefresh(
        _ tokens: OneDriveTokenStore.StoredTokens
    ) async {
        guard let ownerID = currentOwnerID else { return }
        let sessions = await keychainStorage.listAllSessions(ownerID: ownerID)
        for session in sessions where session.provider == .oneDrive {
            await saveSessionMirror(CloudAccountSession(
                provider: .oneDrive,
                userEmail: session.userEmail,
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: tokens.expiresAt,
                ownerID: ownerID
            ))
        }
    }

    private func saveSessionMirror(_ session: CloudAccountSession) async {
        do {
            try await keychainStorage.saveSession(session)
        } catch {
            #if DEBUG
            print("[OneDrive] Failed to mirror session to Keychain: \(error)")
            #endif
        }
    }

    // MARK: - Account

    private func currentAccount() async throws -> CloudStorageAccount {
        var request = URLRequest(url: URL(string: Self.graphMeURL)!)
        request.setValue(
            "Bearer \(try await freshAccessToken())",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw CloudStorageError.invalidResponse
        }

        struct MeResponse: Decodable {
            let id: String?
            let mail: String?
            let userPrincipalName: String?
            let displayName: String?
        }

        guard let me = try? JSONDecoder().decode(MeResponse.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }

        return CloudStorageAccount(
            id: me.id ?? me.userPrincipalName ?? "unknown",
            email: me.mail ?? me.userPrincipalName ?? "",
            displayName: me.displayName
        )
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw CloudStorageError.operationFailed("Не удалось сгенерировать PKCE.")
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return (components.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Якорь для `ASWebAuthenticationSession` — key window текущей сцены.
private final class OneDrivePresentationContext: NSObject,
    ASWebAuthenticationPresentationContextProviding {

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
            ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #endif
    }
}
