import Foundation

public struct BackupJob: Identifiable, Equatable {

    public enum Status: String, Codable {
        case queued
        case preparing
        case uploading
        case savingMetadata
        case completed
        case failed
        case cancelled
    }

    public let id: UUID

    public let startedAt: Date

    public var finishedAt: Date?

    public var status: Status

    public var progress: Double

    public var errorMessage: String?

    public init(
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
