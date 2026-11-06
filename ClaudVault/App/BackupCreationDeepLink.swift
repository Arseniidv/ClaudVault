import Foundation

/// Deep link запуска создания резервной копии из виджета:
///
/// - `claudvault://backup/new?mode=file` — выбор файла
/// - `claudvault://backup/new?mode=scan` — сканирование документа
///
/// Режим `file` открывает `CreateBackupView` с авто-вызовом
/// системного fileImporter; `scan` — камеру `VNDocumentCameraViewController`.
struct BackupCreationDeepLink: Equatable {
    let request: BackupCreationRequest

    /// Возвращает nil для URL, не относящихся к созданию бэкапа.
    static func parse(_ url: URL) -> BackupCreationDeepLink? {
        guard url.scheme == "claudvault",
              url.host == "backup" else {
            return nil
        }

        let path = url.pathComponents.dropFirst().first
        guard path == "new" else { return nil }

        let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "mode" })?
            .value

        switch mode {
        case "file":
            return BackupCreationDeepLink(request: .pickFile)
        case "scan":
            return BackupCreationDeepLink(request: .scanDocument)
        default:
            return nil
        }
    }
}
