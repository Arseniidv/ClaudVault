import Foundation
import SwiftyDropbox

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import ClaudVaultDomain
#endif

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

    /// Единое Keychain-хранилище нормализованных сессий облаков.
    private let keychainStorage = KeychainStorageService.makeDefault()

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

        let account = try await currentAccount()
        await persistSession(for: account)
        return account
    }

    // MARK: - Restore Session

    /// Возвращает аккаунт, если токен Dropbox сохранён в Keychain,
    /// иначе `nil`.
    func restoreConnection() async throws -> CloudStorageAccount? {
        guard DropboxClientsManager.authorizedClient != nil else {
            return nil
        }
        let account = try await currentAccount()
        await persistSession(for: account)
        return account
    }

    func signOut() {
        DropboxClientsManager.unlinkClients()
        Task { try? await keychainStorage.deleteSessions(for: .dropbox) }
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

    /// Дублирует активную Dropbox-сессию в нормализованную
    /// `CloudAccountSession`-запись единого Keychain-хранилища.
    /// Сырые токены SDK уже лежат там же через
    /// `DropboxSecureStorageAccess` — это индекс для
    /// `listAllSessions()` и QR-переноса.
    private func persistSession(for account: CloudStorageAccount) async {
        guard let token = DropboxOAuthManager
            .sharedOAuthManager?
            .getFirstAccessToken(),
            !token.accessToken.isEmpty else {
            return
        }

        let session = CloudAccountSession(
            provider: .dropbox,
            userEmail: account.email,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.tokenExpirationTimestamp.map {
                Date(timeIntervalSince1970: $0)
            }
        )

        do {
            try await keychainStorage.saveSession(session)
        } catch {
            #if DEBUG
            print("[Dropbox] Failed to mirror session to Keychain: \(error)")
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
        #if DEBUG
        print("[Dropbox] API error: \(error)")
        #endif
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
