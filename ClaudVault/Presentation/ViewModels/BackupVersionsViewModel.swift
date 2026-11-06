import Foundation
import Observation

@MainActor
@Observable
final class BackupVersionsViewModel {

    private let fetchBackupVersions: FetchBackupVersionsUseCase
    private let deleteBackupUseCase: DeleteBackupUseCase?
    private let reparseAndBackupUseCase: ReparseAndBackupUseCase?
    private let backupMetadataRepository: BackupMetadataRepository?

    let record: BackupRecord

    private(set) var versions: [BackupVersion] = []
    private(set) var isLoading = false
    private(set) var isMutating = false

    /// Устанавливается после удаления всей записи — view должен закрыться.
    private(set) var recordDeleted = false

    var errorMessage: String?
    var infoMessage: String?

    /// Вызывается после изменений — родитель обновляет списки и квоты.
    var onDataChanged: (() -> Void)?

    init(
        record: BackupRecord,
        fetchBackupVersions: FetchBackupVersionsUseCase,
        deleteBackupUseCase: DeleteBackupUseCase? = nil,
        reparseAndBackupUseCase: ReparseAndBackupUseCase? = nil,
        backupMetadataRepository: BackupMetadataRepository? = nil
    ) {
        self.record = record
        self.fetchBackupVersions = fetchBackupVersions
        self.deleteBackupUseCase = deleteBackupUseCase
        self.reparseAndBackupUseCase = reparseAndBackupUseCase
        self.backupMetadataRepository = backupMetadataRepository
    }

    func loadVersions() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let fetched: [BackupVersion] = try fetchBackupVersions.execute(for: record.id)
            versions = fetched.sorted(by: { $0.uploadedAt > $1.uploadedAt })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Повторный анализ исходного файла: новая версия создаётся
    /// только если SHA-256 изменился.
    func reparse() {
        guard let reparseAndBackupUseCase, !isMutating else { return }
        isMutating = true
        errorMessage = nil
        infoMessage = nil

        Task {
            defer { isMutating = false }
            do {
                let version = try await reparseAndBackupUseCase.execute(
                    record: record,
                    parentFolderID: nil
                ) { _ in }

                if version == nil {
                    infoMessage = "Файл не изменился — новая копия не создана."
                } else {
                    infoMessage = "Создана новая версия резервной копии."
                }

                loadVersions()
                onDataChanged?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Удаляет одну версию: облачный объект → затем метаданные.
    func deleteVersion(_ version: BackupVersion) {
        guard let deleteBackupUseCase, !isMutating else { return }
        isMutating = true
        errorMessage = nil

        Task {
            defer { isMutating = false }
            do {
                try await deleteBackupUseCase.execute(version: version)
                loadVersions()
                onDataChanged?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Удаляет всю резервную копию со всеми облачными объектами.
    func deleteRecord() {
        guard let deleteBackupUseCase, !isMutating else { return }
        isMutating = true
        errorMessage = nil

        Task {
            defer { isMutating = false }
            do {
                try await deleteBackupUseCase.execute(record: record)
                recordDeleted = true
                onDataChanged?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
