
import Foundation

@MainActor
struct FetchBackupVersionsUseCase {

    private let repository: BackupMetadataRepository

    init(repository: BackupMetadataRepository) {
        self.repository = repository
    }

    func execute(for recordID: UUID) throws -> [BackupVersion] {
        try repository.fetchVersions(for: recordID)
    }
}
