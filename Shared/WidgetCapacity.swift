import Foundation
import WidgetKit

/// Settings-derived paging arithmetic (SPEC-NEXT §6 L-2).
///
/// A layout's items are split into pages of `pageSize(for:settings:)`. A
/// widget instance is configured to show exactly one page; overflow spills
/// onto the next page, which the owner reaches by stacking another widget
/// instance configured to that page (native iOS widget stack, W-4). Items
/// that fit on NO page under the current settings are storable but must be
/// announced in-app — `overflowCount` feeds that notice (L-3 option b).
///
/// THE MODEL AND THE RENDERER SHARE ONE FORMULA. `rowsPerColumn` is the
/// declared capacity; `WidgetVisualTests` renders the widget headlessly and
/// counts the text bands per column strip, pinning rendered == declared for
/// columns {1,2,3} × medium/large × fontScale {1.0, 1.6} (G1-3). Changing
/// either side without the other breaks that matrix.
enum WidgetCapacity {
    // MARK: Geometry basis (pinned to the WidgetVisualTests render sizes)

    /// Row font size in points at `fontScale` 1.0 — the prototype's default
    /// 17pt (docs/product/prototype-core-flow.html).
    static let baseFontSize: CGFloat = 17
    /// Header band: REMOVED 2026-09-04 (Owner decision) — the group marker
    /// now floats in the top-trailing corner over the first row's trailing
    /// whitespace, so the full content height belongs to the rows.
    /// Row pitch at (fontScale 1.0, default lineHeight): exactly
    /// `base × pitch0` of the rows area — medium 132/5 = 26.4pt,
    /// large 312/12 = 26.0pt. Measured basis, not chosen (CH-3 was).
    static func baseRowPitch(for family: WidgetFamily) -> CGFloat {
        family == .systemLarge ? 26 : 26.4
    }
    /// Vertical padding per row at the default settings, so that
    /// fontSize × lineHeight + padding reproduces the measured pitch exactly.
    static func baseRowPadding(for family: WidgetFamily) -> CGFloat {
        baseRowPitch(for: family) - baseFontSize * CGFloat(LayoutSettings.measuredBasisLineHeight)
    }

    /// Rows per column at the given settings — the declared capacity (L-2).
    ///
    /// Derived directly from the FULL content height (no header band since
    /// 2026-09-04) divided by the settings-scaled row pitch:
    /// `max(1, floor(rowsArea / pitch))`. Base measured pitches (medium
    /// 26.4pt / large 26.0pt at 5 and 12 rows) still anchor the scale; row
    /// pitch scales with lineHeight the way the prototype does
    /// (`rowH = size × lead`), so lineHeight enters through the same ratio.
    static func rowsPerColumn(for family: WidgetFamily, settings: LayoutSettings) -> Int {
        let rowH = rowHeight(for: family, settings: settings)
        // +1e-6 absorbs float noise when the division is exact, so exact-fit
        // settings declare the row that exactly fills the page.
        return max(1, Int((Double(rowsAreaHeight(for: family) / rowH) + 0.000_001).rounded(.down)))
    }

    /// Effective scale on the row pitch: fontScale × lineHeight ratio.
    /// pitch(settings) = baseRowPitch × effectiveScale, by construction.
    static func effectiveScale(for family: WidgetFamily, settings: LayoutSettings) -> Double {
        let pitch = Double(baseFontSize) * settings.lineHeight
            + Double(baseRowPadding(for: family))
        return settings.fontScale * pitch / Double(baseRowPitch(for: family))
    }

    /// Rendered row height — the same product the model declares:
    /// baseRowPitch × effectiveScale. The renderer MUST build rows with this.
    static func rowHeight(for family: WidgetFamily, settings: LayoutSettings) -> CGFloat {
        baseRowPitch(for: family) * CGFloat(effectiveScale(for: family, settings: settings))
    }

    /// Rows area: the FULL content height at the pinned render sizes
    /// (medium 338×158 → 158pt, large 345×345 → 345pt) — the header band is
    /// gone, so `rowsPerColumn` rows fit and one more does not: the equality
    /// G1-3 pins.
    static func rowsAreaHeight(for family: WidgetFamily) -> CGFloat {
        family == .systemLarge ? 345 : 158
    }

    /// Capacity of one page: rows per column × columns.
    static func pageSize(for family: WidgetFamily, settings: LayoutSettings) -> Int {
        rowsPerColumn(for: family, settings: settings) * settings.columns
    }

    /// Clamps a configured page into the supported 1...maxPages range.
    static func clampPage(_ page: Int) -> Int {
        min(max(page, 1), Limits.maxPages)
    }

    /// Items displayed by a widget configured to `page` (1-based).
    /// Returns an empty array for a page beyond the end of the list.
    static func page(_ items: [LauncherItem], for family: WidgetFamily, page: Int,
                     settings: LayoutSettings) -> [LauncherItem] {
        let size = pageSize(for: family, settings: settings)
        let start = (clampPage(page) - 1) * size
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + size, items.count)])
    }

    /// How many pages this layout actually occupies in `family` (at least 1).
    static func pageCount(_ items: [LauncherItem], for family: WidgetFamily,
                          settings: LayoutSettings) -> Int {
        guard !items.isEmpty else { return 1 }
        let size = pageSize(for: family, settings: settings)
        return min(Limits.maxPages, (items.count + size - 1) / size)
    }

    // MARK: L-3 option (b) — storable, but never silently invisible

    /// Items beyond the 3-page capacity of the SMALLEST shipping family
    /// (medium). Such items are storable (the hard cap `Limits.maxItemsPerLayout`
    /// is unchanged), but no widget instance of the smallest family can show
    /// them, so the app must announce them (L-3 option b / G1-4) instead of
    /// letting them vanish behind a setting. Bounding by the smallest family
    /// means the announcement errs on the safe side: anything it covers is
    /// unreachable in the weakest configuration the owner can build.
    static func overflowCount(_ items: [LauncherItem], settings: LayoutSettings) -> Int {
        let reachable = Limits.maxPages * pageSize(for: .systemMedium, settings: settings)
        return max(0, items.count - reachable)
    }
}
