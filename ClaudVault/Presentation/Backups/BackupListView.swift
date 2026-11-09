import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
struct BackupListView: View {
    // MARK: - Properties
    @State private var viewModel: BackupListViewModel
    @State private var storagesViewModel: StoragesViewModel
    @State private var searchText = ""
    @State private var selectedSort: RecentFilesView.SortOption = .latest
    @State private var selectedProvider: StorageProviderType? = nil
    /// Внешний фильтр облака (macOS: выбор в боковой панели).
    /// Если задан — заменяет внутренний `selectedProvider`.
    private let externalProviderFilter: Binding<StorageProviderType?>?
    /// Роутер навигации по разделам (нужен macOS-меню «+»
    /// для перехода к подключению облака).
    private let navigationRouter: AppNavigationRouter?
    @State private var selectedRecord: BackupRecord?
    @State private var previewFileURL: URL?
    @State private var isDownloadingPreview = false
    /// Файл из облака, открытый в типизированном предпросмотре
    /// по long press (не путать с `previewFileURL` — QuickLook).
    @State private var previewItem: FilePreviewItem?
    /// macOS: состояние таблицы файлов.
    #if os(macOS)
    @State private var tableSortOrder = [
        KeyPathComparator(\BackupTableRow.record.updatedAt, order: .reverse)
    ]
    @State private var tableSelection = Set<UUID>()
    #endif
    /// fileImporter для «Загрузить папку…».
    @State private var isFolderImporterPresented = false
    /// Алерт «Новая папка» из меню «+».
    @State private var isNewFolderAlertPresented = false
    @State private var newFolderName = ""

    private let fileAccessRepository: FileAccessRepository
    private let fileHasher: FileHashing
    private let backupMetadataRepository: BackupMetadataRepository
    private let createBackupWithUpload: CreateBackupWithUploadUseCase
    private let deleteBackupUseCase: DeleteBackupUseCase
    private let reparseAndBackupUseCase: ReparseAndBackupUseCase
    private let transferBackupToProvider: TransferBackupToProviderUseCase?
    private let renameBackupUseCase: RenameBackupUseCase?
    private let fetchBackupVersions: FetchBackupVersionsUseCase
    /// Роутер deep link'ов виджета (`claudvault://backup/new?mode=…`).
    private let actionRouter: BackupActionRouter?

    @State private var isCreateBackupPresented = false
    @State private var isScannerPresented = false
    /// URL PDF, сгенерированного сканером документов. Передаётся
    /// в `CreateBackupView` как предвыбранный файл.
    @State private var pendingScannedPDFURL: URL?
    /// Обёртка для `sheet(item:)`: гарантирует, что `CreateBackupView`
    /// строится с уже готовым URL скана.
    @State private var scannedDocument: ScannedDocument?
    /// Флаг авто-открытия fileImporter — взводится deep link'ом
    /// `?mode=file`, sheet читает его один раз.
    @State private var pendingAutoOpenImporter = false

    // MARK: - Initializer
    init(
        fetchBackupRecords: FetchBackupRecordsUseCase,
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        backupMetadataRepository: BackupMetadataRepository,
        storagesViewModel: StoragesViewModel,
        createBackupWithUpload: CreateBackupWithUploadUseCase,
        deleteBackupUseCase: DeleteBackupUseCase,
        reparseAndBackupUseCase: ReparseAndBackupUseCase,
        transferBackupToProvider: TransferBackupToProviderUseCase? = nil,
        renameBackupUseCase: RenameBackupUseCase? = nil,
        fetchBackupVersions: FetchBackupVersionsUseCase,
        actionRouter: BackupActionRouter? = nil,
        providerFilter: Binding<StorageProviderType?>? = nil,
        navigationRouter: AppNavigationRouter? = nil
    ) {
        let listViewModel = BackupListViewModel(
            fetchBackupRecords: fetchBackupRecords,
            deleteBackupUseCase: deleteBackupUseCase,
            calculateStorageUsage: CalculateStorageUsageUseCase(
                repository: backupMetadataRepository
            ),
            backupMetadataRepository: backupMetadataRepository
        )
        _viewModel = State(initialValue: listViewModel)
        _storagesViewModel = State(wrappedValue: storagesViewModel)
        self.fileAccessRepository = fileAccessRepository
        self.fileHasher = fileHasher
        self.backupMetadataRepository = backupMetadataRepository
        self.createBackupWithUpload = createBackupWithUpload
        self.deleteBackupUseCase = deleteBackupUseCase
        self.reparseAndBackupUseCase = reparseAndBackupUseCase
        self.transferBackupToProvider = transferBackupToProvider
        self.renameBackupUseCase = renameBackupUseCase
        self.fetchBackupVersions = fetchBackupVersions
        self.actionRouter = actionRouter
        self.externalProviderFilter = providerFilter
        self.navigationRouter = navigationRouter
    }

