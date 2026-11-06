import Foundation

@MainActor
final class SaveUploadSessionUseCase {
    private let repository: UploadSessionRepository

    init(repository: UploadSessionRepository) {
        self.repository = repository
    }

    func execute(_ session: UploadSession) async throws {
        try await repository.save(session)
    }
}
