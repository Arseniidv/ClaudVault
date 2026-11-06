import CryptoKit
import Security
import Foundation
import SwiftyDropbox

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum DropboxPKCE{
    static func generateRandomString(byteCount:Int = 32) throws -> String{
        var bytes = [UInt8] (repeating: 0, count: byteCount)
        
        let result = SecRandomCopyBytes(
            kSecRandomDefault,
            byteCount,
            &bytes
        )
        guard result == errSecSuccess else{
            throw PKCEError.randomGenerator()
        }
        return Data(bytes).base64EncodedString()
    }
    static func generateCodeChellage(from verifier:String) ->String?{
        let date = Data(verifier.utf8)
        let digest = SHA256.hash(data: date)
        
        return Data(digest).base64EncodedString()
    
    }
}
enum PKCEError:Error{
    case randomGenerator(status:OSStatus? = nil)
}
private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Dropbox Auth Manager

/// Управляет OAuth-флоу Dropbox через SwiftyDropbox.
/// Результат системного браузера приходит в `handleRedirectURL(_:)`,
/// который вызывается из `onOpenURL` корневой сцены.
@MainActor
final class DropboxAuthManager {

    static let appKey = "d395lxiq0xc1ltc"

    /// Scopes, необходимые файловому менеджеру и информации об аккаунте.
    private static let scopes = [
        "account_info.read",
        "files.metadata.read",
        "files.content.read",
        "files.content.write"
    ]

    /// Продолжение текущего OAuth-флоу. Завершается в `handleRedirectURL`.
    private var pendingAuth: CheckedContinuation<DropboxOAuthResult?, Never>?

    // MARK: - Connect

    /// Запускает авторизацию Dropbox, если сессия ещё не восстановлена.
    /// Возвращает данные аккаунта.
    func connect() async throws -> CloudStorageAccount {
        if DropboxClientsManager.authorizedClient == nil {
            let result = await authorize()

            switch result {
            case .success:
                break
            case .cancel:
                throw CloudStorageError.cancelled
            case .error(let error, let description):
                throw CloudStorageError.operationFailed(
                    description ?? error.localizedDescription
                )
            case nil:
                throw CloudStorageError.operationFailed(
                    "Авторизация Dropbox не была завершена."
                )
            }
        }

        return try await currentAccount()
    }

    // MARK: - Restore Session

    /// Возвращает аккаунт, если токен Dropbox сохранён в Keychain,
    /// иначе `nil`.
    func restoreConnection() async throws -> CloudStorageAccount? {
        guard DropboxClientsManager.authorizedClient != nil else {
            return nil
        }
        return try await currentAccount()
    }

    func signOut() {
        DropboxClientsManager.unlinkClients()
    }

    // MARK: - URL Handling

    /// Вызывается из `onOpenURL`. Возвращает `true`, если URL относится к Dropbox OAuth.
    @discardableResult
    func handleRedirectURL(_ url: URL) -> Bool {
        DropboxClientsManager.handleRedirectURL(
            url,
            includeBackgroundClient: false
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.pendingAuth?.resume(returning: result)
                self?.pendingAuth = nil
            }
        }
    }

    // MARK: - Private

    private func authorize() async -> DropboxOAuthResult? {
        await withCheckedContinuation { continuation in
            pendingAuth = continuation

            let scopeRequest = ScopeRequest(
                scopeType: .user,
                scopes: Self.scopes,
                includeGrantedScopes: true
            )

            #if os(iOS)
            DropboxClientsManager.authorizeFromControllerV2(
                UIApplication.shared,
                controller: Self.topViewController(),
                loadingStatusDelegate: nil,
                openURL: { url in UIApplication.shared.open(url) },
                scopeRequest: scopeRequest
            )
            #elseif os(macOS)
            DropboxClientsManager.authorizeFromControllerV2(
                sharedApplication: NSApplication.shared,
                controller: Self.topViewController(),
                loadingStatusDelegate: nil,
                openURL: { url in NSWorkspace.shared.open(url) },
                scopeRequest: scopeRequest
            )
            #endif
        }
    }

    private func currentAccount() async throws -> CloudStorageAccount {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw CloudStorageError.notConnected
        }

        do {
            let account = try await client.users.getCurrentAccount().response()
            return CloudStorageAccount(
                id: account.accountId,
                email: account.email,
                displayName: account.name.displayName
            )
        } catch let error as CallError<Void> {
            throw Self.mapError(error)
        }
    }

    /// Маппит ошибки SwiftyDropbox в доменные ошибки хранилища.
    static func mapError<E>(_ error: CallError<E>) -> CloudStorageError {
        print("[Dropbox] API error: \(error)")
        switch error {
        case .authError:
            return .unauthorized
        case .accessError:
            return .permissionDenied
        case .rateLimitError:
            return .rateLimited
        case .internalServerError(let statusCode, let message, _):
            return .requestFailed(
                statusCode: statusCode,
                message: message ?? error.description
            )
        case .httpError(let statusCode, let message, _):
            return .requestFailed(
                statusCode: statusCode ?? 0,
                message: message ?? error.description
            )
        case .routeError(let box, let localized, _, _):
            return .operationFailed(localized?.text ?? "\(box)")
        case .clientError(let clientError):
            if case .urlSessionError(let urlError) = clientError {
                return .network(urlError.localizedDescription)
            }
            return .network(clientError.localizedDescription)
        case .badInputError(let message, _):
            return .operationFailed(message ?? "Некорректный запрос к Dropbox.")
        case .serializationError:
            return .invalidResponse
        case .reconnectionError(let reconnectionError):
            return .network(reconnectionError.localizedDescription)
        }
    }

    // MARK: - Presenting

    #if os(iOS)

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        let window = windows.first { $0.isKeyWindow } ?? windows.first

        var presenter = window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }

        return presenter
    }

    #elseif os(macOS)

    private static func topViewController() -> NSViewController? {
        NSApplication.shared.keyWindow?.contentViewController
            ?? NSApplication.shared.windows.first?.contentViewController
    }

    #endif
}
