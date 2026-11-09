#if os(macOS)
import Cocoa

/// AppDelegate macOS-части приложения.
///
/// Обрабатывает системные сервисы macOS (NSServices): пункт
/// «Open in Cloud Manager» в меню Services других приложений.
/// Selector `openInCloudManager` объявлен в Info.plist → NSServices.
final class ClaudVaultMacAppDelegate: NSObject, NSApplicationDelegate {

    /// Приём файлов через Services. `NSMessage` в Info.plist
    /// указывает на этот selector — AppKit вызывает его
    /// с pasteboard, содержащим выделение исходного приложения.
    @objc
    func openInCloudManager(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        var urls: [URL] = []

        // Современный тип file URL.
        if let fileURLs = pboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            urls.append(contentsOf: fileURLs)
        }

        // Legacy NSFilenamesPboardType — POSIX-пути.
        if urls.isEmpty,
           let paths = pboard.propertyList(
               forType: NSPasteboard.PasteboardType(
                   "NSFilenamesPboardType"
               )
           ) as? [String] {
            urls.append(contentsOf: paths.map {
                URL(fileURLWithPath: $0)
            })
        }

        guard !urls.isEmpty else {
            error.pointee = "В выделении нет файлов." as NSString
            return
        }

        RadialMenuCoordinator.shared.present(
            urls: urls,
            source: .services
        )
    }
}
#endif
