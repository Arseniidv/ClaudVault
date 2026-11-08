import Foundation

/// Управляет security-scoped доступом к файлам выделения.
///
/// URL из drag & drop, Services и Finder Sync могут быть
/// security-scoped: без `startAccessingSecurityScopedResource`
/// чтение упадёт с permission-ошибкой. Менеджер удерживает
/// доступ на время операции и всегда отпускает его в `defer`.
@MainActor
final class SecurityScopedAccessManager {

    /// Удерживает доступ ко всем переданным URL на время
    /// выполнения `operation`. Возвращает число URL, для которых
    /// доступ реально был запрошен (0 — доступ не требуется,
    /// файлы читаются без scope, например из Finder Sync).
    @discardableResult
    func withAccess<T>(
        to urls: [URL],
        perform operation: () async throws -> T
    ) async rethrows -> T {
        var started: [URL] = []
        for url in urls where url.startAccessingSecurityScopedResource() {
            started.append(url)
        }
        defer {
            for url in started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
    }
}
