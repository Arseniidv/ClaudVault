import Foundation
import SwiftData
import ClaudVaultDomain

@Model
final class UploadSessionModel {

    @Attribute(.unique)
    var id: UUID

    var fileName: String
    var fileURL: String
    var sessionURL: String
    var totalBytes: Int64
    var uploadedBytes: Int64
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var backupRecordID: UUID?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        fileURL: String,
        sessionURL: String,
        totalBytes: Int64,
        uploadedBytes: Int64 = 0,
        status: SessionStatus = .pending,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        backupRecordID: UUID? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.sessionURL = sessionURL
        self.totalBytes = totalBytes
        self.uploadedBytes = uploadedBytes
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.backupRecordID = backupRecordID
        self.errorMessage = errorMessage
    }
}
