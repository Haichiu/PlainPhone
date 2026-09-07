#!/bin/bash
# PlainPhone — one-command device test kit.
#
# Builds, signs, and installs PlainPhone on a connected iPhone, then prints the
# device checklist (Gate 0, seven-day expiry, two-week check). Everything a
# human must judge is left to the human; this script only removes the Xcode
# session from the loop.
#
#   ./Scripts/device-test.sh              # build + install + checklist
#   ./Scripts/device-test.sh --checklist  # print the checklist only
#   PLAINPHONE_TEAM_ID=ABCDE12345 ./Scripts/device-test.sh
#
# Never uses sudo and never changes the global xcode-select setting.

set -euo pipefail
cd "$(dirname "$0")/.."

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

checklist() {
cat <<'EOF'

================================================================================
DEVICE CHECKLIST — Gate 0 — record the answers, do not guess them
================================================================================

Gate 0 asks exactly one question: does a widget row tap open the target app?
Everything below serves that one question. Record what the device does —
do not guess, do not describe from memory.

SETUP (before the first tap)
1. In the Shortcuts app, create SIXTEEN shortcuts, one per seeded row, each
   named EXACTLY after its app, each with the single action 「打開 App」
   pointed at that app:

     常用 (11):  Beeper, X, ChatGPT, Grok, Obsidian, Notes, Reminders,
                 Calendar, Google Maps, Substack, Letterboxd
     其他 (5):   Photos, Clock, Podcasts, Books, TV

   Rows whose name has a native URL scheme (Notes, Reminders, Calendar,
   Photos, Clock, Podcasts, Books, TV) route directly and need no shortcut.

   Every row launches  shortcuts://run-shortcut?name=<RowName>  — no input
   parameter, no shared "Open" shortcut. A shortcut whose name does not
   match its row exactly will not be found; there are no near-misses.

2. Set up the Home Screen — one page, two widgets, no app icons in the grid.
   Long-press Home Screen -> Edit -> Add Widget -> PlainPhone -> Large.
   Long-press the widget -> Edit Widget -> pick 常用, and set 頁次 = 1.
   Add a second PlainPhone widget (Medium) under the Large one, Edit Widget
   -> pick 其他, and set 頁次 = 1.

--------------------------------------------------------------------------------
G0-1  WIDGET SHOWS THE LIST
--------------------------------------------------------------------------------
Go Home. Both widgets render the seeded names.

    Large widget (常用) shows its rows   [ ]
    Medium widget (其他) shows its rows  [ ]

EVIDENCE: a SCREENSHOT of the Home Screen with both widgets showing.

--------------------------------------------------------------------------------
G0-2  TAP EVERY ROW          >>> START A SCREEN RECORDING FIRST <<<
--------------------------------------------------------------------------------
Start a screen recording (Control Centre -> Screen Record) BEFORE the first
tap. W-6 removed the speed measurement: the only question is whether each
row opens the CORRECT app. Tap all 16 rows, in any order, and record each
answer. The recording is the evidence — not a description of what happened.

  row (常用)             opens correct app?
  ----------------------  -------------------
  Beeper                  [ ]
  X                       [ ]
  ChatGPT                 [ ]
  Grok                    [ ]
  Obsidian                [ ]
  Notes                   [ ]
  Reminders               [ ]
  Calendar                [ ]
  Google Maps             [ ]
  Substack                [ ]
  Letterboxd              [ ]

  row (其他)             opens correct app?
  ----------------------  -------------------
  Photos                  [ ]
  Clock                   [ ]
  Podcasts                [ ]
  Books                   [ ]
  TV                      [ ]

Verdict:  rows opened correctly  ........ / 16

--------------------------------------------------------------------------------
G0-3  WHICH PATH HELD — A OR B                (write the outcome to docs/device/)
--------------------------------------------------------------------------------
From the recording, decide which launch path the device actually took:

  A  Direct: the target app opens and PlainPhone never appears.   [ ]
  B  Bounce: PlainPhone flashes to the foreground first, then the
     target app opens.                                            [ ]

Decision tree:
  - A holds      -> record A in docs/device/ together with the G0-1
                    screenshot and the G0-2 recording. Done.
  - A fails      -> write down the EXACT error or behaviour — nothing
                    happens, bounce back to Home, an error alert, which
                    rows fail — then switch the build to path B (M-4) and
                    re-run G0-1 and G0-2.
  - B also fails -> STOP. Report to the Owner. NO third mechanism may be
                    invented; that is a product decision, not a fix.

Path that held (A / B):  ......   If A failed, exact behaviour:  ......

--------------------------------------------------------------------------------
T3  SEVEN-DAY EXPIRY                    (N-2, N-6 — needs a week of calendar)
--------------------------------------------------------------------------------
Today: open PlainPhone -> 關於 -> 簽名到期. Write the date down:  ...........

On that date, BEFORE re-signing, record:
  - Does the app still launch?                    [ ]
  - Does the widget still show rows, or go blank? [ ]
  - Does tapping a row still work?                [ ]

Then let SideStore refresh (or re-run this script) and confirm recovery.
This is the single most important number for whether PlainPhone survives.

--------------------------------------------------------------------------------
CLOSED  APP GROUP  (was T2)
--------------------------------------------------------------------------------
Closed by F-1: a free personal team cannot get an App Group. Shared storage
between app and widget is Gate 1 work — keychain first (F-2), and only the
Owner decides on paying $99 for an App Group. Nothing to record today.

--------------------------------------------------------------------------------
GATE 1  PENDING
--------------------------------------------------------------------------------
Refresh latency (was T4) and the daily-usability items wait for Gate 1.
No Gate 1 checklist exists yet; finish Gate 0 first.

--------------------------------------------------------------------------------
T5  TWO WEEKS  (the actual definition of done)
--------------------------------------------------------------------------------
One handwritten line a day. Not in the app — the product does not measure you.
  "Did I prefer this to a blank Home Screen today? yes / no / didn't notice"

================================================================================
EOF
}

