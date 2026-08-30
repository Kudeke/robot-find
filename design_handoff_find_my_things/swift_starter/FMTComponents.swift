// FMTComponents.swift
// 可复用组件 — 按钮、行、缩略图

import SwiftUI

// MARK: - 大按钮 (96pt 高,主/次样式)

struct FMTBigButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let subtitle: String?
    let systemImage: String?
    let style: Style
    let action: () -> Void

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
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    if let icon = systemImage {
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .semibold))
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
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary: return FMTTheme.onAccent
        case .secondary: return FMTTheme.accent
        case .destructive: return FMTTheme.error
        }
    }
    private var background: Color {
        switch style {
        case .primary: return FMTTheme.accent
        case .secondary: return FMTTheme.chipBg
        case .destructive: return Color(hex: 0xFFEAEA)
        }
    }
}

// MARK: - 物品行 (Home / Library 列表)

struct FMTItemRow: View {
    let item: FMTItem

    var body: some View {
        HStack(spacing: 14) {
            FMTItemThumbnail(kind: item.kind, size: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    StatusBadge(status: item.status)
                    Text(item.lastUsed)
                        .font(.system(size: 14))
                        .foregroundStyle(FMTTheme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FMTTheme.textTertiary)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(FMTTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name). \(item.status == .ready ? "Ready" : "Needs more training"). Last used \(item.lastUsed).")
        .accessibilityHint("Opens item details")
        .accessibilityAddTraits(.isButton)
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
        case .needsTraining:
            return ("Needs training", FMTTheme.warning, FMTTheme.warningBg)
        }
    }
}

// MARK: - 物品缩略图 (占位 — 后续替换为真实训练帧)

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
