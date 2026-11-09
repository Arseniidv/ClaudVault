import Foundation

@MainActor
public final class FetchUploadSessionsUseCase {
    private let repository: UploadSessionRepository

    public init(repository: UploadSessionRepository) {
        self.repository = repository
    }

    public func execute() async throws -> [UploadSession] {
        try await repository.fetchAll()
    }

    public func execute(id: UUID) async throws -> UploadSession? {
        try await repository.fetch(id: id)
    }
}
