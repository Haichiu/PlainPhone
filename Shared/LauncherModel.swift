import Foundation

/// Hard caps so shared storage cannot grow without bound.
enum Limits {
    static let maxLayouts = 4

    /// Widget pages per layout. Items that do not fit on one page spill onto
    /// the next, which the owner reaches by stacking another widget instance
    /// configured to that page (native iOS widget stack, swipe up/down).
    static let maxPages = 3
    /// BASE rows per column at fontScale 1.0 — MEASURED, not estimated:
    /// rendering 20 rows and counting the text bands that actually appear
    /// gives 5 for medium and 14 for large at the pinned render sizes; large
    /// is set to 12 for margin. These are the constants the DERIVED capacity
    /// (`WidgetCapacity.rowsPerColumn(for:settings:)`, SPEC-NEXT §6 L-2)
    /// divides by the effective scale — they are no longer the capacity.
    ///
    /// At accessibility text sizes the same measurement gives 3 and 7; rows
    /// beyond that were clipped. That degradation is now obsolete: row size
    /// is governed by the owner's `LayoutSettings` (fixed-size fonts), not
    /// by the system Dynamic Type setting.
    static let rowsPerPageMedium = 5
    static let rowsPerPageLarge = 12

    /// Medium rows per column at the SHIPPING default line height (1.80),
    /// as opposed to the 1.2 basis the constants above were measured at.
    /// Pinned against `WidgetCapacity` by BehaviorProbeTests — it is a
    /// restatement of the derived model, never an independent number.
    static let rowsPerPageMediumAtDefault = 4

    static let maxNameLength = 24
    static let maxURLLength = 512

    /// Storage hard cap: 3 pages × a medium page at the shipping defaults
    /// (4 rows × 3 columns) = 36. Raised from 15 on 2026-09-07 (Owner): 15
    /// silently assumed ONE column, but multi-column is the normal layout
    /// (W-3), so a large widget at his settings holds 27 on a single page
    /// and the old cap left it visibly half empty.
    ///
    /// The reachability invariant is preserved, not traded away: 36 is
    /// exactly what 3 pages of the SMALLEST shipping family hold at the
    /// default settings. Narrower settings still shrink the derived
    /// capacity below the cap; that gap stays governed by L-3(b) —
    /// announced by `WidgetCapacity.overflowCount`, never silent.
    /// Reachability is no longer guaranteed by the cap alone — with tight
    /// settings (1 column, large font) the derived capacity can hold fewer
    /// than 15 items across 3 pages. SPEC-NEXT §6 L-3 option (b) governs the
    /// difference: items beyond the derived capacity stay stored but are
    /// announced in-app (`WidgetCapacity.overflowCount`), never silently
    /// hidden.
    ///
    /// History: the first design allowed 32 items while systemLarge showed
    /// 16, leaving 16 permanently unreachable behind a "＋k 個項目…"
    /// caption.
    static let maxItemsPerLayout = maxPages * rowsPerPageMediumAtDefault
        * LayoutSettings.allowedColumns.upperBound
}

struct LauncherItem: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var url: String

    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = Self.clampName(name)
        self.url = Self.clampURL(url)
    }

    /// Bounded decoding: oversized persisted input is clamped on the way in,
    /// so limits hold even for data written by an older or foreign writer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = Self.clampName(try c.decodeIfPresent(String.self, forKey: .name) ?? "")
        url = Self.clampURL(try c.decodeIfPresent(String.self, forKey: .url) ?? "")
    }

    enum CodingKeys: String, CodingKey { case id, name, url }

    static func clampName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.maxNameLength))
    }

    static func clampURL(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Limits.maxURLLength))
    }
}

struct LauncherLayout: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var items: [LauncherItem]

    init(id: UUID = UUID(), name: String, items: [LauncherItem] = []) {
        self.id = id
        self.name = LauncherItem.clampName(name)
        self.items = Array(items.prefix(Limits.maxItemsPerLayout))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = LauncherItem.clampName(try c.decodeIfPresent(String.self, forKey: .name) ?? "")
        let decodedItems = try c.decodeIfPresent([LauncherItem].self, forKey: .items) ?? []
        items = Array(decodedItems.prefix(Limits.maxItemsPerLayout))
    }

    enum CodingKeys: String, CodingKey { case id, name, items }
}

/// Widget configuration is the ONLY layout selector. There is deliberately no
/// global "selected layout": two competing selection mechanisms would force the
/// owner to remember which one is in effect, which is the recall cost this
/// product exists to remove. Legacy blobs carrying `selectedLayoutID` decode
/// cleanly — the key is simply ignored.
struct LauncherData: Codable, Equatable {
    var layouts: [LauncherLayout]
    /// Owner-adjustable widget layout parameters (SPEC-NEXT §6 L-1). Part of
    /// the shared payload so one dataset drives app and widget (S-1).
    var settings: LayoutSettings