    // MARK: - Computed Properties

    /// Привязка фильтра облака: внешняя (macOS-сайдбар)
    /// или внутренняя (чипы на iOS/macOS).
    private var providerSelection: Binding<StorageProviderType?> {
        externalProviderFilter ?? $selectedProvider
    }

    /// Текущее значение фильтра облака.
    private var activeProviderFilter: StorageProviderType? {
        providerSelection.wrappedValue
    }

    /// Провайдер для операций «Загрузить папку…»/«Новая папка»:
    /// фильтр сайдбара → первое подключённое облако → текущий
    /// выбранный провайдер VM.
    private var cloudTargetProvider: StorageProviderType {
        activeProviderFilter
            ?? storagesViewModel.connectedProviders.first
            ?? storagesViewModel.selectedProvider
    }

    /// Подключённые облачные провайдеры с реальным usage — как на экране «Хранилища».
    private var providers: [StorageProvider] {
        storagesViewModel.connectedStorageProviders
    }

    /// Провайдеры, попадающие под текущий фильтр чипсов.
    private var visibleProviders: [StorageProvider] {
        providers.filter {
            activeProviderFilter == nil || $0.provider == activeProviderFilter
        }
    }

    /// Суммарно занятое место по видимым провайдерам, GB.
    private var usedStorage: Double {
        visibleProviders.reduce(0) { $0 + $1.usedStorage }
    }

    /// Суммарная ёмкость по видимым провайдерам, GB.
    private var totalStorage: Double {
        visibleProviders.reduce(0) { $0 + $1.totalStorage }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            #if os(macOS)
            macOSContent
            #else
            ZStack(alignment: .bottomTrailing) {
                AppColors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        FilesHeaderView(selectedSort: $selectedSort)

                        SearchSectionView(searchText: $searchText)

                        FilterSelectorView(
                            selectedProvider: providerSelection,
                            providers: storagesViewModel.connectedProviders
                        )

                        if !searchText.isEmpty {
                            cloudSearchSection
                        }

                        StorageOverviewView(
                            providers: visibleProviders,
                            usedStorage: usedStorage,
                            totalStorage: totalStorage,
                            backupVersionsBytes: viewModel.usedStorageBytes,
                            localFilesBytes: viewModel.localFilesBytes,
                            localFilesCount: viewModel.localFilesCount
                        )

                        recentlyOpenedSection

                        RecentFilesView(
                            records: viewModel.records,
                            searchText: searchText,
                            selectedSort: selectedSort,
                            providerFilter: activeProviderFilter,
                            onFileTap: { record in
                                selectedRecord = record
                            },
                            onDelete: { record in
                                Task {
                                    await viewModel.deleteRecord(record: record)
                                }
                            }
                        )

                        FooterSectionView(
                            connectedClouds: providers.count,
                            totalFiles: viewModel.records.count
                        )
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.screenVertical)
                }

