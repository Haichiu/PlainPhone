import Foundation

/// Reads the embedded provisioning profile's expiry date.
///
/// WHY THIS IS A PRODUCT FEATURE, NOT PLUMBING: this app is installed with a
/// free Apple personal team, whose provisioning profiles last 7 days. When one
/// expires iOS refuses to launch the app *and* its widget extension, so the
/// Home Screen list simply stops working. Surfacing the date turns a silent,
/// surprising failure into a visible, plannable one.
///
/// Requires no entitlement and no network. Returns nil for builds without an
/// embedded profile (simulator builds, and App Store builds if there ever is
/// one), which callers must treat as "not applicable" rather than "expired".
enum ProvisioningProfile {
    static var expirationDate: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url) else { return nil }
        return expirationDate(fromMobileProvision: raw)
    }

    /// Days remaining, rounded down; nil when no profile is embedded.
    static func daysRemaining(from now: Date = .now) -> Int? {
        guard let expiry = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: expiry).day
    }

    /// Pure and testable: extracts `ExpirationDate` from the CMS-wrapped plist.
    ///
    /// A .mobileprovision file is a CMS signature wrapping a plain XML plist.
    /// Rather than parsing CMS, locate the plist payload by its delimiters —
    /// stable, dependency-free, and safe to fail on unexpected input.
    static func expirationDate(fromMobileProvision data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8))?.lowerBound,
              let end = data.range(of: Data("</plist>".utf8))?.upperBound,
              start < end else { return nil }
        let plist = data.subdata(in: start..<end)
        guard let object = try? PropertyListSerialization.propertyList(
                from: plist, options: [], format: nil),
              let dict = object as? [String: Any] else { return nil }
        return dict["ExpirationDate"] as? Date
    }
}
