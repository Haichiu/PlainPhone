import XCTest
import WidgetKit
@testable import PlainPhone

/// Layout settings end to end: the model (defaults, clamps, K-14 decode),
/// the derived capacity (L-2), the overflow announcement (L-3 option b /
/// G1-4), and the store→provider path that carries settings into the widget
/// (W-2/W-5). The rendered-truth side of the capacity model is pinned
/// separately by the G1-3 matrix in WidgetVisualTests.
final class LayoutSettingsTests: XCTestCase {

    // MARK: - Model defaults and clamps

    func testDefaultSettingsMatchOwnerDecision() {
        let s = LayoutSettings.default
        // 2026-09-07: transcribed from the owner's device after he reported
        // preferring these in daily use (版面設定 screenshot).
        XCTAssertEqual(s.columns, 3, "W-3: default is three columns")
        XCTAssertEqual(s.fontScale, 1.0)
        XCTAssertEqual(s.lineHeight, 1.8)
        XCTAssertEqual(s.letterSpacing, 2.0)
        XCTAssertFalse(s.showsGroupMarker,
                       "the group marker is opt-in, not standing furniture")
    }

    func testSettingsClampToAllowedRanges() {
        let s = LayoutSettings(columns: 7, fontScale: 9, lineHeight: 0.1, letterSpacing: 100)
        XCTAssertEqual(s.columns, 3)
        XCTAssertEqual(s.fontScale, 1.6)
        XCTAssertEqual(s.letterSpacing, 3)
        XCTAssertEqual(s.lineHeight, 1.0)

        let low = LayoutSettings(columns: 0, fontScale: 0.1, lineHeight: 0.0, letterSpacing: -100)
        XCTAssertEqual(low.columns, 1)
        XCTAssertEqual(low.fontScale, 0.8)
        XCTAssertEqual(low.lineHeight, 1.0)
        XCTAssertEqual(low.letterSpacing, -0.5)
    }

    // MARK: - K-14: old and partial payloads decode

    func testLegacyLauncherDataBlobWithoutSettingsDecodesToDefaults() throws {
        // A payload written before settings existed: layouts only.
        let legacy = """
        {"layouts":[{"id":"11111111-1111-1111-1111-111111111111","name":"常用","items":[]}]}
        """
        let data = try JSONDecoder().decode(LauncherData.self, from: Data(legacy.utf8))
        XCTAssertEqual(data.settings, LayoutSettings.default,
                       "missing settings key must decode to defaults, not fail (K-14)")
        XCTAssertEqual(data.layouts.map(\.name), ["常用"])
    }

    func testPartialSettingsDecodeMissingFieldsToDefaults() throws {
        let partial = """
        {"layouts":[],"settings":{"columns":3}}
        """
        let data = try JSONDecoder().decode(LauncherData.self, from: Data(partial.utf8))
        XCTAssertEqual(data.settings.columns, 3)
        XCTAssertEqual(data.settings.fontScale, LayoutSettings.default.fontScale)
        XCTAssertEqual(data.settings.lineHeight, LayoutSettings.default.lineHeight)
        XCTAssertEqual(data.settings.letterSpacing, LayoutSettings.default.letterSpacing)
        XCTAssertEqual(data.settings.showsGroupMarker, LayoutSettings.default.showsGroupMarker,
                       "a payload written before the toggle existed must decode to off")
    }

    func testOutOfRangePersistedSettingsClampOnDecode() throws {
        let wild = """
        {"layouts":[],"settings":{"columns":99,"fontScale":42,"lineHeight":-1,"letterSpacing":50}}
        """
        let data = try JSONDecoder().decode(LauncherData.self, from: Data(wild.utf8))
        XCTAssertEqual(data.settings, LayoutSettings(columns: 3, fontScale: 1.6,
                                                     lineHeight: 1.0, letterSpacing: 3))
    }

    // MARK: - Derived capacity (L-2)

