import AppIntents
import Foundation

/// Кнопки управления плеером для интерактивного виджета
/// и Live Activity. Выполняются в процессе расширения —
/// команду передают в приложение через `AudioCommandBus`
/// (App Group + Darwin-уведомление), не открывая приложение.
///
/// Реальное воспроизведение продолжает `AudioPlayerService`
/// в процессе приложения: отдельный `AVPlayer` в расширении
/// не создаётся.

/// Play / Pause.
struct AudioTogglePlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play / Pause"
    static var description = IntentDescription(
        "Переключает воспроизведение текущего аудиотрека."
    )
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        AudioCommandBus.post(.togglePlayPause)
        return .result()
    }
}

/// Следующий трек.
struct AudioNextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription(
        "Переключает на следующий аудиотрек."
    )
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        AudioCommandBus.post(.next)
        return .result()
    }
}

/// Предыдущий трек.
struct AudioPreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription(
        "Переключает на предыдущий аудиотрек."
    )
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        AudioCommandBus.post(.previous)
        return .result()
    }
}

/// Shuffle on/off.
struct AudioToggleShuffleIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle"
    static var description = IntentDescription(
        "Включает или выключает перемешивание очереди."
    )
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        AudioCommandBus.post(.toggleShuffle)
        return .result()
    }
}

/// Цикл режима повтора: выкл → все → один → выкл.
struct AudioCycleRepeatIntent: AppIntent {
    static var title: LocalizedStringResource = "Repeat"
    static var description = IntentDescription(
        "Переключает режим повтора воспроизведения."
    )
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        AudioCommandBus.post(.cycleRepeat)
        return .result()
    }
}
