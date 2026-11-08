import Foundation
import Observation

@MainActor
@Observable
final class CreateBackupViewModel {

    // MARK: - Dependencies

    private let fileAccessRepository: FileAccessRepository
    private let fileHasher: FileHashing
    private let createBackupWithUpload: CreateBackupWithUploadUseCase

    /// Подключённые облака, доступные для загрузки бэкапа.
    let availableProviders: [StorageProviderType]
    /// Облако-приёмник выбранного файла.
    var selectedProvider: StorageProviderType

    // MARK: - State

    var errorMessage: String?
    var isProgressing = false
    var isCompleted = false
    var uploadProgress: Double = 0

    private(set) var selectedFileName: String?
    private(set) var selectedFileURL: URL?
    private(set) var fileSize: Int64?
    private(set) var checksum: String?

    /// Имя, которое пользователь хочет дать копии. Изначально
    /// совпадает с именем выбранного файла, но может быть
    /// изменено в UI (актуально для сканов `scan_<UUID>.pdf`).
    var editableFileName = ""

    // MARK: - Initialization

    init(
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        createBackupWithUpload: CreateBackupWithUploadUseCase,
        availableProviders: [StorageProviderType] = [.googleDrive]
    ) {
        self.fileAccessRepository = fileAccessRepository
        self.fileHasher = fileHasher
        self.createBackupWithUpload = createBackupWithUpload
        self.availableProviders = availableProviders.isEmpty
            ? [.googleDrive]
            : availableProviders
        self.selectedProvider = self.availableProviders.first ?? .googleDrive
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
            editableFileName = Self.defaultFileName(for: url)

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
              let resolvedName = resolvedFileName() else {
            errorMessage = selectedFileURL == nil
                ? "Сначала выберите файл."
                : "Введите имя файла."
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
                fileName: resolvedName,
                sourceIdentifier: sourceURL.path,
                fileURL: sourceURL,
                parentFolderID: nil,
                storageProvider: selectedProvider
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
        editableFileName = ""
        errorMessage = nil
        isCompleted = false
        uploadProgress = 0
    }

    /// Имя по умолчанию для поля редактирования. PDF из сканера
    /// называется `scan_<UUID>.pdf` — подставляем читаемое
    /// «Скан <дата>.pdf», остальным файлам оставляем исходное имя.
    private static func defaultFileName(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasPrefix("scan_"),
           url.pathExtension.lowercased() == "pdf" {
            let stamp = Date.now.formatted(date: .numeric, time: .omitted)
            return "Скан \(stamp).pdf"
        }
        return name
    }

    /// Имя файла для копии: введённое пользователем значение,
    /// очищенное от пробелов и недопустимых для путей символов.
    /// Если расширение не указано — подставляется расширение
    /// исходного файла (например, `.pdf` для скана).
    private func resolvedFileName() -> String? {
        var name = editableFileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")

        guard !name.isEmpty else { return nil }

        // Расширение добавляем, только если пользователь не ввёл
        // его сам (точка в имени считается явным расширением).
        if !name.contains("."),
           let ext = selectedFileURL?.pathExtension,
           !ext.isEmpty {
            name += ".\(ext)"
        }

        return name
    }
}
