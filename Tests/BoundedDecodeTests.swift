import XCTest
@testable import PlainPhone

/// Oversized persisted input must be clamped during DECODING, and the
/// selectedLayoutID must be repaired against the truncated list.
final class BoundedDecodeTests: XCTestCase {

    /// Builds raw JSON that violates every limit, as a foreign/legacy writer
    /// might have stored it.
    private func oversizedBlob(layoutCount: Int,
                               itemsPerLayout: Int,
                               nameLength: Int,
                               urlLength: Int,
                               selectedIndexOfInterest: Int?) throws -> Data {
        var layoutDicts: [[String: Any]] = []
        var interestingID: String?
        for i in 0..<layoutCount {
            let id = UUID().uuidString
            if i == selectedIndexOfInterest { interestingID = id }
            let items: [[String: Any]] = (0..<itemsPerLayout).map { j in
                ["id": UUID().uuidString,
                 "name": String(repeating: "名", count: nameLength) + "\(j)",
                 "url": "https://example.com/" + String(repeating: "u", count: urlLength) + "/\(j)"]
            }
            layoutDicts.append(["id": id,
                                "name": String(repeating: "版", count: nameLength),
                                "items": items])
        }
        var root: [String: Any] = ["layouts": layoutDicts]
        if let interestingID { root["selectedLayoutID"] = interestingID }
        return try JSONSerialization.data(withJSONObject: root)
    }

    func testOversizedBlobIsClampedDuringDecode() throws {
        let blob = try oversizedBlob(layoutCount: 20, itemsPerLayout: 40,
                                     nameLength: 60, urlLength: 600,
                                     selectedIndexOfInterest: nil)
        let data = try JSONDecoder().decode(LauncherData.self, from: blob)

        XCTAssertEqual(data.layouts.count, Limits.maxLayouts,
                       "20 layouts must truncate to \(Limits.maxLayouts)")
        for layout in data.layouts {
            XCTAssertLessThanOrEqual(layout.items.count, Limits.maxItemsPerLayout)
            XCTAssertLessThanOrEqual(layout.name.count, Limits.maxNameLength)
            for item in layout.items {
                XCTAssertLessThanOrEqual(item.name.count, Limits.maxNameLength)
                XCTAssertLessThanOrEqual(item.url.count, Limits.maxURLLength)
            }
        }
    }

    /// BACK COMPATIBILITY: blobs written before `selectedLayoutID` was removed
    /// must still decode. The key is now unknown to the model and must be
    /// ignored silently rather than failing the whole decode — otherwise an
    /// upgrade would present the corruption banner and lock the user out of
    /// their own data.
    func testLegacyBlobWithSelectedLayoutIDStillDecodes() throws {
        let blob = try oversizedBlob(layoutCount: 3, itemsPerLayout: 2,
                                     nameLength: 5, urlLength: 30,
                                     selectedIndexOfInterest: 2)
        let data = try JSONDecoder().decode(LauncherData.self, from: blob)

        XCTAssertEqual(data.layouts.count, 3, "legacy blob must survive decoding intact")
        XCTAssertEqual(data.layouts.first?.items.count, 2)

        // Re-encoding drops the obsolete key without disturbing the layouts.
        let again = try JSONDecoder().decode(LauncherData.self,
                                             from: try JSONEncoder().encode(data))
        XCTAssertEqual(again.layouts.map(\.name), data.layouts.map(\.name))
    }

    /// A legacy blob planted in real storage must not trip the corruption path.
    func testLegacyBlobDoesNotTriggerCorruptionBanner() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let blob = try oversizedBlob(layoutCount: 2, itemsPerLayout: 1,
                                     nameLength: 4, urlLength: 20,
                                     selectedIndexOfInterest: 1)
        suite.set(blob, forKey: LauncherStore.storageKey)

        let store = LauncherStore(defaults: suite)
        XCTAssertFalse(store.hadLoadError, "legacy data must not be reported as corrupt")
        XCTAssertEqual(store.data.layouts.count, 2)
    }

    func testStoreAppliesBoundedDecodingToPersistedBlob() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }

        let blob = try oversizedBlob(layoutCount: 16, itemsPerLayout: 50,
                                     nameLength: 80, urlLength: 700,
                                     selectedIndexOfInterest: nil)
        suite.set(blob, forKey: LauncherStore.storageKey)

        let store = LauncherStore(defaults: suite)
        XCTAssertEqual(store.data.layouts.count, Limits.maxLayouts)
        XCTAssertTrue(store.data.layouts.allSatisfy { $0.items.count <= Limits.maxItemsPerLayout })
    }
}
