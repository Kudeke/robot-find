// ScanningView.swift
// Temporary robot search placeholder for Phase 0 cleanup.

import SwiftUI

struct ScanningView: View {
    let item: FMTItem
    var onFound: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(FMTTheme.accent)
                    .frame(width: 116, height: 116)
                    .background(FMTTheme.chipBg)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Preparing robot search")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(FMTTheme.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("Robot search integration will be added in a later phase.")
                        .font(.system(size: 19))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preparing robot search for \(item.name). Robot search integration will be added in a later phase.")

            Spacer()

            Button(action: onCancel) {
                HStack(spacing: 10) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Cancel")
                        .font(.system(size: 22, weight: .semibold))
                }
                .foregroundStyle(FMTTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(FMTTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .accessibilityLabel("Cancel robot search")
            .accessibilityHint("Returns to the previous screen")
        }
        .background(FMTTheme.background)
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "Preparing robot search for \(item.name)."
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SEARCHING FOR")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(FMTTheme.textSecondary)
                Text(item.name)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(FMTTheme.text)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FMTTheme.text)
                    .frame(width: 56, height: 56)
                    .background(FMTTheme.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityHint("Returns to the previous screen")
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }
}

#Preview {
    ScanningView(item: FMTItem.seed[0])
}
