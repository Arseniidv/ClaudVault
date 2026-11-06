import Foundation
import UniformTypeIdentifiers

final class GoogleDriveRepositoryImpl: CloudStorageRepository {
    private let oauthManager: GoogleOAuthManager
    private let driveService: GoogleDriveService

    init(oauthManager: GoogleOAuthManager) {
        self.oauthManager = oauthManager

        self.driveService = GoogleDriveService(
            tokenProvider: {
                do {
                    return try await oauthManager.freshAccessToken()
                } catch let error as GoogleOAuthError {
                    throw GoogleDriveRepositoryImpl.mapOAuthError(error)
                }
            }
        )
    }

    // MARK: - Connection

    func connect() async throws -> CloudStorageAccount {
        do {
            let account = try await oauthManager.connect()

            return CloudStorageAccount(
                id: account.userID,
                email: account.email,
                displayName: account.name
            )
        } catch let error as GoogleOAuthError {
            throw Self.mapOAuthError(error)
        }
    }
    func restoreConnection() async throws -> CloudStorageAccount? {
        do {
            guard let account = try await oauthManager.restorePreviousSignIn()
            else {
                return nil
            }

            return CloudStorageAccount(
                id: account.userID,
                email: account.email,
                displayName: account.name
            )
        } catch let error as GoogleOAuthError {
            throw Self.mapOAuthError(error)
        }
    }

    func signOut() async throws {
        oauthManager.signOut()
    }

    // MARK: - Files

    func listFiles(
        parentFolderID: String?
    ) async throws -> [CloudFile] {
        try await driveService.listFiles(parentFolderID: parentFolderID)
    }

    func fileMetadata(id: String) async throws -> CloudFile {
        try await driveService.fileMetadata(id: id)
    }

    func createFolder(
        name: String,
        parentFolderID: String?
    ) async throws -> CloudFile {
        try await driveService.createFolder(
            name: name,
            parentFolderID: parentFolderID
        )
    }

    func uploadFile(
        at fileURL: URL,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        let name = fileURL.lastPathComponent
        let mimeType = Self.mimeType(for: fileURL)

        return try await driveService.uploadFile(
            at: fileURL,
            name: name,
            mimeType: mimeType,
            parentFolderID: parentFolderID,
            progressHandler: progressHandler
        )
    }

    func deleteFile(id: String) async throws {
        try await driveService.deleteFile(id: id)
    }

    func downloadFile(
        id: String,
        to destination: URL,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws {
        try await driveService.downloadFile(id: id, to: destination)
    }

    /// Для Google Workspace файлов (Docs/Sheets/Slides) выполняет
    /// экспорт в обычный формат — QuickLook не умеет их нативно.
    /// Остальные файлы скачиваются как обычно.
    func downloadPreviewFile(
        id: String,
        name: String,
        mimeType: String,
        into directory: URL
    ) async throws -> URL {
        guard let export = Self.workspaceExport(for: mimeType) else {
            let destination = directory.appendingPathComponent(name)
            try await driveService.downloadFile(id: id, to: destination)
            return destination
        }

        let baseName = (name as NSString).deletingPathExtension
        let destination = directory
            .appendingPathComponent(baseName.isEmpty ? name : baseName)
            .appendingPathExtension(export.fileExtension)
        try await driveService.exportFile(
            id: id,
            exportMimeType: export.mimeType,
            to: destination
        )
        return destination
    }

    func thumbnailData(for file: CloudFile) async throws -> Data? {
        try await driveService.thumbnailData(for: file)
    }

    func streamDescriptor(
        for file: CloudFile
    ) async throws -> CloudMediaStream {
        try await driveService.streamDescriptor(for: file)
    }

    /// Chunked-загрузка без промежуточного файла (resumable-сессия).
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
        return try await driveService.uploadStreamedFile(
            name: name,
            mimeType: mimeType,
            parentFolderID: parentFolderID,
            sizeBytes: sizeBytes,
            readChunk: readChunk,
            progressHandler: progressHandler
        )
    }

    func searchFiles(query: String) async throws -> [CloudFile] {
        try await driveService.searchFiles(query: query)
    }

    func getStorageUsage() async throws -> CloudStorageUsage {
        try await driveService.getStorageUsage()
    }

    // MARK: - Helpers

    /// Формат экспорта для Google Workspace MIME-типов.
    /// Остальные типы возвращают nil — файл скачивается как есть.
    private static func workspaceExport(
        for mimeType: String
    ) -> (mimeType: String, fileExtension: String)? {
        switch mimeType {
        case "application/vnd.google-apps.document",
             "application/vnd.google-apps.presentation",
             "application/vnd.google-apps.drawing",
             "application/vnd.google-apps.form":
            return ("application/pdf", "pdf")
        case "application/vnd.google-apps.spreadsheet":
            return (
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "xlsx"
            )
        default:
            return nil
        }
    }

    private static func mapOAuthError(
        _ error: GoogleOAuthError
    ) -> CloudStorageError {
        switch error {
        case .missingClientID, .notConfigured:
            return .notConfigured
        case .notSignedIn:
            return .notConnected
        case .noPresentingWindow:
            return .noPresentingWindow
        case .scopeDenied, .missingEmail:
            return .permissionDenied
        case .tokenExchangeFailed:
            return .unauthorized
        case .missingAccount:
            return .operationFailed(
                "Не удалось получить данные Google-аккаунта."
            )
        }
    }

    private static func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension),
              let mimeType = type.preferredMIMEType else {
            return "application/octet-stream"
        }

        return mimeType
    }
}
