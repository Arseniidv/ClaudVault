#if os(iOS)
import SwiftUI
import SwiftData
import ClaudVaultDomain

/// Файловый браузер для iPad-разметки.
///
/// Переиспользует ту же бизнес-логику, что и `BackupListView`
/// (те же use case'ы, ViewModel и компоненты), но с iPad-моделью
/// взаимодействия: поиск в тулбаре, сортировка/фильтрация меню,
/// переключение список/сетка, множественный выбор, контекстные
/// меню и инспектор выбранного файла.
@MainActor
struct IPadFilesView: View {

    // MARK: - Properties

    @State private var viewModel: BackupListViewModel
    @State private var storagesViewModel: StoragesViewModel
    @State private var searchText = ""
    @State private var selectedSort: RecentFilesView.SortOption = .latest
    @State private var selectedProvider: StorageProviderType? = nil
    @State private var selectedRecord: BackupRecord?
    @State private var previewFileURL: URL?
    @State private var isDownloadingPreview = false
    /// Файл из облака, открытый в типизированном предпросмотре
    /// по long press (не путать с `previewFileURL` — QuickLook).
    @State private var previewItem: FilePreviewItem?
    /// fileImporter для «Загрузить папку…» и алерт «Новая папка»
    /// — те же действия, что в меню «+» на iPhone/macOS.
    @State private var isFolderImporterPresented = false
    @State private var isNewFolderAlertPresented = false
    @State private var newFolderName = ""

    @State private var viewMode: ViewMode = .list
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var isInspectorPresented = false
    @State private var isConfirmingBatchDelete = false

    private let fileAccessRepository: FileAccessRepository
    private let fileHasher: FileHashing
    private let backupMetadataRepository: BackupMetadataRepository
    private let createBackupWithUpload: CreateBackupWithUploadUseCase
    private let deleteBackupUseCase: DeleteBackupUseCase
    private let reparseAndBackupUseCase: ReparseAndBackupUseCase
    private let transferBackupToProvider: TransferBackupToProviderUseCase?
    private let renameBackupUseCase: RenameBackupUseCase?
    private let fetchBackupVersions: FetchBackupVersionsUseCase
    private let actionRouter: BackupActionRouter?

    @State private var isCreateBackupPresented = false
    @State private var isScannerPresented = false
    @State private var pendingScannedPDFURL: URL?
    @State private var scannedDocument: ScannedDocument?
    @State private var pendingAutoOpenImporter = false

    enum ViewMode {
        case list
        case grid
    }

