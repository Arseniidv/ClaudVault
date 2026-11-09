
import Foundation

@MainActor
public struct FetchBackupVersionsUseCase {

    private let repository: BackupMetadataRepository

    public init(repository: BackupMetadataRepository) {
        self.repository = repository
    }

    public func execute(for recordID: UUID) throws -> [BackupVersion] {
        try repository.fetchVersions(for: recordID)
    }
}
