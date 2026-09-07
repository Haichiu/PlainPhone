# Changelog

Dated records of what changed and why. Reasons are kept because the
conclusions are easy to re-derive wrongly; the reasoning is not.

## 2026-09-07 — Grid layout, owner settings as defaults, item cap raised

### Shipping defaults now match the owner own device

Read off the 版面設定 screen and adopted verbatim: **3 columns, font 1.00x,
line height 1.80, letter spacing 2.0pt** (`Shared/LayoutSettings.swift`).

One trap found on the way: the capacity formula padding term was written as
`26 - 17 x default.lineHeight`, silently binding it to "the default is 1.2".
Moving the default to 1.80 would have made that term negative and detached
the model from its measured basis. Extracted
`LayoutSettings.measuredBasisLineHeight = 1.2` — the line height the pitches
were *measured* at — so the basis and the shipping default are now separate
ideas. The arithmetic is unchanged.

### Item cap 15 -> 36

15 was `maxPages x rowsPerPageMedium` = 3 x 5, where 5 is the **single
column** row count. Multi-column had since become the normal layout (W-3), so
the cap was throttling a large widget that can show 27 items on one page —
the visible symptom was a half-empty widget.

New cap is `maxPages x a medium page at the shipping defaults` = 3 x (4 rows
x 3 columns) = **36**. Deliberately not 45: the reachability invariant (P-1,
every stored item reachable on some page of the *smallest* shipping family)
had to survive the change, and 36 is exactly where it stays true.

At the defaults: medium 4 x 3 = 12 per page, large 9 x 3 = 27 per page.

### Rows became grid cells

- 0.5pt hairline dividers removed
- 5pt gap between cells, taken from *inside* the row pitch so the capacity
  arithmetic is untouched
- text centred in the cell
- cell fill tried, then removed: 「我不需要這個方塊的存在感，因為我只要有字就好了」。
  The grid is the layout method, not something to draw. The cell survives as
  an invisible tap target, which is what stopped the mis-taps the hairline
  never prevented.

### Group marker is now opt-in

New setting `showsGroupMarker`, **default off**, with a toggle under
版面設定 → 分組記號. The owner knows his groups by their contents; a permanent
mark for an occasional question is standing noise.

When on, it sits in the top-right corner at 2pt padding, and the single cell
underneath it (top row, last column) reserves the marker width so the two
cannot collide. When off, no space is reserved and that cell centres normally.

Two dead ends, recorded so they are not retried blindly:

1. **Marker moved to the bottom-right.** Looked clean in the headless render
   at 345x345 / 338x158; on the device it overlapped a row. The render sizes
   are an assumption, not the device — that was a verification error, not a
   layout one.
2. **`.contentMarginsDisabled()`.** It is the only way to put the marker truly
   against the widget edge, but the iOS ~16pt content margin also positions
   every row, so removing it moved all the text. Owner ordering is explicit:
   the text may not move, the marker is negotiable. Reverted.

### Background

Tried #151515, reverted to pure black the same day. `LauncherPalette` now holds
the single source for it.

### Tests

79/79 pass. Two changes were needed in the test suite itself:

- Tests that verified the *formula* were pinned to the old default line
  height. They now pass `measuredBasisLineHeight` explicitly, so they test the
  formula rather than the current default.
- The G1-3 rendered-rows-equal-declared-rows matrix gained a `showsMarker`
  seam. With taller rows the marker stops overlapping the first row glyphs
  and becomes its own band, which the row counter scored as an extra row.
  The marker is not a row, so the counting render turns it off.

### Signing

Provisioning profile renewed: was expiring 2026-09-09, now **2026-09-14**
(free personal team, 7 days). The earlier failure was a wrong team id taken
from the certificate common name; the correct id came from the existing
profiles. Old profiles were backed up before forcing a refresh.

### Known open questions

- Whether the iOS content margin causes the capacity model to over-declare
  rows on device. The model measures the full widget rectangle; the device
  shows 4 medium rows, which matches the model, so the concern is
  **unconfirmed** either way.
- The generated `.shortcut` files have never been imported or tapped on the
  device. Nothing about the launch path is verified end to end.


## 2026-09-07 (later) — Keychain access group is no longer hardcoded

`LauncherStore.keychainAccessGroup` held the literal string
`<TEAMID>.com.example.plainphone.shared`. It is now `nil`.

Keychain Services files an item into the first entry of the caller’s
`keychain-access-groups` entitlement when no access group is supplied, and
searches every entitled group when reading. Both targets declare exactly one
entry, `$(AppIdentifierPrefix)com.example.plainphone.shared`, verified with
`codesign -d --entitlements`, so omitting the attribute resolves to the same
shared group without naming the team.

Two problems went away: the repository no longer publishes the author’s team
id, and a clone no longer needs that constant edited before app and widget can
see each other’s data. The entitlement was always the source of truth; the
constant was a copy that could only drift.

No migration. Existing items were written to that same group, so unprefixed
queries still find them.

Verified: 79/79 tests, device build, install and launch; no keychain errors on
the launch console. Confirmation that the stored layouts and typography
settings survived is a visual check on the device.