    // MARK: - Initializer (зеркалит BackupListView)

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
        actionRouter: BackupActionRouter? = nil
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
    }

    // MARK: - Computed Properties

    private var providers: [StorageProvider] {
        storagesViewModel.connectedStorageProviders
    }

    private var visibleProviders: [StorageProvider] {
        providers.filter {
            selectedProvider == nil || $0.provider == selectedProvider
        }
    }

    private var usedStorage: Double {
        visibleProviders.reduce(0) { $0 + $1.usedStorage }
    }

    private var totalStorage: Double {
        visibleProviders.reduce(0) { $0 + $1.totalStorage }
    }

    /// Записи после фильтра поиска/провайдера и сортировки —
    /// та же логика, что в `RecentFilesView`.
    private var displayedRecords: [BackupRecord] {
        let filtered = viewModel.records.filter { record in
            (selectedProvider == nil
             || record.storageProvider == selectedProvider) &&
            (searchText.isEmpty
             || record.fileName.localizedCaseInsensitiveContains(searchText))
        }

        switch selectedSort {
        case .latest:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest:
            return filtered.sorted { $0.updatedAt < $1.updatedAt }
        case .name:
            return filtered.sorted {
                $0.fileName.localizedCaseInsensitiveCompare($1.fileName)
                    == .orderedAscending
            }
        }
    }

    /// Провайдер для операций «Загрузить папку…»/«Новая папка»:
    /// фильтр → первое подключённое облако → текущий
    /// выбранный провайдер VM (как в BackupListView).
    private var cloudTargetProvider: StorageProviderType {
        selectedProvider
            ?? storagesViewModel.connectedProviders.first
            ?? storagesViewModel.selectedProvider
    }

    /// Записи, выбранные в режиме мультивыбора.
    private var selectedRecords: [BackupRecord] {
        viewModel.records.filter { selectedIDs.contains($0.id) }
    }

    /// Единственная выбранная запись для инспектора.
    private var inspectedRecord: BackupRecord? {
        selectedRecords.count == 1 ? selectedRecords.first : nil
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: {
                isInspectorPresented && !selectedIDs.isEmpty
            },
            set: { isInspectorPresented = $0 }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    FilterSelectorView(
                        selectedProvider: $selectedProvider,
                        providers: storagesViewModel.connectedProviders
                    )

                    StorageOverviewView(
                        providers: visibleProviders,
                        usedStorage: usedStorage,
                        totalStorage: totalStorage,
                        backupVersionsBytes: viewModel.usedStorageBytes,
                        localFilesBytes: viewModel.localFilesBytes,
                        localFilesCount: viewModel.localFilesCount
                    )

                    if !searchText.isEmpty {
                        cloudSearchSection
                    }

                    recentlyOpenedSection

                    recordsSection

                    FooterSectionView(
                        connectedClouds: providers.count,
                        totalFiles: viewModel.records.count
                    )
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.screenVertical)
            }
            .background(
                AppColors.background
                    .ignoresSafeArea()
            )
            .navigationTitle("Файлы")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск")
            .toolbar { toolbarContent }
            .inspector(isPresented: inspectorPresented) {
                inspectorContent
            }
            .task {
                viewModel.onDataChanged = { [storagesViewModel, viewModel] in
                    viewModel.loadRecords()
                    Task { await storagesViewModel.loadStorageUsage() }
                }
                viewModel.loadRecords()
                Task { await storagesViewModel.loadStorageUsage() }
                consumePendingBackupRequest()
            }
            // Deep link из виджета может прийти и после появления view.
            .onChange(of: actionRouter?.pendingRequest) { _, _ in
                consumePendingBackupRequest()
            }
            .onChange(of: selectedIDs.isEmpty) { _, isEmpty in
                if isEmpty {
                    isInspectorPresented = false
                    isSelecting = false
                }
            }
            // Глобальный поиск по всем подключённым облакам с дебаунсом.
            .task(id: searchText) {
                let query = searchText
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty else {
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
            .sheet(isPresented: $isScannerPresented, onDismiss: {
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
                        viewModel.errorMessage = error.localizedDescription
                        isScannerPresented = false
                    }
                )
            }
            .sheet(isPresented: $isCreateBackupPresented, onDismiss: {
                pendingAutoOpenImporter = false
            }) {
                createBackupView(
                    initialFileURL: nil,
                    autoOpenImporter: pendingAutoOpenImporter
                )
            }
            .sheet(item: $scannedDocument) { document in
                createBackupView(initialFileURL: document.fileURL)
            }
            .sheet(item: $selectedRecord) { record in
                BackupRecordDetailView(
                    viewModel: makeDetailViewModel(for: record)
                )
            }
            .sheet(isPresented: Binding(
                get: { previewFileURL != nil },
                set: { isPresented in
                    if !isPresented {
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
            // «Загрузить папку…» и «Новая папка» — те же действия,
            // что в меню «+» на iPhone/macOS.
            .modifier(FolderActionsModifier(
                isFolderImporterPresented: $isFolderImporterPresented,
                isNewFolderAlertPresented: $isNewFolderAlertPresented,
                newFolderName: $newFolderName,
                storagesViewModel: storagesViewModel,
                cloudTargetProvider: cloudTargetProvider
            ))
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .confirmationDialog(
                "Удалить выбранные файлы?",
                isPresented: $isConfirmingBatchDelete,
                titleVisibility: .visible
            ) {
                Button("Удалить \(selectedIDs.count)", role: .destructive) {
                    Task { await deleteSelectedRecords() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Будут удалены резервные копии и их версии в облаке.")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                toggleSelectionMode()
            } label: {
                Text(isSelecting ? "Готово" : "Выбрать")
            }
            .accessibilityLabel(
                isSelecting ? "Завершить выбор" : "Выбрать файлы"
            )
        }

        if isSelecting && !selectedIDs.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isConfirmingBatchDelete = true
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
                .accessibilityLabel(
                    "Удалить выбранные (\(selectedIDs.count))"
                )
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            sortMenu

            viewModeButton

            addMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(RecentFilesView.SortOption.allCases) { option in
                Button {
                    selectedSort = option
                } label: {
                    if selectedSort == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Сортировка")
    }

    private var viewModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewMode = viewMode == .list ? .grid : .list
            }
        } label: {
            Image(systemName: viewMode == .list
                  ? "square.grid.2x2" : "list.bullet")
        }
        .accessibilityLabel(
            viewMode == .list
                ? "Показать сеткой" : "Показать списком"
        )
    }

    /// Меню создания резервной копии — те же действия,
    /// что у `AddBackupButton` (сканер + выбор файла).
    private var addMenu: some View {
        Menu {
            Button {
                isScannerPresented = true
            } label: {
                Label("Отсканировать документ",
                      systemImage: "doc.viewfinder")
            }

            Button {
                isCreateBackupPresented = true
            } label: {
                Label("Выбрать файл", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Создать резервную копию")
    }

    // MARK: - Selection

    private func toggleSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting.toggle()
            if !isSelecting {
                selectedIDs.removeAll()
            }
        }
    }

    private func handleRecordTap(_ record: BackupRecord) {
        if isSelecting {
            if selectedIDs.contains(record.id) {
                selectedIDs.remove(record.id)
            } else {
                selectedIDs.insert(record.id)
            }
        } else {
            // Тап — выбор записи и показ инспектора.
            selectedIDs = [record.id]
            isInspectorPresented = true
        }
    }

    private func openRecordDetail(_ record: BackupRecord) {
        selectedRecord = record
    }

    private func deleteRecord(_ record: BackupRecord) {
        Task { await viewModel.deleteRecord(record: record) }
    }

    private func deleteSelectedRecords() async {
        for record in selectedRecords {
            await viewModel.deleteRecord(record: record)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    // MARK: - Records Section

    @ViewBuilder
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Резервные копии")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if isSelecting, !selectedIDs.isEmpty {
                    Text("Выбрано: \(selectedIDs.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.55))
                }
            }

            if displayedRecords.isEmpty {
                ContentUnavailableView(
                    "Файлы не найдены",
                    systemImage: "doc",
                    description: Text(
                        "Попробуйте изменить поисковый запрос " +
                        "или фильтр."
                    )
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else {
                switch viewMode {
                case .list:
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(displayedRecords) { record in
                            recordRow(record)
                        }
                    }
                case .grid:
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum: 170,
                                    maximum: 260
                                ),
                                spacing: AppSpacing.sm
                            )
                        ],
                        spacing: AppSpacing.sm
                    ) {
                        ForEach(displayedRecords) { record in
                            recordGridCard(record)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func recordRow(_ record: BackupRecord) -> some View {
        Button {
            handleRecordTap(record)
        } label: {
            IPadFileRowView(
                record: record,
                isSelected: selectedIDs.contains(record.id),
                isSelectionMode: isSelecting
            )
        }
        .buttonStyle(.plain)
        // Двойной тап — открыть детали (высокий приоритет,
        // чтобы не срабатывать вместе с выбором).
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                openRecordDetail(record)
            }
        )
        .contextMenu {
            Button {
                openRecordDetail(record)
            } label: {
                Label("Подробнее", systemImage: "doc.text.magnifyingglass")
            }

            Button(role: .destructive) {
                deleteRecord(record)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
        // Перетаскивание имени файла за пределы приложения
        // (например, в мессенджер или Files).
        .draggable(record.fileName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.fileName)
        .accessibilityHint(
            isSelecting
                ? "Переключить выбор"
                : "Выбрать файл. Двойное касание открывает детали."
        )
    }

    @ViewBuilder
    private func recordGridCard(_ record: BackupRecord) -> some View {
        Button {
            handleRecordTap(record)
        } label: {
            IPadFileGridCardView(
                record: record,
                isSelected: selectedIDs.contains(record.id),
                isSelectionMode: isSelecting
            )
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                openRecordDetail(record)
            }
        )
        .contextMenu {
            Button {
                openRecordDetail(record)
            } label: {
                Label("Подробнее", systemImage: "doc.text.magnifyingglass")
            }

            Button(role: .destructive) {
                deleteRecord(record)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
        .draggable(record.fileName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.fileName)
        .accessibilityHint(
            isSelecting
                ? "Переключить выбор"
                : "Выбрать файл. Двойное касание открывает детали."
        )
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let record = inspectedRecord {
            BackupInspectorView(
                record: record,
                onOpen: { openRecordDetail(record) },
                onDelete: { deleteRecord(record) }
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Выбрано файлов: \(selectedIDs.count)")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Действия применяются ко всем выбранным файлам.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.primary.opacity(0.55))

                Button(role: .destructive) {
                    isConfirmingBatchDelete = true
                } label: {
                    Label("Удалить выбранные", systemImage: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.12))
                        .clipShape(
                            RoundedRectangle(cornerRadius: AppRadius.button)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.background)
        }
    }

    // MARK: - Cloud Search (как в BackupListView)

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

    @ViewBuilder
    private func cloudResultRow(
        _ result: StoragesViewModel.CloudSearchResult
    ) -> some View {
        if result.file.isFolder {
            NavigationLink(value: CloudFolderRoute(
                provider: result.provider,
                folderID: result.file.id,
                folderName: result.file.name
            )) {
                cloudResultRowContent(
                    result, icon: "folder.fill", tint: .orange
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await handleCloudFileTap(result) }
            } label: {
                cloudResultRowContent(
                    result, icon: "doc.fill", tint: result.provider.tint
                )
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

    // MARK: - Recently Opened (как в BackupListView)

    @ViewBuilder
    private var recentlyOpenedSection: some View {
        let items = storagesViewModel.openedFiles(for: selectedProvider)

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


    // MARK: - Deep Links & Sheets (как в BackupListView)

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
            // просим VM открыть шит; раздел пользователь
            // переключает сам через сайдбар.
            storagesViewModel.selectedProvider = provider
            storagesViewModel.requestConnect(provider: provider)
        }
    }

    private struct ScannedDocument: Identifiable {
        let id = UUID()
        let fileURL: URL
    }

    @ViewBuilder
    private func createBackupView(
        initialFileURL: URL?,
        autoOpenImporter: Bool = false
    ) -> some View {
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

    private func makeDetailViewModel(
        for record: BackupRecord
    ) -> BackupVersionsViewModel {
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
}

#endif
