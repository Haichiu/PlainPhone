import Foundation

/// The owner's actual daily set, transcribed from his Home Screen on 2026-08-28.
///
/// The previous defaults (日常 / 專注 / 閱讀) were reverse-engineered from a
/// screenshot of somebody else's Home Screen, which seeded someone else's
/// habits on first launch. These are his.
///
/// SHAPE: 12 + 5 is not arbitrary. A `systemLarge` (12 rows) above a
/// `systemMedium` (5 rows) exactly fills one iPhone page, so the whole daily
/// set is visible without a swipe.
///
/// MECHANISM (SPEC-NEXT §4, M-1): one row = one app name = one same-named
/// shortcut. Every seeded row carries `shortcuts://run-shortcut?name=<RowName>`
/// with no `input` parameter and no shared "Open" shortcut. Routing through
/// Shortcuts is the only documented URL form that reaches an arbitrary
/// third-party app, because Shortcuts can enumerate installed apps and this
/// app cannot (F-8). What a tap looks like on screen — bounce, flash, or
/// neither — is what Gate 0 records on the device; nothing here claims it.
///
/// OWNER SETUP COST, STATED HONESTLY: iOS gives apps no way to create
/// shortcuts, so the owner must build all sixteen same-named shortcuts by
/// hand in the Shortcuts app — once, before any row will launch (README.md
/// documents the steps).
///
/// HISTORY: the single-"Open"-shortcut-with-input experiment is closed.
/// SPEC-NEXT §8 closes T0 as "sixteen shortcuts" and demotes T1 (W-6): speed
/// is no longer measured; the only device question is "does the row open the
/// app".
enum DefaultLayouts {
    // Owner revision 2026-09-06: native apps use schemes, not shortcuts.
    // Private schemes remain subject to device verification after iOS updates.
    static let nativeURLs: [String: String] = [
        "Notes": "mobilenotes://",
        "Reminders": "x-apple-reminder://",
        "Calendar": "calshow://",
        "Photos": "photos-redirect://",
        "Clock": "clock-alarm://",
        "TV": "videos://",
        "Books": "ibooks://",
        "Podcasts": "podcasts://",
    ]

    /// Upgrade only unchanged same-name native shortcut rows. Preserve IDs,
    /// order, custom URLs and settings; never reset the user's stored lists.
    static func upgradeNativeRoutes(in data: inout LauncherData) -> Bool {
        var changed = false
        for layout in data.layouts.indices {
            for item in data.layouts[layout].items.indices {
                let row = data.layouts[layout].items[item]
                if let native = nativeURLs[row.name],
                   row.url == ShortcutsURL.runShortcut(named: row.name) {
                    data.layouts[layout].items[item].url = native
                    changed = true
                }
            }
        }
        return changed
    }

    static var all: [LauncherLayout] { [everyday, occasional] }

    /// Bind this to the `systemLarge` widget.
    static var everyday: LauncherLayout {
        LauncherLayout(name: "常用", items: [
            // A sample daily set, not a recommendation: the seed exists so a
            // fresh install has something to look at and edit. Rows whose
            // name matches a native scheme in `nativeURLs` route directly;
            // the rest expect a same-named shortcut.
            "Beeper", "X", "ChatGPT", "Grok", "Obsidian",
            "Notes", "Reminders", "Calendar", "Google Maps",
            "Substack", "Letterboxd",
        ].map(openApp))
    }

    /// Bind this to the `systemMedium` widget below it.
    static var occasional: LauncherLayout {
        LauncherLayout(name: "其他", items: [
            "Photos", "Clock", "Podcasts", "Books", "TV",
        ].map(openApp))
    }

    /// Display name is the app's own name, by owner decision: it matches the
    /// label already under each icon, so recognition costs nothing to relearn.
    /// M-1 (SPEC-NEXT §4): the row's name doubles as the shortcut name — one
    /// app, one same-named shortcut, no `input`. The owner creates those
    /// shortcuts by hand in the Shortcuts app, once (README documents this).
    private static func openApp(_ appName: String) -> LauncherItem {
        LauncherItem(name: appName,
                     url: nativeURLs[appName] ?? ShortcutsURL.runShortcut(named: appName, input: nil))
    }
}
