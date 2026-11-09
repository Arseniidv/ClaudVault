import SwiftUI
import SwiftData
import FirebaseCore
import SwiftyDropbox

@main
@MainActor
struct ClaudVaultApp: App {

    #if os(macOS)
    /// macOS AppDelegate: принимает файлы через системные Services.
    @NSApplicationDelegateAdaptor(ClaudVaultMacAppDelegate.self)
    private var macAppDelegate
    #endif

    private let dependencies: AppDependencies

    /// Единый VM Menu Bar (macOS): читает те же зависимости,
    /// что и основное окно. На других платформах не используется.
    private let menuBarViewModel: MenuBarViewModel

    init() {
        // 1. Инициализируем Firebase
        FirebaseApp.configure()
        
        // 2. Инициализируем Dropbox App Key (совпадает с URL-схемой db-… в Info.plist).
        // Токены Dropbox храним в едином Keychain-сервисе приложения
        // через DropboxSecureStorageAccess вместо легаси-хранилища SDK.
        let dropboxStorage = DropboxSecureStorageAccess()
        #if os(iOS)
        DropboxClientsManager.setupWithAppKey(
            DropboxAuthManager.appKey,
            secureStorageAccess: dropboxStorage
        )
        #elseif os(macOS)
        DropboxClientsManager.setupWithAppKeyDesktop(
            DropboxAuthManager.appKey,
            secureStorageAccess: dropboxStorage
        )
        #endif

        // Собираем зависимости в локальную переменную: `self`
        // ещё не инициализирован, поэтому читать `self.dependencies`
        // для MenuBarViewModel на этом этапе нельзя.
        let resolvedDependencies: AppDependencies
        do {
            // 3. Создаём SwiftData Container
            let container = try Self.makeContainer()
            resolvedDependencies = Self.makeDependencies(
                container: container
            )
        } catch {
            // Хранилище повреждено и даже аварийный сброс не помог —
            // не падаем: поднимаемся на in-memory контейнере, чтобы
            // приложение осталось работоспособным (данные бэкапов
            // в этом сценарии уже недоступны в любом случае).
            do {
                let container = try CloudVaultModelContainer.make(
                    inMemory: true
                )
                resolvedDependencies = Self.makeDependencies(
                    container: container
                )
            } catch {
                fatalError(
                    "Не удалось инициализировать зависимости: \(error)"
                )
            }
        }
        self.dependencies = resolvedDependencies

        #if os(macOS)
        // Radial Menu: собираем контекст действий, регистрируем
        // глобальную клавишу ⌥Space и Services.
        RadialMenuAppIntegration.configure(
            dependencies: resolvedDependencies
        )
        #endif

        self.menuBarViewModel = MenuBarViewModel(
            dependencies: resolvedDependencies
        )

        // Аудиоплеер — синглтон на процесс: настраиваем
        // аудиосессию, системные команды и шину команд
        // виджета при старте, чтобы воспроизведение
        // работало и при закрытом окне.
        resolvedDependencies.audioPlayerService.activate()
    }

    /// Строит контейнер: сначала персистентный, при повреждении
    /// стора `CloudVaultModelContainer` сам сбрасывает файл и
    /// повторяет попытку.
    private static func makeContainer() throws -> ModelContainer {
        try CloudVaultModelContainer.make(inMemory: false)
    }

    /// Собирает зависимости приложения поверх готового контейнера.
    private static func makeDependencies(
        container: ModelContainer
    ) -> AppDependencies {
        // 4. Создаём репозитории
        let repository = BackupMetadataRepositoryImpl(
            modelContext: container.mainContext
        )

        let fileAccessRepository = LocalFileAccess()
        let fileHasher = SHA256FileHasher()

        // 5. Собираем зависимости приложения
        return AppDependencies(
            modelContainer: container,
            fetchBackupRecords: FetchBackupRecordsUseCase(
                repository: repository
            ),
            fileAccessRepository: fileAccessRepository,
            fileHasher: fileHasher,
            backupMetadataRepository: repository
        )
    }

    var body: some Scene {
        #if os(macOS)
        // `Window` (не WindowGroup) гарантирует единственный
        // экземпляр основного окна: закрытие окна не завершает
        // приложение, а `openWindow(id: "main")` из Menu Bar
        // переиспользует то же окно вместо создания дубля.
        Window("CloudVault", id: "main") {
            rootContent
        }
        .commands {
            // Те же команды, что в меню «+» на экране «Файлы»:
            // идут через BackupActionRouter и исполняются
            // BackupListView, когда окно открыто.
            CommandMenu("Файл") {
                Button("Загрузить файлы…") {
                    dependencies.backupActionRouter.request(.pickFile)
                }
                .keyboardShortcut("u")

                Button("Загрузить папку…") {
                    dependencies.backupActionRouter.request(.pickFolder)
                }

                Button("Новая папка") {
                    dependencies.backupActionRouter.request(.newFolder)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Menu("Добавить облако") {
                    ForEach(connectableCloudProviders, id: \.self) { kind in
                        Button(kind.name) {
                            dependencies.backupActionRouter
                                .request(.connectCloud(kind))
                        }
                    }
                }
            }
        }

        // Постоянный пункт в Menu Bar: иконка отражает статус
        // (sync/error/disconnected), клик открывает компактный
        // поповер с действиями и состоянием провайдеров.
        MenuBarExtra {
            MenuBarView(viewModel: menuBarViewModel)
        } label: {
            Image(systemName: menuBarViewModel.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // Настройки — отдельное окно по ⌘, ( macOS Settings-сцена ).
        Settings {
            SettingsView(
                authViewModel: dependencies.makeAuthViewModel(),
                deviceTransferCoordinator: dependencies.deviceTransferCoordinator
            )
        }
        #else
        WindowGroup {
            rootContent
        }
        #endif
    }

    /// Провайдеры, доступные для подключения и ещё не
    /// подключённые — пункты подменю «Добавить облако».
    private var connectableCloudProviders: [StorageProviderType] {
        let viewModel = dependencies.storagesViewModel
        let connected = Set(viewModel.connectedProviders)
        return viewModel.availableProviders.filter {
            !connected.contains($0)
        }
    }

    /// Содержимое главного окна — общее для `Window` (macOS)
    /// и `WindowGroup` (остальные платформы).
    @ViewBuilder
    private var rootContent: some View {
        RootView(dependencies: dependencies)
            .modelContainer(dependencies.modelContainer)
            // Live Activities для фоновых загрузок:
            // монитор сверяет UploadSession с ActivityKit.
            .task {
                LiveActivityManager.shared.startMonitoring(
                    fetchSessions: dependencies.fetchUpSession
                )
            }
            // 6. Перехватываем URL от Dropbox при возврате в приложение после авторизации
            .onOpenURL { url in
                #if os(macOS)
                // Deep link Radial Menu из Finder Sync Extension:
                // claudvault://radial/open?request=<uuid>
                if RadialMenuCoordinator.shared.handleDeepLink(url) {
                    return
                }
                #endif
                dependencies.dropboxAuthManager.handleRedirectURL(url)
            }
    }
}
