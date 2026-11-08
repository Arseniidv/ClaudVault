import Foundation

struct BackupVersion: Identifiable, Equatable, Codable {
    let id: UUID
    let backupRecordID: UUID

    let fileSize: Int64
    let checksum: String
    /// `var`: у Dropbox id — это путь файла, после переименования
    /// (`renameFile`) он меняется и сохраняется обратно в метаданные.
    var cloudObjectID: String
    let uploadedAt: Date

    init(
        id: UUID = UUID(),
        backupRecordID: UUID,
        fileSize: Int64,
        checksum: String,
        cloudObjectID: String,
        uploadedAt: Date = .now
    ) {
        self.id = id
        self.backupRecordID = backupRecordID
        self.fileSize = fileSize
        self.checksum = checksum
        self.cloudObjectID = cloudObjectID
        self.uploadedAt = uploadedAt
    }
}
