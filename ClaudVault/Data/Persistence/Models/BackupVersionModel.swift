import Foundation
import SwiftData
import ClaudVaultDomain

@Model
final class BackupVersionModel {

    @Attribute(.unique)
    var id: UUID

    var fileSize: Int64
    var checksum: String
    var cloudObjectID: String
    var uploadedAt: Date

    var backupRecord: BackupRecordModel?

    init(
        id: UUID = UUID(),
        fileSize: Int64,
        checksum: String,
        cloudObjectID: String,
        uploadedAt: Date = .now,
        backupRecord: BackupRecordModel? = nil
    ) {
        self.id = id
        self.fileSize = fileSize
        self.checksum = checksum
        self.cloudObjectID = cloudObjectID
        self.uploadedAt = uploadedAt
        self.backupRecord = backupRecord
    }
}
