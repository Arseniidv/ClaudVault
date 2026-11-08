import Foundation

/// Обёртка `ChunkSource`, считающая контрольные суммы
/// передаваемых байт на лету. Читает каждый чанк-файл
/// блоками и скармливает данные `TransferHasher`.
///
/// Хеши корректны только если передача началась с offset=0
/// и дошла до конца без пропусков — иначе `finalizeHashes`
/// вернёт nil и верификация ограничится размером.
final class HashingChunkSource: ChunkSource, @unchecked Sendable {

    private let base: any ChunkSource
    private let hasher = TransferHasher()
    private let readBlockSize = 1 * 1024 * 1024

    /// Смещение, до которого хеш покрыт непрерывно.
    private var contiguousOffset: Int64 = 0
    private var coverageBroken = false
    private var didFinalize = false

    init(base: any ChunkSource) {
        self.base = base
    }

    var totalSize: Int64 { base.totalSize }

    func chunk(at offset: Int64, maxLength: Int64) async throws -> ChunkPayload? {
        guard let payload = try await base.chunk(
            at: offset,
            maxLength: maxLength
        ) else { return nil }

        // Хешируем только при непрерывном покрытии с нуля —
        // при resume с середины файл хешировать не будем.
        if !coverageBroken, payload.absoluteOffset == contiguousOffset {
            do {
                try hashPayload(payload)
                contiguousOffset += payload.length
            } catch {
                coverageBroken = true
            }
        } else {
            coverageBroken = true
        }
        return payload
    }

    func discard(_ payload: ChunkPayload) async {
        await base.discard(payload)
    }

    /// Хеши всего файла, если покрытие полное.
    /// `nil` — передача началась не с нуля или оборвалась:
    /// хеш сравнивать нельзя.
    func finalizeHashes() -> [ContentHash]? {
        guard !didFinalize, !coverageBroken,
              contiguousOffset == totalSize else {
            return nil
        }
        didFinalize = true
        return hasher.finalizeHashes()
    }

    /// Читает диапазон чанка блоками и обновляет хешер.
    private func hashPayload(_ payload: ChunkPayload) throws {
        let handle = try FileHandle(forReadingFrom: payload.fileURL)
        defer { try? handle.close() }
        try handle.seek(
            toOffset: UInt64(payload.fileOffset)
        )

        var remaining = payload.length
        while remaining > 0 {
            let block = min(Int64(readBlockSize), remaining)
            guard let data = try handle.read(upToCount: Int(block)),
                  !data.isEmpty else {
                throw CloudStorageError.operationFailed(
                    "Не удалось прочитать чанк для проверки целостности."
                )
            }
            hasher.update(data)
            remaining -= Int64(data.count)
        }
    }
}
