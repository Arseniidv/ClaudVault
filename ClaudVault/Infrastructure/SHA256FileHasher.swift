import Foundation
import CryptoKit

final class SHA256FileHasher: FileHashing {
    
    nonisolated func hashFile(at url: URL) throws -> String {
        return try sha256(of: url)
    }
    

    private let chunkSize = 1_048_576 // 1 MB

    nonisolated func sha256(of fileURL: URL) throws -> String {

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()

        while true {
            guard let data = try fileHandle.read(upToCount: chunkSize),
                  !data.isEmpty else {
                break
            }

            hasher.update(data: data)
        }

        let digest = hasher.finalize()

        return digest
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