                AddBackupButton(
                    action: { isCreateBackupPresented = true },
                    scanAction: { isScannerPresented = true }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .task {
            wireDataChangedHandler()
            viewModel.loadRecords()
            await storagesViewModel.loadStorageUsage()
            consumePendingBackupRequest()
        }
        // Deep link из виджета может прийти и после появления view.
        .onChange(of: actionRouter?.pendingRequest) { _, _ in
            consumePendingBackupRequest()
        }
        // Глобальный поиск по всем подключённым облакам с дебаунсом.
        .task(id: searchText) {
            let query = searchText
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                storagesViewModel.clearCloudSearch()
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await storagesViewModel.searchCloudFiles(query: query)
        }
        .navigationDestination(for: CloudFolderRoute.self) { route in
            CloudFolderBrowserView(
                provider: route.provider,
                route: route,
                storagesViewModel: storagesViewModel
            )
        }
        // «Загрузить папку…» и «Новая папка» из меню «+».
        .modifier(FolderActionsModifier(
            isFolderImporterPresented: $isFolderImporterPresented,
            isNewFolderAlertPresented: $isNewFolderAlertPresented,
            newFolderName: $newFolderName,
            storagesViewModel: storagesViewModel,
            cloudTargetProvider: cloudTargetProvider
        ))
        // Sheets и alert вынесены в модификатор — иначе
        // цепочка модификаторов не проходит type-check.
        .modifier(BackupSheetsModifier(
            isScannerPresented: $isScannerPresented,
            pendingScannedPDFURL: $pendingScannedPDFURL,
            scannedDocument: $scannedDocument,
            isCreateBackupPresented: $isCreateBackupPresented,
            pendingAutoOpenImporter: $pendingAutoOpenImporter,
            selectedRecord: $selectedRecord,
            previewFileURL: $previewFileURL,
            previewItem: $previewItem,
            errorMessage: Binding(
                get: { viewModel.errorMessage },
                set: { viewModel.errorMessage = $0 }
            ),
            storagesViewModel: storagesViewModel,
            makeDetailViewModel: makeDetailViewModel,
            createBackupView: { url, autoOpen in
                createBackupView(
                    initialFileURL: url,
                    autoOpenImporter: autoOpen
                )
            }
        ))
    }

    /// Подписывает список записей на изменения: перезагружает
    /// записи и статистику облаков. Вынесено из `.task`,
    /// чтобы не перегружать type-checker модификаторов.
    private func wireDataChangedHandler() {
        viewModel.onDataChanged = { [storagesViewModel, viewModel] in
            viewModel.loadRecords()
            Task { await storagesViewModel.loadStorageUsage() }
        }
    }

    /// Выполняет запрос на создание бэкапа, пришедший из виджета
    /// через deep link. Запрос снимается только здесь — если view
    /// ещё не создан (пользователь не авторизован), он дождётся
    /// появления этого экрана после входа.
    private func consumePendingBackupRequest() {
        guard let request = actionRouter?.pendingRequest else { return }
        actionRouter?.pendingRequest = nil

        switch request {
        case .pickFile:
            pendingAutoOpenImporter = true
            isCreateBackupPresented = true
        case .scanDocument:
            isScannerPresented = true
        case .pickFolder:
            isFolderImporterPresented = true
        case .newFolder:
            isNewFolderAlertPresented = true
        case .connectCloud(let provider):
            // Подключение облака живёт на экране «Хранилища»:
            // просим VM открыть шит и переключаем раздел.
            storagesViewModel.selectedProvider = provider
            storagesViewModel.requestConnect(provider: provider)
            navigationRouter?.request(.storages, provider: provider)
        }
    }

    @ViewBuilder
    private func createBackupView(
        initialFileURL: URL?,
        autoOpenImporter: Bool = false
    ) -> CreateBackupView {
        CreateBackupView(
            fileAccessRepository: fileAccessRepository,
            fileHasher: fileHasher,
            createBackupWithUpload: createBackupWithUpload,
            availableProviders: storagesViewModel.connectedProviders,
            initialFileURL: initialFileURL,
            autoOpenImporter: autoOpenImporter,
            onCreated: {
                viewModel.loadRecords()
                Task { await storagesViewModel.loadStorageUsage() }
            }
        )
    }

    private func makeDetailViewModel(for record: BackupRecord) -> BackupVersionsViewModel {
        let detailViewModel = BackupVersionsViewModel(
            record: record,
            fetchBackupVersions: fetchBackupVersions,
            deleteBackupUseCase: deleteBackupUseCase,
            reparseAndBackupUseCase: reparseAndBackupUseCase,
            transferBackupToProvider: transferBackupToProvider,
            renameBackupUseCase: renameBackupUseCase,
            transferTargets: storagesViewModel.connectedProviders,
            backupMetadataRepository: backupMetadataRepository
        )
        detailViewModel.onDataChanged = { [storagesViewModel] in
            viewModel.loadRecords()
            Task { await storagesViewModel.loadStorageUsage() }
        }
        return detailViewModel
    }

    // MARK: - Cloud Search

