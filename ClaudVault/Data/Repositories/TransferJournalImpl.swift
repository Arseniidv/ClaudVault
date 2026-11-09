import Foundation
import SwiftData

@MainActor
final class TransferJournalImpl: TransferJournal {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func begin(_ record: TransferRecord) async throws {
        if let existing = try model(for: record.id) {
            existing.apply(record)
        } else {
            modelContext.insert(TransferRecordModel(record: record))
        }
        try modelContext.save()
    }

    func updateProgress(
        id: UUID,
        offset: Int64? = nil,
        sessionState: String? = nil,
        hashAlgorithm: String? = nil,
        hashValue: String? = nil,
        streamSHA256: String? = nil
    ) async throws {
        guard let model = try model(for: id) else { return }
        if let offset { model.offset = offset }
        if let sessionState { model.sessionState = sessionState }
        if let hashAlgorithm { model.expectedHashAlgorithm = hashAlgorithm }
        if let hashValue { model.expectedHashValue = hashValue }
        if let streamSHA256 { model.streamSHA256 = streamSHA256 }
        model.updatedAt = .now
        try modelContext.save()
    }

    func setState(
        id: UUID,
        state: TransferRecord.State,
        error: String? = nil
    ) async throws {
        guard let model = try model(for: id) else { return }
        model.stateRaw = state.rawValue
        model.errorMessage = error
        model.updatedAt = .now
        try modelContext.save()
    }

    func pendingRecords() async throws -> [TransferRecord] {
        let states = [
            TransferRecord.State.pending.rawValue,
            TransferRecord.State.uploading.rawValue,
            TransferRecord.State.verifying.rawValue
        ]
        let descriptor = FetchDescriptor<TransferRecordModel>(
            predicate: #Predicate { states.contains($0.stateRaw) }
        )
        return try modelContext.fetch(descriptor)
            .map { $0.asRecord() }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func record(id: UUID) async throws -> TransferRecord? {
        try model(for: id)?.asRecord()
    }

    func delete(id: UUID) async throws {
        guard let model = try model(for: id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    private func model(for id: UUID) throws -> TransferRecordModel? {
        let descriptor = FetchDescriptor<TransferRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }
}
