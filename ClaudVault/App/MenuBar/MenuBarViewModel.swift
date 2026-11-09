import Foundation
import Observation
import ClaudVaultDomain

/// Состояние и логика Menu Bar-интерфейса CloudVault (macOS).
///
/// Не дублирует сервисы: читает реальные данные из общих
/// `StoragesViewModel` и `FetchUploadSessionsUseCase`, а действия
/// делегирует существующим use-case'ам и роутерам. Единственный
/// VM на процесс — создаётся в `ClaudVaultApp` и передаётся
/// в `MenuBarExtra`, чтобы иконка и окно показывали одни данные.
@MainActor
@Observable
final class MenuBarViewModel {

    /// Визуальное состояние иконки в Menu Bar.
    enum Status: Equatable {
        /// Подключения есть, активных операций нет.
        case idle
        /// Идёт синхронизация/передача.
        case syncing
        /// Есть ошибки провайдеров или неудачные передачи.
        case error
        /// Нет ни одного подключённого облачного хранилища.
        case disconnected
    }

    /// Снимок состояния одного провайдера для строки Menu Bar.
    struct ProviderRow: Identifiable {
        let provider: StorageProviderType
        var id: String { provider.rawValue }
        let account: CloudStorageAccount?
        let storageUsage: CloudStorageUsage?
        let isBusy: Bool
        let errorMessage: String?
    }

    let dependencies: AppDependencies

    /// Общий VM подключений — тот же экземпляр, что использует
    /// основное окно, поэтому статусы не расходятся.
    private let storagesViewModel: StoragesViewModel

    /// Репозитории по провайдерам — для `TransferEngine.resumePending`.
    private let repositories: [StorageProviderType: CloudStorageRepository]

    /// Сессии передач (upload/backup), отсортированные по updatedAt.
    private(set) var sessions: [UploadSession] = []
    /// Ошибка последнего опроса сессий (не блокирующая).
    private(set) var errorMessage: String?

    private var pollTask: Task<Void, Never>?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.storagesViewModel = dependencies.storagesViewModel
        self.repositories = [
            .googleDrive: dependencies.cloudStorageRepository,
            .dropbox: dependencies.dropboxRepository,
            .oneDrive: dependencies.oneDriveRepository
        ]
    }

    // MARK: - Derived State

    /// Строки для всех поддерживаемых провайдеров
    /// (подключённые и доступные к подключению).
    var providerRows: [ProviderRow] {
        storagesViewModel.availableProviders.map { kind in
            let state = storagesViewModel.state(for: kind)
            return ProviderRow(
                provider: kind,
                account: state.account,
                storageUsage: state.storageUsage,
                isBusy: state.isBusy,
                errorMessage: state.errorMessage
            )
        }
    }

    /// Идёт ли сейчас передача/синхронизация.
    var isSyncing: Bool {
        storagesViewModel.isTransferRunning
            || sessions.contains {
                $0.status == .pending
                    || $0.status == .uploading
                    || $0.status == .paused
            }
    }

    /// Есть ли незавершённые передачи, которые можно возобновить.
    var canResumeTransfers: Bool {
        sessions.contains {
            $0.status == .pending
                || $0.status == .uploading
                || $0.status == .paused
        }
    }

    /// Последние операции для блока «Активность».
    var recentSessions: [UploadSession] {
        Array(sessions.prefix(3))
    }

    var failedSessionsCount: Int {
        sessions.filter { $0.status == .failed }.count
    }

    var status: Status {
        if providerRows.contains(where: { $0.errorMessage != nil })
            || failedSessionsCount > 0 {
            return .error
        }
        if isSyncing { return .syncing }
        if storagesViewModel.connectedProviders.isEmpty {
            return .disconnected
        }
        return .idle
    }

    /// SF Symbol для иконки Menu Bar — отражает `status`.
    var menuBarIcon: String {
        switch status {
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle"
        case .disconnected:
            return "cloud"
        case .idle:
            return "cloud.fill"
        }
    }

    var statusTitle: String {
        switch status {
        case .syncing: return "Синхронизация…"
        case .error: return "Ошибка синхронизации"
        case .disconnected: return "Нет подключённых хранилищ"
        case .idle: return "Готово"
        }
    }

    // MARK: - Monitoring

    /// Запускает периодический опрос сессий передач (раз в 2 с),
    /// чтобы Menu Bar отражал прогресс без открытия окна.
    func startMonitoring() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reloadSessions()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Полное обновление: usage провайдеров + сессии передач.
    func refresh() async {
        await storagesViewModel.loadStorageUsage()
        await reloadSessions()
    }

    private func reloadSessions() async {
        do {
            let fetched = try await dependencies.fetchUpSession.execute()
            sessions = fetched.sorted { $0.updatedAt > $1.updatedAt }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    /// Открывает основное окно на вкладке «Хранилища»
    /// с выбранным провайдером.
    func openProvider(_ provider: StorageProviderType) {
        dependencies.navigationRouter.request(.storages, provider: provider)
    }

    /// «Новая резервная копия»: открывает окно и запрашивает
    /// системный выбор файла через существующий BackupActionRouter —
    /// дальше работает штатный флоу BackupListView.
    func requestNewBackup() {
        dependencies.navigationRouter.request(.files)
        dependencies.backupActionRouter.request(.pickFile)
    }

    /// «Возобновить передачи»: подхватывает незавершённые записи
    /// журнала TransferEngine — тот же механизм, что при старте
    /// приложения в `StoragesViewModel.restoreConnection()`.
    func resumePendingTransfers() {
        let engine = dependencies.transferEngine
        let repos = repositories
        Task {
            await engine.resumePending { raw in
                guard let kind = StorageProviderType(rawValue: raw) else {
                    return nil
                }
                return repos[kind]
            }
            await reloadSessions()
        }
    }

    /// «Настройки»: переключает основное окно на вкладку настроек.
    func openSettings() {
        dependencies.navigationRouter.request(.settings)
    }
}
