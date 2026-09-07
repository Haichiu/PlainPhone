# PlainPhone — GitHub Showcase & Promotional Copy

Developer-oriented copy for the repository. Factual, no marketing fluff.
Every number here is checked against the code as of 2026-09-07; if the code
moves, this file is wrong until someone fixes it.

---

## 1. Repository "About" & taglines

- **Direct:**
  > A text-first iOS 18 launcher widget. Less visual noise, same access to every app.
- **Short:**
  > Pure-text app launcher for iOS 18. No icons, no badges, fully offline.
- **Technical:**
  > A text-only Home Screen launcher widget in SwiftUI + WidgetKit. No dependencies.

---

## 2. README showcase (drop-in Markdown)

```markdown
# PlainPhone

A text-first launcher widget for iOS 18. It replaces the Home Screen icon
grid with a plain-text list you can tap, so the screen stays quiet without
putting your apps out of reach.

SwiftUI and WidgetKit. Offline, no accounts, no third-party dependencies.

---

## The problem

Daily life needs a lot of single-purpose apps — banking, transit, messaging,
authentication. They cannot be collapsed into one app or a browser tab.

The stock Home Screen surrounds all of them with noise: saturated icons,
brand marks, notification badges, and a grid laid out for discovery rather
than for the fifteen apps you actually open.

iOS offers two ways out, and both cost something:

1. **The icon wall.** Instant recognition, maximum clutter.
2. **An empty screen plus Spotlight.** Visually calm, but every launch now
   costs recall and typing.

There is no built-in way to put an interactive, text-only list of apps on
the Home Screen. That is the gap PlainPhone fills.

---

## What it does

- **Tap a name, the app opens.** Rows route through iOS Shortcuts, or
  through a native URL scheme where one exists.
- **Nothing moves on its own.** No icons, no badges, no counters, no page
  indicators. The widget shows no numbers at all, by design.
- **The list is the interface.** Names stay in the order you put them in.

---

## Features

### Typography and layout
- 1, 2, or 3 columns (default 3).
- Font scale 0.8-1.6x, line height 1.0-1.8, letter spacing -0.5 to 3pt,
  adjustable in-app with a live preview of the real widget surface.
- **Capacity is derived, not assumed.** How many rows fit is computed from
  your typography settings, and a test renders the widget headlessly and
  counts the rows that actually appear, for every combination of family,
  column count, and font scale. Model and renderer are pinned to each other,
  so the app cannot claim a row it does not draw.
- At the defaults: 12 items per medium page, 27 per large page.

### Paging and contexts
- Up to 4 layouts, 3 pages each, 36 items per layout.
- Overflow spills onto the next page, which you reach by adding another
  widget instance to a native iOS Widget Stack — no custom gestures, no
  background process.
- Anything stored but not reachable under your current settings is counted
  and announced in the app. Items are never silently hidden.

### App compatibility
- Opens any installed app through a same-named shortcut
  (`shortcuts://run-shortcut?name=<AppName>`), so there is no bundled
  database of URL schemes to go stale.
- Native Apple apps use their own schemes where they have one.
- Arbitrary URLs work too (`https:`, `mailto:`, ...).

### Privacy and storage
- No network code, no telemetry, no analytics, no SDKs.
- App and widget share one payload. With a paid developer account that is an
  App Group; on a free personal team, which cannot create one, it falls back
  to a shared keychain item. Same data either way.
- Bounded decoding: over-long names, over-sized lists and out-of-range
  settings are clamped on the way in rather than trusted.
- Row taps go through `plainphone://open?target=...`, and the app refuses
  any target outside an allow-list of schemes, so the relay cannot be turned
  into an open redirect.

---

## How it works

```text
[ PlainPhone app (SwiftUI) ]
        |  edits layouts + typography
        v
[ shared payload: App Group, or keychain on a free team ]
        |
        v
[ PlainPhone widget (WidgetKit) ]
        |  renders the page slice its settings allow
        v
  tap -> plainphone://open?target=... -> app checks the scheme -> target app
```

---

## Recommended setup

1. Move your apps to the App Library so the Home Screen has no icons.
2. Turn notification badges off.
3. Use a plain dark wallpaper.
4. Add a Large or Medium PlainPhone widget. Stack more instances for extra
   pages or other layouts.

---

## Status

This is a personal tool built for one person, published in case it is useful.

- iOS 18. `systemSmall` is not supported: at that size iOS gives a widget a
  single tap target, so per-row taps are impossible. Shipping it would have
  been a lie.
- Not on the App Store. Install by building it yourself. On a free Apple
  developer account the signature lasts 7 days and must be refreshed.
- The test suite covers the model, storage, paging and the rendered layout.
  On-device verification of the full tap-to-launch path is still in progress.
```

---

## 3. Community launch copy (Show HN / Reddit)

### Title
> Show HN: PlainPhone - a text-only iOS 18 launcher widget

### Body
```text
I built PlainPhone, a text-only launcher widget for iOS 18 in SwiftUI and
WidgetKit.

The motivation: daily life needs a lot of single-purpose apps, but the stock
Home Screen wraps them in bright icons, brand marks and badges. The usual
alternative - an empty screen plus Spotlight - just moves the cost to recall
and typing.

PlainPhone is the middle option: a plain-text list on the Home Screen where
each row is its own tap target.

- Opens any installed app via a same-named Shortcut, so there is no bundled
  URL-scheme database to rot.
- 1-3 columns, adjustable font size, line height and letter spacing.
- Capacity is derived from those settings, and a headless render test counts
  the rows that actually appear - the widget cannot promise a row it clips.
- Multi-page and multi-context via native Widget Stacks. No custom gestures,
  no background work.
- Offline. No analytics, no dependencies.

It is a personal tool rather than a product: no App Store build, and on a
free developer account the signature needs refreshing weekly.

Code and setup: [link]
```

