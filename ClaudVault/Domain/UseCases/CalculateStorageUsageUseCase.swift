
import Foundation

@MainActor
final class CalculateStorageUsageUseCase {

    private let repository: BackupMetadataRepository

    init(repository: BackupMetadataRepository) {
        self.repository = repository
    }

    func execute() throws -> Int64 {
        do {
            return try repository.calculateUsedStorage()
        } catch {
            throw Error.calculationFailed(underlying: error)
        }
    }

    enum Error: Swift.Error, LocalizedError {

        case calculationFailed(underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .calculationFailed:
                return "Не удалось определить размер резервных копий."
            }
        }

        var failureReason: String? {
            switch self {
            case .calculationFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }
}
