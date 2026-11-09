import Foundation
import SwiftData

@Model
final class BackupVersionModel {

    @Attribute(.unique)
    var id: UUID

    var fileSize: Int64
    var checksum: String
    var cloudObjectID: String
    var uploadedAt: Date

    /// Владелец записи — пользователь CloudVault.
    var ownerID: String

    var backupRecord: BackupRecordModel?

    init(
        id: UUID = UUID(),
        fileSize: Int64,
        checksum: String,
        cloudObjectID: String,
        uploadedAt: Date = .now,
        backupRecord: BackupRecordModel? = nil,
        ownerID: String = ""
    ) {
        self.id = id
        self.fileSize = fileSize
        self.checksum = checksum
        self.cloudObjectID = cloudObjectID
        self.uploadedAt = uploadedAt
        self.backupRecord = backupRecord
        self.ownerID = ownerID
    }
}
