import Foundation
import UniformTypeIdentifiers

/// Реализация `CloudStorageRepository` поверх Microsoft Graph API.
/// В качестве `CloudFile.id` используется driveItem `id` —
/// он стабилен и принимается всеми `/items/{id}` эндпоинтами.
final class OneDriveRepositoryImpl: CloudStorageRepository {

    private let authManager: OneDriveAuthManager
    private let service: OneDriveService

    init(authManager: OneDriveAuthManager) {
        self.authManager = authManager
        self.service = OneDriveService(
            tokenProvider: {
                try await authManager.freshAccessToken()
            }
        )
    }

    // MARK: - Connection

    func connect() async throws -> CloudStorageAccount {
        try await authManager.connect()
    }

    func restoreConnection() async throws -> CloudStorageAccount? {
        try await authManager.restoreConnection()
    }

    func signOut() async throws {
        authManager.signOut()
    }

    // MARK: - Files

    func listFiles(parentFolderID: String?) async throws -> [CloudFile] {
        try await service.listFiles(parentFolderID: parentFolderID)
    }

    func fileMetadata(id: String) async throws -> CloudFile {
        try await service.fileMetadata(id: id)
    }

    func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile {
        try await service.createFolder(name: name, parentFolderID: parentFolderID)
    }

    func uploadFile(
        at fileURL: URL,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        try await service.uploadFile(
            at: fileURL,
            name: fileURL.lastPathComponent,
            mimeType: Self.mimeType(for: fileURL),
            parentFolderID: parentFolderID,
            progressHandler: progressHandler
        )
    }

    func deleteFile(id: String) async throws {
        try await service.deleteFile(id: id)
    }

    func downloadFile(
        id: String,
        to destination: URL,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws {
        try await service.downloadFile(id: id, to: destination)
    }

    func thumbnailData(for file: CloudFile) async throws -> Data? {
        try await service.thumbnailData(for: file)
    }

    func streamDescriptor(for file: CloudFile) async throws -> CloudMediaStream {
        try await service.streamDescriptor(for: file)
    }

    /// Chunked-загрузка через Graph upload session.
    func uploadStreamedFile(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64?,
        readChunk: () async throws -> Data?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        guard let sizeBytes else {
            throw CloudStorageError.operationFailed(
                "Размер файла неизвестен — потоковая загрузка невозможна."
            )
        }
        return try await service.uploadStreamedFile(
            name: name,
            mimeType: mimeType,
            parentFolderID: parentFolderID,
            sizeBytes: sizeBytes,
            readChunk: readChunk,
            progressHandler: progressHandler
        )
    }

    func searchFiles(query: String) async throws -> [CloudFile] {
        try await service.searchFiles(query: query)
    }

    func getStorageUsage() async throws -> CloudStorageUsage {
        try await service.getStorageUsage()
    }

    // MARK: - Helpers

    private static func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension),
              let mimeType = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mimeType
    }
}
