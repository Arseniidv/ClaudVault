import Foundation

protocol FileHashing{
    func hashFile(at url:URL) throws ->String
    func sha256(of fileURL:URL) throws -> String
}
