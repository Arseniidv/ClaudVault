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

    public init(
        provider: CloudProviderType,
        userEmail: String,
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.provider = provider
        self.userEmail = userEmail
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}
