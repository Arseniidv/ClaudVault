import Foundation

@MainActor
public final class UpdateUploadProgressUseCase {
    private let repository: UploadSessionRepository

    public init(repository: UploadSessionRepository) {
        self.repository = repository
    }

    public func execute(id: UUID, uploadedBytes: Int64) async throws {
        try await repository.updateProgress(id: id, uploadedBytes: uploadedBytes)
    }

    public func execute(id: UUID, status: SessionStatus) async throws {
        try await  repository.updateStatus(id: id, status: status)
    }

    public func execute(id: UUID, errorMessage: String?) async throws {
        try await repository.updateErrorMessage(id: id, errorMessage: errorMessage)
    }

    public func executeDelete(id: UUID) async throws {
        try await repository.delete(id: id)
    }

    public func executeDeleteCompleted() async throws {
        try await repository.deleteCompleted()
    }
}
