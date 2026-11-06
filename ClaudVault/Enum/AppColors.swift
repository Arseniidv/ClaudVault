import SwiftUI


// This enum contains all the colors used in the app,
// making them easy to find and use throughout the project.
public enum AppColors {
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
    static let background = Color(
        red: 0.055,
        green: 0.067,
        blue: 0.090
    )

    static let surface = Color(
        red: 0.090,
        green: 0.105,
        blue: 0.140
    )
    static let surfaceSecondary = Color(
        red: 0.120,
        green: 0.140,
        blue: 0.180
    )

    // MARK: - Text

    static let textPrimary = Color.white

    static let textSecondary = Color.white.opacity(0.65)

    static let textMuted = Color.white.opacity(0.40)

    // MARK: - Borders

    static let border = Color.white.opacity(0.08)

    static let borderFocused = accent.opacity(0.80)

    // MARK: - Status

    static let success = Color(
        red: 0.25,
        green: 0.78,
        blue: 0.52
    )

    static let warning = Color(
        red: 1.00,
        green: 0.72,
        blue: 0.25
    )

    static let error = Color(
        red: 1.00,
        green: 0.34,
        blue: 0.37
    )
    static let info = accent
    static let overlay = Color.black.opacity(0.55)
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 20

    static let screenPadding: CGFloat = 24

    static let sectionSpacing: CGFloat = 24
}
