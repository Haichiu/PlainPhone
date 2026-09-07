# PlainPhone — Specification

> **方向權威異動（2026-09-02）：** `SPEC-NEXT.md` 為方向權威。其 §8 對本文件的修廢：
> U-3 廢止、N-9 改為一 app 一同名捷徑（無 input）、K-8 改為機制不指定、
> CH-1/CH-3 廢止、D-7 關閉：不能、D-3 保持關閉但路徑 A 優先、T1 降級、
> T0 關閉：十六個、W-7 Dock 移出範圍。衝突時以 `SPEC-NEXT.md` 為準；
> Gate 0 結果另見 `docs/device/`。

> **STATUS: AUTHORITATIVE.** Supersedes the baseline spec (archived at
> `docs/archive/SPEC-baseline-2026-08.md`) and the proposal that preceded it
> (`docs/archive/SPEC-NEXT-proposal-2026-08.md`).
>
> Promoted 2026-08-28 on the owner's instruction. §2 is implemented and
> simulator-verified. §3 is open and **must not be implemented as if settled**.

**Direction:** *安靜的辨識* / quiet recognition.
**Strategy:** `docs/product/STRATEGY.md` · **Evidence:** `docs/product/RESEARCH.md`
**Sequencing:** `docs/product/VALIDATION-AND-ROADMAP.md`

---

## 0. How to read this

- **§2 requirements** are settled. Implement them.
- **§3 open questions** are *not* requirements. Each names the decision, what closes
  it, and what must not be assumed meanwhile.
- **§4 non-goals** are refusals, not gaps. Do not "complete" them.
- Requirement IDs are stable. Reference them in commits and tests.

## 1. What the product is

> **A short list I wrote myself, on an otherwise empty screen: I only have to see it,
> never to remember it.**

The entire interaction is **unlock → see → tap**. Silence is the precondition, not the
achievement: an empty black Home Screen is already quieter than one with a PlainPhone
widget on it. What the product adds is *recognition without imposed choice* — the one
thing native iOS cannot do, since iOS offers only a blank wallpaper, icon tiles, or
Search.

The editor app is a rarely-used maintenance tool. It must never become the product.

**Single user:** the owner, iPhone 14, self-installed. There is no second user, no
onboarding, no distribution.

---

## 2. Requirements

### 2.1 Carried over from the baseline

| ID | Requirement |
|---|---|
| **K-1** | Native SwiftUI app plus WidgetKit extension targeting iOS 18. |
| **K-2** | Home-screen widgets: black background, white text. |
| **K-3** | Each visible text row is independently tappable and opens its configured URL or Shortcuts URL. A visible pass-through of the PlainPhone app is an accepted outcome (see D-3, closed). |
| **K-4** | The app can create, delete, rename, and drag-reorder launcher items. |
| **K-5** | The app can create, rename, and delete layouts. |
| **K-6** | Widget configuration selects which layout **and which page** that widget instance displays. |
| **K-7** | Shortcuts support builds a percent-encoded `shortcuts://run-shortcut?name=…` URL from a name typed by the user. The app must continue to state plainly that iOS cannot enumerate or import the user's shortcuts. |
| **K-8** | Shared persistence between app and widget through an App Group, followed by `WidgetCenter` timeline reloads after edits. |
| **K-9** | Fully offline: no analytics, accounts, network calls, subscription, ads, or third-party runtime dependencies. |
| **K-10** | Bounded persistence: all writes clamped, overflow refused rather than silently truncated. |
| **K-11** | Corrupt stored data is never silently overwritten: read-only on decode failure, explicit banner, explicit user-triggered recovery. |
| **K-12** | Accessibility: Dynamic Type where practical, VoiceOver labels and hints, adequate contrast, sensible empty and error states. |
| **K-13** | Degraded storage (App Group unavailable) is surfaced to the user, never silent. |
| **K-14** | Data written by an older version must keep decoding. Obsolete keys are ignored, never treated as corruption. |

