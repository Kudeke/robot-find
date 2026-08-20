// FMTTheme.swift
// Design tokens — adaptive for light/dark/high-contrast modes.
// All semantic text/surface colors use UIColor system adaptives so they respond
// automatically to Dark Mode and Increase Contrast without manual override.

import SwiftUI

enum FMTTheme {
    // MARK: - Backgrounds
    // UIColor.systemBackground adapts light/dark; .secondarySystemBackground for grouped
    static let background        = Color(UIColor.systemBackground)
    static let backgroundGrouped = Color(UIColor.secondarySystemBackground)
    static let surface           = Color(UIColor.systemBackground)
    static let surfaceAlt        = Color(UIColor.secondarySystemBackground)

    // MARK: - Text — UIColor adaptives automatically increase contrast on "Increase Contrast"
    static let text          = Color(UIColor.label)
    static let textSecondary = Color(UIColor.secondaryLabel)
    static let textTertiary  = Color(UIColor.tertiaryLabel)
    static let separator     = Color(UIColor.separator)

    // MARK: - Brand accent
    // High-contrast: 0x0040DD on white is AA; in dark mode use a lighter variant.
    // We split into two values selected by environment in FMTAdaptiveAccent.
    static let accentLight   = Color(hex: 0x0040DD)      // on white bg, contrast 7.6:1
    static let accentDark    = Color(hex: 0x5B8FFF)      // on #1C1C1E bg, contrast 4.8:1 (AA)
    // Use FMTTheme.accent(for:) or the @Environment-based view modifier (see FMTAccentModifier below)
    // In most contexts, SwiftUI tint colour picks the right blue automatically via .tint(accentLight).
    // Where we need a raw Color value (e.g. background fill), call accent(scheme:).
    static func accent(scheme: ColorScheme) -> Color {
        scheme == .dark ? accentDark : accentLight
    }
    // Convenience — for call sites that can't easily access environment:
    static let accent    = accentLight    // used for light-mode previews / fallback
    static let onAccent  = Color.white

    // MARK: - Semantic status
    static let success   = Color(UIColor { t in t.userInterfaceStyle == .dark
        ? UIColor(hex: 0x32D74B) : UIColor(hex: 0x005A2B) })
    static let successBg = Color(UIColor { t in t.userInterfaceStyle == .dark
        ? UIColor(hex: 0x003818) : UIColor(hex: 0xD9F2E2) })
    static let warning   = Color(UIColor { t in t.userInterfaceStyle == .dark
        ? UIColor(hex: 0xFF9F0A) : UIColor(hex: 0xA04500) })
    static let warningBg = Color(UIColor { t in t.userInterfaceStyle == .dark
        ? UIColor(hex: 0x3D2000) : UIColor(hex: 0xFFF1E0) })
    static let error     = Color(UIColor { t in t.userInterfaceStyle == .dark
        ? UIColor(hex: 0xFF453A) : UIColor(hex: 0xB00020) })

    // MARK: - Component colours
    static let chipBg   = Color(UIColor { t in t.userInterfaceStyle == .dark
        ? UIColor(hex: 0x1C2845) : UIColor(hex: 0xEEF1FB) })
    static let chipText = Color(UIColor { t in t.userInterfaceStyle == .dark
        ? UIColor(hex: 0x5B8FFF) : UIColor(hex: 0x0040DD) })
    static let fieldBg  = Color(UIColor.secondarySystemBackground)

    // MARK: - Radius tokens
    enum Radius {
        static let row: CGFloat  = 18
        static let card: CGFloat = 22
        static let chip: CGFloat = 999
        static let field: CGFloat = 14
    }

    // MARK: - Spacing (8pt grid)
    enum Spacing {
        static let xs: CGFloat  = 4
        static let s: CGFloat   = 8
        static let m: CGFloat   = 12
        static let l: CGFloat   = 16
        static let xl: CGFloat  = 20
        static let xxl: CGFloat = 32
    }

    // Minimum touch target (above HIG's 44pt)
    static let minTouchTarget: CGFloat = 60
}

// MARK: - Hex helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex & 0xFF)          / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF)          / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - Environment-aware accent modifier

/// Apply to a View to make accent auto-switch for dark mode.
struct FMTAccentKey: EnvironmentKey {
    static let defaultValue: Color = FMTTheme.accentLight
}

extension EnvironmentValues {
    var fmtAccent: Color {
        get { self[FMTAccentKey.self] }
        set { self[FMTAccentKey.self] = newValue }
    }
}

/// A view modifier that injects the correct accent colour for the current scheme.
struct FMTAdaptiveAccent: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .environment(\.fmtAccent, FMTTheme.accent(scheme: scheme))
            .tint(FMTTheme.accent(scheme: scheme))
    }
}

extension View {
    /// Apply at root (NavigationStack / sheet) to propagate the adaptive accent.
    func fmtAdaptiveAccent() -> some View {
        modifier(FMTAdaptiveAccent())
    }
}
