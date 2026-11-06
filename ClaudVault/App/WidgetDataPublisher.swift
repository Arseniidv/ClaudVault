import Foundation
import WidgetKit

/// Публикует снимок состояния облачных хранилищ в App Group,
/// чтобы виджет `CloudVaultWidgetExtension` мог его прочитать.
///
/// Вызывается из `StoragesViewModel` после каждой загрузки usage,
/// подключения/отключения аккаунта и завершения restore сессий.
enum WidgetDataPublisher {

    /// Кодирует данные в JSON и перезаписывает ключ в общем
    /// `UserDefaults` App Group, затем просит WidgetKit обновить таймлайн.
    /// Виджет работает по политике `.never` — без этого вызова
    /// он не узнает о новых данных.
    @MainActor
    static func publish(accounts: [WidgetAccountInfo]) {
        guard let defaults = UserDefaults(suiteName: WidgetStorage.appGroupID) else {
            return
        }

        // Email'ы маскируем до записи в App Group: виджет может
        // отображаться на экране блокировки, а JSON-снимок попадает
        // в бэкап устройства — полные адреса там не нужны.
        let maskedAccounts = accounts.map {
            WidgetAccountInfo(
                provider: $0.provider,
                email: maskEmail($0.email),
                usedBytes: $0.usedBytes,
                totalBytes: $0.totalBytes
            )
        }

        let payload = MultiStorageWidgetData(
            lastUpdatedAt: Date(),
            accounts: maskedAccounts
        )

        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }

        defaults.set(data, forKey: WidgetStorage.dataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `user@gmail.com` → `u***@gmail.com`. Без `@` — просто `***`.
    private static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, let first = parts[0].first else {
            return "***"
        }
        return "\(first)***@\(parts[1])"
    }
}
