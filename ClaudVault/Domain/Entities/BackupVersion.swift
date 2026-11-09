import Foundation

public struct BackupVersion: Identifiable, Equatable, Codable {
    public let id: UUID
    public let backupRecordID: UUID

    public let fileSize: Int64
    public let checksum: String
    /// `var`: у Dropbox id — это путь файла, после переименования
    /// (`renameFile`) он меняется и сохраняется обратно в метаданные.
    public var cloudObjectID: String
    public let uploadedAt: Date

    public init(
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
