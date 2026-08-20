// HomeView.swift
// RobotFind - Home screen

import SwiftUI

// MARK: - Item data model

struct FMTItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let kind: ItemKind
    let status: Status
    let lastUsed: String
    let confidence: Confidence
    let trainedOn: String
    let clips: Int

    enum ItemKind: String, Codable {
        case keys, mug, cane, headphones, wallet, remote, charger, meds
        var swatch: (Color, Color) {
            switch self {
            case .keys:       return (Color(hex: 0xF4C95D), Color(hex: 0x9C7B2E))
            case .mug:        return (Color(hex: 0xC73E3A), Color(hex: 0x7A1F1C))
            case .cane:       return (Color(hex: 0xE8E8EE), Color(hex: 0x8C8C92))
            case .headphones: return (Color(hex: 0x3B3B40), Color(hex: 0x1C1C1E))
            case .wallet:     return (Color(hex: 0x5C3A21), Color(hex: 0x2E1B0F))
            case .remote:     return (Color(hex: 0x2C2C2E), Color(hex: 0x1C1C1E))
            case .charger:    return (Color(hex: 0xFFFFFF), Color(hex: 0xC7C7CC))
            case .meds:       return (Color(hex: 0xE29A38), Color(hex: 0xA56118))
            }
        }
    }
    enum Status: String, Codable { case ready, needsViews }
    enum Confidence: String, Codable { case high, medium, low }

    static let seed: [FMTItem] = [
        .init(id: "keys",       name: "House keys",         kind: .keys,       status: .ready,
              lastUsed: "Today, 9:12 AM", confidence: .high,   trainedOn: "Apr 22, 2026", clips: 4),
        .init(id: "mug",        name: "Red coffee mug",     kind: .mug,        status: .ready,
              lastUsed: "Yesterday",      confidence: .high,   trainedOn: "Apr 14, 2026", clips: 4),
        .init(id: "cane",       name: "White cane",         kind: .cane,       status: .ready,
              lastUsed: "2 days ago",     confidence: .high,   trainedOn: "Apr 02, 2026", clips: 4),
        .init(id: "headphones", name: "AirPods case",       kind: .headphones, status: .ready,
              lastUsed: "3 days ago",     confidence: .medium, trainedOn: "Mar 28, 2026", clips: 4),
        .init(id: "wallet",     name: "Brown wallet",       kind: .wallet,     status: .needsViews,
              lastUsed: "Last week",      confidence: .low,    trainedOn: "Mar 14, 2026", clips: 2),
        .init(id: "remote",     name: "TV remote",          kind: .remote,     status: .ready,
              lastUsed: "Last week",      confidence: .medium, trainedOn: "Mar 12, 2026", clips: 4),
        .init(id: "meds",       name: "Morning medication", kind: .meds,       status: .ready,
              lastUsed: "2 weeks ago",    confidence: .high,   trainedOn: "Mar 01, 2026", clips: 4),
    ]
}

// MARK: - Home screen

struct HomeView: View {
    @State private var items: [FMTItem] = {
        if let data = UserDefaults.standard.data(forKey: "fmt.items"),
           let saved = try? JSONDecoder().decode([FMTItem].self, from: data) {
            return saved
        }
        return FMTItem.seed
    }()
    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var showLibrary  = false
    @State private var showTeach    = false
    @State private var showPicker   = false

    // Driving fullScreenCover(item:) — guaranteed non-nil inside the cover closures
    @State private var scanningItem: FMTItem? = nil
    @State private var foundItem:    FMTItem? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection

                    VStack(spacing: 12) {
                        FMTBigButton(
                            title: "Find an item",
                            subtitle: "Prepare robot search",
                            systemImage: "magnifyingglass",
                            style: .primary
                        ) { showPicker = true }
                        .accessibilityLabel("Find an item")
                        .accessibilityHint("Opens a list of your items so you can pick one to find")

                        FMTBigButton(
                            title: "Teach a new item",
                            subtitle: "Record 4 short videos",
                            systemImage: "plus",
                            style: .secondary
                        ) { showTeach = true }
                        .accessibilityLabel("Teach a new item")
                        .accessibilityHint("Starts the 5-step Teach wizard")
                    }
                    .padding(.horizontal, 20)

