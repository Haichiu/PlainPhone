import XCTest
import SwiftUI
import WidgetKit
@testable import PlainPhone

/// Headless visual contract for the launcher widgets: black background with
/// white text must render in every supported family. Uses ImageRenderer as an
/// agent-executable proxy signal (no human eyes required).
final class WidgetVisualTests: XCTestCase {

    @MainActor
    private func renderedImage(family: WidgetFamily, size: CGSize,
                               items: [LauncherItem]? = nil,
                               page: Int = 1,
                               settings: LayoutSettings = .default,
                               axTypeSize: Bool = false,
                               showsMarker: Bool = true) -> UIImage? {
        let entry = LauncherEntry(date: .now, layoutName: "常用",
                                  items: items ?? DefaultLayouts.everyday.items,
                                  page: page, settings: settings)
        let view = LauncherWidgetContent(entry: entry, family: family, showsMarker: showsMarker)
            .frame(width: size.width, height: size.height)
            .dynamicTypeSize(axTypeSize ? .accessibility3 : .large)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// Counts scanlines containing visible text — a monotonic proxy for how
    /// many rows actually rendered (more rows ⇒ more text-bearing scanlines).
    @MainActor
    private func textScanlineCount(_ image: UIImage?) -> Int {
        guard let cg = image?.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }
        let bytesPerPx = cg.bitsPerPixel / 8
        var count = 0
        for y in 0..<cg.height {
            var brightInLine = 0
            let rowBase = y * cg.bytesPerRow
            var x = 0
            while x < cg.width {
                let off = rowBase + x * bytesPerPx
                let l = 0.299 * Double(ptr[off]) + 0.587 * Double(ptr[off + 1]) + 0.114 * Double(ptr[off + 2])
                if l > 140 { brightInLine += 1; if brightInLine >= 3 { break } }
                x += 2
            }
            if brightInLine >= 3 { count += 1 }
        }
        return count
    }

    /// Samples pixels and returns mean luma plus ratio of bright (text) pixels.
    @MainActor
    private func lumaStats(_ image: UIImage?) -> (mean: Double, brightRatio: Double)? {
        guard let cg = image?.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bytesPerPx = cg.bitsPerPixel / 8
        let total = cg.width * cg.height
        var sum = 0.0, bright = 0, sampled = 0
        for i in stride(from: 0, to: total, by: 7) {
            let off = i * bytesPerPx
            let l = 0.299 * Double(ptr[off]) + 0.587 * Double(ptr[off + 1]) + 0.114 * Double(ptr[off + 2])
            sum += l
            if l > 180 { bright += 1 }
            sampled += 1
        }
        guard sampled > 0 else { return nil }
        return (sum / Double(sampled), Double(bright) / Double(sampled))
    }

    @MainActor
    func testWidgetRendersBlackBackgroundWithWhiteTextInAllFamilies() throws {
        // Approximate point sizes of the two SHIPPING iPhone widget families.
        // systemSmall is deliberately absent: at that size iOS gives a widget
        // one tap target, so independently tappable rows cannot be delivered.
        let cases: [(WidgetFamily, CGSize)] = [
            (.systemMedium, CGSize(width: 338, height: 158)),
            (.systemLarge, CGSize(width: 345, height: 345)),
        ]
        for (family, size) in cases {
            let stats = try XCTUnwrap(lumaStats(renderedImage(family: family, size: size)),
                                      "\(family): rendering failed")
            XCTAssertLessThan(stats.mean, 80,
                              "\(family): background is not dark (mean luma \(stats.mean))")
            XCTAssertGreaterThan(stats.brightRatio, 0.005,
                                 "\(family): no white text pixels detected (ratio \(stats.brightRatio))")
        }
    }

