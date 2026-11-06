import Foundation

@MainActor
struct DeleteBackupRecordUseCase{
    private let repository:BackupMetadataRepository
    init(repository: BackupMetadataRepository) {
        self.repository = repository
    }
    func execute(id:UUID) throws{
        try repository.deleteRecord(id: id)
    }
}
