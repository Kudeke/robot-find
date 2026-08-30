// FMTTheme.swift
// 设计 token — 直接对应 HTML 原型里的 FMT_THEMES.light
// 暗色主题与高对比度变体留作后续扩展(用 @Environment(\.colorScheme) 切换)

import SwiftUI

enum FMTTheme {
    // 颜色
    static let background = Color.white
    static let backgroundGrouped = Color(hex: 0xF2F2F7)
    static let surface = Color.white
    static let surfaceAlt = Color(hex: 0xF2F2F7)

    static let text = Color.black
    static let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.78)
    static let textTertiary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.45)
    static let separator = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.18)

    static let accent = Color(hex: 0x0040DD)
    static let onAccent = Color.white

    static let success = Color(hex: 0x005A2B)
    static let successBg = Color(hex: 0xD9F2E2)
    static let warning = Color(hex: 0xA04500)
    static let warningBg = Color(hex: 0xFFF1E0)
    static let error = Color(hex: 0xB00020)

    static let chipBg = Color(hex: 0xEEF1FB)
    static let chipText = Color(hex: 0x0040DD)
    static let fieldBg = Color(hex: 0xF2F2F7)

    // 圆角
    enum Radius {
        static let row: CGFloat = 18
        static let card: CGFloat = 22
        static let chip: CGFloat = 999
        static let field: CGFloat = 14
    }

    // 间距 (8pt 网格)
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 32
    }

    // 触摸目标最小尺寸 (高于 HIG 的 44pt)
    static let minTouchTarget: CGFloat = 60
}

// 辅助:十六进制颜色
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
