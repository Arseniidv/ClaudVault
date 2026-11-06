import Foundation

/// Информация о занятом и доступном месте в облачном хранилище.
struct CloudStorageUsage: Equatable {
    let usedBytes: Int64
    let totalBytes: Int64
    let availableBytes: Int64

    var usedGB: Double {
        Double(usedBytes) / 1_000_000_000
    }

    var totalGB: Double {
        Double(totalBytes) / 1_000_000_000
    }

    var availableGB: Double {
        Double(availableBytes) / 1_000_000_000
    }

    var usedBytesInGB: Double {
        usedGB
    }

    var totalBytesInGB: Double {
        totalGB
    }

    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}
