// ItemPickerView.swift
// Item Picker modal sheet — spec: README §7.7a

import SwiftUI

struct ItemPickerView: View {
    let items: [FMTItem]
    var onPick: (FMTItem) -> Void = { _ in }
    var onCancel: () -> Void = {}

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    // Recently used = first 3; rest = remainder
    private var recent: [FMTItem] { Array(filtered.prefix(3)) }
    private var rest:   [FMTItem] { filtered.count > 3 ? Array(filtered.dropFirst(3)) : [] }

    private var filtered: [FMTItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            // Search field
            searchField
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Lists
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        noResultsState
                    } else {
                        if !recent.isEmpty {
                            pickerSection(title: "Recently used", items: recent)
                        }
                        if !rest.isEmpty {
                            pickerSection(title: "All items", items: rest)
                                .padding(.top, recent.isEmpty ? 12 : 20)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(FMTTheme.background)
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "Find an item. \(items.count) items available."
            )
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FMTTheme.text)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Cancel")
            .accessibilityHint("Cancels finding")

            Spacer()

            Text("Find an item")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FMTTheme.text)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            // Mirror spacer
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Search field (matches Library style)

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FMTTheme.textSecondary)

            TextField("Search items", text: $query)
                .font(.system(size: 17))
                .focused($searchFocused)
                .submitLabel(.search)
                .accessibilityLabel("Search items")
                .accessibilityHint("Type or dictate to search")

            if query.isEmpty {
                Button {
                    searchFocused = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(FMTTheme.accent)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Dictate search")
                .accessibilityHint("Activates voice input for search")
            } else {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FMTTheme.textTertiary)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Clear search")
                .accessibilityHint("Removes the current search text")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(FMTTheme.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.field))
    }

    // MARK: - Section

    private func pickerSection(title: String, items: [FMTItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(FMTTheme.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 28)

            // Grouped card
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PickerRow(item: item, isLast: index == items.count - 1) {
                        onPick(item)
                    }
                }
            }
            .background(FMTTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - No results

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(FMTTheme.textTertiary)
            Text("No items match \"\(query)\"")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FMTTheme.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No items match \(query)")
    }
}

// MARK: - Picker row

private struct PickerRow: View {
    let item: FMTItem
    let isLast: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                FMTItemThumbnail(kind: item.kind, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(FMTTheme.text)
                        .lineLimit(1)
                    Text(item.lastUsed)
                        .font(.system(size: 14))
                        .foregroundStyle(FMTTheme.textSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FMTTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(FMTTheme.surface)
            // Separator (except last row)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(FMTTheme.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 78) // indent past thumbnail
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), last used \(item.lastUsed)")
        .accessibilityHint("Starts scanning for this item")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ItemPickerView(items: FMTItem.seed)
}
