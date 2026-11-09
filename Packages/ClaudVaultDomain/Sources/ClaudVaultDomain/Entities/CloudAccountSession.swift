import Foundation

public nonisolated enum CloudProviderType: String, Codable, CaseIterable {
    case googleDrive = "google_drive"
    case dropbox = "dropbox"
    case oneDrive = "onedrive"
}

public nonisolated struct CloudAccountSession: Codable, Equatable {
    public let provider: CloudProviderType
    public let userEmail: String
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    /// Идентификатор пользователя CloudVault (владельца сессии).
    /// Пустая строка — записи, сохранённые до введения изоляции
    /// аккаунтов; они не выдаются ни одному пользователю и
    /// мигрируются `KeychainStorageService.claimLegacySessions`.
    public var ownerID: String

    public init(
        provider: CloudProviderType,
        userEmail: String,
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        ownerID: String = ""
    ) {
        self.provider = provider
        self.userEmail = userEmail
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.ownerID = ownerID
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case userEmail
        case accessToken
        case refreshToken
        case expiresAt
        case ownerID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(CloudProviderType.self, forKey: .provider)
        userEmail = try container.decode(String.self, forKey: .userEmail)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        // Записи старого формата без ownerID декодируются с ""
        // и дальше обрабатываются миграцией.
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID) ?? ""
    }
}
