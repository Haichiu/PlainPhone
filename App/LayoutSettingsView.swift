import SwiftUI

/// In-app layout settings (SPEC-NEXT §6 L-1, W-2): columns, font scale,
/// line height, letter spacing. Every change writes through
/// `LauncherStore.updateSettings(_:)`, which saves the shared payload and
/// reloads all widget timelines (W-5) — the widgets reflect the change on
/// their next render without leaving this screen's lifetime.
///
/// Sliders keep a local draft while dragging (live preview) and commit on
/// release, so a single gesture is one shared-channel write + one timeline
/// reload rather than one per frame tick.
struct LayoutSettingsView: View {
    @EnvironmentObject private var store: LauncherStore

    @State private var columns = LayoutSettings.default.columns
    @State private var fontScale = LayoutSettings.default.fontScale
    @State private var lineHeight = LayoutSettings.default.lineHeight
    @State private var letterSpacing = LayoutSettings.default.letterSpacing
    @State private var showsGroupMarker = LayoutSettings.default.showsGroupMarker

    var body: some View {
        Form {
            Section("欄數") {
                Picker("欄數", selection: $columns) {
                    Text("一欄").tag(1)
                    Text("兩欄").tag(2)
                    Text("三欄").tag(3)
                }
                .pickerStyle(.segmented)
                .onChange(of: columns) { commit() }
            }

            Section("分組記號") {
                Toggle("在右上角顯示記號", isOn: $showsGroupMarker)
                    .onChange(of: showsGroupMarker) { commit() }
                Text("圓點／方形／三角／菱形，依版面順序。平常關著，需要確認某個小工具是哪一組時再打開。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("文字") {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("字級")
                        Spacer(minLength: 0)
                        Text(String(format: "%.2f×", fontScale))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontScale,
                           in: LayoutSettings.allowedFontScale) { editing in
                        if !editing { commit() }
                    }
                    Text("\(LayoutSettings.allowedFontScale.lowerBound.formatted(.number.precision(.fractionLength(1))))–\(LayoutSettings.allowedFontScale.upperBound.formatted(.number.precision(.fractionLength(1))))×").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("行高")
                        Spacer(minLength: 0)
                        Text(String(format: "%.2f", lineHeight))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $lineHeight,
                           in: LayoutSettings.allowedLineHeight) { editing in
                        if !editing { commit() }
                    }
                    Text("每列高度＝字級×行高").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("字距")
                        Spacer(minLength: 0)
                        Text(String(format: "%.1f pt", letterSpacing))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $letterSpacing,
                           in: LayoutSettings.allowedLetterSpacing) { editing in
                        if !editing { commit() }
                    }
                    Text("\(LayoutSettings.allowedLetterSpacing.lowerBound.formatted())–\(LayoutSettings.allowedLetterSpacing.upperBound.formatted()) pt").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section("預覽（小工具實際外觀）") {
                widgetPreview
                    .frame(height: 158)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            Section("小工具容量") {
                // Capacity is derived, not constant (L-2). State the current
                // derivation so the sliders' effect on page size is legible.
                VStack(alignment: .leading, spacing: 2) {
                    Text("中型小工具")
                    Text("每頁 \(mediumRows) 列 × \(columns) 欄 = \(mediumPageSize) 個項目，最多 \(Limits.maxPages) 頁。")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("大型小工具")
                    Text("每頁 \(largeRows) 列 × \(columns) 欄 = \(largePageSize) 個項目。")
                        .foregroundStyle(.secondary)
                }
                overflowNotices
            }
        }
        .navigationTitle("版面設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFromStore)
    }

    // MARK: - Live preview

    /// The REAL widget surface (same view the extension renders), fed the
    /// current draft settings. Hit-testing is off: the preview is a mirror,
    /// not a second launcher.
    private var widgetPreview: some View {
        let items = store.data.layouts.first?.items ?? DefaultLayouts.everyday.items
        return LauncherWidgetContent(
            entry: LauncherEntry(date: .now, layoutName: store.data.layouts.first?.name ?? "預覽",
                                 items: Array(items.prefix(mediumPageSize)),
                                 page: 1,
                                 settings: draft),
            family: .systemMedium)
    }

    // MARK: - L-3(b): settings that shrink capacity must be loud

    /// One line per layout whose stored items exceed the derived 3-page
    /// capacity: storable, but invisible on the smallest widgets unless the
    /// owner changes something. Never silent (G1-4).
    @ViewBuilder
    private var overflowNotices: some View {
        let overflowing = store.data.layouts.map { layout in
            (name: layout.name, count: WidgetCapacity.overflowCount(layout.items, settings: draft))
        }.filter { $0.count > 0 }
        if overflowing.isEmpty {
            Text("目前設定下，所有項目都排得進小工具的三頁。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(overflowing, id: \.name) { entry in
                Text("版面「\(entry.name)」有 \(entry.count) 個項目在小工具上看不到")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Draft state

    private var draft: LayoutSettings {
        LayoutSettings(columns: columns, fontScale: fontScale,
                       lineHeight: lineHeight, letterSpacing: letterSpacing,
                       showsGroupMarker: showsGroupMarker)
    }

    private var mediumRows: Int {
        WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: draft)
    }
    private var largeRows: Int {
        WidgetCapacity.rowsPerColumn(for: .systemLarge, settings: draft)
    }
    private var mediumPageSize: Int {
        WidgetCapacity.pageSize(for: .systemMedium, settings: draft)
    }
    private var largePageSize: Int {
        WidgetCapacity.pageSize(for: .systemLarge, settings: draft)
    }

    private func loadFromStore() {
        let s = store.data.settings
        columns = s.columns
        fontScale = s.fontScale
        lineHeight = s.lineHeight
        letterSpacing = s.letterSpacing
        showsGroupMarker = s.showsGroupMarker
    }

    private func commit() {
        store.updateSettings(draft)
    }
}
