import SwiftUI

/// Root screen: manage layouts (create, rename, select, delete) and open the
/// per-layout item editor.
struct HomeView: View {
    @EnvironmentObject private var store: LauncherStore
    @State private var newLayoutName = ""
    @State private var showAddLayout = false
    @State private var showLimitAlert = false

    var body: some View {
        NavigationStack {
            List {
                if store.hadLoadError {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("已儲存的資料無法讀取。為避免覆蓋原資料，尚未寫入任何變更。")
                        }
                        .foregroundStyle(.red)
                        Button("復原：以目前內容重新儲存") {
                            store.recoverFromCorruption()
                        }
                    }
                } else if store.storageSource == .standardFallback {
                    Section {
                        // No icon beside this text: an Image next to a multiline
                        // Text in a List cell trips the accessibility auditor's
                        // textClipped false positive, however arranged (HStack,
                        // combined elements, Text-embedded symbol — all verified
                        // flagged while a simulator screenshot shows the copy
                        // rendering in full, three lines, no ellipsis). Orange
                        // keeps the degraded state loud instead.
                        Text("共用通道不可用：清單資料只存在本機，不會與小工具共用；小工具只會顯示內建的種子清單。")
                            .foregroundStyle(.orange)
                    }
                }

                Section("版面（\(store.data.layouts.count)/\(Limits.maxLayouts)）") {
                    ForEach(store.data.layouts) { layout in
                        row(for: layout)
                    }
                    .onDelete { store.deleteLayout(at: $0) }
                }

                Section {
                    Button {
                        if store.data.layouts.count >= Limits.maxLayouts {
                            showLimitAlert = true
                        } else {
                            newLayoutName = ""
                            showAddLayout = true
                        }
                    } label: {
                        // Built explicitly rather than with Label: at
                        // accessibility text sizes Label keeps icon and text on
                        // one line and truncates the text. Letting the Text wrap
                        // vertically is the difference between a readable row
                        // and a clipped one.
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "plus.circle")
                            Text("新增版面")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityHint("最多 \(Limits.maxLayouts) 個版面")
                }

                Section {
                    NavigationLink(value: AppRoute.layoutSettings) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text("版面設定（欄數、字級、行高、字距）")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityHint("小工具的欄數與文字排版")
                }

                Section("關於") {
                    // Explicit stacking keeps values readable at accessibility
                    // Dynamic Type sizes (LabeledContent truncates its value).
                    VStack(alignment: .leading, spacing: 2) {
                        Text("小工具每頁")
                        Text("每頁列數由版面設定（欄數、字級、行高）推導，最多 \(Limits.maxPages) 頁。")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("放不下的項目")
                        Text("會落到下一頁。在小工具設定中選頁次，把不同頁次的小工具疊起來，就能上下滑動切換；設定讓容量變小時，放不下的項目會在版面與設定畫面標示。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("編輯後")
                        Text("自動更新所有小工具").foregroundStyle(.secondary)
                    }
                    signingExpiry
                }
            }
            .navigationTitle("PlainPhone")
            // Single registration point for every pushed screen.
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .layout(let layoutID):
                    LayoutEditorView(layoutID: layoutID)
                case .item(let layoutID, let itemID):
                    if let layout = store.data.layouts.first(where: { $0.id == layoutID }),
                       let item = layout.items.first(where: { $0.id == itemID }) {
                        ItemEditorView(existingItem: item) { updated in
                            store.updateItem(updated, in: layoutID)
                        }
                    } else {
                        ContentUnavailableView("項目不存在", systemImage: "questionmark.circle")
                    }
                case .layoutSettings:
                    LayoutSettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .alert("版面數量已達上限", isPresented: $showLimitAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("最多只能有 \(Limits.maxLayouts) 個版面，請先刪除一個。")
            }
            .alert("新增版面", isPresented: $showAddLayout) {
                TextField("版面名稱", text: $newLayoutName)
                Button("建立") {
                    _ = store.addLayout(named: newLayoutName.isEmpty ? "新版面" : newLayoutName)
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    /// Free personal-team provisioning profiles last 7 days; on expiry iOS
    /// stops launching the app AND its widget extension, so the Home Screen
    /// list silently dies. Showing the date makes that wall visible and
    /// plannable. Absent on simulator builds, where it is simply not shown.
    @ViewBuilder
    private var signingExpiry: some View {
        if let expiry = ProvisioningProfile.expirationDate {
            let days = max(ProvisioningProfile.daysRemaining() ?? 0, 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("簽名到期")
                Text("\(expiry.formatted(date: .abbreviated, time: .shortened))（剩 \(days) 天）"
                     + (days <= 2 ? "　請盡快重新安裝" : ""))
                    .foregroundStyle(days <= 2 ? .orange : .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("簽名到期，剩 \(days) 天")
        }
    }

    @ViewBuilder
    private func row(for layout: LauncherLayout) -> some View {
        // No selection affordance: which layout a widget shows is decided in
        // that widget's own configuration, not here. A second selector would
        // force the owner to remember which one is in effect.
        NavigationLink(value: AppRoute.layout(layout.id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name)
                    .font(.headline)
                Text("\(layout.items.count) 個項目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("版面 \(layout.name)，\(layout.items.count) 個項目")
        .accessibilityHint("點兩下開啟編輯")
    }
}
