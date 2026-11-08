import Foundation
import SwiftData

/// Репозиторий сессий загрузки на собственном фоновом `ModelContext`.
///
/// Прогресс загрузки обновляется очень часто; выполнять fetch+save
/// на `mainContext` главного потока нельзя — это приводит к зависанию
/// UI и падениям внутри SwiftData. Выделенный контекст сериализуется
/// через `NSLock`, поэтому все обращения к нему безопасны с любого
/// потока, а `@Model`-объекты никогда не покидают репозиторий
/// (наружу уходят только доменные `UploadSession`).
final class UploadSessionRepositoryImpl: UploadSessionRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let modelContext: ModelContext

    /// Сигнал о сохранении сессии — будит мониторинг
    /// Live Activities, чтобы активность появилась без
    /// ожидания очередного тика опроса.
    var onSessionChange: (@Sendable () -> Void)?

    /// Владелец данных; nil — сеанса нет, репозиторий пуст.
    private var ownerID: String? {
        CurrentUserContext.shared.ownerID
    }

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func save(_ session: UploadSession) async throws {
        try perform { context in
            let model = UploadSessionModelMapper.toModel(session)
            model.ownerID = ownerID ?? ""
            context.insert(model)
            try context.save()
        }
        onSessionChange?()
    }

    func fetchAll() async throws -> [UploadSession] {
        guard let ownerID else { return [] }
        return try perform { context in
            let descriptor = FetchDescriptor<UploadSessionModel>(
                predicate: #Predicate { $0.ownerID == ownerID }
            )
            return try context.fetch(descriptor)
                .map { UploadSessionModelMapper.toDomain($0) }
        }
    }

    func fetch(id: UUID) async throws -> UploadSession? {
        guard let ownerID else { return nil }
        return try perform { context in
            let descriptor = FetchDescriptor<UploadSessionModel>(
                predicate: #Predicate {
                    $0.id == id && $0.ownerID == ownerID
                }
            )
            return try context.fetch(descriptor)
                .first
                .map { UploadSessionModelMapper.toDomain($0) }
        }
    }

    func updateProgress(id: UUID, uploadedBytes: Int64) async throws {
        try perform { context in
            guard let model = try fetchModel(id: id, in: context) else {
                throw NSError(domain: "UploadSessionRepository", code: 404)
            }

            model.uploadedBytes = uploadedBytes
            model.updatedAt = .now
            try context.save()
        }
    }

    func updateStatus(id: UUID, status: SessionStatus) async throws {
        try perform { context in
            guard let model = try fetchModel(id: id, in: context) else {
                throw NSError(domain: "UploadSessionRepository", code: 404)
            }

            model.statusRaw = status.rawValue
            model.updatedAt = .now
            try context.save()
        }
    }

    func updateErrorMessage(id: UUID, errorMessage: String?) async throws {
        try perform { context in
            guard let model = try fetchModel(id: id, in: context) else {
                throw NSError(domain: "UploadSessionRepository", code: 404)
            }

            model.errorMessage = errorMessage
            model.updatedAt = .now
            try context.save()
        }
    }

    func delete(id: UUID) async throws {
        try perform { context in
            guard let model = try fetchModel(id: id, in: context) else {
                return
            }

            context.delete(model)
            try context.save()
        }
    }

    func deleteCompleted() async throws {
        guard let ownerID else { return }
        try perform { context in
            let descriptor = FetchDescriptor<UploadSessionModel>(
                predicate: #Predicate {
                    $0.statusRaw == "completed" && $0.ownerID == ownerID
                }
            )
            let models = try context.fetch(descriptor)

            for model in models {
                context.delete(model)
            }

            try context.save()
        }
    }

    // MARK: - Private

    private func perform<T>(_ work: (ModelContext) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work(modelContext)
    }

    private func fetchModel(
        id: UUID,
        in context: ModelContext
    ) throws -> UploadSessionModel? {
        let descriptor = FetchDescriptor<UploadSessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
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
