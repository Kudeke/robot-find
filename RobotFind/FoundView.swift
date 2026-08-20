// FoundView.swift
// Found screen — spec: README §7.7c

import SwiftUI

struct FoundView: View {
    let item: FMTItem
    var spatialDescription: String = "About 1 foot ahead, slightly to your right."
    var onFindAgain:  () -> Void = {}
    var onFindAnother: () -> Void = {}
    var onDone:       () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Close button top-right
            HStack {
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FMTTheme.text)
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Done")
                .accessibilityHint("Closes the found screen")
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            // Success circle + text
            VStack(spacing: 28) {
                Circle()
                    .fill(FMTTheme.successBg)
                    .frame(width: 156, height: 156)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(FMTTheme.success)
                    )
                    .accessibilityLabel("Success")
                    .accessibilityAddTraits(.isImage)

                VStack(spacing: 8) {
                    Text("Found!")
                        .font(.system(size: 36, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(FMTTheme.success)
                        .accessibilityAddTraits(.isHeader)

                    Text(item.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FMTTheme.text)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)

                    Text(spatialDescription)
                        .font(.system(size: 17))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                FMTBigButton(
                    title: "Find again",
                    systemImage: "magnifyingglass",
                    style: .primary,
                    action: onFindAgain
                )
                .accessibilityLabel("Find again")
                .accessibilityHint("Continues scanning for the same item")

                FMTBigButton(
                    title: "Find another item",
                    style: .secondary,
                    action: onFindAnother
                )
                .accessibilityLabel("Find another item")
                .accessibilityHint("Returns to the item picker")

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
                .accessibilityHint("Closes scanning and returns Home")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .background(FMTTheme.background)
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "Found \(item.name). \(spatialDescription)"
            )
        }
    }
}

#Preview {
    FoundView(item: FMTItem.seed[0])
}
