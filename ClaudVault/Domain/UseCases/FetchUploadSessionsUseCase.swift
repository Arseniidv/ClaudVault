import Foundation

@MainActor
final class FetchUploadSessionsUseCase {
    private let repository: UploadSessionRepository

    init(repository: UploadSessionRepository) {
        self.repository = repository
    }

    func execute() async throws -> [UploadSession] {
        try await repository.fetchAll()
    }

    func execute(id: UUID) async throws -> UploadSession? {
        try await repository.fetch(id: id)
    }
}
