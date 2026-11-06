import Foundation

protocol UploadSessionRepository {
    func save(_ session: UploadSession) async throws
    func fetchAll() async throws -> [UploadSession]
    func fetch(id: UUID) async throws -> UploadSession?
    func updateProgress(id: UUID, uploadedBytes: Int64) async throws
    func updateStatus(id: UUID, status: SessionStatus) async throws
    func updateErrorMessage(id: UUID, errorMessage: String?) async throws
    func delete(id: UUID) async throws
    func deleteCompleted() async throws
    
    
}
