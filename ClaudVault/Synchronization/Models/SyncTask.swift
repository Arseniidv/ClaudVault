import Foundation

enum SyncTaskStatus {
    case transferring
    case completed
    case failed
}

struct SyncTask: Identifiable {
    let id: UUID

    let fileName: String
    let source: String
    let destination: String
    let progress: Double
    let transferredSize: Double
    let totalSize: Double
    let speed: Double
    let remainingTime: String
    let status: SyncTaskStatus

    init(
        id: UUID = UUID(),
        fileName: String,
        source: String,
        destination: String,
        progress: Double,
        transferredSize: Double,
        totalSize: Double,
        speed: Double,
        remainingTime: String,
        status: SyncTaskStatus
    ) {
        self.id = id
        self.fileName = fileName
        self.source = source
        self.destination = destination
        self.progress = progress
        self.transferredSize = transferredSize
        self.totalSize = totalSize
        self.speed = speed
        self.remainingTime = remainingTime
        self.status = status
    }
}
