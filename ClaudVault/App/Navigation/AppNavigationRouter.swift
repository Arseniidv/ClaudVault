import Foundation
import Observation

/// Запрос на переключение раздела приложения извне его окна —
/// например, из Menu Bar. Аналог `BackupActionRouter`, но для
/// навигации по вкладкам `RootView`.
struct AppNavigationRequest: Equatable {
    let id = UUID()
    let tab: AppTab
    /// Провайдер, который нужно выбрать на вкладке «Хранилища».
    let provider: StorageProviderType?
}

@MainActor
@Observable
final class AppNavigationRouter {
    private(set) var pending: AppNavigationRequest?

    func request(
        _ tab: AppTab,
        provider: StorageProviderType? = nil
    ) {
        pending = AppNavigationRequest(tab: tab, provider: provider)
    }

    func consume() {
        pending = nil
    }
}
