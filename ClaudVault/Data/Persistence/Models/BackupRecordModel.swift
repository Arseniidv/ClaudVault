import Foundation
import SwiftData

@Model
final class BackupRecordModel {

    @Attribute(.unique)
    var id: UUID

    var fileName: String
    var sourceIdentifier: String

    var createdAt: Date
    var updatedAt: Date

    var storageProviderRaw: String?
    var localFilePath: String?
    var localFileBookmark: String?

    @Relationship(
        deleteRule: .cascade,
        inverse: \BackupVersionModel.backupRecord
    )
    var versions: [BackupVersionModel] = []

    init(
        id: UUID = UUID(),
        fileName: String,
        sourceIdentifier: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        storageProviderRaw: String? = nil,
        localFilePath: String? = nil,
        localFileBookmark: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.sourceIdentifier = sourceIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.storageProviderRaw = storageProviderRaw
        self.localFilePath = localFilePath
        self.localFileBookmark = localFileBookmark
    }
}
