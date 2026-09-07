import SwiftUI
import WidgetKit

struct LauncherEntry: TimelineEntry {
    let date: Date
    let layoutName: String
    let items: [LauncherItem]
    /// 1-based page this widget instance is configured to show.
    let page: Int
    /// Owner-adjustable layout parameters (SPEC-NEXT §6 L-1). Defaults cover
    /// the pre-settings call sites; the provider always passes stored values.
    var settings: LayoutSettings = .default
    /// Which layout this is in the owner's list (0-based). Drives the header
    /// marker symbol — the owner's 2026-09-04 decision: groups are told apart
    /// by a geometric mark (dot, square, triangle, diamond), never the name.
    var markerIndex: Int = 0
}

// Pure presentation for the launcher widgets. Compiled into both the widget
// and app targets so unit tests can render it headlessly via ImageRenderer,
// and so the in-app settings screen can preview the real widget surface.

/// The widget's surface colours. Owner tried #151515 and went back to pure
/// black the same day (2026-09-07): "最黑最黑的那種顏色". On OLED that is
/// literally unlit pixels, so the widget has no edge of its own.
enum LauncherPalette {
    static let background = Color(red: 0, green: 0, blue: 0)
}

/// Real-widget entry point: reads the injected widget family environment.
struct LauncherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LauncherEntry

    var body: some View {
        LauncherWidgetContent(entry: entry, family: family)
    }
}

/// Pure rendering, parameterized by family so tests can render headlessly.
///
/// Visual baseline is `docs/product/prototype-core-flow.html`: black
/// background, dense white text rows with hairline rules, no digits. The
/// owner's `LayoutSettings` drive the typography (font scale, line height,
/// letter spacing) and the column count; the page's item slice is sized by
/// the derived capacity model in `WidgetCapacity`, whose row heights this
/// view reproduces exactly — the G1-3 render-count matrix pins
/// rendered rows == declared capacity.
///
/// The widget deliberately displays no counts, badges, page numbers, or any
/// other changing content: numbers are the noise this product removes.
struct LauncherWidgetContent: View {
    let entry: LauncherEntry
    let family: WidgetFamily
    /// Test seam: the group marker is not a row, but it renders inside the
    /// rows area. Once rows grow tall (default line height 1.80) it stops
    /// overlapping the first row's glyphs and becomes its own band, which
    /// would make the G1-3 row counter read one row too many. Only that
    /// counting render turns it off; every shipping call site keeps it.
    var showsMarker: Bool = true

    private var settings: LayoutSettings { entry.settings }

    /// Drawn only when the owner asked for it AND this is not the counting
    /// render. Off by default: he said he does not need it day to day, only
    /// occasionally to confirm which group a widget is showing.
    private var markerVisible: Bool { showsMarker && settings.showsGroupMarker }

