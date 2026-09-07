import XCTest
import WidgetKit
@testable import PlainPhone

final class BehaviorProbeTests: XCTestCase {
    func testNativeRouteUpgradePreservesCustomRowsAndIsIdempotent() {
        let original = LauncherData(layouts: [LauncherLayout(name: "我的清單", items: [
            LauncherItem(name: "Notes", url: ShortcutsURL.runShortcut(named: "Notes")),
            LauncherItem(name: "Notes", url: "https://example.com/custom"),
            LauncherItem(name: "Beeper", url: ShortcutsURL.runShortcut(named: "Beeper")),
        ])])
        var upgraded = original
        XCTAssertTrue(DefaultLayouts.upgradeNativeRoutes(in: &upgraded))
        XCTAssertEqual(upgraded.layouts[0].items[0].url, "mobilenotes://")
        XCTAssertEqual(upgraded.layouts[0].items.map(\.id), original.layouts[0].items.map(\.id))
        XCTAssertEqual(upgraded.layouts[0].id, original.layouts[0].id)
        XCTAssertEqual(upgraded.layouts[0].items[1...], original.layouts[0].items[1...])
        XCTAssertEqual(upgraded.settings, original.settings)
        XCTAssertFalse(DefaultLayouts.upgradeNativeRoutes(in: &upgraded))
    }

    // MARK: Default layouts

    func testDefaultLayoutsExistWithItems() {
        // Exactly one starter list. Seeding several layouts would be seeding
        // someone else's habits; the owner authors their own.
        // 12 + 5 is a shape claim: one systemLarge above one systemMedium fills an
        // iPhone page, so the whole daily set is reachable without a swipe.
        XCTAssertEqual(DefaultLayouts.all.map(\.name), ["常用", "其他"])
        XCTAssertLessThanOrEqual(DefaultLayouts.everyday.items.count, Limits.rowsPerPageLarge)
        XCTAssertLessThanOrEqual(DefaultLayouts.occasional.items.count, Limits.rowsPerPageMedium)
        for layout in DefaultLayouts.all {
            XCTAssertFalse(layout.items.isEmpty, "\(layout.name) has no items")
            XCTAssertLessThanOrEqual(layout.items.count, Limits.maxItemsPerLayout)
        }
    }

    func testDefaultItemsHaveURLs() {
        for layout in DefaultLayouts.all {
            for item in layout.items {
                XCTAssertNotNil(URL(string: item.url), "\(item.name) → \(item.url)")
                XCTAssertFalse(item.url.isEmpty)
                // M-1 (SPEC-NEXT §4): one row = one app name = one same-named
                // shortcut — no `input` parameter, no shared "Open" shortcut.
                if let native = DefaultLayouts.nativeURLs[item.name] {
                    XCTAssertEqual(item.url, native)
                } else {
                    XCTAssertEqual(ShortcutsURL.shortcutName(from: item.url), item.name)
                }
                let comps = URLComponents(string: item.url)
                XCTAssertNil(comps?.queryItems?.first { $0.name == "input" },
                             "seed URLs must not carry an input parameter: \(item.url)")
            }
        }
    }

    // MARK: Derived per-family rows per column (L-2: capacity is a function
    // of settings now; the base constants are the measured fontScale-1.0 rows)

