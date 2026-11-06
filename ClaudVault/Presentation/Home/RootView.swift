
import SwiftUI
import SwiftData

@MainActor
struct RootView: View {
    let dependencies: AppDependencies
    @StateObject private var authViewModel: AuthViewModel
    @State private var storagesViewModel: StoragesViewModel
    @State private var selectedTab: AppTab = .files
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @State private var isAppLocked = false
    /// Роутер deep link'ов создания бэкапа из виджета.
    /// Живёт в RootView, чтобы пережить экран входа: запрос
    /// исполнится, когда `BackupListView` появится после авторизации.
    @State private var backupActionRouter = BackupActionRouter()
    /// Приложение уже было разблокировано в этой сессии (нет смысла
    /// запирать повторно при каждом scenePhase → .active).
    @State private var hasUnlockedThisSession = false
    @Environment(\.scenePhase) private var scenePhase

    /// Должна ли сейчас показываться блокировка.
    private var shouldLock: Bool {
        biometricLockEnabled
            && dependencies.biometricAuthService.isAvailable()
            && authViewModel.currentUser != nil
    }
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _authViewModel = StateObject(
            wrappedValue: dependencies.makeAuthViewModel()
        )
        _storagesViewModel = State(
            wrappedValue: dependencies.makeStoragesViewModel()
        )
    }
    var body: some View {
        Group {
            if authViewModel.currentUser != nil {
                mainAppView
            } else {
                LoginView(authViewModel: authViewModel)
            }
        }
        .overlay {
            if isAppLocked {
                AppLockView(
                    biometricAuthService: dependencies.biometricAuthService,
                    onUnlock: {
                        hasUnlockedThisSession = true
                        isAppLocked = false
                    }
                )
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            authViewModel.observeAuthState()
            // Восстановление сессии Google без показа UI.
            await storagesViewModel.restoreConnection()
        }
        .onChange(of: authViewModel.currentUser != nil) { _, hasUser in
            if !hasUser {
                // Сессия завершена — при следующем входе снова спросим биометрию.
                hasUnlockedThisSession = false
                isAppLocked = false
            } else if shouldLock && !hasUnlockedThisSession {
                // Холодный старт / вход в аккаунт — блокируем сразу.
                isAppLocked = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard shouldLock else { return }
            switch newPhase {
            case .background, .inactive:
                // Сворачивание, блокировка экрана, app switcher.
                isAppLocked = true
            case .active:
                break
            @unknown default:
                break
            }
        }
        .onOpenURL { url in
            // Ссылка подтверждения email (passwordless sign-in).
            authViewModel.handleIncomingURL(url)
            // OAuth-колбэк Google Sign-In.
            dependencies.googleOAuthManager.handleURL(url)
            // QR-ссылка переноса подключений между устройствами.
            dependencies.deviceTransferCoordinator.handleIncomingURL(url)
            // Deep link из виджета хранилищ: claudvault://storage/{provider}
            handleStorageDeepLink(url)
            // Deep link создания бэкапа из виджета:
            // claudvault://backup/new?mode=file|scan
            handleBackupCreationDeepLink(url)
        }
    }

    /// Открывает раздел «Хранилища» по deep link виджета.
    /// Если в URL указан провайдер — выбирает его в ViewModel.
    private func handleStorageDeepLink(_ url: URL) {
        guard let link = StorageDeepLink.parse(url) else { return }

        selectedTab = .storages

        if let provider = link.provider,
           storagesViewModel.availableProviders.contains(provider) {
            storagesViewModel.selectedProvider = provider
        }
    }

    /// Открывает создание резервной копии по deep link виджета.
    /// Само действие (пикер файла / сканер) выполнит
    /// `BackupListView` через `backupActionRouter`.
    private func handleBackupCreationDeepLink(_ url: URL) {
        guard let link = BackupCreationDeepLink.parse(url) else { return }
        selectedTab = .files
        backupActionRouter.request(link.request)
    }
    private var mainAppView: some View {
        TabView(selection: $selectedTab) {
            BackupListView(
                fetchBackupRecords: dependencies.fetchBackupRecords,
                fileAccessRepository: dependencies.fileAccessRepository,
                fileHasher: dependencies.fileHasher,
                backupMetadataRepository: dependencies.backupMetadataRepository,
                storagesViewModel: storagesViewModel,
                createBackupWithUpload: dependencies.createBackupWithUpload,
                deleteBackupUseCase: dependencies.deleteBackup,
                reparseAndBackupUseCase: dependencies.reparseAndBackup,
                fetchBackupVersions: dependencies.fetchBackupVersions,
                actionRouter: backupActionRouter
            )
            .tabItem {
                Label(
                    AppTab.files.title,
                    systemImage: selectedTab == .files
                        ? AppTab.files.selectedIcon
                        : AppTab.files.icon
                )
            }
            .tag(AppTab.files)

            // MARK: - Storages

            NavigationStack {
                StoragesView(viewModel: storagesViewModel)
            }
            .tabItem {
                Label(
                    AppTab.storages.title,
                    systemImage: selectedTab == .storages
                        ? AppTab.storages.selectedIcon
                        : AppTab.storages.icon
                )
            }
            .tag(AppTab.storages)

            // MARK: - Synchronization

            NavigationStack {
                SynchronizationView(
                    viewModel: dependencies.makeSynchronizationViewModel()
                )
            }
            .tabItem {
                Label(
                    AppTab.synchronization.title,
                    systemImage: selectedTab == .synchronization
                        ? AppTab.synchronization.selectedIcon
                        : AppTab.synchronization.icon
                )
            }
            .tag(AppTab.synchronization)

            // MARK: - Settings

            NavigationStack {
                SettingsView(
                    authViewModel: authViewModel,
                    deviceTransferCoordinator: dependencies.deviceTransferCoordinator
                )
            }
            .tabItem {
                Label(
                    AppTab.settings.title,
                    systemImage: selectedTab == .settings
                        ? AppTab.settings.selectedIcon
                        : AppTab.settings.icon
                )
            }
            .tag(AppTab.settings)
        }
        .sheet(isPresented: Binding(
            get: { dependencies.deviceTransferCoordinator.isPresented },
            set: { dependencies.deviceTransferCoordinator.isPresented = $0 }
        )) {
            DeviceTransferView(
                viewModel: dependencies.makeDeviceTransferViewModel()
            )
        }
    }
}
