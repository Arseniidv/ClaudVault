
import Foundation

public struct BackupRecord: Identifiable, Equatable, Codable {

    public let id: UUID

    public var fileName: String
    public var sourceIdentifier: String

    public let createdAt: Date
    public var updatedAt: Date

    public var input: String
    public var storageProvider: StorageProviderType

    /// Путь к исходному файлу на диске (для отображения).
    public var localFilePath: String?

    /// Security-scoped bookmark (base64) исходного файла —
    /// позволяет повторно получить доступ к файлу после перезапуска.
    public var localFileBookmark: String?

    public init(
        id: UUID = UUID(),
        input: String = "",
        fileName: String,
        sourceIdentifier: String,
        storageProvider: StorageProviderType = .unknown,
        localFilePath: String? = nil,
        localFileBookmark: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.input = input
        self.fileName = fileName
        self.sourceIdentifier = sourceIdentifier
        self.storageProvider = storageProvider
        self.localFilePath = localFilePath
        self.localFileBookmark = localFileBookmark
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
