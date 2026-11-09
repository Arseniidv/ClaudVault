import Foundation
import OSLog
import SwiftyDropbox
import ClaudVaultDomain

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

    private static let logger = Logger(
        subsystem: "ClaudVault",
        category: "dropbox-auth"
    )

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
    /// Владелец, инициировавший OAuth-флоу. SDK сохраняет токен в
    /// `handleRedirectURL` до нашего continuation — без этой проверки
    /// редирект, пришедший после смены пользователя, записал бы
    /// Dropbox-токен под чужим ownerID.
    private var pendingAuthOwnerID: String?

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
        guard let ownerID = currentOwnerID, !ownerID.isEmpty else {
            throw CloudStorageError.notConnected
        }

        if DropboxClientsManager.authorizedClient != nil {
            if currentClientIsOwned() {
                do {
                    let account = try await currentAccount()
                    try requireOwner(ownerID)
                    await persistSession(for: account, ownerID: ownerID)
                    return account
                } catch let error as CloudStorageError
                            where error == .unauthorized {
                    // Подтверждённый отказ авторизации (в т.ч. revoked
                    // refresh token): удаляем только этот токен и
                    // запускаем OAuth заново.
                    discardInvalidToken()
                } catch {
                    throw error
                }
            } else {
                DropboxClientsManager.resetClients()
            }
        }

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

        try requireOwner(ownerID)
        do {
            try requireDurableStoredToken()
        } catch {
            // OAuth вернул токен без refresh/expiration — такая
            // «сессия» не переживёт истечение access token.
            DropboxClientsManager.resetClients()
            throw error
        }

        let account = try await currentAccount()
        try requireOwner(ownerID)
        await persistSession(for: account, ownerID: ownerID)
        return account
    }

    // MARK: - Restore Session

    /// Возвращает аккаунт, если у текущего пользователя сохранён
    /// durable Dropbox-токен (access + refresh + expiration),
    /// иначе `nil`. Токены других пользователей CloudVault не
    /// подхватываются.
    func restoreConnection() async throws -> CloudStorageAccount? {
        guard let ownerID = currentOwnerID, !ownerID.isEmpty else {
            return nil
        }

        // In-memory клиент мог остаться от прежнего пользователя
        // или быть повреждённым: сбрасываем и пробуем восстановить
        // owned-токен из Keychain, а не сдаёмся с nil.
        if DropboxClientsManager.authorizedClient != nil,
           !currentClientIsOwned() {
            DropboxClientsManager.resetClients()
        }
        if DropboxClientsManager.authorizedClient == nil {
            try restoreOwnedClient()
        }

        guard DropboxClientsManager.authorizedClient != nil,
              currentClientIsOwned() else {
            return nil
        }

        let account: CloudStorageAccount
        do {
            account = try await currentAccount()
        } catch let error as CloudStorageError
                    where error == .unauthorized {
            // Refresh token отозван/истёк: credentials бесполезны,
            // удаляем только этот UID и сообщаем «не подключено».
            discardInvalidToken()
            return nil
        } catch {
            throw error
        }

        // За время сетевого запроса пользователь мог смениться —
        // не зеркалируем чужой аккаунт под новым владельцем.
        guard currentOwnerID == ownerID else {
            DropboxClientsManager.resetClients()
            return nil
        }

        await persistSession(for: account, ownerID: ownerID)
        return account
    }

    /// Отключение Dropbox текущим пользователем: удаляет только
    /// ЕГО токены и scoped-записи. `unlinkClients()` не подходит —
    /// он вызывает `deleteInfoForAllKeys` и стёр бы токены
    /// других пользователей CloudVault.
    func signOut() async throws {
        let ownerID = currentOwnerID
        for uid in try secureStorage.ownedUserIds() {
            try secureStorage.deleteOwnedToken(for: uid)
        }
        DropboxClientsManager.resetClients()
        if let ownerID {
            try await keychainStorage.deleteSessions(
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

    /// Восстанавливает authorizedClient из durable-токена,
    /// принадлежащего текущему пользователю. Вызывается из
    /// `restoreConnection` и при активации пользователя, если SDK
    /// не поднял клиент сам (например, на старте приложение
    /// инициализировалось до восстановления Firebase-сессии).
    func restoreOwnedClient() throws {
        guard DropboxClientsManager.authorizedClient == nil,
              let manager = DropboxOAuthManager.sharedOAuthManager else {
            return
        }
        for uid in try secureStorage.ownedUserIds() {
            guard let token = try secureStorage.loadOwnedAccessToken(for: uid),
                  token.refreshToken != nil,
                  token.tokenExpirationTimestamp != nil else {
                continue
            }
            DropboxClientsManager.authorizedClient = DropboxClient(
                accessTokenProvider: manager.accessTokenProviderForToken(token),
                sessionConfiguration: .default
            )
            return
        }
    }

    /// Проверяет, что активный authorizedClient соответствует
    /// токену, доступному текущему пользователю CloudVault.
    /// Scoped-хранилище само отсекает чужие записи.
    private func currentClientIsOwned() -> Bool {
        guard currentOwnerID != nil,
              let token = DropboxOAuthManager.sharedOAuthManager?
                .getFirstAccessToken() else {
            return false
        }
        return (try? secureStorage.loadOwnedAccessToken(for: token.uid)) != nil
    }

    // MARK: - URL Handling

    /// Вызывается из `onOpenURL`. Возвращает `true`, если URL относится к Dropbox OAuth.
    @discardableResult
    func handleRedirectURL(_ url: URL) -> Bool {
        // Перехватываем только OAuth-редиректы Dropbox
        // (схема db-<appKey>) — остальные URL (Google, OneDrive,
        // QR-перенос) обрабатываются своими менеджерами.
        guard url.scheme == Self.redirectScheme else { return false }

        // Редирект belongs OAuth-флоу, начатому другим
        // пользователем CloudVault: не передаём его в SDK, иначе
        // `storeAccessToken` записал бы токен под текущим ownerID.
        if pendingAuth != nil,
           let expectedOwnerID = pendingAuthOwnerID,
           expectedOwnerID != CurrentUserContext.shared.ownerID {
            resumePendingAuth(with: nil)
            return true
        }

        return DropboxClientsManager.handleRedirectURL(
            url,
            includeBackgroundClient: false,
            sessionConfiguration: .default
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
        pendingAuthOwnerID = nil
        pendingAuth?.resume(returning: result)
        pendingAuth = nil
    }

    private func authorize() async -> DropboxOAuthResult? {
        // Незавершённый флоу (повторный тап «Подключить») не должен
        // оставлять свой continuation висеть — завершаем его.
        resumePendingAuth(with: nil)

        return await withCheckedContinuation { continuation in
            pendingAuth = continuation
            pendingAuthOwnerID = currentOwnerID
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
    /// Сырые токены SDK уже лежат в owner-scoped записях через
    /// `DropboxSecureStorageAccess` — это индекс для
    /// `listAllSessions()` и QR-переноса. `ownerID` передаётся
    /// явно: контекст мог смениться за время сетевого запроса.
    private func persistSession(
        for account: CloudStorageAccount,
        ownerID: String
    ) async {
        guard !ownerID.isEmpty else { return }

        do {
            guard let token = try currentOwnedAccessToken(
                preferredUID: account.id
            ), !token.accessToken.isEmpty else {
                return
            }

            let session = CloudAccountSession(
                provider: .dropbox,
                userEmail: account.email,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: token.tokenExpirationTimestamp.map {
                    Date(timeIntervalSince1970: $0)
                },
                ownerID: ownerID
            )

            try await keychainStorage.saveSession(session)
        } catch {
            // Зеркало нужно для QR-переноса и списка сессий; сама
            // Dropbox-авторизация уже сохранена SDK в scoped Keychain.
            // Токены в лог не пишем.
            Self.logger.error(
                "Failed to mirror Dropbox session: \(error.localizedDescription)"
            )
        }
    }

    /// Токен текущего владельца: сначала по Dropbox account id,
    /// затем по первому токену, видимому SDK для этого владельца.
    private func currentOwnedAccessToken(
        preferredUID: String
    ) throws -> DropboxAccessToken? {
        if !preferredUID.isEmpty,
           let token = try secureStorage.loadOwnedAccessToken(
               for: preferredUID
           ) {
            return token
        }
        if let first = DropboxOAuthManager.sharedOAuthManager?
            .getFirstAccessToken(),
           let token = try secureStorage.loadOwnedAccessToken(
               for: first.uid
           ) {
            return token
        }
        return nil
    }

    /// После OAuth/восстановления убеждаемся, что токен —
    /// полноценный short-lived: без refresh+expiration SDK создал
    /// бы long-lived provider и сессия не пережила бы истечение.
    private func requireDurableStoredToken() throws {
        guard let token = try currentOwnedAccessToken(preferredUID: "")
        else {
            throw CloudStorageError.operationFailed(
                "Dropbox не вернул сохранённый токен сессии."
            )
        }
        guard token.refreshToken != nil,
              token.tokenExpirationTimestamp != nil else {
            throw CloudStorageError.operationFailed(
                "Dropbox не вернул refresh token. Подключите аккаунт заново."
            )
        }
    }

    private func requireOwner(_ ownerID: String) throws {
        guard currentOwnerID == ownerID else {
            throw CloudStorageError.cancelled
        }
    }

    /// Удаляет токен, подтверждённо отклонённый Dropbox (auth error
    /// после refresh). Ошибка удаления не должна мешать сообщить
    /// пользователю «не подключено» — при следующем входе cleanup
    /// повторится.
    private func discardInvalidToken() {
        if let uid = DropboxOAuthManager.sharedOAuthManager?
            .getFirstAccessToken()?.uid {
            try? secureStorage.deleteOwnedToken(for: uid)
        }
        DropboxClientsManager.resetClients()
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
    nonisolated static func mapError<E>(_ error: CallError<E>) -> CloudStorageError {
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
