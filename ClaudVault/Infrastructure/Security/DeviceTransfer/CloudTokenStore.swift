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
            dropboxStorage.owner(ofDropboxUID: token.uid) == ownerID else {
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
        guard let session = googleSessionStore.load(ownerID: ownerID),
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
        return googleSessionStore.load(ownerID: ownerID)?.email == email
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
            restoreDropbox(tokens, ownerID: ownerID)
            restored.append("Dropbox")
        }

        if let tokens = payload.google {
            googleSessionStore.save(GoogleRestoredSession(
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

    /// Восстановление Dropbox: кладём refresh-токен в Keychain-стор
    /// SwiftyDropbox, фиксируем владельца и поднимаем authorizedClient —
    /// дальше SDK сам обновляет access token'ы, а при следующем
    /// запуске сессия подхватится через `setupWithAppKey` для
    /// пользователей с записью о владельце.
    private func restoreDropbox(
        _ tokens: CloudTokenPayload.DropboxTokens,
        ownerID: String
    ) {
        guard let manager = DropboxOAuthManager.sharedOAuthManager else {
            return
        }
        let token = DropboxAccessToken(
            accessToken: tokens.accessToken,
            uid: tokens.uid,
            refreshToken: tokens.refreshToken,
            tokenExpirationTimestamp: tokens.tokenExpirationTimestamp
        )
        dropboxStorage.setOwner(ownerID, forDropboxUID: token.uid)
        _ = manager.storeAccessToken(token)
        DropboxClientsManager.authorizedClient = DropboxClient(
            accessToken: token,
            dropboxOauthManager: manager
        )
    }
}