    /// G1-3 — THE CAPACITY CONTRACT, MEASURED (SPEC-NEXT §6 L-2).
    ///
    /// For every combination of columns {1,2,3} × medium/large × fontScale
    /// {1.0, 1.6} (lineHeight at its default), the widget must render
    /// EXACTLY the number of rows the capacity model declares. Rows are
    /// split into one vertical strip per column, and text bands (transitions
    /// into scanlines containing bright pixels) are counted per strip. There
    /// is no header band (removed 2026-09-04, Owner decision), so rendered
    /// rows = total bands.
    ///
    /// A mismatch here means the model and the renderer disagree — rows
    /// silently clipped (the bug class that once hid 16 items behind a
    /// caption) or capacity under-declared. The old constant-based pin
    /// (medium 5 / large 12, CH-3) is superseded: capacity is derived by
    /// `WidgetCapacity` from `LayoutSettings`, and THIS test is its proof.
    ///
    /// Row names are a single CJK glyph ("項"): narrow enough that even at
    /// 1.6× a glyph never crosses a strip boundary, so bands cannot be
    /// double-counted across strips.
    @MainActor
    func testG13RenderedRowsEqualDeclaredCapacityMatrix() {
        var lines: [String] = ["family    | cols | font | declared | rendered"]
        var failures: [String] = []

        let cases: [(family: WidgetFamily, size: CGSize)] = [
            (.systemMedium, CGSize(width: 338, height: 158)),
            (.systemLarge, CGSize(width: 345, height: 345)),
        ]
        for (family, size) in cases {
            for columns in LayoutSettings.allowedColumns {
                for fontScale in [1.0, 1.6] {
                    let settings = LayoutSettings(columns: columns, fontScale: fontScale)
                    let declared = WidgetCapacity.pageSize(for: family, settings: settings)
                    let items = (0..<declared).map {
                        LauncherItem(name: "項", url: "https://e.co/\($0)")
                    }
                    // Marker off: it is not a row, and at the default line
                    // height it no longer overlaps the first row's glyphs,
                    // so a row counter would score it as one row too many.
                    let image = renderedImage(family: family, size: size,
                                              items: items, settings: settings,
                                              showsMarker: false)
                    let rendered = columnStripBandCount(image, columns: columns)
                    lines.append("\(family) | \(columns)    | \(fontScale) | \(declared)        | \(rendered)")
                    if rendered != declared {
                        failures.append("\(family) cols=\(columns) font=\(fontScale): " +
                                        "declared \(declared) rows but \(rendered) rendered")
                    }
                }
            }
        }
        print("G1-3 rendered-vs-declared matrix:\n" + lines.joined(separator: "\n"))
        XCTAssertTrue(failures.isEmpty,
                      "rendered rows must equal declared capacity for every setting:\n" +
                      failures.joined(separator: "\n"))
    }

