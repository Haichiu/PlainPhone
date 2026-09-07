import Foundation

/// Owner-adjustable widget layout parameters (SPEC-NEXT §6 L-1; W-2/W-3).
///
/// These live inside the shared `LauncherData` payload: the app edits them
/// through `LauncherStore.updateSettings(_:)`, the widget receives them via
/// `LauncherEntry`, and one dataset therefore drives both sides (S-1).
///
/// Ranges were fixed by owner decision: columns 1...3 with 3 as the default
/// (W-3: multi-column is the normal layout, not the exception), and the
/// typography ranges bracket the proportions of
/// `docs/product/prototype-core-flow.html` (17pt text at a 1.2 line ratio).
///
/// K-14: decoding is total. A blob missing any key — an old payload written
/// before settings existed, or a partial write — decodes to the default for
/// every missing field. Out-of-range values are clamped on the way in, the
/// same bounded-decode discipline `LauncherItem` applies to names and URLs.
struct LayoutSettings: Codable, Equatable {
    /// Columns per page (1...3, default 3).
    var columns: Int
    /// Multiplier on the base row font size (0.8...1.6, default 1.0).
    var fontScale: Double
    /// Line-height ratio: row pitch = fontSize × lineHeight (1.0...1.8, default 1.8).
    var lineHeight: Double
    /// Letter spacing in points (−0.5...3, default 2.0).
    var letterSpacing: Double
    /// Whether the group marker (dot / square / triangle / diamond) is drawn
    /// in the widget's top-right corner. Default OFF (Owner, 2026-09-07):
    /// he knows his groups by their contents and does not want the mark
    /// present all the time — only occasionally, to confirm which group a
    /// widget is showing. A permanent mark for an occasional question is
    /// exactly the kind of standing noise this product removes.
    var showsGroupMarker: Bool

    /// The shipping defaults. Transcribed from the owner's own device on
    /// 2026-09-07 (版面設定 screenshot): three columns, 1.00× font, 1.80 line
    /// height, 2.0pt letter spacing. These are the settings he reported
    /// preferring in daily use, so they are the values a fresh install gets.
    static let `default` = LayoutSettings()

    /// The line height the measured row pitches in `WidgetCapacity` were
    /// taken at. It is a FIXED basis, deliberately not `default.lineHeight`:
    /// the padding term must keep describing the same measurement even when
    /// the shipping default moves (it moved to 1.80 on 2026-09-07).
    static let measuredBasisLineHeight: Double = 1.2

    /// Slider/segmented ranges, shared by the editor UI and the clamps below
    /// so the UI can never offer a value the model would silently rewrite.
    static let allowedColumns = 1...3
    static let allowedFontScale = 0.8...1.6
    static let allowedLineHeight = 1.0...1.8
    static let allowedLetterSpacing = -0.5...3.0

    init(columns: Int = 3, fontScale: Double = 1.0,
         lineHeight: Double = 1.8, letterSpacing: Double = 2.0,
         showsGroupMarker: Bool = false) {
        self.columns = Self.clamp(columns, into: Self.allowedColumns)
        self.fontScale = Self.clamp(fontScale, into: Self.allowedFontScale)
        self.lineHeight = Self.clamp(lineHeight, into: Self.allowedLineHeight)
        self.letterSpacing = Self.clamp(letterSpacing, into: Self.allowedLetterSpacing)
        self.showsGroupMarker = showsGroupMarker
    }

    /// K-14: every key is optional; missing fields fall back to the defaults
    /// instead of failing the whole payload decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            columns: try c.decodeIfPresent(Int.self, forKey: .columns)
                ?? LayoutSettings.default.columns,
            fontScale: try c.decodeIfPresent(Double.self, forKey: .fontScale)
                ?? LayoutSettings.default.fontScale,
            lineHeight: try c.decodeIfPresent(Double.self, forKey: .lineHeight)
                ?? LayoutSettings.default.lineHeight,
            letterSpacing: try c.decodeIfPresent(Double.self, forKey: .letterSpacing)
                ?? LayoutSettings.default.letterSpacing,
            showsGroupMarker: try c.decodeIfPresent(Bool.self, forKey: .showsGroupMarker)
                ?? LayoutSettings.default.showsGroupMarker)
    }

    enum CodingKeys: String, CodingKey {
        case columns, fontScale, lineHeight, letterSpacing, showsGroupMarker
    }

    private static func clamp<T: Comparable>(_ value: T, into range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
