import Foundation

/// Пакет токенов облачных провайдеров для переноса между устройствами.
///
/// Сериализуется в JSON и шифруется AES.GCM (ключ из ECDH-обмена
/// через `QRVerificationService`) до отправки в Firestore —
/// в открытом виде токены по сети не передаются.
struct CloudTokenPayload: Codable {
    var version: Int
    var exportedAt: Date
    var oneDrive: OneDriveTokens?
    var dropbox: DropboxTokens?
    var google: GoogleTokens?

    init(
        version: Int = 1,
        exportedAt: Date = Date(),
        oneDrive: OneDriveTokens? = nil,
        dropbox: DropboxTokens? = nil,
        google: GoogleTokens? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.oneDrive = oneDrive
        self.dropbox = dropbox
        self.google = google
    }

    struct OneDriveTokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    struct DropboxTokens: Codable {
        var accessToken: String
        var uid: String
        var refreshToken: String?
        var tokenExpirationTimestamp: TimeInterval?
    }

    struct GoogleTokens: Codable {
        var refreshToken: String
        var clientID: String
        var userID: String
        var email: String
        var displayName: String?
        var grantedScopes: [String]
    }
}