    private var rows: [LauncherItem] {
        WidgetCapacity.page(entry.items, for: family, page: entry.page,
                            settings: settings)
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                columns
            }
        }
        // Owner decision 2026-09-04: the group marker floats free — no
        // header band, the full height belongs to the rows. It briefly moved
        // to the bottom on 2026-09-07 to dodge the first row's text; the
        // owner asked for the top-right corner back the same day, so the
        // collision is solved where it belongs instead — the first cell of
        // the last column reserves the marker's width (see LauncherRow).
        .overlay(alignment: .topTrailing) { if markerVisible { marker } }
        .containerBackground(for: .widget) { LauncherPalette.background }
    }

    /// The group marker: dot → square → triangle → diamond by the layout's
    /// position in the owner's list. No name, no colors (Owner, 2026-09-04);
    /// VoiceOver keeps the layout name for identification.
    private var marker: some View {
        Image(systemName: markerSymbol)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            // As far into the corner as the system content margin allows.
            // Getting closer means disabling that margin, which moves every
            // name too — and the names are the part that may not move.
            .padding(2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("版面：\(entry.layoutName)" + voiceOverSummary)
    }

    private var markerSymbol: String {
        ["circle.fill", "square.fill", "triangle.fill", "diamond.fill"][min(entry.markerIndex, 3)]
    }

    /// Multi-column page (W-3). Columns share the width equally; rows flow
    /// row-major like the prototype's CSS grid (item 0 top-left), so reading
    /// order matches the single-column list. The rows area is the FULL
    /// content height (no header band since 2026-09-04); at the pinned
    /// render sizes that is exactly what the capacity model declares.
    private var columns: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<settings.columns, id: \.self) { col in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(columnItems(col).enumerated()), id: \.element.id) { index, item in
                        LauncherRow(item: item, settings: settings,
                                    rowHeight: WidgetCapacity.rowHeight(for: family, settings: settings),
                                    // Only one cell in the whole widget sits
                                    // under the marker: top row, last column.
                                    reservesMarkerSpace: markerVisible
                                        && index == 0 && col == settings.columns - 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Row-major split: column `col` holds items col, col+columns, col+2×columns…
    private func columnItems(_ col: Int) -> [LauncherItem] {
        guard col < settings.columns else { return [] }
        return rows.indices.filter { $0 % settings.columns == col }.map { rows[$0] }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(emptyMessage)
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
    }

    /// Distinguishes "nothing to show anywhere" from "this page is past the end",
    /// so a mis-configured page is diagnosable rather than mysteriously blank.
    private var emptyMessage: String {
        entry.items.isEmpty
            ? "此版面沒有項目\n請在 PlainPhone 中新增"
            : "這一頁沒有項目\n請在小工具設定中改頁次"
    }

    private var voiceOverSummary: String {
        let names = rows.map(\.name).joined(separator: "、")
        return rows.isEmpty ? "，目前沒有項目" : "，共 \(rows.count) 個項目：\(names)"
    }
}

/// One tappable text row.
///
/// MECHANISM (SPEC-NEXT §4 M-3, path B — the shipping mechanism): the row is
/// a `Link` to this app's own scheme, `plainphone://open?target=…`, so every
/// hop stays inside Apple's documented contracts. F-5: `Link` hands the URL
/// to the *containing* app; PlainPhoneApp resolves the whitelisted target
/// and opens it from inside the app, where opening a custom scheme is fully
/// supported. Rows are never linked straight to a foreign-scheme URL: F-6
/// leaves iOS routing for those undocumented, and documentedness is the
/// whole point of path B (M-3).
///
/// Path A (`Button(intent: OpenURLIntent(url))`) was falsified on the
/// owner's physical device [2026-09-03]: tapping a row targeting
/// `shortcuts://` does nothing at all — no error surfaced to the user,
/// consistent with the iOS 18 `NSOSStatusErrorDomain -10814` custom-scheme
/// failure recorded in docs/product/RESEARCH.md. M-1 shortcut rows and
/// free-form https/mailto rows therefore all ship path B. PlainPhone
/// visibly flashing on the way to the target is an accepted cost (M-3), and
/// W-6 sets no speed target.
///
/// Typography comes from the owner's settings, not the system text styles:
/// fixed `size = baseFontSize × fontScale` with `kerning` for letter
/// spacing, inside an exact-height row so pitch = fontSize × lineHeight —
/// the prototype's `rowH = size × lead`. The height is the same number the
/// capacity model derives, which is what keeps G1-3's rendered == declared.
///
/// systemSmall is not supported, because at that size iOS provides a single
/// widget-level tap target and a list of independently tappable rows cannot
/// be delivered honestly (F-7).
struct LauncherRow: View {
    let item: LauncherItem
    let settings: LayoutSettings
    /// Exact row height from the capacity model (`WidgetCapacity.rowHeight`).
    let rowHeight: CGFloat
    /// True for the single cell the group marker floats over (top row, last
    /// column): it keeps the marker's width clear so the two never collide.
    var reservesMarkerSpace: Bool = false

    /// Width the marker occupies: 7pt glyph + its 2pt padding, rounded up.
    static let markerWidth: CGFloat = 9

    /// Gap between adjacent cells, taken out of the inside of the pitch box
    /// so the capacity arithmetic is untouched. Owner, 2026-09-07: with equal
    /// cells the separation should come from space, not from a rule — and a
    /// real gap also separates the tap targets, which a 0.5pt hairline did
    /// not.
    ///
    /// The cell is SPACE, not a drawn box. Owner, same day: "我不需要這個方塊
    /// 的存在感，因為我只要有字就好了" — the grid was the layout method, never
    /// something to render. So the gap and the centring stay; the fill does
    /// not. The cell still exists as an invisible tap target.
    static let cellGap: CGFloat = 5

    var body: some View {
        Group {
            if let destination = PlainPhoneURL.open(itemURL: item.url) {
                Link(destination: destination) { label }
            } else {
                label
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .padding(Self.cellGap / 2)
        .frame(height: rowHeight)
    }

    private var label: some View {
        Text(item.name)
            .font(.system(size: WidgetCapacity.baseFontSize * CGFloat(settings.fontScale)))
            .kerning(CGFloat(settings.letterSpacing))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.leading, 4)
            .padding(.trailing, reservesMarkerSpace ? Self.markerWidth : 4)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityHint(URL(string: item.url)?.scheme == "shortcuts"
                               ? "執行捷徑 \(ShortcutsURL.shortcutName(from: item.url) ?? "")"
                               : "開啟 \(item.name)")
    }
}
