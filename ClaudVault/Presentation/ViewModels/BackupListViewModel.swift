import Observation
import Foundation
import ClaudVaultDomain

@MainActor
@Observable
final class BackupListViewModel {

    // MARK: - Dependencies
    private let fetchBackupRecords: FetchBackupRecordsUseCase
    private let deleteBackupUseCase: DeleteBackupUseCase
    private let calculateStorageUsage: CalculateStorageUsageUseCase
    private let backupMetadataRepository: BackupMetadataRepository

    // MARK: - State Properties
    private(set) var records: [BackupRecord] = []
    private(set) var usedStorageBytes: Int64 = 0
    private(set) var localFilesBytes: Int64 = 0
    /// Размер последней версии каждого бэкапа (id записи → байты).
    /// Используется колонкой «Размер» в macOS-таблице.
    private(set) var recordSizes: [UUID: Int64] = [:]
    private(set) var isLoading = false
    private(set) var isMutating = false
    
    var errorMessage: String?
    var onDataChanged: (() -> Void)?

    
    init(
        fetchBackupRecords: FetchBackupRecordsUseCase,
        deleteBackupUseCase: DeleteBackupUseCase,
        calculateStorageUsage: CalculateStorageUsageUseCase,
        backupMetadataRepository: BackupMetadataRepository
    ) {
        self.fetchBackupRecords = fetchBackupRecords
        self.deleteBackupUseCase = deleteBackupUseCase
        self.calculateStorageUsage = calculateStorageUsage
        self.backupMetadataRepository = backupMetadataRepository
    }

    // MARK: - Computed Properties
    var localFilesCount: Int {
        records.count
    }

    func loadRecords() {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }

        do {
            records = try fetchBackupRecords.execute()
            refreshStorageUsage()
            recomputeLocalStats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRecord(record: BackupRecord) async {
        guard !isMutating else { return }
        isMutating = true
        errorMessage = nil

        do {
            try await deleteBackupUseCase.execute(record: record)
            
           
            loadRecords()
            refreshStorageUsage()
            recomputeLocalStats()

            onDataChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isMutating = false
    }

    func refreshStorageUsage() {
        do {
            usedStorageBytes = try calculateStorageUsage.execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Последняя версия бэкапа — нужна для Quick Look
    /// (скачивание облачного объекта по `cloudObjectID`).
    func latestVersion(for recordID: UUID) -> BackupVersion? {
        try? backupMetadataRepository
            .fetchVersions(for: recordID)
            .first
    }

    private func recomputeLocalStats() {
        var bytes: Int64 = 0
        var sizes: [UUID: Int64] = [:]
        for record in records {
            if let versions = try? backupMetadataRepository.fetchVersions(for: record.id),
               let latest = versions.first {
                bytes += latest.fileSize
                sizes[record.id] = latest.fileSize
            }
        }
        localFilesBytes = bytes
        recordSizes = sizes
    }
}