### 2.2 Changed from the baseline

| ID | Was | Becomes | Why |
|---|---|---|---|
| **CH-1** | Max 32 items per layout | **36** — derived, not chosen: `maxPages × a medium page at the shipping defaults` (3 × 4 rows × 3 columns). Was 15 (3 × 5) until 2026-09-07, when that formula was found to assume one column. | Enforces P-1 below. The baseline stored 32 while `systemLarge` displayed 16, so **16 items were permanently unreachable**. This was a real bug, not a limit. |
| **CH-2** | Max 12 layouts | **4** | n=1 with a handful of contexts. 12 leaked the assumption that this was built for other people. |
| **CH-3** | Family capacities 4 / 8 / 16 | **Rows per column at the measured 1.2 basis: medium 5, large 13 — MEASURED; at the shipping defaults (line height 1.80) the model derives 4 and 9.** `systemSmall` no longer ships (D-1, closed). | Rendering 20 rows and counting the text bands that actually appear gives 5 and 14 at the default text size; large is set to 12 for margin. Capacity is now a measurement, not an assertion. |
| **CH-4** | Display name max 40 chars | **24** | A 40-character row cannot be taken in at a glance. |
| **CH-5** | Seeded 日常 / 專注 / 閱讀, reverse-engineered from a screenshot | **The owner's own daily set**, transcribed from his Home Screen on 2026-08-28: 「常用」 (11 rows, bind to `systemLarge`) and 「其他」 (5 rows, bind to `systemMedium`). Every row routes through Shortcuts (N-9). | Stage 0 landed (see `docs/product/VALIDATION-AND-ROADMAP.md` §1.8), so the placeholder starter is gone. LINE, Music, Firefox and Safari are deliberately absent: they stay in the Dock, so listing them again would waste a row. |
| **CH-6** | Row tap mechanism asserted to work | The **observed device behaviour** is recorded in this spec and in `README.md`, including any visible transition through PlainPhone. | The baseline documented this as "pending device verification" while the README read as though it worked. |

### 2.3 Removed

| ID | Removed | Why |
|---|---|---|
| **RM-1** | The `＋k 個項目…` overflow caption | It announced hidden options with no way to reach them — a dead end, and precisely the imposed-choice noise the product exists to remove. **Paging replaces it** (P-1); an earlier proposal to delete overflow entirely was rejected by the owner in favour of paging. |
| **RM-2** | `LauncherData.selectedLayoutID` and the global "selected layout" concept | Two competing layout selectors is itself a recall problem. Widget configuration is now the sole selector; absent configuration, fall back to the first layout. Legacy blobs carrying the key still decode (K-14). |
| **RM-3** | `systemSmall` support | At that size iOS provides one widget-level tap target, so a list of independently tappable rows cannot be delivered honestly. Shipping it would have shipped a lie. |
| **RM-4** | Reference-screenshot provenance for defaults | Superseded by CH-5. Retain the design principle: original, unbranded, no trademarked presentation. |

### 2.4 New

