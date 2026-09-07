import XCTest
@testable import PlainPhone

final class LauncherModelTests: XCTestCase {

    func testNameClampedToFortyCharacters() {
        let long = String(repeating: "字", count: 50)
        let item = LauncherItem(name: long, url: "https://example.com")
        XCTAssertEqual(item.name.count, Limits.maxNameLength)
    }

    func testURLClampedTo512Characters() {
        let long = "https://example.com/?" + String(repeating: "a", count: 600)
        let item = LauncherItem(name: "x", url: long)
        XCTAssertLessThanOrEqual(item.url.count, Limits.maxURLLength)
    }

    func testNameAndURLTrimmed() {
        let item = LauncherItem(name: "  電話  ", url: " tel: ")
        XCTAssertEqual(item.name, "電話")
        XCTAssertEqual(item.url, "tel:")
    }

    func testLayoutCapsItemsAtLimit() {
        let items = (0..<40).map { LauncherItem(name: "i\($0)", url: "https://e.co/\($0)") }
        let layout = LauncherLayout(name: "上限", items: items)
        XCTAssertEqual(layout.items.count, Limits.maxItemsPerLayout)
    }

    func testDataCapsLayoutsAtLimit() {
        let layouts = (0..<20).map { LauncherLayout(name: "L\($0)") }
        let data = LauncherData(layouts: layouts)
        XCTAssertEqual(data.layouts.count, Limits.maxLayouts)
    }

    // MARK: Shortcuts URL encoding

    func testShortcutURLEncoding() {
        let url = ShortcutsURL.runShortcut(named: "番茄鐘")
        XCTAssertTrue(url.hasPrefix("shortcuts://run-shortcut?name="), url)
        XCTAssertEqual(ShortcutsURL.shortcutName(from: url), "番茄鐘")
    }

    func testShortcutURLEncodesSpacesAndSpecialCharacters() {
        let name = "Focus Timer 25 min & tea"
        let url = ShortcutsURL.runShortcut(named: name)
        XCTAssertFalse(url.contains(" "), "spaces must be percent-encoded: \(url)")
        XCTAssertEqual(ShortcutsURL.shortcutName(from: url), name)
    }

    func testIsShortcutURL() {
        XCTAssertTrue(ShortcutsURL.isShortcutURL(ShortcutsURL.runShortcut(named: "x")))
        XCTAssertFalse(ShortcutsURL.isShortcutURL("https://example.com"))
    }

    // MARK: Path B relay URLs (SPEC-NEXT §4 M-3)

    func testPlainPhoneURLOpenEncodesShortcutRow() {
        let item = ShortcutsURL.runShortcut(named: "番茄鐘")
        let relay = PlainPhoneURL.open(itemURL: item)
        XCTAssertEqual(relay?.scheme, "plainphone")
        XCTAssertEqual(relay?.host, "open")
        XCTAssertEqual(PlainPhoneURL.resolve(relay!), URL(string: item))
    }

    func testPlainPhoneURLOpenEncodesHTTPSRow() {
        let item = "https://example.com/path?x=1"
        let relay = PlainPhoneURL.open(itemURL: item)
        XCTAssertNotNil(relay)
        XCTAssertEqual(PlainPhoneURL.resolve(relay!), URL(string: item))
    }

    func testPlainPhoneURLOpenRejectsEmptyString() {
        XCTAssertNil(PlainPhoneURL.open(itemURL: ""))
    }

    func testPlainPhoneURLOpenRejectsUnparseableURL() {
        XCTAssertNil(PlainPhoneURL.open(itemURL: "ht tp://example.com"))
    }

    func testPlainPhoneURLResolveAcceptsAllWhitelistedSchemes() {
        for target in DefaultLayouts.nativeURLs.values {
            let relay = PlainPhoneURL.open(itemURL: target)
            XCTAssertEqual(relay.flatMap(PlainPhoneURL.resolve), URL(string: target))
        }
        let targets = ["shortcuts://run-shortcut?name=Beeper",
                       "https://example.com",
                       "http://example.com",
                       "mailto:foo@example.com"]
        for target in targets {
            let relay = PlainPhoneURL.open(itemURL: target)
            XCTAssertNotNil(relay, target)
            XCTAssertEqual(PlainPhoneURL.resolve(relay!), URL(string: target), target)
        }
    }

    func testPlainPhoneURLResolveIsCaseInsensitive() {
        let relay = PlainPhoneURL.open(itemURL: "MAILTO:Foo@Bar.com")
        XCTAssertNotNil(relay)
        XCTAssertEqual(PlainPhoneURL.resolve(relay!), URL(string: "MAILTO:Foo@Bar.com"))
        let upperRelay = URL(string: "PLAINPHONE://open?target=shortcuts://run-shortcut?name=x")
        XCTAssertNotNil(PlainPhoneURL.resolve(upperRelay!))
        // Uppercase target scheme: still on the whitelist.
        let upperTarget = PlainPhoneURL.open(itemURL: "SHORTCUTS://run-shortcut?name=Beeper")
        XCTAssertEqual(PlainPhoneURL.resolve(upperTarget!), URL(string: "SHORTCUTS://run-shortcut?name=Beeper"))
    }

    func testPlainPhoneURLResolveRejectsUnknownTargetScheme() {
        // open() encodes any parseable row; the whitelist lives in resolve.
        let relay = PlainPhoneURL.open(itemURL: "tel:+886912345678")
        XCTAssertNotNil(relay)
        XCTAssertNil(PlainPhoneURL.resolve(relay!))
    }

    func testPlainPhoneURLResolveRejectsMissingTarget() {
        XCTAssertNil(PlainPhoneURL.resolve(URL(string: "plainphone://open")!))
        XCTAssertNil(PlainPhoneURL.resolve(URL(string: "plainphone://open?other=x")!))
        XCTAssertNil(PlainPhoneURL.resolve(URL(string: "plainphone://open?target=")!))
    }

    func testPlainPhoneURLResolveRejectsFileAndJavaScriptSchemes() {
        // Non-whitelisted schemes are refused even when the relay is crafted
        // by hand, bypassing open(): file and javascript must never be
        // opened on the user's behalf.
        XCTAssertNil(PlainPhoneURL.resolve(URL(string: "plainphone://open?target=file:///etc/passwd")!))
        XCTAssertNil(PlainPhoneURL.resolve(URL(string: "plainphone://open?target=javascript:alert(1)")!))
        // …and equally when the row came through open() itself.
        if let fileRelay = PlainPhoneURL.open(itemURL: "file:///etc/passwd") {
            XCTAssertNil(PlainPhoneURL.resolve(fileRelay))
        }
        if let jsRelay = PlainPhoneURL.open(itemURL: "javascript:alert(1)") {
            XCTAssertNil(PlainPhoneURL.resolve(jsRelay))
        }
    }

    func testPlainPhoneURLResolveRejectsForeignRelayURLs() {
        // Open-redirect guard: resolve only ever answers plainphone relays.
        XCTAssertNil(PlainPhoneURL.resolve(URL(string: "https://attacker.example/?target=https://example.com")!))
    }
}
