# PlainPhone

A private, offline, subscription-free iOS 18 SwiftUI app plus WidgetKit
extension: a black-and-white **text launcher** for one person.

> **A short list I wrote myself, on an otherwise empty screen: I only have to
> see it, never to remember it.**

`SPEC.md` is authoritative. This file documents how to build it, how to set the
phone up, and — in §"What is actually verified" — exactly what has and has not
been proven.

---

## The Home Screen setup is part of the product

The widget is only worth having on a screen that is otherwise empty. Without
this setup you get a text list *next to* an icon wall, which is a worse icon
wall. Do this first:

1. **Remove every icon from the Home Screen.** Long-press an icon → *Remove from
   Home Screen*. The app stays installed and stays in App Library.
2. **Hide the other pages.** Long-press the Home Screen → tap the page dots →
   uncheck every page except the first.
3. **Keep the Dock.** Up to four icons stay. They are fixed-position muscle
   memory that costs no recall, and keeping them frees the entire grid for text.
4. **Solid black wallpaper.** Settings → Wallpaper → a plain black image.
5. **Turn badges off.** Settings → Notifications → per app → Badges off.
   Red dots are half the noise this product removes.
6. **Add two widgets.** Long-press → *Edit* → *Add Widget* → PlainPhone → add
   one **Large** and one **Medium**, stacked vertically to fill the page.
   Long-press each → *Edit Widget* → bind the large one to your main layout and
   the medium one to the overflow layout.

Stock iOS can do steps 1–5 by itself, for free. What it cannot do is show a
compact list of independently tappable rows with names you chose. That gap is
the entire reason PlainPhone exists.

## Pages and context switching — no PlainPhone feature required

PlainPhone deliberately has no in-app page switcher. iOS already has one.

- **More rows than fit:** rows spill onto page 2 and 3. Add a second widget
  instance, set its 頁次 to 2, then **drag it onto the first** to build a native
  **Widget Stack**. Swipe up/down to move between pages.
- **Different contexts:** the same trick with instances bound to *different
  layouts* — e.g. 常用 and 夜間.
- In the stack's settings, **turn off Smart Rotate and Widget Suggestions**, or
  iOS will change your list behind your back. A list that moves on its own is
  not a list you can rely on.

## Capacity

Capacity is **derived from the owner's layout settings**, not a fixed number.
The measured basis (line height 1.2, one column):

| Family | Rows per column | At accessibility text sizes |
|---|---|---|
| systemMedium | 5 | 3 |
| systemLarge | 13 | 7 |

These are **measured**, not estimated: the test suite renders 20 rows and counts
the text bands that actually appear. Taller rows or more columns move the number
— the model recomputes it, and the G1-3 matrix pins rendered rows == declared
rows for every combination.

At the **shipping defaults** (3 columns, line height 1.80 — the owner's own
settings, transcribed from his device on 2026-09-07):

| Family | Rows | Columns | Items per page |
|---|---|---|---|
| systemMedium | 4 | 3 | **12** |
| systemLarge | 9 | 3 | **27** |

**One page holds the whole daily set.** A large widget (27 items) above a medium
widget (12 items) fills an iPhone page: **39 items, no swiping.** Bind them to
two layouts, e.g. 「常用」 and 「其他」.

- Max **3** pages, **4** layouts, **36** items per layout, names ≤ **24**
  characters, URLs ≤ **512**.
- `systemSmall` is **not supported**: at that size iOS gives a widget a single
  tap target, so independently tappable rows are impossible. Shipping it would
  have shipped a lie.
- 36 = 3 pages × 12, a *medium* page at the shipping defaults — the smallest
  shipping family. That is deliberate:
  **every stored item must be reachable on some page in every family.** It was
  15 until 2026-09-07, when the cap was found to assume a single column while
  multi-column had become the normal layout, leaving large widgets half empty.
  Narrower settings can still shrink the derived capacity below the cap; those
  items stay stored and are announced in the app, never silently hidden. The
  previous version stored 32 items while the large widget showed 16, so 16 items
  were permanently unreachable behind a "＋k 個項目…" caption. That caption is
  gone; the bug is gone with it.
- The widget shows **no numbers** — no counts, badges, page indicators, or
  anything that changes on its own.

## Row taps — stated honestly

Each row is a `Button(intent: OpenURLIntent(url))` whose URL is
`shortcuts://run-shortcut?name=<AppName>` — one row, one app, one shortcut
named exactly like the row (SPEC-NEXT M-1). The old experiment of one shared
`Open` shortcut fed the app name as `input` is retired: T0 is closed as
"sixteen shortcuts", and no seeded URL carries an `input` parameter anymore.

**Apple documents no supported way for a widget to open an arbitrary
third-party app.** `.widgetURL` and `Link` are documented as opening a scene in
the *containing* app; `OpenURLIntent` is documented against universal links.

So whether a tap flashes through PlainPhone or the Shortcuts app before the
target app opens is decided by device testing (Gate 0), not by this document.
W-6 removed the speed question entirely: the only test is "does it open".

Rows whose URL you type yourself (`https://`, `mailto:`, custom schemes) are
still supported as a secondary path. Custom schemes (`line://`,
`obsidian://`) are **unverified** — developer reports say iOS 18 widgets
reject them with `NSOSStatusErrorDomain -10814`. The URL field accepts free
text anyway, because a preset database of app schemes is the single loudest
complaint against every competing launcher.

## Shortcuts

The seeded rows assume you have created one shortcut per row name in the
Shortcuts app — **16 shortcuts for the starter list**, each containing a
single **Open App** action pointed at the app of the same name. This is a
one-time, by-hand setup cost: iOS gives apps no way to create shortcuts, and
there is no import. A row whose shortcut is missing or misnamed does nothing
when tapped. Do not skip this step; the widget is inert without it.