| ID | Requirement |
|---|---|
| **P-1** | **Paging, with a reachability invariant.** Items that do not fit on a page spill onto the next, up to `maxPages` (3). **Every stored item must be reachable on some page in every shipping family** — hence the item cap is bounded by the *smallest* shipping page size. An item that no widget can display must be impossible to store. |
| **P-2** | **Page switching uses native iOS Widget Stacks; PlainPhone adds no code for it.** Place one widget instance per page, stack them, disable Smart Rotate and Widget Suggestions. The same mechanism serves context switching: stack instances bound to *different layouts*. |
| **N-1** | **The required host configuration is part of the product.** `README.md` must document the Home Screen setup the product assumes: every icon removed from the Home Screen grid (apps remain installed), all other pages hidden, solid black wallpaper, badges disabled per app. **The Dock keeps up to four icons** (owner decision 2026-08-28): they are fixed-position muscle memory that costs no recall, and keeping them frees the entire grid for text. |
| **N-7** | **One page must hold the whole daily set without swiping.** A `systemLarge` above a `systemMedium` fills an iPhone page and yields **39 items** at the shipping defaults (27 + 12). Bind them to two layouts. If the set stops fitting, the correct response is to shorten the set, not to add a swipe. |
| **N-9** | **Every row routes through Shortcuts**, using `shortcuts://run-shortcut?name=Open&input=<AppName>`. | Only about three of the owner's sixteen apps publish a documented URL scheme, and D-2 is unresolved. Shortcuts is the one documented URL form that can reach an arbitrary third-party app, because Shortcuts can enumerate installed apps and this app cannot. It costs a visible bounce through the Shortcuts app on every tap — the cost T1 measures. Whether ONE shortcut suffices, or sixteen are needed, is decided by **T0**. |
| **N-8** | **Accessibility degradation is stated, not hidden.** At accessibility text sizes the measured capacity falls to 7 (large) and 3 (medium) and further rows are clipped. This is documented in the app and `README.md`. It is not designed around: the sole user runs the default text size. |
| **N-2** | **Provisioning expiry is visible in the app.** Read `ExpirationDate` from the embedded provisioning profile and display it with days remaining. Requires no entitlement and no network. On a free personal team the profile expires every 7 days, after which iOS will not launch the app *or its widget extension*. A daily tool must not fail silently and by surprise. Absent profile means "not applicable", never "expired". |
| **N-3** | **The widget displays no numbers.** No counts, badges, overflow indicators, page numbers, status, or time-varying content. Rows and the layout name only. |
| **N-4** | **Honest capability statements.** Any limitation found during device verification is stated plainly in `README.md`. No capability may be described as working on the basis of a simulator result. |
| **N-6** | **Installation is via SideStore on a free personal team** (D-6, closed). `Scripts/device-test.sh` builds and installs; re-signing thereafter is SideStore's background refresh. The 7-day window and the 3-app device ceiling are documented in `README.md`, not hidden. |

---

## 3. Open questions — NOT requirements

| ID | Question | Closed by | Until then |
|---|---|---|---|
| **D-2** | Do custom-scheme rows (`line://`, `obsidian://`) work, or only universal links plus `shortcuts://`? `[FACT]` Apple documents `OpenURLIntent` against universal-link handling, and iOS 18 widget reports show custom schemes failing with `NSOSStatusErrorDomain -10814`. | Device test **T1** | Do not add scheme-specific special cases speculatively. The free-text URL field stays; it is the product's actual differentiator against preset-list competitors. |
| **D-4** | ~~Final values for CH-1 – CH-4, and the real contents of the starter list.~~ **CLOSED 2026-08-28.** The list is the owner's real one; rows-per-page are measured, not invented. What remains open is only whether 16 rows still feel right after two weeks (**T5**). | Stage 0 (done) → **T5** | The caps are now consequences of a measurement plus a real list, not guesses. |
| **D-7** | Can a free personal team provision the App Group? First-party Xcode metadata says yes (`validTeamTypes` includes `XCODE_FREE_PROGRAM`); one research pass claimed no. | Device test **T2** | Do not design an App-Group-free fallback until T2 fails. |

### Closed since the proposal

| ID | Resolution |
|---|---|
| **D-1** | **Closed: `systemSmall` does not ship.** `Link` and per-row tap targets exist only in medium and large; a small widget has a single destination. Rather than wait for T1, the honest option was taken (RM-3). |
| **D-3** | **Closed: a visible pass-through is acceptable.** `[EVIDENCE]` The reference implementation the owner used daily ships exactly this as a documented setting ("Always Through Dumb Phone"), and he left that product over price, not behaviour. T1 therefore asks *"is our pass-through as fast as the one he already accepted"*, not *"does direct opening work"*. |
| **D-5** | **Closed: keep layouts.** The owner confirmed he used multiple pages in different contexts. Delivered by P-2 at zero code cost. |
| **D-6** | **Closed: free personal team + SideStore.** `[FACT]` SideStore re-signs with a personal certificate and refreshes in the background over Wi-Fi, no computer after setup. Paid membership is not assumed. If the owner later builds several self-made apps, the $99/year becomes a platform fee amortised across them — an observable count of apps, not a judgement about PlainPhone. Nothing in this spec depends on it. |

