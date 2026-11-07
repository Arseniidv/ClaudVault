import CryptoKit
import Foundation

/// Инкрементальные контрольные суммы передаваемого файла:
/// MD5, SHA-1, SHA-256 и Dropbox `content_hash`
/// (SHA-256 по блокам 4 МиБ). Данные подаются чанками —
/// файл целиком в память не загружается.
final class TransferHasher: @unchecked Sendable {

    /// Размер блока Dropbox content_hash.
    static let dropboxBlockSize = 4 * 1024 * 1024

    private var md5 = Insecure.MD5()
    private var sha1 = Insecure.SHA1()

    /// Dropbox content_hash: SHA-256 каждого 4-МиБ блока,
    /// затем SHA-256 конкатенации дайджестов.
    private var dropboxBlock = Data()
    private var dropboxDigests: [SHA256.Digest] = []

    private(set) var hashedBytes: Int64 = 0
    private var didFinalize = false

    func update(_ data: Data) {
        guard !didFinalize, !data.isEmpty else { return }
        md5.update(data: data)
        sha1.update(data: data)
        hashedBytes += Int64(data.count)

        var index = data.startIndex
        while index < data.endIndex {
            let take = min(
                Self.dropboxBlockSize - dropboxBlock.count,
                data.endIndex - index
            )
            dropboxBlock.append(data[index..<index + take])
            index += take
            if dropboxBlock.count == Self.dropboxBlockSize {
                dropboxDigests.append(SHA256.hash(data: dropboxBlock))
                dropboxBlock.removeAll(keepingCapacity: true)
            }
        }
    }

    /// Все вычисленные хеши. Вызывать один раз после
    /// завершения передачи всех байт.
    func finalizeHashes() -> [ContentHash] {
        guard !didFinalize else { return [] }
        didFinalize = true

        var hashes = [
            ContentHash(
                algorithm: .md5,
                value: md5.finalize().hexEncoded
            ),
            ContentHash(
                algorithm: .sha1,
                value: sha1.finalize().hexEncoded
            )
        ]

        var digests = dropboxDigests
        if !dropboxBlock.isEmpty {
            digests.append(SHA256.hash(data: dropboxBlock))
        }
        var combined = Data()
        for digest in digests {
            combined.append(contentsOf: digest)
        }
        hashes.append(
            ContentHash(
                algorithm: .dropboxContent,
                value: SHA256.hash(data: combined).hexEncoded
            )
        )
        return hashes
    }
}

private extension Digest {
    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