    func testRowsPerColumnFollowsOwnerFormulaAtDefaultLineHeight() {
        // Header band removed 2026-09-04 (Owner): the rows area is the full
        // content height (medium 158pt / large 345pt). Declared rows come
        // from the model and are pinned by G1-3 against the render; medium
        // stays 5, large is now 13 (was 12) at the default font.
        let basis = LayoutSettings.measuredBasisLineHeight
        for columns in LayoutSettings.allowedColumns {
            let medium = LayoutSettings(columns: columns, fontScale: 1.0, lineHeight: basis)
            XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: medium), 5)
            let large = LayoutSettings(columns: columns, fontScale: 1.0, lineHeight: basis)
            XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemLarge, settings: large), 13)

            let maxFont = LayoutSettings(columns: columns, fontScale: 1.6, lineHeight: basis)
            XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: maxFont), 3)
            XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemLarge, settings: maxFont), 8)

            // …and at the SHIPPING line height (1.80) the taller pitch costs
            // rows. Both readings come from one formula; neither is a
            // constant the renderer can drift away from (G1-3 pins that).
            let shipping = LayoutSettings(columns: columns, fontScale: 1.0)
            XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: shipping), 4)
            XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemLarge, settings: shipping), 9)
        }
    }

    func testCapacityShrinksWithTighterLineHeight() {
        let airy = LayoutSettings(columns: 1, fontScale: 1.0, lineHeight: 1.0)
        let dense = LayoutSettings(columns: 1, fontScale: 1.0, lineHeight: 1.8)
        XCTAssertGreaterThan(WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: airy),
                             WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: dense),
                             "row pitch grows with lineHeight, so capacity must shrink — the declaration stays honest")
    }

    func testPageSizeIsRowsTimesColumns() {
        // Header band removed 2026-09-04: per-page capacity = rows per
        // column (medium 5 / large 13) × columns.
        for columns in LayoutSettings.allowedColumns {
            let s = LayoutSettings(columns: columns, fontScale: 1.0,
                                   lineHeight: LayoutSettings.measuredBasisLineHeight)
            XCTAssertEqual(WidgetCapacity.pageSize(for: .systemMedium, settings: s), 5 * columns)
            XCTAssertEqual(WidgetCapacity.pageSize(for: .systemLarge, settings: s), 13 * columns)
        }
    }

    func testPageSlicingUsesDerivedPageSize() {
        // 12 items, one column, default font: medium page = 5 (as before).
        let items = (0..<12).map { LauncherItem(name: "i\($0)", url: "https://e.co/\($0)") }
        let oneColumn = LayoutSettings(columns: 1, fontScale: 1.0,
                                       lineHeight: LayoutSettings.measuredBasisLineHeight)
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemMedium, page: 1, settings: oneColumn).map(\.name),
                       (0..<5).map { "i\($0)" })
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemMedium, page: 2, settings: oneColumn).map(\.name),
                       (5..<10).map { "i\($0)" })
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemLarge, page: 1, settings: oneColumn).map(\.name),
                       items.map(\.name))

        // Three columns × 4 rows (the default): all 12 fit on one page.
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemMedium, page: 1,
                                           settings: .default).map(\.name),
                       items.map(\.name))

        // Pages past the end are empty; out-of-range pages clamp.
        XCTAssertTrue(WidgetCapacity.page(items, for: .systemLarge, page: 2,
                                          settings: .default).isEmpty)
        XCTAssertEqual(WidgetCapacity.clampPage(0), 1)
        XCTAssertEqual(WidgetCapacity.clampPage(99), Limits.maxPages)
        XCTAssertEqual(WidgetCapacity.pageCount(items, for: .systemMedium, settings: .default), 1)
        XCTAssertEqual(WidgetCapacity.pageCount(items, for: .systemLarge, settings: .default), 1)
        XCTAssertEqual(WidgetCapacity.pageCount([], for: .systemLarge, settings: .default), 1)
    }

    // MARK: - L-3 option (b): overflow is countable and announced

    func testOverflowCountIsZeroWhenCapacityHoldsEverything() {
        let items = (0..<Limits.maxItemsPerLayout).map {
            LauncherItem(name: "i\($0)", url: "https://e.co/\($0)")
        }
        XCTAssertEqual(WidgetCapacity.overflowCount(items, settings: .default), 0,
                       "the cap IS 3 medium pages at the defaults (3 × 12 = 36)")
        let wide = LayoutSettings(columns: 3, fontScale: 1.0,
                                  lineHeight: LayoutSettings.measuredBasisLineHeight)
        XCTAssertEqual(WidgetCapacity.overflowCount(items, settings: wide), 0,
                       "a tighter line height only ever adds rows, never removes them")
    }

    func testOverflowCountGrowsWhenSettingsShrinkCapacity() {
        let items = (0..<Limits.maxItemsPerLayout).map {
            LauncherItem(name: "i\($0)", url: "https://e.co/\($0)")
        }
        // 1 column at 1.6×: medium rowsPerColumn = floor(5/1.6) = 3 →
        // 3-page capacity 9 → items 9…14 (6) must be announced, not silent.
        let tight = LayoutSettings(columns: 1, fontScale: 1.6,
                                   lineHeight: LayoutSettings.measuredBasisLineHeight)
        let reachable = Limits.maxPages * WidgetCapacity.pageSize(for: .systemMedium, settings: tight)
        XCTAssertEqual(reachable, 9)
        XCTAssertEqual(WidgetCapacity.overflowCount(items, settings: tight),
                       Limits.maxItemsPerLayout - reachable)
        XCTAssertTrue(WidgetCapacity.overflowCount([], settings: tight) == 0)
    }

    /// G1-4: no stored item may be invisible on every page of a family
    /// without being announced. Sweeps the settings grid; for each family,
    /// every item must be either sliced onto some page (the same `page`
    /// arithmetic the renderer consumes) or counted by `overflowCount`.
    func testG14NoSilentBlackHolesUnderAnySettings() {
        let items = (0..<Limits.maxItemsPerLayout).map {
            LauncherItem(name: "i\($0)", url: "https://e.co/\($0)")
        }
        var settingsChecked = 0
        for columns in LayoutSettings.allowedColumns {
            for fontScale in stride(from: 0.8, through: 1.6, by: 0.2) {
                for lineHeight in [1.0, 1.2, 1.5, 1.8] {
                    let settings = LayoutSettings(columns: columns, fontScale: fontScale,
                                                  lineHeight: lineHeight)
                    let announced = WidgetCapacity.overflowCount(items, settings: settings)
                    for family in [WidgetFamily.systemMedium, .systemLarge] {
                        var visibleNames = Set<String>()
                        for page in 1...Limits.maxPages {
                            visibleNames.formUnion(
                                WidgetCapacity.page(items, for: family, page: page,
                                                    settings: settings).map(\.name))
                        }
                        for (index, item) in items.enumerated() {
                            let onSomePage = visibleNames.contains(item.name)
                            let isAnnounced = index >= items.count - announced
                            XCTAssertTrue(onSomePage || isAnnounced,
                                          "\(family) columns=\(columns) font=\(fontScale) lead=\(lineHeight): " +
                                          "item \(item.name) is on no page and unannounced — silent black hole")
                        }
                    }
                    settingsChecked += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(settingsChecked, 24, "sweep must cover the grid")
    }

    // MARK: - Store → provider → entry (W-2/W-5)

    func testUpdateSettingsPersistsThroughStoreAndReload() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        let updated = LayoutSettings(columns: 3, fontScale: 1.4, lineHeight: 1.6,
                                     letterSpacing: 1.5)
        store.updateSettings(updated)

        XCTAssertEqual(store.data.settings, updated, "in-memory settings change immediately")
        let reloaded = LauncherStore(defaults: suite)
        XCTAssertEqual(reloaded.data.settings, updated,
                       "settings persist through the shared payload round-trip")
    }

    func testProviderCarriesStoredSettingsIntoEntry() {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        store.updateSettings(LayoutSettings(columns: 3, fontScale: 1.6, lineHeight: 1.0,
                                            letterSpacing: 2))

        let provider = LauncherProvider(defaults: suite)
        let entry = provider.resolveEntry(for: nil)
        XCTAssertEqual(entry.settings.columns, 3)
        XCTAssertEqual(entry.settings.fontScale, 1.6)
        XCTAssertEqual(entry.settings.lineHeight, 1.0)
        XCTAssertEqual(entry.settings.letterSpacing, 2)
    }
}
