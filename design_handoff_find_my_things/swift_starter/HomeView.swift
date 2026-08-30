// HomeView.swift
// Find My Things — Home 屏 SwiftUI 实现
// 对应 HTML 原型中的 ScreenHome
//
// 使用方法:
// 1. 新建 iOS App 项目 (SwiftUI, iOS 17+)
// 2. 把这个文件、FMTTheme.swift、FMTComponents.swift 加进项目
// 3. 在 ContentView.swift 里写: HomeView()
// 4. ⌘R 跑起来

import SwiftUI

// MARK: - Item 数据模型

struct FMTItem: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: ItemKind
    let status: Status
    let lastUsed: String
    let confidence: Confidence
    let trainedOn: String
    let clips: Int

    enum ItemKind: String {
        case keys, mug, cane, headphones, wallet, remote, charger, meds
        var swatch: (Color, Color) {
            switch self {
            case .keys: return (Color(hex: 0xF4C95D), Color(hex: 0x9C7B2E))
            case .mug: return (Color(hex: 0xC73E3A), Color(hex: 0x7A1F1C))
            case .cane: return (Color(hex: 0xE8E8EE), Color(hex: 0x8C8C92))
            case .headphones: return (Color(hex: 0x3B3B40), Color(hex: 0x1C1C1E))
            case .wallet: return (Color(hex: 0x5C3A21), Color(hex: 0x2E1B0F))
            case .remote: return (Color(hex: 0x2C2C2E), Color(hex: 0x1C1C1E))
            case .charger: return (Color(hex: 0xFFFFFF), Color(hex: 0xC7C7CC))
            case .meds: return (Color(hex: 0xE29A38), Color(hex: 0xA56118))
            }
        }
    }
    enum Status { case ready, needsTraining }
    enum Confidence { case high, medium, low }

    static let seed: [FMTItem] = [
        .init(id: "keys", name: "House keys", kind: .keys, status: .ready,
              lastUsed: "Today, 9:12 AM", confidence: .high, trainedOn: "Apr 22, 2026", clips: 4),
        .init(id: "mug", name: "Red coffee mug", kind: .mug, status: .ready,
              lastUsed: "Yesterday", confidence: .high, trainedOn: "Apr 14, 2026", clips: 4),
        .init(id: "cane", name: "White cane", kind: .cane, status: .ready,
              lastUsed: "2 days ago", confidence: .high, trainedOn: "Apr 02, 2026", clips: 4),
        .init(id: "headphones", name: "AirPods case", kind: .headphones, status: .ready,
              lastUsed: "3 days ago", confidence: .medium, trainedOn: "Mar 28, 2026", clips: 4),
        .init(id: "wallet", name: "Brown wallet", kind: .wallet, status: .needsTraining,
              lastUsed: "Last week", confidence: .low, trainedOn: "Mar 14, 2026", clips: 2),
        .init(id: "remote", name: "TV remote", kind: .remote, status: .ready,
              lastUsed: "Last week", confidence: .medium, trainedOn: "Mar 12, 2026", clips: 4),
        .init(id: "meds", name: "Morning medication", kind: .meds, status: .ready,
              lastUsed: "2 weeks ago", confidence: .high, trainedOn: "Mar 01, 2026", clips: 4),
    ]
}

// MARK: - Home 屏

struct HomeView: View {
    @State private var items: [FMTItem] = FMTItem.seed
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 大标题区
                    headerSection

                    // 主操作:Find / Teach
                    VStack(spacing: 12) {
                        FMTBigButton(
                            title: "Find an item",
                            subtitle: "Scan with the camera",
                            systemImage: "magnifyingglass",
                            style: .primary
                        ) {
                            // TODO: 跳转到 Item Picker
                        }
                        .accessibilityLabel("Find an item")
                        .accessibilityHint("Opens a list of your items so you can pick one to find")

                        FMTBigButton(
                            title: "Teach a new item",
                            subtitle: "Record 4 short videos",
                            systemImage: "plus",
                            style: .secondary
                        ) {
                            // TODO: 跳转到 Teach 向导
                        }
                        .accessibilityLabel("Teach a new item")
                        .accessibilityHint("Starts the 5-step Teach wizard")
                    }
                    .padding(.horizontal, 20)

                    // My items 列表
                    HStack(alignment: .firstTextBaseline) {
                        Text("My items")
                            .font(.system(size: 22, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(items.count) saved")
                            .font(.system(size: 15))
                            .foregroundStyle(FMTTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
                    .padding(.bottom, 12)

                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                FMTItemRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Quick help
                    Button {
                        // TODO: 打开 Help sheet
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.circle")
                            Text("Quick help")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(FMTTheme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
                    }
                    .padding(20)
                    .accessibilityLabel("Quick help")
                    .accessibilityHint("Opens contextual help and tutorials")
                }
            }
            .background(FMTTheme.background)
            .navigationDestination(for: FMTItem.self) { item in
                Text("Item Detail: \(item.name)") // 占位 — 后续实现 ItemDetailView
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // TODO: 打开 Settings
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings")
                }
            }
        }
    }

    // 大标题 + 问候
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find My Things")
                .font(.system(size: 34, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text("Hello. You have \(items.count) items saved.")
                .font(.system(size: 17))
                .foregroundStyle(FMTTheme.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }
}

#Preview {
    HomeView()
}
