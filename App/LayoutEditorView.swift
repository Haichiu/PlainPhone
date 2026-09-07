import SwiftUI

/// Editor for one layout: add, delete, rename, and drag-reorder items.
struct LayoutEditorView: View {
    @EnvironmentObject private var store: LauncherStore
    @Environment(\.dismiss) private var dismiss

    let layoutID: UUID

    /// Always reflects the current (possibly renamed) layout.
    private var currentName: String {
        store.data.layouts.first { $0.id == layoutID }?.name ?? "版面"
    }

    @State private var showAddItem = false
    @State private var renamingLayout = false
    @State private var newLayoutName = ""

    private var layoutIndex: Int? {
        store.data.layouts.firstIndex { $0.id == layoutID }
    }

    var body: some View {
        Group {
            if let idx = layoutIndex {
                editor(forItemAt: idx)
            } else {
                ContentUnavailableView("版面不存在", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(currentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增項目")
            }
        }
    }

    @ViewBuilder
    private func editor(forItemAt idx: Int) -> some View {
        let canAddMore = store.data.layouts[idx].items.count < Limits.maxItemsPerLayout
        // L-3 (b): settings-driven capacity may leave stored items with no
        // page that can show them; they are storable but must be announced.
        let overflow = WidgetCapacity.overflowCount(store.data.layouts[idx].items,
                                                    settings: store.data.settings)
        List {
            Section("項目（\(store.data.layouts[idx].items.count)/\(Limits.maxItemsPerLayout)）") {
                ForEach(store.data.layouts[idx].items) { item in
                    NavigationLink(value: AppRoute.item(layoutID: layoutID, itemID: item.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name.isEmpty ? "（未命名）" : item.name)
                            Text(item.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityIdentifier("layout-item-row")
                }
                .onDelete { store.deleteItems(at: $0, in: layoutID) }
                .onMove { store.moveItems(in: layoutID, from: $0, to: $1) }
            }
            if overflow > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("目前設定下有 \(overflow) 個項目在小工具上看不到",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("小工具每頁容量由版面設定推導；這些項目超出三頁總容量。可在「版面設定」放寬欄數或字級，或刪減項目。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !canAddMore {
                Section {
                    Label("已達每個版面 \(Limits.maxItemsPerLayout) 個項目上限", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            NavigationStack {
                ItemEditorView(existingItem: nil) { newItem in
                    _ = store.addItem(newItem, to: layoutID)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("重新命名版面", isPresented: $renamingLayout) {
            TextField("名稱", text: $newLayoutName)
            Button("儲存") {
                let trimmed = newLayoutName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                store.renameLayout(id: layoutID, to: trimmed)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("最多 \(Limits.maxNameLength) 個字")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("重新命名版面") {
                        newLayoutName = currentName
                        renamingLayout = true
                    }
                    Button("刪除版面", role: .destructive) {
                        store.deleteLayout(id: layoutID)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("版面選項")
            }
        }
    }
}
