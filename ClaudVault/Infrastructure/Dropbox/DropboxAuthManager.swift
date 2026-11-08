import Foundation
import SwiftyDropbox

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
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

    /// Продолжение текущего OAuth-флоу. Завершается в `handleRedirectURL`
    /// или по таймауту — иначе отмена браузерного флоу вешала бы
    /// `connect()` навсегда.
    private var pendingAuth: CheckedContinuation<DropboxOAuthResult?, Never>?

    /// `true`, пока идёт OAuth-флоу через внешний системный браузер.
    /// В отличие от Google/OneDrive (ASWebAuthenticationSession внутри
    /// приложения), Dropbox открывает браузер — приложение уходит в
    /// `inactive`/`background`. Пока флаг поднят, RootView не должен
    /// блокировать приложение по scenePhase: иначе при возврате из
    /// браузера пользователь проходил бы повторную разблокировку
    /// CloudVault, хотя Firebase-сессия всё это время остаётся активной.
    private(set) var isExternalAuthorizationInProgress = false
    /// Задача таймаута OAuth-флоу; отменяется при получении редиректа.
    private var authTimeoutTask: Task<Void, Never>?

    /// Максимальное время ожидания OAuth-редиректа от Dropbox.
    /// Пользователь может не успеть войти в аккаунт в системном
    /// браузере — по истечении `authorize()` возвращает nil,
    /// а `connect()` бросает `operationFailed`.
    private static let authTimeout: TimeInterval = 120

    /// Единое Keychain-хранилище нормализованных сессий облаков.
    private let keychainStorage = KeychainStorageService.makeDefault()
    /// Мост к Keychain-токенам SDK и карте владельцев Dropbox UID.
    private let secureStorage = DropboxSecureStorageAccess()

    /// Текущий пользователь CloudVault; nil — сеанса нет.
    private var currentOwnerID: String? {
        CurrentUserContext.shared.ownerID
    }

    // MARK: - Connect

    /// Запускает авторизацию Dropbox, если сессия ещё не восстановлена.
    /// Возвращает данные аккаунта.
    func connect() async throws -> CloudStorageAccount {
        // In-memory клиент может принадлежать другому
        // пользователю CloudVault — сбрасываем перед входом.
        if DropboxClientsManager.authorizedClient != nil,
           !currentClientIsOwned() {
            DropboxClientsManager.resetClients()
        }

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

    /// Возвращает аккаунт, если токен Dropbox текущего пользователя
    /// сохранён, иначе `nil`. Токены других пользователей
    /// CloudVault не подхватываются.
    func restoreConnection() async throws -> CloudStorageAccount? {
        if DropboxClientsManager.authorizedClient == nil {
            restoreOwnedClient()
        }

        guard DropboxClientsManager.authorizedClient != nil,
              currentClientIsOwned() else {
            DropboxClientsManager.resetClients()
            return nil
        }
        let account = try await currentAccount()
        await persistSession(for: account)
        return account
    }

    /// Отключение Dropbox текущим пользователем: удаляет только
    /// ЕГО токены и scoped-записи. `unlinkClients()` не подходит —
    /// он вызывает `deleteInfoForAllKeys` и стёр бы токены
    /// других пользователей CloudVault.
    func signOut() {
        for uid in secureStorage.ownedUserIds() {
            // deleteInfo удаляет и токен SDK (`dropbox-sdk|<uid>`),
            // и запись о владельце (`dropbox-owner|<uid>`) —
            // clearStoredAccessToken сводится к тому же deleteInfo.
            _ = secureStorage.deleteInfo(for: uid)
        }
        DropboxClientsManager.resetClients()
        guard let ownerID = currentOwnerID else { return }
        Task {
            try? await keychainStorage.deleteSessions(
                for: .dropbox,
                ownerID: ownerID
            )
        }
    }

    /// Очистка только in-memory клиента Dropbox при смене
    /// пользователя CloudVault. Токены в Keychain сохраняются —
    /// они привязаны к ownerID и недоступны другому аккаунту.
    func clearInMemoryClients() {
        DropboxClientsManager.resetClients()
    }

    /// Восстанавливает authorizedClient из токена, принадлежащего
    /// текущему пользователю. Вызывается из `restoreConnection`
    /// и при активации пользователя, если SDK не поднял клиент
    /// сам (например, на старте приложение инициализировалось
    /// до восстановления Firebase-сессии).
    func restoreOwnedClient() {
        guard DropboxClientsManager.authorizedClient == nil,
              let manager = DropboxOAuthManager.sharedOAuthManager else {
            return
        }
        for uid in secureStorage.ownedUserIds() {
            guard let token = secureStorage.getDropboxAccessToken(for: uid)
            else { continue }
            _ = manager.storeAccessToken(token)
            DropboxClientsManager.authorizedClient = DropboxClient(
                accessToken: token,
                dropboxOauthManager: manager
            )
            return
        }
    }

    /// Проверяет, что активный authorizedClient принадлежит
    /// текущему пользователю CloudVault — по карте владельцев
    /// `dropbox-owner|<uid>`.
    private func currentClientIsOwned() -> Bool {
        guard let ownerID = currentOwnerID,
              let token = DropboxOAuthManager.sharedOAuthManager?
                .getFirstAccessToken() else {
            return false
        }
        return secureStorage.owner(ofDropboxUID: token.uid) == ownerID
    }

    // MARK: - URL Handling

    /// Вызывается из `onOpenURL`. Возвращает `true`, если URL относится к Dropbox OAuth.
    @discardableResult
    func handleRedirectURL(_ url: URL) -> Bool {
        // Перехватываем только OAuth-редиректы Dropbox
        // (схема db-<appKey>) — остальные URL (Google, OneDrive,
        // QR-перенос) обрабатываются своими менеджерами.
        guard url.scheme == Self.redirectScheme else { return false }
        return DropboxClientsManager.handleRedirectURL(
            url,
            includeBackgroundClient: false
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.resumePendingAuth(with: result)
            }
        }
    }

    // MARK: - Private

    /// URL-схема OAuth-редиректа Dropbox: `db-<appKey>`
    /// (зарегистрирована в Info.plist).
    private static var redirectScheme: String {
        "db-\(appKey)"
    }

    /// Единая точка завершения pending-флоу: снимает таймаут
    /// и возобновляет continuation ровно один раз.
    private func resumePendingAuth(with result: DropboxOAuthResult?) {
        isExternalAuthorizationInProgress = false
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        pendingAuth?.resume(returning: result)
        pendingAuth = nil
    }

    private func authorize() async -> DropboxOAuthResult? {
        // Незавершённый флоу (повторный тап «Подключить») не должен
        // оставлять свой continuation висеть — завершаем его.
        resumePendingAuth(with: nil)

        return await withCheckedContinuation { continuation in
            pendingAuth = continuation
            isExternalAuthorizationInProgress = true

            // Страховка от зависания: если редирект не пришёл
            // (браузер закрыт, `onOpenURL` не сработал),
            // завершаем флоу nil → `connect()` бросит ошибку.
            authTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.authTimeout * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                self?.resumePendingAuth(with: nil)
            }

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
        guard let ownerID = currentOwnerID else { return }

        // Dropbox UID совпадает с account_id аккаунта — фиксируем
        // владельца ДО чтения токена: getFirstAccessToken() видит
        // только токены с записью о владельце.
        secureStorage.setOwner(ownerID, forDropboxUID: account.id)

        guard let token = secureStorage.getDropboxAccessToken(
            for: account.id
        ) ?? DropboxOAuthManager.sharedOAuthManager?.getFirstAccessToken(),
            !token.accessToken.isEmpty else {
            return
        }

        // На случай расхождения account_id и token.uid помечаем
        // владельцем и фактический UID токена.
        secureStorage.setOwner(ownerID, forDropboxUID: token.uid)

        let session = CloudAccountSession(
            provider: .dropbox,
            userEmail: account.email,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.tokenExpirationTimestamp.map {
                Date(timeIntervalSince1970: $0)
            },
            ownerID: currentOwnerID ?? ""
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
