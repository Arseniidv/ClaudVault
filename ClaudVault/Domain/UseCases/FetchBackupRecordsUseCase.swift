import Foundation

@MainActor
struct FetchBackupRecordsUseCase{
    private let repository:BackupMetadataRepository
    init(repository: BackupMetadataRepository) {
        self.repository = repository
    }
    func execute() throws ->[BackupRecord]{
        try repository.fetchRecords()
    }
}
