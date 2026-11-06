import Foundation

@MainActor
struct SaveBackupVersionUseCase{
    private let repository:BackupMetadataRepository
    
    init(repository: BackupMetadataRepository) {
        self.repository = repository
    }
    func execute(_version:BackupVersion) throws{
        try repository.saveVersion(_version)
    }
}
