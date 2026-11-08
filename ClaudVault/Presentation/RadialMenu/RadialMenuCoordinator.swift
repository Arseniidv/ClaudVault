#if os(macOS)
import AppKit
import Foundation
import Observation

/// Координатор жизненного цикла Radial Menu.
///
/// Получает готовый `FileSelection` (из Finder Sync Extension,
/// Services, drag & drop, глобальной клавиши или clipboard-fallback),
/// оценивает доступные действия через `FileActionRegistry`,
/// управляет `RadialMenuPanel` и делегирует выполнение
/// обработчикам `FileActionHandling`.
///
/// Сам координатор не реализует облачные операции — только
/// оркестрирует выбор и вызов Use Cases.
@MainActor
@Observable
final class RadialMenuCoordinator {

    static let shared = RadialMenuCoordinator()

    // MARK: - UI State

    enum Mode: Equatable {
        /// Кольцо действий над файлами.
        case actions
        /// Выбор облака для upload/transfer.
        case providers
        /// Детали файлов и статус копий.
        case information
        /// Fallback: выделение получить не удалось.
        case fallback
    }

    private(set) var isPresented = false
    private(set) var mode: Mode = .actions
    private(set) var selection: FileSelection?
    private(set) var actionDescriptors: [FileActionDescriptor] = []
    private(set) var information: [FileInspectionInfo] = []
    /// Транзиентное сообщение в центре панели (статус/ошибка).
    private(set) var statusMessage: String?
    private(set) var isWorking = false
    /// Действие, ожидающее выбора провайдера.
    private(set) var pendingProviderAction: FileActionKind?
    /// Наведение на сектор кольца — показывает описание.
    var hoveredAction: FileActionKind?

    // MARK: - Dependencies

    private var context: FileActionContext?
    private let registry = FileActionRegistry()
    private let validator = FileAccessValidator()
    private let accessibilityResolver = AccessibilitySelectionResolver()
    private let clipboardResolver = ClipboardSelectionResolver()
    private var windowController: RadialMenuWindowController?
    private var resignKeyObserver: NSObjectProtocol?

    /// Extended Mode: попытка читать выделение чужих приложений
    /// через Accessibility API. По умолчанию выключен —
    /// пользователь включает его в настройках осознанно.
    private(set) var extendedSelectionEnabled = false

    /// Разрешено ли добавлять сразу несколько файлов через
    /// кнопку «+» в меню (NSOpenPanel с multiple selection).
    private(set) var multiFileSelectionEnabled = false

    private init() {
        registry.register(UploadActionHandler())
        registry.register(DownloadActionHandler())
        registry.register(TransferActionHandler())
        #if os(macOS)
        registry.register(ShareActionHandler())
        #endif
        registry.register(InformationActionHandler())
    }

    /// Вызывается один раз при старте приложения после сборки
    /// AppDependencies.
    func configure(
        context: FileActionContext,
        extendedSelectionEnabled: Bool,
        multiFileSelectionEnabled: Bool
    ) {
        self.context = context
        self.extendedSelectionEnabled = extendedSelectionEnabled
        self.multiFileSelectionEnabled = multiFileSelectionEnabled
        ProviderAvailabilityService.shared.configure(
            repositories: context.repositories,
            supportedProviders: context.supportedProviders
        )
    }

    func setExtendedSelectionEnabled(_ enabled: Bool) {
        extendedSelectionEnabled = enabled
    }

    func setMultiFileSelectionEnabled(_ enabled: Bool) {
        multiFileSelectionEnabled = enabled
    }

    // MARK: - Adding files

