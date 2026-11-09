#if os(macOS)
import Cocoa
import UniformTypeIdentifiers
import ClaudVaultDomain

/// Share: системное меню «Поделиться» macOS для локальных файлов.
/// Для облачных ссылок провайдеры CloudVault share API
/// не предоставляют — используем NSSharingServicePicker.
@MainActor
final class ShareActionHandler: FileActionHandling {

    let kind: FileActionKind = .share

    func evaluate(
        selection: FileSelection,
        context: FileActionContext
    ) async -> FileActionDescriptor {
        FileActionDescriptor(
            kind: kind,
            isEnabled: !selection.isEmpty,
            statusText: selection.isEmpty ? "Нет файлов" : nil
        )
    }

    func perform(
        selection: FileSelection,
        context: FileActionContext,
        provider: StorageProviderType?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> FileActionOutcome {
        guard !selection.isEmpty else {
            throw CloudStorageError.operationFailed("Нет файлов.")
        }

        // Якорь — ключевое окно (Radial Menu panel).
        guard let view = NSApp.keyWindow?.contentView
                ?? NSApp.windows.first?.contentView else {
            throw CloudStorageError.operationFailed(
                "Не удалось показать меню «Поделиться»."
            )
        }

        let picker = NSSharingServicePicker(items: selection.urls)
        picker.show(
            relativeTo: NSRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 0,
                height: 0
            ),
            of: view,
            preferredEdge: .minY
        )
        return .completed("Открыто меню «Поделиться».")
    }
}
#endif
