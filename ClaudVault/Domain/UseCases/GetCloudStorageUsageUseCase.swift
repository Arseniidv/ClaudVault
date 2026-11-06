import Foundation

@MainActor
final class GetCloudStorageUsageUseCase {
    private let repository: CloudStorageRepository

    init(repository: CloudStorageRepository) {
        self.repository = repository
    }

    func execute() async throws -> CloudStorageUsage {
        try await repository.getStorageUsage()
    }
}
