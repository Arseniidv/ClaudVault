import Cocoa
import FinderSync

/// Finder Sync Extension CloudVault.
///
/// Добавляет в контекстное меню Finder пункт «Open in Cloud Manager».
/// При выборе пункта расширение получает `selectedItemURLs()`,
/// сохраняет запрос в App Group и открывает deep link
/// `claudvault://radial/open?request=<id>` — основное приложение
/// читает запрос и показывает Radial Menu.
///
/// Расширение намеренно «пустое»: вся облачная логика живёт
/// в основном приложении, здесь только тонкий мост Finder → App.
final class ClaudVaultFinderSync: FIFinderSync {

    private let finderController = FIFinderSyncController.default()

    /// Домашняя директория — минимальный monitored root, чтобы
    /// контекстное меню было доступно во всех окнах Finder
    /// в пределах домашней папки. Callback'и содержимого
    /// (бейджи, requestDirectoryContents) не реализованы.
    override init() {
        super.init()
        finderController.directoryURLs = [
            FileManager.default.homeDirectoryForCurrentUser
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Показываем пункт только в контекстных меню файлов/папок
        // и в фоне окна — не в меню тулбара.
        switch menuKind {
        case .contextualMenuForContainer,
             .contextualMenuForItems,
             .contextualMenuForSidebar:
            break
        default:
            return nil
        }

        let menu = NSMenu(title: "")
        let item = NSMenuItem(
            title: "Open in Cloud Manager",
            action: #selector(openInCloudManager(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "CloudVault"
        )
        menu.addItem(item)
        return menu
    }

    @objc private func openInCloudManager(_ sender: Any?) {
        // Выделенные объекты; для меню «пустого места» в окне
        // используем цель клика (targetedURL).
        var urls = finderController.selectedItemURLs() ?? []
        if urls.isEmpty, let targeted = finderController.targetedURL() {
            urls = [targeted]
        }
        // Оставляем только существующие локальные файлы/папки.
        urls = urls.filter { url in
            url.isFileURL && FileManager.default.fileExists(
                atPath: url.path
            )
        }
        guard !urls.isEmpty else { return }

        let request = RadialMenuRequest(
            source: .finderSync,
            fileURLs: urls
        )
        guard AppGroupRequestStore.write(request) != nil else { return }

        guard let deepLink = URL(
            string: "claudvault://radial/open?request=\(request.id.uuidString)"
        ) else { return }
        NSWorkspace.shared.open(deepLink)
    }
}
