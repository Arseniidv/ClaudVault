import Foundation

@MainActor
final class UpdateUploadProgressUseCase {
    private let repository: UploadSessionRepository

    init(repository: UploadSessionRepository) {
        self.repository = repository
    }

    func execute(id: UUID, uploadedBytes: Int64) async throws {
        try await repository.updateProgress(id: id, uploadedBytes: uploadedBytes)
    }

    func execute(id: UUID, status: SessionStatus) async throws {
        try await  repository.updateStatus(id: id, status: status)
    }

    func execute(id: UUID, errorMessage: String?) async throws {
        try await repository.updateErrorMessage(id: id, errorMessage: errorMessage)
    }

    func executeDelete(id: UUID) async throws {
        try await repository.delete(id: id)
    }

    func executeDeleteCompleted() async throws {
        try await repository.deleteCompleted()
    }
}
