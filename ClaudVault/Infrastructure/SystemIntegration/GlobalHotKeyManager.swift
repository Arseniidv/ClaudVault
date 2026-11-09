#if os(macOS)
import Cocoa
import Carbon.HIToolbox


enum RadialHotKeyPreset: String, CaseIterable, Identifiable, Sendable {
    // Безопасные пресеты — первыми в списке.
    case optionSpace
    case optionShiftSpace
    case controlCommandSpace
    // Пресеты, конфликтующие с системными сочетаниями macOS —
    // в конце списка и с предупреждением в UI.
    case controlSpace
    case controlOptionSpace
    case commandOptionSpace

    var id: String { rawValue }

    /// Системное сочетание macOS, с которым пресет может
    /// конфликтовать: Carbon-регистрация hotkey пройдёт,
    /// но система способна перехватить клавишу раньше.
    /// nil — известных конфликтов нет.
    var systemConflict: String? {
        switch self {
        case .controlSpace:
            return "⌃Space — системное переключение источника ввода"
        case .controlOptionSpace:
            return "⌃⌥Space — системное переключение источника ввода"
        case .commandOptionSpace:
            return "⌘⌥Space — системный поиск Finder"
        case .optionSpace, .optionShiftSpace, .controlCommandSpace:
            return nil
        }
    }

    var title: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlSpace: return "⌃ Space"
        case .optionShiftSpace: return "⌥ ⇧ Space"
        case .controlOptionSpace: return "⌃ ⌥ Space"
        case .commandOptionSpace: return "⌘ ⌥ Space"
        case .controlCommandSpace: return "⌃ ⌘ Space"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_Space) }

    /// Carbon-модификаторы для `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        switch self {
        case .optionSpace:
            return UInt32(optionKey)
        case .controlSpace:
            return UInt32(controlKey)
        case .optionShiftSpace:
            return UInt32(optionKey | shiftKey)
        case .controlOptionSpace:
            return UInt32(controlKey | optionKey)
        case .commandOptionSpace:
            return UInt32(cmdKey | optionKey)
        case .controlCommandSpace:
            return UInt32(controlKey | cmdKey)
        }
    }
}

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    /// Вызывается в главном потоке при нажатии комбинации.
    var onTriggered: (@MainActor () -> Void)?

    private(set) var isRegistered = false
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var currentPreset: RadialHotKeyPreset = .optionSpace

    private init() {}

    /// Применяет настройки: включение и выбранный пресет.
    /// Идемпотентно — повторный вызов перерегистрирует клавишу.
    func apply(enabled: Bool, preset: RadialHotKeyPreset) {
        currentPreset = preset
        if enabled {
            register()
        } else {
            unregister()
        }
    }

    // MARK: - Carbon hotkey

    private static let signature = OSType(0x43564D44) // 'CVMD'
    private static let hotKeyID: UInt32 = 1

    private func register() {
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context -> OSStatus in
                guard let event, let context else {
                    return OSStatus(eventNotHandledErr)
                }
                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard paramStatus == noErr,
                      hotKeyID.signature == GlobalHotKeyManager.signature,
                      hotKeyID.id == GlobalHotKeyManager.hotKeyID
                else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                Task { @MainActor in
                    manager.onTriggered?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard handlerStatus == noErr else { return }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.signature
        hotKeyID.id = Self.hotKeyID

        let status = RegisterEventHotKey(
            currentPreset.keyCode,
            currentPreset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = status == noErr
        if !isRegistered {
            // Комбинация занята другим приложением.
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        isRegistered = false
    }
}
#endif
