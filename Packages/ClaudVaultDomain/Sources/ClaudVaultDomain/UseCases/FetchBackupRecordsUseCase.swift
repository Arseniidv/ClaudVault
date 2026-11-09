import Foundation

@MainActor
public struct FetchBackupRecordsUseCase{
    private let repository:BackupMetadataRepository
    public init(repository: BackupMetadataRepository) {
        self.repository = repository
    }
    public func execute() throws ->[BackupRecord]{
        try repository.fetchRecords()
    }
}
