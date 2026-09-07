import XCTest
@testable import PlainPhone

/// The provisioning-profile expiry reader is a product feature, not plumbing:
/// a free personal team's profile lasts 7 days, and on expiry iOS refuses to
/// launch the app AND its widget extension — the Home Screen list silently
/// dies. These tests pin the parser's contract, including its failure modes,
/// because a wrong answer here is worse than no answer.
final class ProvisioningProfileTests: XCTestCase {

    /// A .mobileprovision is a CMS signature wrapping a plain XML plist.
    /// This fixture reproduces that shape: binary noise, the plist, more noise.
    private func fixture(expiry: String) -> Data {
        var data = Data([0x30, 0x82, 0x0A, 0xBC, 0x06, 0x09, 0x2A])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>Name</key><string>iOS Team Provisioning Profile</string>
        <key>ExpirationDate</key><date>\(expiry)</date>
        </dict></plist>
        """.utf8))
        data.append(Data([0x00, 0xFF, 0x31, 0x82]))
        return data
    }

    func testExtractsExpirationDateFromCMSWrappedPlist() throws {
        let parsed = try XCTUnwrap(
            ProvisioningProfile.expirationDate(fromMobileProvision: fixture(expiry: "2026-09-04T12:00:00Z")))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z"))
        XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    /// Free personal-team profiles are issued for 7 days. Round-tripping that
    /// span guards the arithmetic the About screen shows the owner.
    func testSevenDayProfileReportsSevenDays() throws {
        let issued = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-28T09:00:00Z"))
        let expiry = issued.addingTimeInterval(7 * 24 * 3600)
        let parsed = try XCTUnwrap(ProvisioningProfile.expirationDate(
            fromMobileProvision: fixture(expiry: ISO8601DateFormatter().string(from: expiry))))
        let days = try XCTUnwrap(Calendar.current.dateComponents([.day], from: issued, to: parsed).day)
        XCTAssertEqual(days, 7)
    }

    /// MUST fail closed. Returning a bogus date would tell the owner the app
    /// is fine on the day it stops launching.
    func testMalformedInputReturnsNilRatherThanGuessing() {
        XCTAssertNil(ProvisioningProfile.expirationDate(fromMobileProvision: Data()))
        XCTAssertNil(ProvisioningProfile.expirationDate(fromMobileProvision: Data("not a profile".utf8)))
        // Opening delimiter but no closing one.
        XCTAssertNil(ProvisioningProfile.expirationDate(
            fromMobileProvision: Data("<?xml version=\"1.0\"?><dict>".utf8)))
        // Well-formed plist that simply has no ExpirationDate key.
        XCTAssertNil(ProvisioningProfile.expirationDate(fromMobileProvision: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Name</key><string>x</string></dict></plist>
        """.utf8)))
    }

    /// Simulator builds embed no profile; "not applicable" must not be
    /// rendered as "expired".
    func testNoEmbeddedProfileIsNotApplicableNotExpired() {
        if ProvisioningProfile.expirationDate == nil {
            XCTAssertNil(ProvisioningProfile.daysRemaining(),
                         "absent profile must yield nil, never a negative day count")
        }
    }
}
