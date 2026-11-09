#if os(macOS)
import Cocoa
import SwiftUI

/// Borderless плавающая панель Radial Menu.
/// `canBecomeKey` переопределён: borderless-окна по умолчанию
/// не могут стать key window, а нам нужны клавиатурные события
/// (Esc, стрелки) и drop-таргет.
final class RadialMenuPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Управляет `NSPanel` с SwiftUI-содержимым Radial Menu.
/// Панель живёт поверх всех приложений (`canJoinAllSpaces`),
/// не привязана к главному окну CloudVault и может открываться
/// при закрытом главном окне.
@MainActor
final class RadialMenuWindowController: NSWindowController {

    static let panelSize = NSSize(width: 460, height: 460)

    init(coordinator: RadialMenuCoordinator) {
        let panel = RadialMenuPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let hosting = NSHostingController(
            rootView: RadialMenuView(coordinator: coordinator)
        )
        panel.contentViewController = hosting

        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Показывает панель по центру экрана с курсором.
    /// При необходимости активирует приложение — панель должна
    /// стать key window для клавиатуры и drag & drop.
    func show() {
        guard let panel = window as? RadialMenuPanel else { return }
        centerOnMouseScreen()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerOnMouseScreen() {
        guard let panel = window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            $0.frame.contains(mouse)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - Self.panelSize.width / 2,
            y: visibleFrame.midY - Self.panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
#endif