    init(layouts: [LauncherLayout] = [], settings: LayoutSettings = .default) {
        self.layouts = Array(layouts.prefix(Limits.maxLayouts))
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([LauncherLayout].self, forKey: .layouts) ?? []
        layouts = Array(decoded.prefix(Limits.maxLayouts))
        // K-14: blobs written before settings existed (or truncated writes)
        // decode to the defaults instead of failing the payload.
        settings = try c.decodeIfPresent(LayoutSettings.self, forKey: .settings)
            ?? LayoutSettings.default
    }

    enum CodingKeys: String, CodingKey { case layouts, settings }
}

/// Strongly-typed navigation routes. A single navigationDestination(for:
/// AppRoute.self) is registered in HomeView; nested screens push values
/// without re-declaring destinations (duplicate declarations for one type in
/// one NavigationStack are invalid configuration).
enum AppRoute: Hashable {
    case layout(UUID)
    case item(layoutID: UUID, itemID: UUID)
    /// In-app layout-settings screen (W-2): columns, font scale, line
    /// height, letter spacing. Writes through `LauncherStore.updateSettings`,
    /// which triggers the widget timeline reload (W-5).
    case layoutSettings
}

enum ShortcutsURL {
    /// Builds a percent-encoded `shortcuts://run-shortcut?name=...` URL.
    /// iOS cannot enumerate or import the user's shortcuts; the name must
    /// match a shortcut the user created manually.
    /// M-1 (SPEC-NEXT §4): the seeded rows call this with `input: nil` — one
    /// row = one app name = one same-named shortcut, no `input`, no shared
    /// "Open" shortcut (T0 closed: sixteen shortcuts). `input` stays in the
    /// API for free-form rows that feed a shortcut taking input; the seeds
    /// simply don't use it.
    ///
    /// URLComponents percent-encodes the values, so non-ASCII names such as
    /// CJK app names are safe here.
    static func runShortcut(named shortcutName: String, input: String? = nil) -> String {
        guard let base = URL(string: "shortcuts://run-shortcut"),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return "" }
        comps.queryItems = [URLQueryItem(name: "name", value: shortcutName)]
            + (input.map { [URLQueryItem(name: "input", value: $0)] } ?? [])
        return comps.string ?? ""
    }

    static func isShortcutURL(_ urlString: String) -> Bool {
        urlString.lowercased().hasPrefix("shortcuts://")
    }

    /// Recovers the shortcut name from a previously generated run-shortcut URL.
    static func shortcutName(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              comps.scheme?.lowercased() == "shortcuts",
              comps.host?.lowercased() == "run-shortcut" else { return nil }
        return comps.queryItems?.first(where: { $0.name == "name" })?.value
    }
}

/// Path B relay URLs (SPEC-NEXT §4 M-3). A widget row Links to the app's
/// OWN scheme — F-5 guarantees the URL is handed to the containing app —
/// and the app opens the target itself, where custom schemes are fully
/// supported. Rows never Link to a foreign-scheme URL directly: F-6 leaves
/// iOS routing for those undocumented, and staying inside documented
/// contracts is the entire value of path B.
enum PlainPhoneURL {
    /// Encodes a row's stored URL as `plainphone://open?target=<encoded>`,
    /// percent-encoded through URLComponents queryItems like
    /// `ShortcutsURL.runShortcut`. Empty or unparseable URLs yield nil, so
    /// the row falls back to a static label.
    static func open(itemURL: String) -> URL? {
        guard !itemURL.isEmpty,
              URL(string: itemURL) != nil,
              let base = URL(string: "plainphone://open"),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [URLQueryItem(name: "target", value: itemURL)]
        return comps.url
    }

    /// The only schemes the app will open on the user's behalf. resolve is
    /// the open-redirect guard: anything outside it is refused, so the relay
    /// can never be used to hand the app an arbitrary handler.
    private static let allowedSchemes: Set<String> = Set(
        ["shortcuts", "https", "http", "mailto"] +
        DefaultLayouts.nativeURLs.values.compactMap { URL(string: $0)?.scheme }
    )

    /// Resolves a received `plainphone://open?target=…` relay URL back to
    /// its target. Returns nil unless the URL is a plainphone relay (scheme
    /// check is case-insensitive) carrying a non-empty target whose scheme
    /// is whitelisted (also case-insensitive).
    static func resolve(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "plainphone",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = comps.queryItems?.first(where: { $0.name == "target" })?.value,
              !target.isEmpty,
              let targetURL = URL(string: target),
              let scheme = targetURL.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else { return nil }
        return targetURL
    }
}
