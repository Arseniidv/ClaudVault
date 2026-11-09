import Foundation

public struct UploadSession: Identifiable, Equatable {
    public let id: UUID
    public let fileName: String
    public let fileURL: URL
    public let sessionURL: URL?
    public let totalBytes: Int64
    public var uploadedBytes: Int64
    public var status: SessionStatus
    public let createdAt: Date
    public var updatedAt: Date

    /// Запись резервной копии, для которой выполняется загрузка.
    public var backupRecordID: UUID?

    /// Текст последней ошибки (для статуса .failed).
    public var errorMessage: String?

    public init(
        id: UUID,
        fileName: String,
        fileURL: URL,
        sessionURL: URL?,
        totalBytes: Int64,
        uploadedBytes: Int64,
        status: SessionStatus,
        createdAt: Date,
        updatedAt: Date,
        backupRecordID: UUID? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.sessionURL = sessionURL
        self.totalBytes = totalBytes
        self.uploadedBytes = uploadedBytes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.backupRecordID = backupRecordID
        self.errorMessage = errorMessage
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(uploadedBytes) / Double(totalBytes)
    }

    public var progressPercentage: Int {
        Int(progress * 100)
    }
}

public enum SessionStatus: String, Equatable {
    case completed
    case pending
    case uploading
    case paused
    case failed
}
