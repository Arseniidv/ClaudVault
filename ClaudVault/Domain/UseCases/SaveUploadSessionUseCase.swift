import Foundation

@MainActor
public final class SaveUploadSessionUseCase {
    private let repository: UploadSessionRepository

    public init(repository: UploadSessionRepository) {
        self.repository = repository
    }

    public func execute(_ session: UploadSession) async throws {
        try await repository.save(session)
    }
}
