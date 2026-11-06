import Foundation
import Observation

@MainActor
@Observable
final class CreateBackupViewModel {

    // MARK: - Dependencies

    private let fileAccessRepository: FileAccessRepository
    private let fileHasher: FileHashing
    private let createBackupWithUpload: CreateBackupWithUploadUseCase

    // MARK: - State

    var errorMessage: String?
    var isProgressing = false
    var isCompleted = false
    var uploadProgress: Double = 0

    private(set) var selectedFileName: String?
    private(set) var selectedFileURL: URL?
    private(set) var fileSize: Int64?
    private(set) var checksum: String?

    // MARK: - Initialization

    init(
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        createBackupWithUpload: CreateBackupWithUploadUseCase
    ) {
        self.fileAccessRepository = fileAccessRepository
        self.fileHasher = fileHasher
        self.createBackupWithUpload = createBackupWithUpload
    }

    // MARK: - Select File

    func progressFile(at url: URL) async {
        isProgressing = true
        errorMessage = nil
        isCompleted = false
        uploadProgress = 0

        selectedFileName = nil
        selectedFileURL = nil
        fileSize = nil
        checksum = nil

        defer {
            isProgressing = false
        }

        do {
            // Доступ к файлу и SHA-256 — тяжёлые операции, уводим
            // с MainActor, чтобы UI не подвисал на больших файлах.
            let fileAccess = fileAccessRepository
            let hasher = fileHasher
            let result = try await Task.detached(priority: .userInitiated) {
                try fileAccess.withAccess(to: url) { accessibleURL in
                    let hash = try hasher.sha256(of: accessibleURL)

                    let resourceValues = try accessibleURL.resourceValues(
                        forKeys: [.fileSizeKey]
                    )

                    return (hash, Int64(resourceValues.fileSize ?? 0))
                }
            }.value

            selectedFileName = url.lastPathComponent
            selectedFileURL = url
            checksum = result.0
            fileSize = result.1

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Create Backup

    /// Создаёт реальную резервную копию: SHA-256 → загрузка в Google Drive
    /// → сохранение метаданных версии. Прогресс загрузки отображается
    /// в `uploadProgress` (0...1).
    func createBackup() async {
        guard let sourceURL = selectedFileURL,
              let selectedFileName else {
            errorMessage = "Сначала выберите файл."
            return
        }

        isProgressing = true
        errorMessage = nil
        isCompleted = false
        uploadProgress = 0

        defer {
            isProgressing = false
        }

        do {
            _ = try await createBackupWithUpload.execute(
                fileName: selectedFileName,
                sourceIdentifier: sourceURL.path,
                fileURL: sourceURL,
                parentFolderID: nil
            ) { [weak self] fraction in
                guard let self else { return }
                Task { @MainActor in
                    self.uploadProgress = fraction
                }
            }

            isCompleted = true
            uploadProgress = 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        selectedFileName = nil
        selectedFileURL = nil
        fileSize = nil
        checksum = nil
        errorMessage = nil
        isCompleted = false
        uploadProgress = 0
    }
}