    func testFamilyPageSizes() {
        // Defaults moved to the owner's own device settings on 2026-09-07
        // (3 columns, line height 1.80): the taller row pitch costs rows,
        // medium 5 → 4 and large 13 → 9, while the wider page more than
        // repays it (large: 13 items → 27).
        XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: .default), 4)
        XCTAssertEqual(WidgetCapacity.rowsPerColumn(for: .systemLarge, settings: .default), 9)
        XCTAssertEqual(WidgetCapacity.pageSize(for: .systemMedium, settings: .default), 12)
        XCTAssertEqual(WidgetCapacity.pageSize(for: .systemLarge, settings: .default), 27)
        // The storage cap restates the derived model; it must not drift.
        XCTAssertEqual(Limits.rowsPerPageMediumAtDefault,
                       WidgetCapacity.rowsPerColumn(for: .systemMedium, settings: .default),
                       "the cap's medium-row term must equal what the model derives")
    }

    /// THE INVARIANT at default settings: every stored item must be
    /// reachable on some page, in the SMALLEST shipping family. The previous
    /// design stored 32 items while systemLarge showed 16, leaving half of
    /// them permanently unreachable. Under tighter settings the derived
    /// capacity can drop below the storage cap — that gap is governed by
    /// L-3(b) and swept by testG14NoSilentBlackHolesUnderAnySettings.
    func testEveryStoredItemIsReachableOnSomePage() {
        XCTAssertEqual(Limits.maxItemsPerLayout,
                       Limits.maxPages * WidgetCapacity.pageSize(for: .systemMedium, settings: .default),
                       "storage cap must equal pages × a smallest-family page at the defaults")

        let items = (0..<Limits.maxItemsPerLayout).map {
            LauncherItem(name: "i\($0)", url: "https://e.co/\($0)")
        }
        for family in [WidgetFamily.systemMedium, .systemLarge] {
            var seen: [String] = []
            for page in 1...Limits.maxPages {
                seen += WidgetCapacity.page(items, for: family, page: page,
                                            settings: .default).map(\.name)
            }
            XCTAssertEqual(seen, items.map(\.name),
                           "\(family): pages must cover every item exactly once, in order")
        }
    }


    func testPagingContract() {
        let items = (0..<12).map { LauncherItem(name: "i\($0)", url: "https://e.co/\($0)") }

        // One column at the MEASURED basis line height (1.2, not the 1.80
        // shipping default): medium page = 5 base rows, large = 13.
        let oneColumn = LayoutSettings(columns: 1, fontScale: 1.0,
                                       lineHeight: LayoutSettings.measuredBasisLineHeight)
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemMedium, page: 1,
                                           settings: oneColumn).map(\.name),
                       (0..<5).map { "i\($0)" })
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemMedium, page: 2,
                                           settings: oneColumn).map(\.name),
                       (5..<10).map { "i\($0)" })
        // Large holds all 12 on page 1, so page 2 is past the end.
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemLarge, page: 1,
                                           settings: oneColumn).map(\.name),
                       items.map(\.name))
        XCTAssertTrue(WidgetCapacity.page(items, for: .systemLarge, page: 2,
                                          settings: oneColumn).isEmpty)

        // Default settings (three columns × 4 rows) hold all 12 on one
        // medium page — the whole point of the 2026-09-07 change.
        XCTAssertEqual(WidgetCapacity.page(items, for: .systemMedium, page: 1,
                                           settings: .default).map(\.name),
                       items.map(\.name))

        // Out-of-range configured pages clamp instead of trapping.
        XCTAssertEqual(WidgetCapacity.clampPage(0), 1)
        XCTAssertEqual(WidgetCapacity.clampPage(99), Limits.maxPages)
        XCTAssertEqual(WidgetCapacity.pageCount(items, for: .systemMedium, settings: .default), 1)
        XCTAssertEqual(WidgetCapacity.pageCount(items, for: .systemLarge, settings: .default), 1)
        XCTAssertEqual(WidgetCapacity.pageCount([], for: .systemLarge, settings: .default), 1)
    }

    // MARK: Ordering persists through the store

    func testMoveItemPersistsOrder() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        var layout = try XCTUnwrap(store.data.layouts.first)
        let original = layout.items.map(\.name)
        guard original.count >= 2 else { return XCTFail("need >=2 items") }

        // Array.move semantics: moving offset 0 "toOffset 1" is a no-op (the
        // destination is adjusted for prior removals), so use toOffset 2.
        store.moveItems(in: layout.id, from: IndexSet(integer: 0), to: 2)

        let inMemory = try XCTUnwrap(store.data.layouts.first { $0.id == layout.id }).items.map(\.name)
        XCTAssertNotEqual(inMemory, original, "in-memory order must change after move")

        let reloaded = LauncherStore(defaults: suite)
        let after = try XCTUnwrap(reloaded.data.layouts.first { $0.id == layout.id }).items.map(\.name)
        XCTAssertEqual(after, inMemory, "order must persist across reload")
        XCTAssertEqual(after.first, original[1], "moved item lands first")
    }
}

