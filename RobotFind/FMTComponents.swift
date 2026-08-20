// FMTComponents.swift
// 可复用组件 — 按钮、行、缩略图

import SwiftUI

// MARK: - 大按钮 (主/次样式, Dynamic Type aware)

struct FMTBigButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let subtitle: String?
    let systemImage: String?
    let style: Style
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.fmtAccent) private var accent

    init(title: String, subtitle: String? = nil, systemImage: String? = nil,
         style: Style = .primary, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize >= .accessibility1 {
                    // AX sizes: stack icon + text vertically, full width
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            if let icon = systemImage {
                                Image(systemName: icon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(title)
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let sub = subtitle {
                            Text(sub)
                                .font(.subheadline.weight(.medium))
                                .opacity(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 4) {
                        HStack(spacing: 12) {
                            if let icon = systemImage {
                                Image(systemName: icon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(title)
                                .font(.system(size: 22, weight: .semibold))
                        }
                        if let sub = subtitle {
                            Text(sub)
                                .font(.system(size: 15, weight: .medium))
                                .opacity(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                }
            }
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary: return FMTTheme.onAccent
        case .secondary: return accent
        case .destructive: return FMTTheme.error
        }
    }
    private var background: Color {
        switch style {
        case .primary: return accent
        case .secondary: return FMTTheme.chipBg
        case .destructive: return Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: 0x3B0000) : UIColor(hex: 0xFFEAEA)
        })
        }
    }
}

// MARK: - 物品行 (Home / Library 列表, Dynamic Type aware)

struct FMTItemRow: View {
    let item: FMTItem

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize >= .accessibility1 {
                // AX sizes: stack thumbnail above text
                VStack(alignment: .leading, spacing: 10) {
                    FMTItemThumbnail(kind: item.kind, size: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        statusRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } else {
                HStack(spacing: 14) {
                    FMTItemThumbnail(kind: item.kind, size: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 22, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        statusRow
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FMTTheme.textTertiary)
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(FMTTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name). \(item.status == .ready ? "Ready" : "Needs more views"). Last used \(item.lastUsed).")
        .accessibilityHint("Opens item details")
        .accessibilityAddTraits(.isButton)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            StatusBadge(status: item.status)
            Text(item.lastUsed)
                .font(.system(size: 14))
                .foregroundStyle(FMTTheme.textSecondary)
        }
    }
}

private struct StatusBadge: View {
    let status: FMTItem.Status

    var body: some View {
        let (label, color, bg) = config
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(bg)
        .clipShape(Capsule())
    }

    private var config: (String, Color, Color) {
        switch status {
        case .ready:
            return ("Ready", FMTTheme.success, FMTTheme.successBg)
        case .needsViews:
            return ("Needs views", FMTTheme.warning, FMTTheme.warningBg)
        }
    }
}

// MARK: - 物品缩略图 (占位 — 后续替换为真实捕获帧)

struct FMTItemThumbnail: View {
    let kind: FMTItem.ItemKind
    let size: CGFloat

    var body: some View {
        let (a, b) = kind.swatch
        RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(colors: [a, b],
                                 startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
            .accessibilityHidden(true) // 由父行统一播报
    }
}
