import Foundation

/// Координатор экрана переноса подключений между устройствами.
///
/// - Кнопка в настройках выставляет `isPresented = true`.
/// - Входящая ссылка `claudvault://verify?session=…` (deep link)
///   складывается в `pendingVerificationURL` и открывает экран
///   в режиме сканера.
@MainActor
@Observable
final class DeviceTransferCoordinator {

    var isPresented = false
    private(set) var pendingVerificationURL: URL?

    /// Вызывается при входящем deep-link, когда экран переноса
    /// уже открыт: без этого ссылку обработал бы только следующий
    /// `onAppear`, и пользователь увидел бы устаревшую сессию.
    var onIncomingURL: (() -> Void)?

    /// Вызывается после успешного QR-импорта токенов:
    /// StoragesViewModel сбрасывает состояние провайдеров
    /// и заново восстанавливает сессии — иначе импортированные
    /// подключения были бы невидимы до перезапуска приложения
    /// (restoreState уже выставлен при стартовом restore).
    var onConnectionsRestored: (() -> Void)?

    func open() {
        isPresented = true
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == QRVerificationService.urlScheme,
              url.host == QRVerificationService.urlHost else {
            return
        }
        pendingVerificationURL = url
        isPresented = true
        onIncomingURL?()
    }

    /// Забирает отложенную ссылку (вызывается экраном переноса).
    func consumePendingVerificationURL() -> URL? {
        defer { pendingVerificationURL = nil }
        return pendingVerificationURL
    }
}
