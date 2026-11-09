import Foundation

/// Информация о занятом и доступном месте в облачном хранилище.
public struct CloudStorageUsage: Equatable {
    public let usedBytes: Int64
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(usedBytes: Int64, totalBytes: Int64, availableBytes: Int64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public var usedGB: Double {
        Double(usedBytes) / 1_000_000_000
    }

    public var totalGB: Double {
        Double(totalBytes) / 1_000_000_000
    }

    public var availableGB: Double {
        Double(availableBytes) / 1_000_000_000
    }

    public var usedBytesInGB: Double {
        usedGB
    }

    public var totalBytesInGB: Double {
        totalGB
    }

    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}
