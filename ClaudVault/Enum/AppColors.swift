import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif


// This enum contains all the colors used in the app,
// making them easy to find and use throughout the project.
//
// Цвета адаптированы под системную тему (light/dark):
// поверхности и текст используют динамические NSColor/UIColor,
// поэтому экраны корректно отображаются в обеих темах.
public enum AppColors {

    // MARK: - Adaptive helpers

    #if os(macOS)
    private typealias PlatformColor = NSColor

    private static func dynamic(
        light: PlatformColor,
        dark: PlatformColor
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua])
                == .darkAqua ? dark : light
        })
    }
    #else
    private typealias PlatformColor = UIColor

    private static func dynamic(
        light: PlatformColor,
        dark: PlatformColor
    ) -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? dark : light
        })
    }
    #endif

    private static func rgb(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        alpha: CGFloat = 1
    ) -> PlatformColor {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    // MARK: - Accent

    public static let accent = Color(
        red: 0.25,
        green: 0.48,
        blue: 1.00
    )

    static let accentHover = Color(
        red: 0.34,
        green: 0.56,
        blue: 1.00
    )

    static let accentMuted = accent.opacity(0.16)

    /// Текст/иконки на цветных акцентных фонах — всегда белые.
    static let onAccent = Color.white

    // MARK: - Surfaces

    static let background = dynamic(
        light: rgb(0.95, 0.96, 0.98),
        dark: rgb(0.055, 0.067, 0.090)
    )

    static let surface = dynamic(
        light: rgb(1.00, 1.00, 1.00),
        dark: rgb(0.090, 0.105, 0.140)
    )

    static let surfaceSecondary = dynamic(
        light: rgb(0.92, 0.93, 0.95),
        dark: rgb(0.120, 0.140, 0.180)
    )

    // MARK: - Text

    /// Основной текст — адаптивный label color
    /// (белый в dark, почти чёрный в light).
    static let textPrimary = Color.primary

    static let textSecondary = Color.primary.opacity(0.65)

    static let textMuted = Color.primary.opacity(0.45)

    // MARK: - Borders

    static let border = Color.primary.opacity(0.10)

    static let borderFocused = accent.opacity(0.80)

    // MARK: - Status

    static let success = dynamic(
        light: rgb(0.10, 0.55, 0.30),
        dark: rgb(0.25, 0.78, 0.52)
    )

    static let warning = dynamic(
        light: rgb(0.75, 0.45, 0.05),
        dark: rgb(1.00, 0.72, 0.25)
    )

    static let error = dynamic(
        light: rgb(0.80, 0.15, 0.18),
        dark: rgb(1.00, 0.34, 0.37)
    )

    static let info = accent
    static let overlay = Color.black.opacity(0.55)
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 20

    static let screenPadding: CGFloat = 24

    static let sectionSpacing: CGFloat = 24
}
