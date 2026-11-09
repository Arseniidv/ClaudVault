import Foundation
import SwiftData
import ClaudVaultDomain

/// Журнал chunked-передач на собственном фоновом `ModelContext`.
///
/// `updateProgress` вызывается после каждого подтверждённого чанка
/// (8 МБ) — при больших файлах это сотни fetch+save. Выполнять их
/// на `mainContext` в `@MainActor`-движке нельзя: это грузит
/// главный поток и ведёт к зависаниям UI. Выделенный контекст
/// сериализуется через `NSLock`, а `@Model`-объекты никогда не
/// покидают репозиторий (наружу уходят доменные `TransferRecord`).
final class TransferJournalImpl: TransferJournal, @unchecked Sendable {

    private let lock = NSLock()
    private let modelContext: ModelContext

    /// Владелец данных; nil — сеанса нет, журнал пуст.
    private var ownerID: String? {
        CurrentUserContext.shared.ownerID
    }

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func begin(_ record: TransferRecord) async throws {
        try perform { context in
            if let existing = try fetchModel(id: record.id, in: context) {
                existing.apply(record)
                existing.ownerID = ownerID ?? existing.ownerID
            } else {
                let model = TransferRecordModel(record: record)
                model.ownerID = ownerID ?? ""
                context.insert(model)
            }
            try context.save()
        }
    }

    func updateProgress(
        id: UUID,
        offset: Int64? = nil,
        sessionState: String? = nil,
        hashAlgorithm: String? = nil,
        hashValue: String? = nil,
        streamSHA256: String? = nil
    ) async throws {
        try perform { context in
            guard let model = try fetchModel(id: id, in: context) else { return }
            if let offset { model.offset = offset }
            if let sessionState { model.sessionState = sessionState }
            if let hashAlgorithm { model.expectedHashAlgorithm = hashAlgorithm }
            if let hashValue { model.expectedHashValue = hashValue }
            if let streamSHA256 { model.streamSHA256 = streamSHA256 }
            model.updatedAt = .now
            try context.save()
        }
    }

    func setState(
        id: UUID,
        state: TransferRecord.State,
        error: String? = nil
    ) async throws {
        try perform { context in
            guard let model = try fetchModel(id: id, in: context) else { return }
            model.stateRaw = state.rawValue
            model.errorMessage = error
            model.updatedAt = .now
            try context.save()
        }
    }

    func pendingRecords() async throws -> [TransferRecord] {
        guard let ownerID else { return [] }
        return try perform { context in
            let states = [
                TransferRecord.State.pending.rawValue,
                TransferRecord.State.uploading.rawValue,
                TransferRecord.State.verifying.rawValue
            ]
            let descriptor = FetchDescriptor<TransferRecordModel>(
                predicate: #Predicate {
                    states.contains($0.stateRaw) && $0.ownerID == ownerID
                }
            )
            return try context.fetch(descriptor)
                .map { $0.asRecord() }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    func record(id: UUID) async throws -> TransferRecord? {
        try perform { context in
            try fetchModel(id: id, in: context)?.asRecord()
        }
    }

    func delete(id: UUID) async throws {
        try perform { context in
            guard let model = try fetchModel(id: id, in: context) else { return }
            context.delete(model)
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
    ) throws -> TransferRecordModel? {
        let descriptor = FetchDescriptor<TransferRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }
}
