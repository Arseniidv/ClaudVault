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
        }
    }
}

// MARK: - Google OAuth Manager

@MainActor
final class GoogleOAuthManager {

    static let driveScope = "https://www.googleapis.com/auth/drive.file"

    private(set) var isConfigured = false

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

        return try makeAccount(from: user)
    }

    // MARK: - Restore Session

    func restorePreviousSignIn() async throws -> GoogleAccount? {
        try ensureConfigured()

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return try makeAccount(from: user)
        } catch let error as NSError {
            // Исправлено: заменено GIDSignInErrorCode на GIDSignInError
            if error.domain == kGIDSignInErrorDomain,
               error.code == GIDSignInError.hasNoAuthInKeychain.rawValue {
                return nil
            }

            throw Self.mapSignInError(error)
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
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

    // MARK: - Account Mapping

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
