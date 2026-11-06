import Foundation

struct BackupJob: Identifiable, Equatable {

    enum Status: String, Codable {
        case queued
        case preparing
        case uploading
        case savingMetadata
        case completed
        case failed
        case cancelled
    }

    let id: UUID

    let startedAt: Date

    var finishedAt: Date?

    var status: Status

    var progress: Double

    var errorMessage: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        status: Status = .queued,
        progress: Double = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.progress = min(max(progress, 0), 1)
        self.errorMessage = errorMessage
    }
}
