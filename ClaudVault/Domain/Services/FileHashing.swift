import Foundation

protocol FileHashing{
    nonisolated func hashFile(at url:URL) throws ->String
    nonisolated func sha256(of fileURL:URL) throws -> String
}
