
import Foundation

struct BackupRecord: Identifiable, Equatable, Codable {

    let id: UUID

    var fileName: String
    var sourceIdentifier: String

    let createdAt: Date
    var updatedAt: Date

    var input: String
    var storageProvider: StorageProviderType

    /// Путь к исходному файлу на диске (для отображения).
    var localFilePath: String?

    /// Security-scoped bookmark (base64) исходного файла —
    /// позволяет повторно получить доступ к файлу после перезапуска.
    var localFileBookmark: String?

    init(
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
