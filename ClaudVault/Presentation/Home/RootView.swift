
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

@MainActor
struct RootView: View {
    let dependencies: AppDependencies
    @StateObject private var authViewModel: AuthViewModel
    @State private var storagesViewModel: StoragesViewModel
    @State private var selectedTab: AppTab = .files
    #if os(iOS)
    /// Выбранный раздел iPad-сайдбара (NavigationSplitView).
    @State private var ipadSection: IPadSection = .files
    #endif
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @State private var isAppLocked = false
    /// Полноэкранный аудиоплеер (открывается из мини-плеера
    /// или deep link `claudvault://player` из виджета).
    @State private var showAudioPlayer = false
    /// Роутер deep link'ов создания бэкапа живёт в
    /// `AppDependencies`, чтобы быть доступным не только
    /// этому окну, но и Menu Bar.
    /// Приложение уже было разблокировано в этой сессии (нет смысла
    /// запирать повторно при каждом scenePhase → .active).
    @State private var hasUnlockedThisSession = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    /// Открывает окно настроек (⌘,) — macOS Settings-сцена.
    @Environment(\.openSettings) private var openSettings
    #endif

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
        .onChange(of: dependencies.navigationRouter.pending?.id) { _, _ in
            // Запрос навигации извне окна (Menu Bar):
            // переключаем вкладку и потребляем запрос.
            guard let request = dependencies.navigationRouter.pending
            else { return }

            #if os(macOS)
            // На macOS настройки — отдельное окно (Settings-сцена),
            // а не вкладка: открываем его и не меняем раздел.
            if request.tab == .settings {
                openSettings()
                dependencies.navigationRouter.consume()
                return
            }
            #endif

            selectedTab = request.tab
            #if os(iOS)
            ipadSection = IPadSection(rawValue: request.tab.rawValue)
                ?? .files
            #endif

            if let provider = request.provider,
               storagesViewModel.availableProviders.contains(provider) {
                storagesViewModel.selectedProvider = provider
            }

            dependencies.navigationRouter.consume()
        }
        .onChange(of: authViewModel.currentUser?.id) { _, _ in
            // Смена пользователя CloudVault: сбрасываем состояние
            // облачных подключений предыдущего аккаунта и
            // восстанавливаем сессии уже от имени нового.
            // Контекст владельца к этому моменту уже переключён
            // UserSessionCoordinator'ом в auth-потоке.
            Task { await storagesViewModel.handleUserChange() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // OAuth Dropbox выполняется во внешнем браузере: пока он
            // открыт, приложение в inactive/background — это не должно
            // блокировать CloudVault, иначе после возврата пользователь
            // проходил бы повторную разблокировку. Firebase-сессия при
            // этом не затрагивается.
            guard shouldLock,
                  !dependencies.dropboxAuthManager
                      .isExternalAuthorizationInProgress
            else { return }
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
            // Deep link аудиоплеера из виджета:
            // claudvault://player
            if url.scheme == "claudvault", url.host == "player",
               authViewModel.currentUser != nil {
                showAudioPlayer = true
            }
        }
    }

    /// Открывает раздел «Хранилища» по deep link виджета.
    /// Если в URL указан провайдер — выбирает его в ViewModel.
    private func handleStorageDeepLink(_ url: URL) {
        guard let link = StorageDeepLink.parse(url) else { return }

        selectedTab = .storages
        #if os(iOS)
        ipadSection = .storages
        #endif

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
        #if os(iOS)
        ipadSection = .files
        #endif
        dependencies.backupActionRouter.request(link.request)
    }
    private var mainAppView: some View {
        Group {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPadOS: адаптивный NavigationSplitView с сайдбаром
                // и инспектором. iPhone и macOS остаются на TabView.
                IPadRootView(
                    selection: $ipadSection,
                    dependencies: dependencies,
                    authViewModel: authViewModel,
                    storagesViewModel: storagesViewModel,
                    backupActionRouter: dependencies.backupActionRouter
                )
            } else {
                tabView
            }
            #else
            // macOS: NavigationSplitView с боковой панелью
            // разделов и облаков; настройки — в окне ⌘,.
            MacRootView(
                selection: $selectedTab,
                dependencies: dependencies,
                storagesViewModel: storagesViewModel
            )
            #endif
        }
        .sheet(isPresented: Binding(
            get: { dependencies.deviceTransferCoordinator.isPresented },
            set: { dependencies.deviceTransferCoordinator.isPresented = $0 }
        )) {
            DeviceTransferView(
                viewModel: dependencies.makeDeviceTransferViewModel()
            )
        }
        // Мини-плеер поверх всех разделов: виден, пока в
        // очереди есть трек. Тап открывает полный плеер.
        .overlay(alignment: .bottom) {
            MiniPlayerView(service: dependencies.audioPlayerService) {
                showAudioPlayer = true
            }
            .animation(.easeInOut(duration: 0.25), value: dependencies.audioPlayerService.currentTrack != nil)
        }
        .sheet(isPresented: $showAudioPlayer) {
            AudioPlayerView(service: dependencies.audioPlayerService)
        }
    }

    /// TabView-разметка для iPhone и macOS — без изменений.
    private var tabView: some View {
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
                transferBackupToProvider: dependencies.transferBackupToProvider,
                renameBackupUseCase: dependencies.renameBackup,
                fetchBackupVersions: dependencies.fetchBackupVersions,
                actionRouter: dependencies.backupActionRouter
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
    }
}
