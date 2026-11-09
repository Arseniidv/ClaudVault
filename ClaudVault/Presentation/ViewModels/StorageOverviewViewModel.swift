
import Foundation
import Observation
import ClaudVaultDomain

@MainActor
@Observable
final class StorageOverviewViewModel {

    private let calculateStorageUsage: CalculateStorageUsageUseCase

    private(set) var usedStorage: Int64 = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(calculateStorageUsage: CalculateStorageUsageUseCase) {
        self.calculateStorageUsage = calculateStorageUsage
    }

    func loadStorageUsage() {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            usedStorage = try calculateStorageUsage.execute()
        } catch {
            errorMessage = "Не удалось получить размер резервных копий."
        }
    }

    var usedStorageInGB: Double {
        Double(usedStorage) / 1_000_000_000
    }
}
