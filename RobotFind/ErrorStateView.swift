// ErrorStateView.swift
// Reusable error / edge-state components. Spec: README §8

import SwiftUI

// MARK: - Full-screen recovery (permission denied, storage full, etc.)

struct RecoveryView: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryLabel: String = "Open Settings"
    var primaryAction: () -> Void = {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    var secondaryLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Circle()
                    .fill(FMTTheme.chipBg)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(FMTTheme.accent)
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(FMTTheme.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(message)
                        .font(.system(size: 17))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(FMTTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(FMTTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryLabel)
                .accessibilityHint("Opens the action")

                if let label = secondaryLabel, let action = secondaryAction {
                    Button(action: action) {
                        Text(label)
                            .font(.system(size: 17))
                            .foregroundStyle(FMTTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(FMTTheme.background)
        .onAppear {
            UIAccessibility.post(notification: .screenChanged,
                                 argument: "\(title). \(message)")
        }
    }
}

// MARK: - Inline scanning overlay (timeout / covered / low-light / battery)

struct ScanningAlertOverlay: View {
    enum Kind {
        case timeout(itemName: String)
        case covered
        case lowLight
        case batteryWarn
        case batteryCritical
        case multipleMatches
    }

    let kind: Kind
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text(primaryLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(hex: 0xFFD60A))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryLabel)
                .accessibilityHint(primaryHint)

                if !secondaryLabel.isEmpty {
                    Button(action: onSecondary) {
                        Text(secondaryLabel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(secondaryLabel)
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .onAppear {
            UIAccessibility.post(notification: .announcement,
                                 argument: "\(title). \(message)")
        }
    }

    // MARK: Content per kind

    private var iconName: String {
        switch kind {
        case .timeout:        return "clock"
        case .covered:        return "square.stack.3d.up.slash"
        case .lowLight:       return "flashlight.off.fill"
        case .batteryWarn:    return "battery.25"
        case .batteryCritical: return "battery.0"
        case .multipleMatches: return "rectangle.on.rectangle"
        }
    }
    private var iconColor: Color {
        switch kind {
        case .batteryWarn, .batteryCritical: return Color(hex: 0xFF9500)
        default: return Color(hex: 0xFFD60A)
        }
    }
    private var title: String {
        switch kind {
        case .timeout:         return "Not finding it"
        case .covered:         return "Might be hidden"
        case .lowLight:        return "It\u{2019}s dark here"
        case .batteryWarn:     return "Battery at 15%"
        case .batteryCritical: return "Battery critical"
        case .multipleMatches: return "Two possible matches"
        }
    }
    private var message: String {
        switch kind {
        case .timeout(let name):
            return "I couldn\u{2019}t find your \(name) nearby. Want to try a different room or re-train?"
        case .covered:
            return "I think it might be hidden. Try opening drawers or moving closer."
        case .lowLight:
            return "Tap below to turn on the flashlight."
        case .batteryWarn:
            return "Scanning uses extra battery. Consider charging soon."
        case .batteryCritical:
            return "Battery too low to continue. Scanning paused."
        case .multipleMatches:
            return "I see two possible matches. Tap once for the closer one, twice for the farther one."
        }
    }
    private var primaryLabel: String {
        switch kind {
        case .timeout:         return "Try another room"
        case .covered:         return "Got it"
        case .lowLight:        return "Turn on flashlight"
        case .batteryWarn:     return "Keep scanning"
        case .batteryCritical: return "Stop scanning"
        case .multipleMatches: return "Closer one"
        }
    }
    private var primaryHint: String {
        switch kind {
        case .timeout:         return "Continues scanning"
        case .covered:         return "Dismisses the hint"
        case .lowLight:        return "Enables the flashlight"
        case .batteryWarn:     return "Continues scanning"
        case .batteryCritical: return "Exits scanning"
        case .multipleMatches: return "Selects the closer match"
        }
    }
    private var secondaryLabel: String {
        switch kind {
        case .timeout:         return "Re-train this item"
        case .batteryWarn:     return "Stop scanning"
        case .multipleMatches: return "Farther one"
        default:               return ""
        }
    }
}

// MARK: - Empty home state (no items taught yet)

struct EmptyItemsView: View {
    var onTeach: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(FMTTheme.textTertiary)
                .accessibilityHidden(true)

            Text("You haven\u{2019}t taught me any items yet.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FMTTheme.text)
                .multilineTextAlignment(.center)

            Button(action: onTeach) {
                Text("Tap \u{201C}Teach a new item\u{201D} to start.")
                    .font(.system(size: 15))
                    .foregroundStyle(FMTTheme.accent)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Teach a new item to start")
            .accessibilityHint("Opens the teach wizard")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You haven\u{2019}t taught me any items yet. Activate to start teaching.")
    }
}

// MARK: - Storage full banner

struct StorageFullView: View {
    var onGoToLibrary: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 36))
                .foregroundStyle(FMTTheme.error)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Your iPhone is out of space")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(FMTTheme.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Delete an item to free up space, then try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(FMTTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onGoToLibrary) {
                Text("Go to Library")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FMTTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(FMTTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to Library")
            .accessibilityHint("Opens the Library so you can delete an item")
        }
        .padding(24)
        .background(FMTTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.card))
        .padding(.horizontal, 20)
        .onAppear {
            UIAccessibility.post(notification: .announcement,
                                 argument: "Your iPhone is out of space. Go to Library to delete an item.")
        }
    }
}

#Preview("Recovery") {
    RecoveryView(
        systemImage: "camera.fill",
        title: "Camera access needed",
        message: "RobotFind needs camera access for guided item teaching.",
        secondaryLabel: "Not now",
        secondaryAction: {}
    )
}

#Preview("Scanning alert — timeout") {
    ZStack {
        Color.black.ignoresSafeArea()
        ScanningAlertOverlay(kind: .timeout(itemName: "House keys"))
    }
}

#Preview("Storage full") {
    StorageFullView()
}
