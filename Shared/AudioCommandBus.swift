import Foundation
import CoreFoundation

/// Команды управления аудиоплеером, передаваемые между
/// процессами (приложение ↔ виджет/Live Activity).
///
/// Widget Extension и Live Activity выполняются в отдельных
/// процессах и не имеют доступа к `AVPlayer` приложения.
/// Поэтому интенты пишут команду в App Group `UserDefaults`
/// и посылают Darwin-уведомление; `AudioPlayerService`
/// в процессе приложения слушает уведомление, читает и
/// исполняет последнюю команду.
enum AudioPlayerCommand: String, Codable {
    case togglePlayPause
    case next
    case previous
    case toggleShuffle
    case cycleRepeat
}

/// Шина команд аудиоплеера.
///
/// Два канала одновременно:
/// 1. `UserDefaults` App Group — сама команда (тип + время).
/// 2. Darwin-имя уведомления — «будильник», чтобы приложение
///    не опрашивало хранилище по таймеру.
enum AudioCommandBus {

    private nonisolated static let commandKey = "latest_audio_player_command"

    /// Публикует команду. Вызывается из `AppIntent` виджета
    /// или Live Activity — может выполниться в любом процессе.
    /// `nonisolated`: AppIntent.perform() не MainActor,
    /// а запись в App Group + Darwin-нотификация
    /// actor-изоляции не требуют.
    nonisolated static func post(_ command: AudioPlayerCommand) {
        let payload = AudioCommandPayload(
            command: command,
            issuedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(payload),
              let defaults = UserDefaults(
                  suiteName: WidgetStorage.appGroupID
              )
        else { return }
        defaults.set(data, forKey: commandKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AudioWidgetConfig.commandNotificationName),
            nil,
            nil,
            true
        )
    }

    /// Читает и удаляет последнюю команду. Вызывается
    /// приложением по Darwin-уведомлению.
    @discardableResult
    static func consumeLatest() -> AudioPlayerCommand? {
        guard let defaults = UserDefaults(
            suiteName: WidgetStorage.appGroupID
        ), let data = defaults.data(forKey: commandKey),
            let payload = try? JSONDecoder().decode(
                AudioCommandPayload.self, from: data
            )
        else { return nil }
        defaults.removeObject(forKey: commandKey)
        return payload.command
    }

    /// Токен регистрации Darwin-наблюдателя.
    /// Хранит box с обработчиком; живёт до `invalidate()`.
    final class ObserverToken {
        fileprivate let observer: UnsafeMutableRawPointer
        fileprivate let box: Unmanaged<HandlerBox>

        fileprivate init(observer: UnsafeMutableRawPointer, box: Unmanaged<HandlerBox>) {
            self.observer = observer
            self.box = box
        }

        /// Снимает регистрацию и освобождает box.
        func invalidate() {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                CFNotificationName(AudioWidgetConfig.commandNotificationName),
                nil
            )
            box.release()
        }
    }

    /// Регистрирует обработчик Darwin-уведомления о команде.
    /// Возвращаемый токен нужно удерживать и при необходимости
    /// вызвать `invalidate()`. Обработчик вызывается не на main
    /// — диспатчить внутри callback.
    static func observe(
        _ handler: @escaping @Sendable () -> Void
    ) -> ObserverToken {
        let box = Unmanaged.passRetained(HandlerBox(handler))
        let observer = UnsafeMutableRawPointer(
            box.toOpaque()
        )
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<HandlerBox>.fromOpaque(observer)
                    .takeUnretainedValue()
                box.handler()
            },
            AudioWidgetConfig.commandNotificationName,
            nil,
            .deliverImmediately
        )
        return ObserverToken(observer: observer, box: box)
    }

    /// Бокс для хранения closure: CFNotificationCenter передаёт
    /// в callback только `void *` контекст наблюдателя.
    /// Не private — используется в сигнатурах `ObserverToken`.
    final class HandlerBox {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) {
            self.handler = handler
        }
    }
}

private nonisolated struct AudioCommandPayload: Codable {
    let command: AudioPlayerCommand
    let issuedAt: Date
}
