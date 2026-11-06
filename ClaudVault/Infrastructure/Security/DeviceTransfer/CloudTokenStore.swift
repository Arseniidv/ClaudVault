import Foundation
import SwiftyDropbox
import GoogleSignIn

/// Сбор и восстановление токенов облачных провайдеров
/// для QR-переноса между устройствами.
///
/// Чтение — только из уже авторизованных сессий SDK
/// (Keychain SwiftyDropbox / GIDSignIn / OneDriveTokenStore).
@MainActor
final class CloudTokenStore {

    private let oneDriveTokenStore = OneDriveTokenStore()
    private let googleSessionStore = GoogleSessionStore()

    // MARK: - Collect

    /// Собирает токены всех подключённых провайдеров.
    /// Провайдер без активной сессии просто не попадает в пакет.
    func collect() -> CloudTokenPayload {
        CloudTokenPayload(
            oneDrive: collectOneDrive(),
            dropbox: collectDropbox(),
            google: collectGoogle()
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

    private func collectDropbox() -> CloudTokenPayload.DropboxTokens? {
        guard let token = DropboxOAuthManager
            .sharedOAuthManager?
            .getFirstAccessToken(),
            !token.accessToken.isEmpty else {
            return nil
        }
        return CloudTokenPayload.DropboxTokens(
            accessToken: token.accessToken,
            uid: token.uid,
            refreshToken: token.refreshToken,
            tokenExpirationTimestamp: token.tokenExpirationTimestamp
        )
    }

    private func collectGoogle() -> CloudTokenPayload.GoogleTokens? {
        if let user = GIDSignIn.sharedInstance.currentUser,
           !user.refreshToken.tokenString.isEmpty,
           let clientID = GIDSignIn.sharedInstance.configuration?.clientID,
           let email = user.profile?.email {
            return CloudTokenPayload.GoogleTokens(
                refreshToken: user.refreshToken.tokenString,
                clientID: clientID,
                userID: user.userID ?? "",
                email: email,
                displayName: user.profile?.name,
                grantedScopes: user.grantedScopes ?? []
            )
        }

        // Fallback: сессия, восстановленная через QR-перенос.
        // GIDSignIn о ней не знает, токены лежат в GoogleSessionStore.
        guard let session = googleSessionStore.load(),
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

    // MARK: - Restore

    /// Раскладывает токены из пакета по Keychain-хранилищам
    /// соответствующих провайдеров.
    @discardableResult
    func restore(_ payload: CloudTokenPayload) throws -> [String] {
        // Защита от несовместимых/повреждённых форматов: неизвестная
        // major-версия пакета не должна молча раскладываться по Keychain.
        guard payload.version == 1 else {
            throw DeviceTransferError.unsupportedPayloadVersion
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
            restoreDropbox(tokens)
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
            ))
            restored.append("Google Drive")
        }

        return restored
    }

    /// Восстановление Dropbox: кладём refresh-токен в Keychain-стор
    /// SwiftyDropbox и поднимаем authorizedClient — дальше SDK сам
    /// обновляет access token'ы, а при следующем запуске сессия
    /// подхватится через `setupWithAppKey`.
    private func restoreDropbox(_ tokens: CloudTokenPayload.DropboxTokens) {
        guard let manager = DropboxOAuthManager.sharedOAuthManager else {
            return
        }
        let token = DropboxAccessToken(
            accessToken: tokens.accessToken,
            uid: tokens.uid,
            refreshToken: tokens.refreshToken,
            tokenExpirationTimestamp: tokens.tokenExpirationTimestamp
        )
        _ = manager.storeAccessToken(token)
        DropboxClientsManager.authorizedClient = DropboxClient(
            accessToken: token,
            dropboxOauthManager: manager
        )
    }
}
