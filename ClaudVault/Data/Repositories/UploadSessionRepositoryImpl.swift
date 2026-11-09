import Foundation
import SwiftData
import ClaudVaultDomain

@MainActor
final class UploadSessionRepositoryImpl: UploadSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save(_ session: UploadSession) async throws {
        let model = UploadSessionModelMapper.toModel(session)
        modelContext.insert(model)
        try modelContext.save()
    }

    func fetchAll() async throws -> [UploadSession] {
        let descriptor = FetchDescriptor<UploadSessionModel>()
        let models = try modelContext.fetch(descriptor)
        return models.map { UploadSessionModelMapper.toDomain($0) }
    }

    func fetch(id: UUID) async throws -> UploadSession? {
        let descriptor = FetchDescriptor<UploadSessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        let models = try modelContext.fetch(descriptor)
        return models.first.map { UploadSessionModelMapper.toDomain($0) }
    }

    func updateProgress(id: UUID, uploadedBytes: Int64) async throws {
        let descriptor = FetchDescriptor<UploadSessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            throw NSError(domain: "UploadSessionRepository", code: 404)
        }

        model.uploadedBytes = uploadedBytes
        model.updatedAt = .now
        try modelContext.save()
    }

    func updateStatus(id: UUID, status: SessionStatus) async throws {
        let descriptor = FetchDescriptor<UploadSessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            throw NSError(domain: "UploadSessionRepository", code: 404)
        }

        model.statusRaw = status.rawValue
        model.updatedAt = .now
        try modelContext.save()
    }

    func updateErrorMessage(id: UUID, errorMessage: String?) async throws {
        let descriptor = FetchDescriptor<UploadSessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            throw NSError(domain: "UploadSessionRepository", code: 404)
        }

        model.errorMessage = errorMessage
        model.updatedAt = .now
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<UploadSessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            return
        }

        modelContext.delete(model)
        try modelContext.save()
    }

    func deleteCompleted() async throws {
        let descriptor = FetchDescriptor<UploadSessionModel>(
            predicate: #Predicate { $0.statusRaw == "completed" }
        )
        let models = try modelContext.fetch(descriptor)

        for model in models {
            modelContext.delete(model)
        }

        try modelContext.save()
    }
}

enum UploadSessionModelMapper {
    static func toDomain(_ model: UploadSessionModel) -> UploadSession {
        UploadSession(
            id: model.id,
            fileName: model.fileName,
            fileURL: URL(string: model.fileURL) ?? URL(fileURLWithPath: ""),
            sessionURL: model.sessionURL.isEmpty
                ? nil
                : URL(string: model.sessionURL),
            totalBytes: model.totalBytes,
            uploadedBytes: model.uploadedBytes,
            status: SessionStatus(rawValue: model.statusRaw) ?? .pending,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            backupRecordID: model.backupRecordID,
            errorMessage: model.errorMessage
        )
    }

    static func toModel(_ session: UploadSession) -> UploadSessionModel {
        UploadSessionModel(
            id: session.id,
            fileName: session.fileName,
            fileURL: session.fileURL.absoluteString,
            sessionURL: session.sessionURL?.absoluteString ?? "",
            totalBytes: session.totalBytes,
            uploadedBytes: session.uploadedBytes,
            status: session.status,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            backupRecordID: session.backupRecordID,
            errorMessage: session.errorMessage
        )
    }
}