    /// Открывает NSOpenPanel и добавляет выбранные файлы
    /// к текущему выделению. При включённой настройке
    /// `multiFileSelectionEnabled` панель разрешает выбор
    /// нескольких файлов сразу.
    func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = multiFileSelectionEnabled
        panel.prompt = "Добавить"
        panel.message = multiFileSelectionEnabled
            ? "Выберите файлы"
            : "Выберите файл"
        panel.begin { [weak self, weak panel] response in
            guard response == .OK, let urls = panel?.urls, !urls.isEmpty
            else { return }
            Task { @MainActor in
                self?.mergeFiles(urls)
            }
        }
    }

    /// Валидирует новые URL и объединяет их с текущим выделением
    /// без дубликатов (по standardized path). Если выделения
    /// ещё нет (fallback-режим) — создаёт новое.
    private func mergeFiles(_ urls: [URL]) {
        let validated = validator.validate(urls, source: .filePicker)
        guard !validated.isEmpty else {
            statusMessage = "Выбранные файлы недоступны."
            return
        }

        guard let current = selection else {
            present(validated)
            return
        }

        var seen = Set(current.files.map {
            $0.url.standardizedFileURL
        })
        var merged = current.files
        for file in validated.files
        where !seen.contains(file.url.standardizedFileURL) {
            seen.insert(file.url.standardizedFileURL)
            merged.append(file)
        }

        guard merged.count != current.files.count else {
            statusMessage = "Эти файлы уже в выделении."
            return
        }

        selection = FileSelection(
            files: merged,
            source: current.source
        )
        statusMessage = nil
        Task { await evaluateActions() }
    }

    // MARK: - Presentation entry points

    /// Единая точка входа из всех источников: валидирует URL
    /// и показывает меню или fallback.
    func present(urls: [URL], source: SelectionSource) {
        let selection = validator.validate(urls, source: source)
        guard !selection.isEmpty else {
            presentFallback(
                message: "Выделенные файлы недоступны или были удалены."
            )
            return
        }
        present(selection)
    }

    func present(_ selection: FileSelection) {
        guard !selection.isEmpty else {
            presentFallback(message: "Выделение пустое.")
            return
        }
        self.selection = selection
        mode = .actions
        statusMessage = nil
        hoveredAction = nil
        isPresented = true
        ensureWindowController()
        windowController?.show()
        Task { await evaluateActions() }
        Task { await ProviderAvailabilityService.shared.refreshIfNeeded() }
    }

    /// Глобальная горячая клавиша: пытается Accessibility
    /// (если Extended Mode), иначе показывает fallback.
    func hotKeyInvoked() async {
        if extendedSelectionEnabled {
            if let selection = await accessibilityResolver.resolve() {
                present(selection)
                return
            }
        }
        presentFallback(
            message: "Не удалось определить выбранные файлы.\n"
                + "Используйте контекстное меню Finder («Open in Cloud Manager»),\n"
                + "Services или перетащите файлы на меню."
        )
    }

    /// Finder Sync Extension → deep link.
    /// Возвращает `true`, если URL относится к Radial Menu.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard let requestID = FinderExtensionBridge.requestID(from: url)
        else { return false }

        AppGroupRequestStore.cleanupExpiredRequests()
        guard let request = AppGroupRequestStore.consume(id: requestID)
        else {
            presentFallback(
                message: "Запрос из Finder устарел. Повторите действие."
            )
            return true
        }
        present(
            urls: request.fileURLs,
            source: Self.selectionSource(for: request.source)
        )
        return true
    }

    private static func selectionSource(
        for source: RadialMenuRequest.Source
    ) -> SelectionSource {
        switch source {
        case .finderSync: return .finderSync
        case .services: return .services
        case .accessibility: return .accessibility
        case .dragAndDrop: return .dragAndDrop
        case .clipboard: return .clipboard
        }
    }

    /// Fallback-режим: меню без файлов — с подсказкой и
    /// кнопкой «взять файлы из буфера обмена».
    func presentFallback(message: String) {
        selection = nil
        actionDescriptors = []
        information = []
        pendingProviderAction = nil
        mode = .fallback
        statusMessage = message
        isPresented = true
        ensureWindowController()
        windowController?.show()
    }

    /// Явный fallback на буфер обмена — пользователь сам
    /// решил использовать clipboard, автоподстановки нет.
    func useClipboardFallback() async {
        if let selection = await clipboardResolver.resolve() {
            present(selection)
        } else {
            statusMessage = "В буфере обмена нет файлов."
        }
    }

    // MARK: - Actions

    private func evaluateActions() async {
        guard let selection, let context else { return }
        let descriptors = await registry.evaluateAll(
            selection: selection,
            context: context
        )
        // Пока шла оценка, выделение могло измениться.
        guard self.selection == selection, isPresented else { return }
        actionDescriptors = descriptors
    }

    func selectAction(_ kind: FileActionKind) {
        guard let descriptor = actionDescriptors.first(where: {
            $0.kind == kind
        }), descriptor.isEnabled, !isWorking else { return }

        if kind.requiresProvider {
            pendingProviderAction = kind
            mode = .providers
            statusMessage = nil
            Task { await ProviderAvailabilityService.shared.refresh() }
            return
        }
        Task { await perform(kind: kind, provider: nil) }
    }

    func selectProvider(_ provider: StorageProviderType) {
        guard let kind = pendingProviderAction else { return }
        pendingProviderAction = nil
        mode = .actions
        statusMessage = nil
        Task { await perform(kind: kind, provider: provider) }
    }

    func backToActions() {
        guard mode == .providers || mode == .information else { return }
        pendingProviderAction = nil
        mode = .actions
        statusMessage = nil
    }

    private func perform(
        kind: FileActionKind,
        provider: StorageProviderType?
    ) async {
        guard let selection, let context else { return }
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            let outcome = try await registry.perform(
                kind: kind,
                selection: selection,
                context: context,
                provider: provider
            )
            switch outcome {
            case .completed(let message):
                statusMessage = message
                // Короткая пауза, чтобы пользователь увидел результат,
                // затем закрываем меню.
                try? await Task.sleep(for: .milliseconds(1400))
                if isPresented { dismiss() }
            case .showInformation(let infos):
                information = infos
                mode = .information
            }
        } catch {
            statusMessage = error.localizedDescription
            mode = .actions
        }
    }

    // MARK: - Window

    private func ensureWindowController() {
        guard windowController == nil else { return }
        let controller = RadialMenuWindowController(coordinator: self)
        windowController = controller

        // Клик вне меню / переход фокуса в другое приложение → закрыть.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: controller.window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        isPresented = false
        selection = nil
        actionDescriptors = []
        information = []
        statusMessage = nil
        mode = .actions
        pendingProviderAction = nil
        hoveredAction = nil
        windowController?.close()
    }
}
#endif