if [ "${1:-}" = "--checklist" ]; then checklist; exit 0; fi

[ -d "$DEVELOPER_DIR" ] || fail "Xcode not found at $DEVELOPER_DIR"

bold "==> Simulator tests first (a device round is expensive; do not waste one)"
xcodebuild -project PlainPhone.xcodeproj -scheme PlainPhone \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 \
  | grep -E 'error:|Executed .* tests|\*\* TEST' | tail -5

bold ""
bold "==> Looking for a connected device"
DEVICES=$(xcrun devicectl list devices 2>/dev/null | grep -i 'connected' || true)
if [ -z "$DEVICES" ]; then
  warn "No connected device found."
  warn "Plug the iPhone in, unlock it, and trust this Mac. Then re-run."
  warn ""
  warn "Printing the checklist anyway so you can work from an existing install:"
  checklist
  exit 0
fi
echo "$DEVICES"

# A free personal team is fine; we only need its identifier.
if [ -z "${PLAINPHONE_TEAM_ID:-}" ]; then
  warn "PLAINPHONE_TEAM_ID is not set — relying on Xcode's automatic signing."
  warn "If signing fails, find your team id with:"
  warn "    security find-identity -v -p codesigning | grep 'Apple Development'"
  warn "and re-run as: PLAINPHONE_TEAM_ID=XXXXXXXXXX $0"
  TEAM_ARGS=()
else
  TEAM_ARGS=(DEVELOPMENT_TEAM="$PLAINPHONE_TEAM_ID")
fi

bold ""
bold "==> Building for device"
DERIVED=$(mktemp -d)
trap 'rm -rf "$DERIVED"' EXIT

if ! xcodebuild -project PlainPhone.xcodeproj -scheme PlainPhone \
     -destination 'generic/platform=iOS' -configuration Debug \
     -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
     "${TEAM_ARGS[@]}" build 2>&1 | tail -30; then
  fail "Device build failed. Most likely signing: open PlainPhone.xcodeproj once, \
pick your Apple ID under Signing & Capabilities for BOTH targets, then re-run."
fi

APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name 'PlainPhone.app' -print -quit)
[ -n "$APP" ] || fail "Build succeeded but PlainPhone.app was not found."

bold ""
bold "==> Embedded provisioning profile"
PROFILE="$APP/embedded.mobileprovision"
if [ -f "$PROFILE" ]; then
  # The profile is a CMS-wrapped plist; pull the date out textually.
  EXPIRY=$(strings "$PROFILE" | grep -A1 ExpirationDate | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | head -1)
  echo "    expires: ${EXPIRY:-unknown}"
  echo "    ^ this is the T3 date. The app shows the same value under 關於."
else
  warn "    no embedded profile — this build is not device-signed."
fi

bold ""
bold "==> Installing"
xcrun devicectl device install app --device "$(xcrun devicectl list devices 2>/dev/null | grep -i connected | head -1 | awk '{print $3}')" "$APP" \
  || fail "Install failed. If this is a free account, check you are under the 3-app device limit."

bold ""
bold "Installed. SideStore will handle re-signing from here — see README.md."
checklist