---

## 4. Non-goals

Considered and refused, with reasoning in `docs/product/RESEARCH.md` §3.

- Reducing screen time or compulsive use. The success criterion is preference, not
  behaviour change. **This is the most important non-goal**: it is what keeps the
  product from drifting into a blocker.
- App blocking, shields, friction, delays, Screen Time / Family Controls APIs.
- Any number, count, badge, streak, or statistic anywhere in the product.
- Notifications from PlainPhone. It must never interrupt.
- Intention prompts, "today's one thing", motivational or changing text.
- Search within the launcher. The list exists so that nothing must be searched.
- A curated database of app URL schemes. Competitors ship one and their loudest
  complaint is *"if the app you have isn't on the preset list"*. A free-text URL field
  is strictly more capable for one user who can look a scheme up once.
- Analytics or usage tracking of any kind, including temporarily "for the experiment".
- App Store distribution, onboarding, monetisation, second users.
- Icons, images, colour, theming beyond black and white.
- Sync, cloud, accounts, or any network access.
- Enumerating installed apps or the user's shortcuts. `[FACT]` iOS does not permit it.
- Folders, nesting, or more than one purpose per screen. (Pages are overflow, not
  hierarchy.)
- In-app page switching. Widget Stacks already do it (P-2).

## 5. Platform constraints (facts the design must respect)

- `[FACT]` Apple documents no supported mechanism for a Home Screen widget to open an
  arbitrary third-party app. `.widgetURL` / `Link` are documented as opening a scene
  in the *containing* app; `OpenURLIntent` is documented against universal links;
  `openAppWhenRun = true` explicitly foregrounds the containing app.
- `[FACT]` `Link` provides independent tap targets only in `systemMedium` and
  `systemLarge`.
- `[FACT]` `UIApplication.shared` is unavailable in app extensions; the working
  pattern targets the AppIntent at the main app.
- `[FACT]` WidgetKit timelines are system-budgeted; timely refresh is not guaranteed.
- `[FACT]` `shortcuts://run-shortcut` necessarily routes through the Shortcuts app.
- `[FACT]` iOS cannot enumerate installed apps; `LSApplicationQueriesSchemes` is capped
  at 50 entries and governs `canOpenURL`, not `open`.
- `[FACT]` Free personal-team provisioning profiles last 7 days. On expiry iOS will not
  launch the app or its widget extension.
- `[FACT]` A free personal team allows **3 installed apps per device** and **10 App IDs
  per 7 days**. Each app extension consumes an App ID, so PlainPhone costs 2.
- `[FACT]` Family Controls requires paid membership
  (`validTeamTypes: ['APPLE_DEVELOPER_PROGRAM']`). With a free account it is unavailable.
- `[FACT]` Stock iOS 18+ can already remove every Home Screen icon, hide pages, empty
  the Dock, and disable badges per app. The product must justify itself *against* that
  baseline, not against a default iPhone.

## 6. Privacy requirements

- No network access of any kind. No analytics, telemetry, crash reporting, or accounts.
- All data stays in the App Group container on device.
- **The product does not measure its user.** Even validation (T5) is a hand-written
  daily note, never in-app instrumentation. This is a privacy requirement *and* a
  product-character requirement.
- No third-party runtime dependencies.

## 7. UX requirements

- **U-1** The widget is readable at a glance without scanning. If finding a row
  requires reading top to bottom, the list is too long — fix the data, not the type.
- **U-2** The widget is static furniture. Nothing on it changes unless the owner edits
  it.