    /// Секция результатов глобального поиска по всем подключённым дискам.
    @ViewBuilder
    private var cloudSearchSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 8) {
                Text("Файлы в облаке")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                if storagesViewModel.isCloudSearchRunning {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .scaleEffect(0.7)
                }
            }

            if storagesViewModel.cloudSearchResults.isEmpty
                && !storagesViewModel.isCloudSearchRunning {
                Text("Ничего не найдено в подключённых хранилищах.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(storagesViewModel.cloudSearchResults) { result in
                    cloudResultRow(result)
                }
            }
        }
    }

    /// Строка результата поиска: папка → push-навигация в браузер
    /// папки, файл → скачивание + QuickLook-просмотр.
    @ViewBuilder
    private func cloudResultRow(_ result: StoragesViewModel.CloudSearchResult) -> some View {
        if result.file.isFolder {
            NavigationLink(value: CloudFolderRoute(
                provider: result.provider,
                folderID: result.file.id,
                folderName: result.file.name
            )) {
                cloudResultRowContent(result, icon: "folder.fill", tint: .orange)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await handleCloudFileTap(result) }
            } label: {
                cloudResultRowContent(result, icon: "doc.fill", tint: result.provider.tint)
            }
            .buttonStyle(.plain)
            // Long press — типизированный предпросмотр; тап — QuickLook.
            .onLongPressGesture(minimumDuration: 0.5) {
                previewItem = FilePreviewItem(
                    provider: result.provider,
                    file: result.file
                )
            }
        }
    }

    private func cloudResultRowContent(
        _ result: StoragesViewModel.CloudSearchResult,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.file.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(result.provider.tint)
                            .frame(width: 6, height: 6)

                        Text(result.provider.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.55))
                    }
                }

                Spacer()

                if let size = result.file.sizeBytes {
                    Text(ByteFormatting.string(fromByteCount: size))
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.45))
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Тап по файлу из результатов поиска: скачивание во временный
    /// кэш и QuickLook-просмотр.
    private func handleCloudFileTap(
        _ result: StoragesViewModel.CloudSearchResult
    ) async {
        guard !isDownloadingPreview else { return }
        isDownloadingPreview = true
        defer { isDownloadingPreview = false }

        do {
            let url = try await storagesViewModel.downloadForPreview(
                result.file,
                provider: result.provider
            )
            previewFileURL = url
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recently Opened Cloud Files

    /// Секция «Последние открытые»: облачные файлы, которые пользователь
    /// открывал (превью/плеер/свойства). При выбранном фильтре-чипе
    /// показываются только файлы этого провайдера.
    @ViewBuilder
    private var recentlyOpenedSection: some View {
        let items = storagesViewModel.openedFiles(for: activeProviderFilter)

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Последние открытые")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                ForEach(items) { opened in
                    openedFileRow(opened)
                }
            }
        }
    }

    private func openedFileRow(_ opened: OpenedCloudFile) -> some View {
        Button {
            Task { await handleOpenedFileTap(opened) }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(opened.provider.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(opened.file.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(opened.provider.tint)
                            .frame(width: 6, height: 6)

                        Text(opened.provider.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.55))

                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.35))

                        Text(opened.openedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.45))
                    }
                }

                Spacer()
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // Long press — типизированный предпросмотр; тап — QuickLook.
        .onLongPressGesture(minimumDuration: 0.5) {
            previewItem = FilePreviewItem(
                provider: opened.provider,
                file: opened.file
            )
        }
    }

    /// Тап по файлу из «Последних открытых»: скачивание
    /// во временный кэш и QuickLook-просмотр.
    private func handleOpenedFileTap(_ opened: OpenedCloudFile) async {
        guard !isDownloadingPreview else { return }
        isDownloadingPreview = true
        defer { isDownloadingPreview = false }

        do {
            let url = try await storagesViewModel.downloadForPreview(
                opened.file,
                provider: opened.provider
            )
            previewFileURL = url
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }


    // MARK: - Backup List
    private var backupList: some View {
        List {
            ForEach(viewModel.records) { record in
                HStack(spacing: AppSpacing.sm) {
                    NavigationLink {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("История версий")
                                .font(.title)
                            Text("Файл: \(record.fileName)")
                            Text("ID записи: \(record.id.uuidString)")
                        }
                        .padding()
                    } label: {
                        backupRowContent(record)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }

    // MARK: - Backup Row Content
    private func backupRowContent(_ record: BackupRecord) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(record.fileName)
                    .font(AppTypography.bodyMedium)

                Text(
                    "Обновлено: \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Empty State
    private var emptyState: some View {
        ContentUnavailableView(
            "Нет резервных копий",
            systemImage: "externaldrive",
            description: Text(
                "Создайте первую резервную копию, чтобы она появилась здесь."
            )
        )
    }
}

// MARK: - macOS

#if os(macOS)
extension BackupListView {

    /// Раскладка macOS: таблица файлов на всю ширину,
    /// карточка хранилища и «последние открытые» — в правой
    /// колонке, поиск — в тулбаре через `.searchable`.
    var macOSContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                FilterSelectorView(
                    selectedProvider: providerSelection,
                    providers: storagesViewModel.connectedProviders
                )
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.sm)

                if !searchText.isEmpty {
                    ScrollView {
                        cloudSearchSection
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .padding(.vertical, AppSpacing.sm)
                    }
                    .frame(maxHeight: 240)
                }

                filesTable
            }
            .frame(minWidth: 480, idealWidth: 640)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    StorageOverviewView(
                        providers: visibleProviders,
                        usedStorage: usedStorage,
                        totalStorage: totalStorage,
                        backupVersionsBytes: viewModel.usedStorageBytes,
                        localFilesBytes: viewModel.localFilesBytes,
                        localFilesCount: viewModel.localFilesCount
                    )

                    recentlyOpenedSection

                    FooterSectionView(
                        connectedClouds: providers.count,
                        totalFiles: viewModel.records.count
                    )
                }
                .padding(AppSpacing.md)
            }
            .frame(minWidth: 240, idealWidth: 290, maxWidth: 340)
        }
        .navigationTitle("Файлы")
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
        }
    }

    /// Меню «+» в тулбаре окна — macOS-аналог плавающей
    /// кнопки на iOS. Те же команды доступны в меню «Файл»
    /// и через `BackupActionRouter`.
    private var addMenu: some View {
        Menu {
            Button("Загрузить файлы…") {
                requestBackup(.pickFile)
            }
            .keyboardShortcut("u", modifiers: .command)

            Button("Загрузить папку…") {
                requestBackup(.pickFolder)
            }

            Button("Новая папка") {
                requestBackup(.newFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Menu("Добавить облако") {
                ForEach(connectableProviders, id: \.self) { kind in
                    Button(kind.name) {
                        requestBackup(.connectCloud(kind))
                    }
                }
            }
        } label: {
            Label("Добавить", systemImage: "plus")
        }
        .help("Добавить файлы или облако")
    }

    /// Провайдеры, которых ещё нет среди подключённых —
    /// кандидаты для «Добавить облако…».
    private var connectableProviders: [StorageProviderType] {
        let connected = Set(storagesViewModel.connectedProviders)
        return storagesViewModel.availableProviders.filter {
            !connected.contains($0)
        }
    }

    private func requestBackup(_ request: BackupCreationRequest) {
        actionRouter?.request(request)
    }

    /// Строки таблицы: записи, отфильтрованные облаком
    /// и поисковым запросом (как `RecentFilesView` на iOS).
    private var tableRows: [BackupTableRow] {
        viewModel.records
            .filter { record in
                (activeProviderFilter == nil
                    || record.storageProvider == activeProviderFilter)
                    && (searchText.isEmpty
                        || record.fileName
                            .localizedCaseInsensitiveContains(searchText))
            }
            .map {
                BackupTableRow(
                    record: $0,
                    sizeBytes: viewModel.recordSizes[$0.id]
                )
            }
    }

    private var filesTable: some View {
        MacBackupTable(
            rows: tableRows,
            sortOrder: $tableSortOrder,
            selection: $tableSelection,
            isLoading: viewModel.isLoading,
            loadFailed: viewModel.errorMessage != nil,
            searchQuery: searchText,
            providerFilterActive: activeProviderFilter != nil,
            filterProviderConnected: activeProviderFilter.map {
                storagesViewModel.connectedProviders.contains($0)
            } ?? true,
            onOpen: { record in
                selectedRecord = record
            },
            onDelete: { record in
                Task { await viewModel.deleteRecord(record: record) }
            },
            onQuickLook: { record in
                Task { await previewRecord(record) }
            },
            onCreate: {
                pendingAutoOpenImporter = true
                isCreateBackupPresented = true
            },
            onRetry: {
                viewModel.loadRecords()
            }
        )
    }

    /// Быстрый просмотр записи бэкапа: скачивает последнюю
    /// версию из облака во временный кэш и показывает QuickLook.
    private func previewRecord(_ record: BackupRecord) async {
        guard !isDownloadingPreview else { return }

        let provider = record.storageProvider
        guard storagesViewModel.connectedProviders.contains(provider),
              let version = viewModel.latestVersion(for: record.id)
        else {
            viewModel.errorMessage =
                "Не удалось подготовить файл для просмотра."
            return
        }

        isDownloadingPreview = true
        defer { isDownloadingPreview = false }

        let ext = URL(fileURLWithPath: record.fileName).pathExtension
        let mimeType = UTType(filenameExtension: ext)?
            .preferredMIMEType ?? "application/octet-stream"
        let cloudFile = CloudFile(
            id: version.cloudObjectID,
            name: record.fileName,
            mimeType: mimeType,
            sizeBytes: version.fileSize,
            modifiedAt: version.uploadedAt
        )

        do {
            previewFileURL = try await storagesViewModel
                .downloadForPreview(cloudFile, provider: provider)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
#endif

// MARK: - Sheets & Alerts

/// Идентифицируемая обёртка для PDF из сканера — нужна для
/// `sheet(item:)`, чтобы content-геттер всегда получал актуальный URL.
struct ScannedDocument: Identifiable {
    let id = UUID()
    let fileURL: URL
}

/// Все sheet'ы и alert списка бэкапов — вынесены из `body`,
/// чтобы не перегружать type-checker цепочки модификаторов.
struct BackupSheetsModifier: ViewModifier {
    @Binding var isScannerPresented: Bool
    @Binding var pendingScannedPDFURL: URL?
    @Binding var scannedDocument: ScannedDocument?
    @Binding var isCreateBackupPresented: Bool
    @Binding var pendingAutoOpenImporter: Bool
    @Binding var selectedRecord: BackupRecord?
    @Binding var previewFileURL: URL?
    @Binding var previewItem: FilePreviewItem?
    let errorMessage: Binding<String?>
    let storagesViewModel: StoragesViewModel
    let makeDetailViewModel: (BackupRecord) -> BackupVersionsViewModel
    let createBackupView: (URL?, Bool) -> CreateBackupView

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .sheet(isPresented: $isScannerPresented, onDismiss: {
                // После закрытия сканера открываем создание бэкапа
                // с готовым PDF-сканом.
                if let url = pendingScannedPDFURL {
                    pendingScannedPDFURL = nil
                    scannedDocument = ScannedDocument(fileURL: url)
                }
            }) {
                DocumentScannerView(
                    onScanComplete: { url in
                        pendingScannedPDFURL = url
                        isScannerPresented = false
                    },
                    onCancel: {
                        isScannerPresented = false
                    },
                    onError: { error in
                        errorMessage.wrappedValue = error.localizedDescription
                        isScannerPresented = false
                    }
                )
            }
            #endif
            .sheet(isPresented: $isCreateBackupPresented, onDismiss: {
                pendingAutoOpenImporter = false
            }) {
                createBackupView(nil, pendingAutoOpenImporter)
            }
            .sheet(item: $scannedDocument) { document in
                createBackupView(document.fileURL, false)
            }
            .sheet(item: $selectedRecord) { record in
                BackupRecordDetailView(
                    viewModel: makeDetailViewModel(record)
                )
            }
            .sheet(isPresented: Binding(
                get: { previewFileURL != nil },
                set: { isPresented in
                    if !isPresented {
                        // Удаляем временную копию после закрытия просмотра.
                        if let url = previewFileURL {
                            try? FileManager.default.removeItem(
                                at: url.deletingLastPathComponent()
                            )
                        }
                        previewFileURL = nil
                    }
                }
            )) {
                if let url = previewFileURL {
                    QuickLookPreview(url: url)
                }
            }
            .sheet(item: $previewItem) { item in
                FilePreviewView(item: item, storagesViewModel: storagesViewModel)
            }
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { errorMessage.wrappedValue != nil },
                    set: { if !$0 { errorMessage.wrappedValue = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage.wrappedValue = nil
                }
            } message: {
                Text(errorMessage.wrappedValue ?? "")
            }
    }
}

// MARK: - Folder Actions

/// «Загрузить папку…» (fileImporter → рекурсивная загрузка
/// в облако) и алерт «Новая папка» — команды меню «+».
/// Вынесено в модификатор, чтобы не перегружать цепочку
/// модификаторов `body` (type-check timeout).
struct FolderActionsModifier: ViewModifier {
    @Binding var isFolderImporterPresented: Bool
    @Binding var isNewFolderAlertPresented: Bool
    @Binding var newFolderName: String
    let storagesViewModel: StoragesViewModel
    let cloudTargetProvider: StorageProviderType

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isFolderImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    storagesViewModel.selectedProvider = cloudTargetProvider
                    Task {
                        await storagesViewModel.uploadFolder(fileURL: url)
                    }
                case .failure(let error):
                    storagesViewModel.selectedProvider = cloudTargetProvider
                    storagesViewModel.reportFilePickerError(error)
                }
            }
            .alert("Новая папка", isPresented: $isNewFolderAlertPresented) {
                TextField("Название папки", text: $newFolderName)

                Button("Создать") {
                    let name = newFolderName
                    newFolderName = ""
                    storagesViewModel.selectedProvider = cloudTargetProvider
                    Task {
                        await storagesViewModel.createFolder(
                            named: name,
                            in: cloudTargetProvider
                        )
                    }
                }

                Button("Отмена", role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text("Папка будет создана в текущей папке облака.")
            }
    }
}

// MARK: - Preview
private struct PreviewCloudStorageRepository: CloudStorageRepository {
    func getStorageUsage() async throws -> CloudStorageUsage {
        CloudStorageUsage(usedBytes: 0, totalBytes: 0, availableBytes: 0)
    }
    func connect() async throws -> CloudStorageAccount {
        throw CloudStorageError.notImplemented
    }
    func restoreConnection() async throws -> CloudStorageAccount? {
        nil
    }
    func signOut() async throws {}
    func listFiles(parentFolderID: String?) async throws -> [CloudFile] {
        []
    }
    func fileMetadata(id: String) async throws -> CloudFile {
        throw CloudStorageError.notFound
    }
    func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile {
        throw CloudStorageError.notImplemented
    }
    func uploadFile(
        at fileURL: URL,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        throw CloudStorageError.notImplemented
    }
    func deleteFile(id: String) async throws {
        throw CloudStorageError.notImplemented
    }
}

#Preview {
    let container = try! ModelContainer(
        for: BackupRecordModel.self, BackupVersionModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
    let mockStorageRepository = PreviewCloudStorageRepository()
    let fileAccess = LocalFileAccess()
    let hasher = SHA256FileHasher()
    let uploadRepository = UploadSessionRepositoryImpl(modelContainer: container)

    BackupListView(
        fetchBackupRecords: FetchBackupRecordsUseCase(repository: repository),
        fileAccessRepository: fileAccess,
        fileHasher: hasher,
        backupMetadataRepository: repository,
        storagesViewModel: StoragesViewModel(
            repository: mockStorageRepository
        ),
        createBackupWithUpload: CreateBackupWithUploadUseCase(
            backupRepository: repository,
            cloudStorageRepository: mockStorageRepository,
            fileHasher: hasher,
            fileAccessRepository: fileAccess,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: SaveUploadSessionUseCase(repository: uploadRepository),
            updateUploadProgressUseCase: UpdateUploadProgressUseCase(repository: uploadRepository)
        ),
        deleteBackupUseCase: DeleteBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: mockStorageRepository
        ),
        reparseAndBackupUseCase: ReparseAndBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: mockStorageRepository,
            fileHasher: hasher,
            fileAccessRepository: fileAccess,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: SaveUploadSessionUseCase(repository: uploadRepository),
            updateUploadProgressUseCase: UpdateUploadProgressUseCase(repository: uploadRepository)
        ),
        fetchBackupVersions: FetchBackupVersionsUseCase(repository: repository)
    )
    .modelContainer(container)
}