                    itemsHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 32)
                        .padding(.bottom, 12)

                    if items.isEmpty {
                        EmptyItemsView(onTeach: { showTeach = true })
                            .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    FMTItemRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Button {
                        // TODO: open Help sheet
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.circle")
                            Text("Quick help")
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(FMTTheme.separator,
                                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
                    }
                    .padding(20)
                    .accessibilityLabel("Quick help")
                    .accessibilityHint("Opens contextual help and tutorials")
                }
            }
            .background(FMTTheme.background)
            .onChange(of: items) { _, newItems in
                if let data = try? JSONEncoder().encode(newItems) {
                    UserDefaults.standard.set(data, forKey: "fmt.items")
                }
            }
            .navigationDestination(for: FMTItem.self) { item in
                ItemDetailView(item: item, onDelete: { id in
                    items.removeAll { $0.id == id }
                })
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings")
                }
            }
        }
        .fmtAdaptiveAccent()
        // ── Sheets ────────────────────────────────────────────────────────────
        .sheet(isPresented: $showSettings) {
            SettingsView().fmtAdaptiveAccent()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(items: $items).fmtAdaptiveAccent()
        }
        .sheet(isPresented: $showPicker) {
            ItemPickerView(
                items: items,
                onPick: { item in
                    showPicker = false
                    // Wait for the sheet dismiss animation before opening the cover
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        scanningItem = item
                    }
                },
                onCancel: { showPicker = false }
            )
            .fmtAdaptiveAccent()
        }
        // ── Full-screen covers — use item: form so content is never nil ───────
        .fullScreenCover(isPresented: $showTeach) {
            TeachWizardView(
                onCancel: { showTeach = false },
                onComplete: { result in
                    showTeach = false
                    let newItem = FMTItem(
                        id: result.itemID,
                        name: result.name,
                        kind: Self.inferKind(from: result.name),
                        status: .ready,
                        lastUsed: "Just now",
                        confidence: .high,
                        trainedOn: Self.todayString(),
                        clips: 4
                    )
                    items.append(newItem)
                    if result.tryFind {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scanningItem = newItem
                        }
                    }
                }
            )
            .fmtAdaptiveAccent()
        }
        // Single scanning cover driven by optional item
        .fullScreenCover(item: $scanningItem) { item in
            ScanningView(
                item: item,
                onFound: {
                    // Capture before nil-ing
                    let found = scanningItem
                    scanningItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        foundItem = found
                    }
                },
                onCancel: { scanningItem = nil }
            )
            .fmtAdaptiveAccent()
        }
        // Single found cover driven by optional item
        .fullScreenCover(item: $foundItem) { item in
            FoundView(
                item: item,
                onFindAgain: {
                    let again = foundItem
                    foundItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        scanningItem = again
                    }
                },
                onFindAnother: {
                    foundItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showPicker = true
                    }
                },
                onDone: { foundItem = nil }
            )
            .fmtAdaptiveAccent()
        }
    }

    // MARK: - Helpers for Teach completion

    static func todayString() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: Date())
    }

    static func inferKind(from name: String) -> FMTItem.ItemKind {
        let s = name.lowercased()
        if s.contains("key")                              { return .keys }
        if s.contains("mug") || s.contains("cup") || s.contains("coffee") { return .mug }
        if s.contains("cane")                             { return .cane }
        if s.contains("headphone") || s.contains("airpod") || s.contains("earphone") { return .headphones }
        if s.contains("wallet") || s.contains("purse")   { return .wallet }
        if s.contains("remote")                           { return .remote }
        if s.contains("med") || s.contains("pill") || s.contains("tablet") { return .meds }
        return .charger   // neutral grey swatch for unknown items
    }

    // MARK: - "My items" section header

    @ViewBuilder
    private var itemsHeader: some View {
        let titleView = Text("My items")
            .font(.title2.weight(.bold))
            .accessibilityAddTraits(.isHeader)
        let buttonView = Button {
            showLibrary = true
        } label: {
            Text("\(items.count) saved")
                .font(.subheadline)
                .foregroundStyle(FMTTheme.accent)
        }
        .accessibilityLabel("See all \(items.count) saved items")
        .accessibilityHint("Opens the Library with search")

        if typeSize >= .accessibility1 {
            VStack(alignment: .leading, spacing: 6) {
                titleView
                buttonView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline) {
                titleView
                Spacer()
                buttonView
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RobotFind")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Hello. You have \(items.count) items saved.")
                .font(.body)
                .foregroundStyle(FMTTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }
}

#Preview {
    HomeView()
}
