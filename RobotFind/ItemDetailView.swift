// ItemDetailView.swift
// Item Detail screen — spec: README §7.5

import SwiftUI

// MARK: - Guided view angle labels

private enum VideoAngle: CaseIterable {
    case front, side, top, otherBg
    var label: String {
        switch self {
        case .front:   return "Front"
        case .side:    return "Side"
        case .top:     return "Top"
        case .otherBg: return "Other bg"
        }
    }
}

// MARK: - Confidence helpers (extend FMTItem.Confidence)

private extension FMTItem.Confidence {
    var displayLabel: String {
        switch self {
        case .high:   return "Capture complete"
        case .medium: return "More views helpful"
        case .low:    return "More views recommended"
        }
    }
    var color: Color {
        switch self {
        case .high:   return FMTTheme.success
        case .medium: return FMTTheme.warning
        case .low:    return FMTTheme.error
        }
    }
    var accessibilityLabel: String {
        switch self {
        case .high:   return "Capture complete"
        case .medium: return "More views helpful"
        case .low:    return "More guided views recommended"
        }
    }
}

// MARK: - ItemDetailView

struct ItemDetailView: View {
    let item: FMTItem
    var onDelete: (String) -> Void = { _ in }

    @EnvironmentObject private var connectionManager: SSHConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showUndoToast = false
    @State private var pendingDeleteTask: Task<Void, Never>?
    @State private var showMission = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                subtitleRow
                captureStatusCard
                guidedViewsSection
                serverProfileSection
                actionButtons
            }
            .padding(.bottom, 40)
        }
        .background(FMTTheme.backgroundGrouped)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottom) {
            if showUndoToast { undoToast }
        }
        // VoiceOver: announce screen on appear
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "\(item.name). \(item.confidence.accessibilityLabel)."
            )
        }
        .sheet(isPresented: $showMission) {
            RobotMissionView(item: item)
                .environmentObject(connectionManager)
                .fmtAdaptiveAccent()
        }
    }

    // MARK: - Subtitle row ("Captured … • N views")

    private var subtitleRow: some View {
        Text("Captured \(item.trainedOn) · \(item.clips) views")
            .font(.system(size: 17))
            .foregroundStyle(FMTTheme.textSecondary)
            .padding(.horizontal, FMTTheme.Spacing.xl)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .accessibilityLabel("Captured on \(item.trainedOn), \(item.clips) views")
    }

    // MARK: - Capture status card

    private var captureStatusCard: some View {
        HStack(spacing: 18) {
            FMTItemThumbnail(kind: item.kind, size: 88)
            VStack(alignment: .leading, spacing: 4) {
                Text("CAPTURE STATUS")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(FMTTheme.textSecondary)
                Text(item.confidence.displayLabel)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(item.confidence.color)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(FMTTheme.Spacing.xl)
        .background(FMTTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.card))
        .padding(.horizontal, FMTTheme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture status: \(item.confidence.accessibilityLabel)")
    }

    // MARK: - Guided views strip

    private var guidedViewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GUIDED VIEWS")
                .font(.system(size: 13, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(FMTTheme.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, FMTTheme.Spacing.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(VideoAngle.allCases.enumerated()), id: \.offset) { index, angle in
                        GuidedViewThumb(
                            item: item,
                            index: index + 1,
                            angle: angle
                        )
                    }
                }
                .padding(.horizontal, FMTTheme.Spacing.xl)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            FMTBigButton(
                title: "Find this item",
                systemImage: "magnifyingglass",
                style: .primary
            ) {
                showMission = true
            }
            .disabled(!canStartMission)
            .opacity(canStartMission ? 1 : 0.5)
            .accessibilityLabel("Find this item")
            .accessibilityHint(canStartMission ? "Starts a robot search for \(item.name)" : findDisabledReason)

            if !canStartMission {
                Text(findDisabledReason)
                    .font(.system(size: 15))
                    .foregroundStyle(FMTTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(findDisabledReason)
            }

            FMTBigButton(
                title: "Capture more views",
                systemImage: "plus",
                style: .secondary
            ) {
                // TODO: push to Teach re-train wizard
            }
            .accessibilityLabel("Capture more views")
            .accessibilityHint("Records additional guided views for \(item.name)")

            FMTBigButton(
                title: "Delete item",
                systemImage: "trash",
                style: .destructive
            ) {
                initiateDelete()
            }
            .accessibilityLabel("Delete \(item.name)")
            .accessibilityHint("Deletes this item. You have 3 seconds to undo.")
        }
        .padding(FMTTheme.Spacing.xl)
    }

    private var canStartMission: Bool {
        item.objectProfile?.objectID.isEmpty == false && connectionManager.state == .connected
    }

    private var findDisabledReason: String {
        if item.objectProfile?.objectID.isEmpty != false {
            return "Teach this item before searching."
        }
        return "Connect to the server before starting a search."
    }

    // MARK: - Developer ObjectProfile inspection

    private var serverProfileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SERVER PROFILE")
                .font(.system(size: 13, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(FMTTheme.textSecondary)
                .accessibilityAddTraits(.isHeader)

            if let profile = item.objectProfile {
                profileField("Object ID", value: profile.objectID)
                profileField("Category", value: profile.category)
                profileField("Visual Description", value: profile.visualDescription)
                profileField(
                    "Distinctive Features",
                    value: profile.distinctiveFeatures.isEmpty
                        ? "None returned"
                        : profile.distinctiveFeatures.map { "• \($0)" }.joined(separator: "\n")
                )
                profileField("Navigation Description", value: profile.navigationDescription)
            } else {
                Text("No server ObjectProfile")
                    .font(.system(size: 17))
                    .foregroundStyle(FMTTheme.textSecondary)
                    .accessibilityLabel("No server ObjectProfile available")
            }
        }
        .padding(FMTTheme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FMTTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.card))
        .padding(.horizontal, FMTTheme.Spacing.xl)
        .padding(.top, 24)
    }

    private func profileField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FMTTheme.textSecondary)
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(FMTTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Undo toast

    private var undoToast: some View {
        HStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FMTTheme.error)
            Text("\(item.name) will be deleted")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FMTTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo") {
                cancelDelete()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(FMTTheme.accent)
            .frame(minWidth: 60, minHeight: 44)
            .accessibilityLabel("Undo delete")
            .accessibilityHint("Cancels deletion of \(item.name)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Delete logic

    private func initiateDelete() {
        pendingDeleteTask?.cancel()

        withAnimation(.spring(response: 0.35)) {
            showUndoToast = true
        }

        UIAccessibility.post(
            notification: .announcement,
            argument: "\(item.name) will be deleted. Activate Undo button to cancel."
        )

        pendingDeleteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { commitDelete() }
        }
    }

    private func cancelDelete() {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        withAnimation(.spring(response: 0.35)) {
            showUndoToast = false
        }
        UIAccessibility.post(notification: .announcement, argument: "Deletion cancelled.")
    }

    private func commitDelete() {
        withAnimation { showUndoToast = false }
        onDelete(item.id)
        dismiss()
    }
}

// MARK: - Guided view thumbnail

private struct GuidedViewThumb: View {
    let item: FMTItem
    let index: Int
    let angle: VideoAngle

    var body: some View {
        let (colorA, colorB) = item.kind.swatch
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [colorA, colorB],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            // Hatching overlay (diagonal stripes, matches prototype)
            Canvas { ctx, size in
                let step: CGFloat = 12
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    ctx.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 6)
                    x += step
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Play button circle
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Angle label pill
            Text(angle.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)
        }
        .frame(width: 110, height: 150)
        .accessibilityLabel("Guided view \(index) of 4, \(angle.label) view")
        .accessibilityHint("Double tap to play")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(item: FMTItem.seed[0])
    }
    .environmentObject(SSHConnectionManager())
}