- **U-3** Every row states what it opens in the owner's own words.
- **U-4** Errors and degraded states are explicit and actionable: unreadable storage,
  unavailable App Group, approaching profile expiry, a page configured past the end.
- **U-5** The editor is optimised for rare use, not for speed. It may be plain.
- **U-6** Accessibility per K-12 is not negotiable at any list length. Where a
  size cannot be honoured — see N-8 — the limit is measured and published rather
  than quietly tolerated.

## 8. Engineering constraints

- Native SwiftUI, WidgetKit, AppIntents, Foundation only. No packages.
- Keep modules cohesive and shallow in interface. No abstraction without a present need.
- Xcode is at `/Applications/Xcode.app` but the active developer directory points at
  CommandLineTools. Prefix all commands with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Never use `sudo` or
  change global `xcode-select`.
- Work only inside this project directory. Never read credentials or alter global
  developer settings. Preserve unrelated files.
- The App Group string stays mirrored in `Shared/LauncherStore.swift`.
- Removing capability is a legitimate and preferred change. Deletions need no
  compensating feature.

## 9. Definition of done

A green build is **not** done. This product is done when:

1. Every §2 requirement is implemented and mechanically verified.
2. Every §3 open question is closed by recorded evidence, and the outcome is written
   into this spec and `README.md` — including outcomes that were unwelcome.
3. **T1 has a screen recording**, and the actual tap behaviour is documented honestly.
4. **H7 holds**: after two weeks of ordinary daily use the owner still prefers the list
   to the blank Home Screen baseline.

If H7 fails, the correct outcome is to retire the product, not to add features to it.

## 10. Verification requirements

### Automated (run on every change)

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PlainPhone.xcodeproj -scheme PlainPhone \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

| ID | Verification | Status |
|---|---|---|
| **V-1** | Every stored item is reachable on some page in every shipping family; pages partition the list in order with no duplicates and no gaps (P-1). | ✅ `testEveryStoredItemIsReachableOnSomePage` |
| **V-6** | The declared rows-per-page is what actually renders — counted from the rendered image, not asserted (CH-3, N-8). | ✅ `testRenderedRowCapacityMeetsDeclaredPageSize` |
| **V-2** | No numeric content in widget output; starter rows contain no digits (N-3). | ✅ `testWidgetRendersNoDigits` |
| **V-3** | `ExpirationDate` is parsed from a CMS-wrapped profile, malformed input returns nil rather than guessing, absent profile is "not applicable" (N-2). | ✅ `ProvisioningProfileTests` |
| **V-4** | Legacy blobs containing `selectedLayoutID` still decode and do not raise the corruption banner (K-14, RM-2). | ✅ `testLegacyBlobDoesNotTriggerCorruptionBanner` |
| **V-5** | Black background, white text, and legible edge branches (empty layout, last page, page past end) render in both shipping families, including at accessibility text sizes (K-2, U-4). | ✅ `WidgetVisualTests` |

### Device (requires a signed install — `Scripts/device-test.sh`)

| ID | Verification | Status |
|---|---|---|
| **T1** | Tap behaviour with a screen recording, for every shipping family × URL kind (universal link, `sms:`/`mailto:`, `shortcuts://`, custom scheme). Measures **pass-through duration**, not merely success (D-2, CH-6). | ⏳ pending |
| **T2** | App Group provisioning and cross-process read on a free personal team (D-7). | ⏳ pending |
| **T3** | Behaviour at 7-day profile expiry, and recovery via SideStore background refresh (N-2, N-6). | ⏳ pending |
| **T4** | Widget refresh latency after an edit. | ⏳ pending |
| **T5** | Two weeks of daily use, recorded as a hand-written daily note (H7). | ⏳ pending |

Procedures are in `docs/product/VALIDATION-AND-ROADMAP.md` §1.4, and the
runnable checklist is `Scripts/device-test.sh --checklist`.

**Never claim a check passed unless it was actually run.** Simulator results may not
be reported as device behaviour.