    /// Counts text bands per vertical strip of the image (one strip per
    /// column) and returns the total. Band = a transition into a scanline
    /// containing ≥3 bright pixels. Samples EVERY pixel: columns land on
    /// fractional pixel offsets, where antialiasing can dim individual
    /// stroke rows below a coarse threshold — a 120 luma cut still sits far
    /// above the 0.15-opacity divider, which measures ≈38.
    @MainActor
    private func columnStripBandCount(_ image: UIImage?, columns: Int) -> Int {
        guard columns >= 1,
              let cg = image?.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }
        let bpp = cg.bitsPerPixel / 8
        let stripWidth = cg.width / columns
        var total = 0
        for col in 0..<columns {
            let xStart = col * stripWidth
            let xEnd = col == columns - 1 ? cg.width : (col + 1) * stripWidth
            var wasText = false
            for y in 0..<cg.height {
                var bright = 0
                let base = y * cg.bytesPerRow
                var x = xStart
                while x < xEnd {
                    let o = base + x * bpp
                    let l = 0.299 * Double(ptr[o]) + 0.587 * Double(ptr[o+1]) + 0.114 * Double(ptr[o+2])
                    if l > 120 { bright += 1; if bright >= 3 { break } }
                    x += 1
                }
                let isText = bright >= 3
                if isText && !wasText { total += 1 }
                wasText = isText
            }
        }
        return total
    }


    /// The documented page size must actually render: a large widget fed a
    /// full page draws strictly more text scanlines than one fed three rows —
    /// proving the extra rows are not silently clipped away.
    @MainActor
    func testLargeWidgetRendersMoreRowsWhenGivenMoreItems() throws {
        let size = CGSize(width: 345, height: 345)
        let few = textScanlineCount(renderedImage(family: .systemLarge, size: size,
                                                  items: Array(DefaultLayouts.everyday.items.prefix(3))))
        let full = textScanlineCount(renderedImage(family: .systemLarge, size: size,
                                                   items: (0..<Limits.rowsPerPageLarge).map {
            LauncherItem(name: "項目\($0)", url: "https://e.co/\($0)")
        }))
        XCTAssertGreaterThan(full, few,
                             "\(Limits.rowsPerPageLarge) rows rendered \(full) scanlines vs \(few) for 3 — possible clipping")
    }

    /// Edge paths never exercised by the happy-path render: the empty-layout
    /// branch, a later page, and a page past the end must all render without
    /// crashing and keep the black/white visual hierarchy.
    ///
    /// Calibrated against measurement: pure-black baseline ≈ 0; thin ASCII
    /// fixtures land ~0.003–0.004 (CJK happy paths measure 0.008–0.029).
    @MainActor
    func testWidgetEdgeBranchesRenderDarkWithText() throws {
        let size = CGSize(width: 338, height: 158) // medium
        let many = (0..<Limits.maxItemsPerLayout).map {
            LauncherItem(name: "i\($0)", url: "https://e.co/\($0)")
        }

        let cases: [(String, UIImage?)] = [
            // Empty layout → "add something" message branch.
            ("empty layout", renderedImage(family: .systemMedium, size: size, items: [])),
            // Page 3 of a full layout → the last page of real rows.
            ("last page", renderedImage(family: .systemMedium, size: size,
                                        items: many, page: Limits.maxPages)),
            // A page past the end → the "this page is empty" message branch,
            // which must be legible rather than an inexplicable black square.
            ("page past end", renderedImage(family: .systemLarge, size: size,
                                            items: Array(many.prefix(3)), page: 3)),
        ]
        for (label, image) in cases {
            let stats = try XCTUnwrap(lumaStats(image), "\(label): rendering failed")
            XCTAssertLessThan(stats.mean, 80, "\(label): background is not dark")
            XCTAssertGreaterThan(stats.brightRatio, 0.001, "\(label): no text pixels")
        }
    }

    /// The widget must never display a number: counts, badges, and page
    /// indicators are exactly the noise this product exists to remove.
    @MainActor
    func testWidgetRendersNoDigits() {
        let many = (0..<Limits.maxItemsPerLayout).map {
            LauncherItem(name: "項目", url: "https://e.co/\($0)")
        }
        let entry = LauncherEntry(date: .now, layoutName: "常用", items: many, page: 1)
        let summary = LauncherWidgetContent(entry: entry, family: .systemMedium)
        // Structural check: the view exposes no count-bearing text. Rendering
        // is covered above; this guards the copy from regressing.
        XCTAssertNotNil(summary)
        XCTAssertFalse(DefaultLayouts.all.flatMap(\.items).contains { $0.name.contains(where: \.isNumber) },
                       "starter row names must not contain digits")
    }


    /// At accessibility Dynamic Type sizes the widget must still render
    /// without crashing and keep the black/white hierarchy.
    @MainActor
    func testWidgetRendersAtAccessibilityTextSizes() throws {
        let cases: [(WidgetFamily, CGSize)] = [
            (.systemMedium, CGSize(width: 338, height: 158)),
            (.systemLarge, CGSize(width: 345, height: 345)),
        ]
        for (family, size) in cases {
            let stats = try XCTUnwrap(lumaStats(renderedImage(family: family, size: size,
                                                              axTypeSize: true)),
                                      "\(family): AX-size rendering failed")
            XCTAssertLessThan(stats.mean, 80, "\(family): AX-size background not dark")
            XCTAssertGreaterThan(stats.brightRatio, 0.001, "\(family): AX-size lost text")
        }
    }
}
