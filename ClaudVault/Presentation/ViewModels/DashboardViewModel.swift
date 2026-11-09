import Foundation
import Observation
import ClaudVaultDomain

@MainActor
@Observable
final class DashboardViewModel {

    private let fetchBackupRecords: FetchBackupRecordsUseCase

    private(set) var records: [BackupRecord] = []
    private(set) var isLoading = false
    var errorMessage: String?

    var backupCount: Int {
        records.count
    }

    var lastBackupDate: Date? {
        records.map(\.updatedAt).max()
    }

    var recentRecords: [BackupRecord] {
        Array(
            records.sorted(by: { $0.updatedAt > $1.updatedAt })
                .prefix(5)
        )
    }

    init(fetchBackupRecords: FetchBackupRecordsUseCase) {
        self.fetchBackupRecords = fetchBackupRecords
    }

    func loadDashboard() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            records = try fetchBackupRecords.execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