Item editor → type **捷徑** → type the shortcut's exact name. The app builds a
percent-encoded `shortcuts://run-shortcut?name=…` URL and previews it live.
iOS does not let apps enumerate your shortcuts, so the name must match one you
created yourself.

## Installing (free Apple account + SideStore)

No paid membership is assumed.

```bash
./Scripts/device-test.sh
```

That runs the simulator tests, builds and signs for a connected iPhone,
installs it, prints the provisioning expiry date, and prints the device
checklist. `./Scripts/device-test.sh --checklist` prints the checklist alone.

First time only, in Xcode: open `PlainPhone.xcodeproj`, and for **both** the
`PlainPhone` and `PlainPhoneWidget` targets set *Signing & Capabilities* →
your Apple ID team, and a unique bundle ID (`com.<you>.plainphone` and
`com.<you>.plainphone.widget`). If you change the App Group from
`group.com.plainphone.shared`, change it in `Shared/LauncherStore.swift` too.

### The 7-day wall

A free personal team's provisioning profile lasts **7 days**. When it expires
iOS refuses to launch the app *and its widget extension* — the Home Screen list
just stops working. So:

- The app shows the expiry date under **關於 ▸ 簽名到期**, and warns in the last
  two days. It never fails silently.
- **SideStore** re-signs with your personal certificate and refreshes in the
  background over Wi-Fi, with no computer needed after setup.
- A free account also allows only **3 installed apps per device** and **10 App
  IDs per 7 days**. PlainPhone consumes **2** App IDs, because the widget
  extension counts as one.

## Project layout

```
PlainPhone.xcodeproj          4 targets
App/
  PlainPhoneApp.swift         @main entry point
  HomeView.swift              layout list, storage banners, signing expiry
  LayoutEditorView.swift      per-layout item editor
  ItemEditorView.swift        row editor: URL or Shortcuts-name mode
Shared/                       compiled into app and widget targets
  LauncherModel.swift         Codable model + bounded decoding + limits
  LauncherStore.swift         storage seam + persistence + timeline reloads
  DefaultLayouts.swift        the single starter list
  WidgetCapacity.swift        page size and paging arithmetic
  LauncherWidgetViews.swift   pure widget views (headlessly render-testable)
  LauncherProvider.swift      resolves layout + page from widget config
  LayoutSelection.swift       layout picker entity/query for widget config
  ProvisioningProfile.swift   reads ExpirationDate from the embedded profile
Widget/
  PlainPhoneWidgetBundle.swift
  LauncherWidgets.swift       medium/large widget wiring
  WidgetConfigurationIntent.swift
Tests/                        XCTest unit tests + behavioural probes
UITests/                      XCUITest navigation/editing probe
Scripts/device-test.sh        one-command device build + install + checklist
Scripts/verify-ui.sh          scoped UI-test run + SwiftUI log audit
SPEC.md                       requirements of the current implementation
CHANGELOG.md                  dated record of changes, with the reasoning
```

Both targets declare App Group **`group.com.plainphone.shared`**. Shared storage
is one bounded JSON blob under `plainphone.layouts.v1`; every edit calls
`WidgetCenter.reloadAllTimelines()`.

Data written by older versions still decodes. The obsolete `selectedLayoutID`
key is ignored rather than treated as corruption — an upgrade must never lock
you out of your own list.

## Bounded persistence

Writes are clamped before save; overflow adds are refused, never silently
truncated. If the stored blob fails to decode, a red banner appears with an
explicit recovery button and ordinary edits are blocked from writing, so the
original bytes can never be silently overwritten.

## Running the tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PlainPhone.xcodeproj -scheme PlainPhone \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`Scripts/verify-ui.sh [SIM_UDID]` additionally runs the UI tests while auditing
the unified log for SwiftUI "Invalid Configuration" warnings, with bounded
temp-file retention and a 900 s timeout.

Toolchain gotcha: after adding a test method, `-only-testing:<target>/<method>`
may enumerate 0 tests due to the incremental manifest cache. Run the whole
class, or touch the file.

## What is actually verified

**Verified on the simulator (46 unit tests passing):** compilation of all
targets, widget `.appex` embedding, entitlements wiring, paging arithmetic and
the reachability invariant, bounded decoding of oversized blobs, legacy-blob
compatibility, corruption preservation, Shortcuts URL encoding, persistence
round-trips, provisioning-profile date parsing including its failure modes, and
headless rendering of black-on-white in both shipping families across the
empty, last-page, past-the-end, and accessibility-text-size branches.

**NOT verified — requires a signed device (`Scripts/device-test.sh`):**

| | Question |
|---|---|
| **T1** | Does tapping a row open the target app, and how long is the pass-through? Do custom schemes work at all? |
| **T2** | Does a free personal team actually get the App Group? First-party Xcode metadata says yes; one research pass said no. |
| **T3** | What exactly happens at the 7-day expiry, and does SideStore recover it? |
| **T4** | How long after an edit does the widget update? |
| **T5** | After two weeks, is this still preferred to a blank Home Screen? |

T5 is the real definition of done. If it fails, the right answer is to retire
PlainPhone — not to add features to it.

Simulator results are never reported as device behaviour.

## Design provenance

Original adaptation of the minimalist text-launcher genre: black background,
white text, quiet hierarchy. No third-party code, no analytics, no accounts, no
network calls. Row labels are functional descriptions; no branded assets or
trademarked presentation are used.

The starter list is the owner's own daily set — 16 rows across the 「常用」 and
「其他」 layouts, each row named after its app and launching its same-named
shortcut. It exists only so the widget is legible before you replace it with
your own list.
