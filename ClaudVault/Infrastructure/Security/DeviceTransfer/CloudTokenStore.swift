import Foundation
import SwiftyDropbox
import GoogleSignIn

/// Сбор и восстановление токенов облачных провайдеров
/// для QR-переноса между устройствами.
///
/// Чтение — только из сессий, принадлежащих `ownerID`:
/// scoped Keychain-записи провайдеров и карта владельцев
/// Dropbox. Токены других пользователей CloudVault в пакет
/// не попадают.
@MainActor
final class CloudTokenStore {

    private let oneDriveTokenStore = OneDriveTokenStore()
    private let googleSessionStore = GoogleSessionStore()
    private let keychainStorage = KeychainStorageService.makeDefault()
    private let dropboxStorage = DropboxSecureStorageAccess()

    // MARK: - Collect

    /// Собирает токены всех подключённых провайдеров владельца
    /// `ownerID`. Провайдер без активной сессии просто не попадает
    /// в пакет.
    func collect(ownerID: String) async -> CloudTokenPayload {
        async let oneDrive = collectOneDrive()
        let dropbox = collectDropbox(ownerID: ownerID)
        let google = await collectGoogle(ownerID: ownerID)
        return await CloudTokenPayload(
            oneDrive: oneDrive,
            dropbox: dropbox,
            google: google
        )
    }

    private func collectOneDrive() -> CloudTokenPayload.OneDriveTokens? {
        guard let tokens = oneDriveTokenStore.load(),
              !tokens.refreshToken.isEmpty else {
            return nil
        }
        return CloudTokenPayload.OneDriveTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
    }

    private func collectDropbox(ownerID: String) -> CloudTokenPayload.DropboxTokens? {
        guard let token = DropboxOAuthManager
            .sharedOAuthManager?
            .getFirstAccessToken(),
            !token.accessToken.isEmpty,
            (try? dropboxStorage.isTokenOwned(
                uid: token.uid,
                ownerID: ownerID
            )) == true else {
            return nil
        }
        return CloudTokenPayload.DropboxTokens(
            accessToken: token.accessToken,
            uid: token.uid,
            refreshToken: token.refreshToken,
            tokenExpirationTimestamp: token.tokenExpirationTimestamp
        )
    }

    private func collectGoogle(ownerID: String) async -> CloudTokenPayload.GoogleTokens? {
        if let user = GIDSignIn.sharedInstance.currentUser,
           !user.refreshToken.tokenString.isEmpty,
           let clientID = GIDSignIn.sharedInstance.configuration?.clientID,
           let email = user.profile?.email,
           await ownsGoogleAccount(email: email, ownerID: ownerID) {
            return CloudTokenPayload.GoogleTokens(
                refreshToken: user.refreshToken.tokenString,
                clientID: clientID,
                userID: user.userID ?? "",
                email: email,
                displayName: user.profile?.name,
                grantedScopes: user.grantedScopes ?? []
            )
        }

        // Fallback: сессия, восстановленная через QR-перенос
        // или экспортированная при смене пользователя.
        // GIDSignIn о ней не знает, токены лежат в GoogleSessionStore.
        guard let session = try? googleSessionStore.load(ownerID: ownerID),
              !session.refreshToken.isEmpty,
              session.grantedScopes.contains(GoogleOAuthManager.driveScope) else {
            return nil
        }
        return CloudTokenPayload.GoogleTokens(
            refreshToken: session.refreshToken,
            clientID: session.clientID,
            userID: session.userID,
            email: session.email,
            displayName: session.displayName,
            grantedScopes: session.grantedScopes
        )
    }

    /// Проверяет, что Google-аккаунт из GIDSignIn записан
    /// за указанным пользователем CloudVault.
    private func ownsGoogleAccount(
        email: String,
        ownerID: String
    ) async -> Bool {
        if await keychainStorage.loadSession(
            for: .googleDrive,
            email: email,
            ownerID: ownerID
        ) != nil {
            return true
        }
        do {
            return try googleSessionStore.load(ownerID: ownerID)?.email == email
        } catch {
            return false
        }
    }

    // MARK: - Restore

    /// Раскладывает токены из пакета по scoped Keychain-хранилищам
    /// текущего пользователя CloudVault (`ownerID`).
    @discardableResult
    func restore(_ payload: CloudTokenPayload, ownerID: String) throws -> [String] {
        // Защита от несовместимых/повреждённых форматов: неизвестная
        // major-версия пакета не должна молча раскладываться по Keychain.
        guard payload.version == 1 else {
            throw DeviceTransferError.unsupportedPayloadVersion
        }
        guard !ownerID.isEmpty else {
            throw DeviceTransferError.notAuthenticated
        }

        var restored: [String] = []

        if let tokens = payload.oneDrive {
            oneDriveTokenStore.save(OneDriveTokenStore.StoredTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: tokens.expiresAt
            ))
            restored.append("OneDrive")
        }

        if let tokens = payload.dropbox {
            try restoreDropbox(tokens, ownerID: ownerID)
            restored.append("Dropbox")
        }

        if let tokens = payload.google {
            // Ошибка записи пробрасывается — иначе UI отрапортовал
            // бы «Google Drive» восстановленным при пустом Keychain.
            try googleSessionStore.save(GoogleRestoredSession(
                refreshToken: tokens.refreshToken,
                clientID: tokens.clientID,
                userID: tokens.userID,
                email: tokens.email,
                displayName: tokens.displayName,
                grantedScopes: tokens.grantedScopes,
                accessToken: nil,
                accessTokenExpiresAt: nil
            ), ownerID: ownerID)
            restored.append("Google Drive")
        }

        return restored
    }

    /// Восстановление Dropbox: кладём полный токен (access + refresh +
    /// expiration) в Keychain-стор SwiftyDropbox. `storeAccessToken`
    /// пишет owner-scoped запись текущего пользователя — отдельный
    /// owner-маппинг больше не нужен. Дальше SDK сам обновляет
    /// access token'ы, а при следующем запуске сессия подхватится
    /// через `setupWithAppKey`/`restoreOwnedClient`.
    private func restoreDropbox(
        _ tokens: CloudTokenPayload.DropboxTokens,
        ownerID: String
    ) throws {
        guard let manager = DropboxOAuthManager.sharedOAuthManager else {
            throw DeviceTransferError.storageFailed
        }
        // Токен будет записан под CurrentUserContext — он обязан
        // совпадать с владельцем, для которого собирали пакет.
        guard CurrentUserContext.shared.ownerID == ownerID else {
            throw DeviceTransferError.notAuthenticated
        }
        let token = DropboxAccessToken(
            accessToken: tokens.accessToken,
            uid: tokens.uid,
            refreshToken: tokens.refreshToken,
            tokenExpirationTimestamp: tokens.tokenExpirationTimestamp
        )
        guard manager.storeAccessToken(token) else {
            throw DeviceTransferError.storageFailed
        }
        DropboxClientsManager.authorizedClient = DropboxClient(
            accessTokenProvider: manager.accessTokenProviderForToken(token),
            sessionConfiguration: .default
        )
    }
}
