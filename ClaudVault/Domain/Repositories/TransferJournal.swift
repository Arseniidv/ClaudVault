import Foundation

/// Хранилище журнала передач. Записи в состояниях
/// `pending`/`uploading`/`verifying` — кандидаты на возобновление.
protocol TransferJournal: Sendable {
    /// Создаёт запись. Идемпотентно по `record.id`:
    /// повторный вызов с тем же id обновляет запись.
    func begin(_ record: TransferRecord) async throws
    /// Обновляет подтверждённое смещение и/или состояние сессии.
    func updateProgress(
        id: UUID,
        offset: Int64?,
        sessionState: String?,
        hashAlgorithm: String?,
        hashValue: String?,
        streamSHA256: String?
    ) async throws
    /// Обновляет только подтверждённое смещение.
    func updateOffset(id: UUID, offset: Int64) async throws
    func setState(id: UUID, state: TransferRecord.State, error: String?) async throws
    func pendingRecords() async throws -> [TransferRecord]
    func record(id: UUID) async throws -> TransferRecord?
    /// Удаляет запись (после успешного завершения или отмены).
    func delete(id: UUID) async throws
}

extension TransferJournal {
    func setState(id: UUID, state: TransferRecord.State) async throws {
        try await setState(id: id, state: state, error: nil)
    }

    func updateProgress(id: UUID, offset: Int64) async throws {
        try await updateProgress(
            id: id,
            offset: offset,
            sessionState: nil,
            hashAlgorithm: nil,
            hashValue: nil,
            streamSHA256: nil
        )
    }

    func updateOffset(id: UUID, offset: Int64) async throws {
        try await updateProgress(id: id, offset: offset)
    }

    func updateSessionState(id: UUID, state: String) async throws {
        try await updateProgress(
            id: id,
            offset: nil,
            sessionState: state,
            hashAlgorithm: nil,
            hashValue: nil,
            streamSHA256: nil
        )
    }
}