/// The widget layout-picker data source must reflect saved layouts and filter
/// stale IDs (e.g. after a layout was deleted) without crashing.
final class LayoutQueryTests: XCTestCase {

    @MainActor
    func testSuggestedEntitiesMatchSavedLayouts() async throws {
        let suiteName = "test.layoutquery.suggested"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        defer { d.removePersistentDomain(forName: suiteName) }
        _ = LauncherStore(defaults: d)

        // Query MUST read from the same storage it was given.
        let suggested = try await LayoutQuery(suiteName: suiteName).suggestedEntities()
        XCTAssertEqual(suggested.map(\.name), DefaultLayouts.all.map(\.name))
    }

    @MainActor
    func testEntitiesForIdentifiersFilterStaleIDs() async throws {
        let suiteName = "test.layoutquery.stale"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        defer { d.removePersistentDomain(forName: suiteName) }
        let store = LauncherStore(defaults: d)
        store.seedIfNeeded() // materialize defaults so IDs are stable across stores
        let valid = try XCTUnwrap(store.data.layouts.first?.id.uuidString)

        let staleID = UUID().uuidString
        let resolved = try await LayoutQuery(suiteName: suiteName).entities(for: [staleID, valid])
        XCTAssertEqual(resolved.map(\.id), [valid], "stale ID must be filtered out")
    }

    @MainActor
    func testDefaultResultIsFirstLayoutOfItsOwnStorage() async throws {
        let suiteName = "test.layoutquery.default"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        defer { d.removePersistentDomain(forName: suiteName) }
        _ = LauncherStore(defaults: d)

        let def = await LayoutQuery(suiteName: suiteName).defaultResult()
        XCTAssertEqual(def?.name, DefaultLayouts.all.first?.name)
    }
}

/// The widget's "which layout do I show" decision: valid intent → that layout;
/// stale intent ID → graceful fallback to selected/first layout.
final class LauncherProviderSelectionTests: XCTestCase {

    @MainActor
    private func makeProviderAndSuite() -> (LauncherProvider, UserDefaults, LauncherStore) {
        let suiteName = "test.provider.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        let store = LauncherStore(defaults: d)
        store.seedIfNeeded()
        return (LauncherProvider(defaults: d), d, store)
    }

    private func teardown(_ d: UserDefaults) {
        if let name = d.object(forKey: "__name") as? String {}
    }

    @MainActor
    func testValidIntentResolvesConfiguredLayout() async throws {
        let suiteName = "test.provider.valid.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        defer { d.removePersistentDomain(forName: suiteName) }
        let store = LauncherStore(defaults: d)
        store.seedIfNeeded()
        _ = store.addLayout(named: "夜間")
        let target = try XCTUnwrap(store.data.layouts.first { $0.name == "夜間" })

        var intent = SelectLayoutIntent()
        intent.layout = LauncherLayoutEntity(id: target.id.uuidString, name: target.name)
        intent.page = 2
        let entry = await LauncherProvider(defaults: d).resolveEntry(for: intent)
        XCTAssertEqual(entry.layoutName, "夜間")
        XCTAssertEqual(entry.page, 2, "configured page must reach the entry")
    }

    @MainActor
    func testStaleIntentIDFallsBackToFirstLayout() async throws {
        let suiteName = "test.provider.stale.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        defer { d.removePersistentDomain(forName: suiteName) }
        let store = LauncherStore(defaults: d)
        store.seedIfNeeded()
        let first = try XCTUnwrap(store.data.layouts.first)

        var intent = SelectLayoutIntent()
        intent.layout = LauncherLayoutEntity(id: UUID().uuidString, name: "已刪除")
        let entry = await LauncherProvider(defaults: d).resolveEntry(for: intent)
        XCTAssertEqual(entry.layoutName, first.name,
                       "stale intent must fall back to the first layout")
        XCTAssertEqual(entry.page, 1, "absent page configuration defaults to page 1")
    }
}
