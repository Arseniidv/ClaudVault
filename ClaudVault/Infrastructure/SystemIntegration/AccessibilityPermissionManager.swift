#if os(macOS)
import Cocoa
import ApplicationServices


enum AccessibilityPermissionManager {
    /// Выдано ли разрешение Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
#endif
