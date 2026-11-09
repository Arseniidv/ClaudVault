#if os(macOS)
import Foundation

/// Определяет, какие облачные провайдеры сейчас подключены.
///
/// Используется Radial Menu, чтобы показывать в выборе провайдера
/// только реально доступные облака. `restoreConnection()` у
/// репозиториев неинтерактивен (тот же вызов, что и при запуске
/// приложения), результат кэшируется на 60 секунд.
@MainActor
@Observable
final class ProviderAvailabilityService {

    static let shared = ProviderAvailabilityService()

    private(set) var connectedProviders: [StorageProviderType] = []
    private(set) var isRefreshing = false

    private var repositories:
        [StorageProviderType: CloudStorageRepository] = [:]
    private var supportedProviders: [StorageProviderType] = []
    private var lastRefresh: Date?
    private let cacheLifetime: TimeInterval = 60

    private init() {}

    func configure(
        repositories: [StorageProviderType: CloudStorageRepository],
        supportedProviders: [StorageProviderType]
    ) {
        self.repositories = repositories
        self.supportedProviders = supportedProviders
    }

    /// Обновляет список подключённых провайдеров (с кэшем).
    /// Безопасно вызывать при каждом открытии меню.
    func refreshIfNeeded() async {
        if let lastRefresh,
           Date().timeIntervalSince(lastRefresh) < cacheLifetime {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = supportedProviders.filter {
            repositories[$0] != nil
        }
        var connected: [StorageProviderType] = []

        // Проверки независимы — выполняем параллельно.
        await withTaskGroup(of: (StorageProviderType, Bool).self) { group in
            for provider in providers {
                group.addTask { [repositories] in
                    guard let repository = repositories[provider] else {
                        return (provider, false)
                    }
                    let account = try? await repository.restoreConnection()
                    return (provider, account != nil)
                }
            }
            for await (provider, isConnected) in group {
                if isConnected { connected.append(provider) }
            }
        }

        // Сохраняем порядок supportedProviders, а не порядок
        // завершения async-задач.
        connectedProviders = providers.filter { connected.contains($0) }
        lastRefresh = .now
    }
}
#endif
