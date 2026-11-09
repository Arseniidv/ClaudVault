
import Foundation

@MainActor
public final class CalculateStorageUsageUseCase {

    private let repository: BackupMetadataRepository

    public init(repository: BackupMetadataRepository) {
        self.repository = repository
    }

    public func execute() throws -> Int64 {
        do {
            return try repository.calculateUsedStorage()
        } catch {
            throw Error.calculationFailed(underlying: error)
        }
    }

    public enum Error: Swift.Error, LocalizedError {

        case calculationFailed(underlying: Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .calculationFailed:
                return "Не удалось определить размер резервных копий."
            }
        }

        public var failureReason: String? {
            switch self {
            case .calculationFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }
}
