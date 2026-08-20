// LibraryView.swift
// Library screen — spec: README §7.4

import SwiftUI

struct LibraryView: View {
    @Binding var items: [FMTItem]

    @State private var query = ""
    @State private var path = NavigationPath()
    @State private var showTeach = false
    @FocusState private var searchFocused: Bool

    private var filtered: [FMTItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    subtitleRow
                    searchField
                    itemList
                }
                .padding(.bottom, 40)
            }
            .background(FMTTheme.backgroundGrouped)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTeach = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .accessibilityLabel("Teach a new item")
                    .accessibilityHint("Starts adding a new item")
                }
            }
            .navigationDestination(for: FMTItem.self) { item in
                ItemDetailView(item: item, onDelete: { id in
                    items.removeAll { $0.id == id }
                })
            }
        }
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "Library. \(items.count) items, all on this device."
            )
        }
        .fullScreenCover(isPresented: $showTeach) { teachSheet }
    }

    // MARK: - Teach sheet
    private var teachSheet: some View {
        TeachWizardView(
            onCancel: { showTeach = false },
            onComplete: { result in
                showTeach = false
                let newItem = FMTItem(
                    id: result.itemID,
                    name: result.name,
                    kind: HomeView.inferKind(from: result.name),
                    status: .ready,
                    lastUsed: "Just now",
                    confidence: .high,
                    trainedOn: HomeView.todayString(),
                    clips: 4
                )
                items.append(newItem)
            }
        )
    }

    // MARK: - Subtitle

    private var subtitleRow: some View {
        Text("\(items.count) items, all on this device.")
            .font(.system(size: 17))
            .foregroundStyle(FMTTheme.textSecondary)
            .padding(.horizontal, FMTTheme.Spacing.xl)
            .padding(.top, 4)
            .padding(.bottom, FMTTheme.Spacing.l)
            .accessibilityLabel("\(items.count) items saved on this device")
    }

    // MARK: - Search field

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
                .accessibilityHint("Type or dictate to search your items")

            if query.isEmpty {
                Button {
                    searchFocused = true
                    // TODO: activate dictation via UITextView dictation API
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(FMTTheme.accent)
                }
                .accessibilityLabel("Dictate search")
                .accessibilityHint("Activates voice input for search")
                .frame(minWidth: 44, minHeight: 44)
            } else {
                Button {
                    query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FMTTheme.textTertiary)
                }
                .accessibilityLabel("Clear search")
                .accessibilityHint("Removes the current search text")
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, FMTTheme.Spacing.l)
        .padding(.vertical, 14)
        .background(FMTTheme.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.field))
        .padding(.horizontal, FMTTheme.Spacing.xl)
        .padding(.bottom, FMTTheme.Spacing.m)
    }

    // MARK: - Item list

    @ViewBuilder
    private var itemList: some View {
        if items.isEmpty {
            emptyLibraryState
        } else if filtered.isEmpty {
            noResultsState
        } else {
            VStack(spacing: 10) {
                ForEach(filtered) { item in
                    NavigationLink(value: item) {
                        FMTItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                    // VoiceOver custom actions per spec §7.4
                    .accessibilityAction(named: "Find") {
                        // TODO: push to Scanning with this item
                    }
                    .accessibilityAction(named: "Re-train") {
                        // TODO: push to Teach re-train wizard
                    }
                    .accessibilityAction(named: "Rename") {
                        // TODO: show rename sheet
                    }
                    .accessibilityAction(named: "Delete") {
                        deleteItem(item)
                    }
                }
            }
            .padding(.horizontal, FMTTheme.Spacing.xl)
        }
    }

    // MARK: - Empty states

    private var emptyLibraryState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(FMTTheme.textTertiary)
            Text("You haven't taught me any items yet.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FMTTheme.text)
                .multilineTextAlignment(.center)
            Text("Tap \"Teach a new item\" to start.")
                .font(.system(size: 15))
                .foregroundStyle(FMTTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, FMTTheme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You haven't taught me any items yet. Tap Teach a new item to start.")
    }

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
        .padding(.horizontal, FMTTheme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No items match \(query)")
    }

    // MARK: - Delete

    private func deleteItem(_ item: FMTItem) {
        FeaturePrintStore.shared.delete(for: item.id)
        withAnimation {
            items.removeAll { $0.id == item.id }
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(item.name) deleted."
        )
    }
}

#Preview {
    LibraryView(items: .constant(FMTItem.seed))
}
