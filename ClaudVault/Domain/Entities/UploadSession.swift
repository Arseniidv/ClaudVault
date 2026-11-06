import Foundation

struct UploadSession: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let fileURL: URL
    let sessionURL: URL?
    let totalBytes: Int64
    var uploadedBytes: Int64
    var status: SessionStatus
    let createdAt: Date
    var updatedAt: Date

    /// Запись резервной копии, для которой выполняется загрузка.
    var backupRecordID: UUID?

    /// Текст последней ошибки (для статуса .failed).
    var errorMessage: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(uploadedBytes) / Double(totalBytes)
    }

    var progressPercentage: Int {
        Int(progress * 100)
    }
}

enum SessionStatus: String, Equatable {
    case completed
    case pending
    case uploading
    case paused
    case failed
}
