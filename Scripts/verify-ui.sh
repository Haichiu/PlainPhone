#!/bin/bash
# Scoped UI-test verification with SwiftUI "Invalid Configuration" audit.
#
# Log policy (bounded, never accumulating):
#   - Both the unified-log capture AND the xcodebuild output go to mktemp
#     files that are trap-removed when this script exits.
#   - Stale artifacts from any crashed earlier run are swept at start if they
#     exceed LOG_AGE_LIMIT seconds (default 3600).
#   - xcodebuild is killed after XCODEBUILD_TIMEOUT seconds (default 900 =
#     15 minutes) via a watchdog.
#
# Exit status: 0 pass, 1 fail (test failure, timeout, or warning found),
# 2 usage/environment error.
#
# Usage:
#   Scripts/verify-ui.sh [SIM_UDID]
#   Scripts/verify-ui.sh --self-test   # exercises timeout + gate logic only
set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_AGE_LIMIT="${LOG_AGE_LIMIT:-3600}"
TIMEOUT="${XCODEBUILD_TIMEOUT:-900}"

run_with_timeout() {
  # run_with_timeout SECONDS CMD... — returns CMD's exit code, or nonzero
  # (128+SIGTERM) if the watchdog fires.
  local secs="$1"; shift
  local pid rc=0 watchdog
  "$@" & pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) & watchdog=$!
  wait "$pid" || rc=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$rc"
}

sweep_stale_artifacts() {
  # Age-limited cleanup of our own artifact names only. Covers BOTH mktemp
  # kinds so hard-kill leftovers are reclaimed by the declared age policy.
  # rm -rf is safe here: every matched path lives under /tmp/plainphone-*;
  # selftest leftovers may be directories (mktemp -d), plain files need only
  # rm -f — branching keeps the intent explicit instead of failing on dirs
  # under set -e.
  local f
  for f in /tmp/plainphone-uilog.* \
           /tmp/plainphone-buildlog.* \
           /tmp/plainphone-selftest.* ; do
    [[ -e "$f" || -d "$f" ]] || continue
    if [[ $(( $(date +%s) - $(stat -f %m "$f") )) -gt "$LOG_AGE_LIMIT" ]]; then
      if [[ -d "$f" ]]; then rm -rf "$f"; else rm -f "$f"; fi
    fi
  done
}

gate_check() {
  # gate_check TEST_RC LOGFILE BUILDLOG -> exit code for the whole audit
  local rc="$1" logfile="$2" buildlog="$3"
  local bad=0
  grep -qi "Invalid Configuration" "$logfile"  && bad=$((bad+1))
  grep -q  "Invalid Configuration" "$buildlog"  && bad=$((bad+1))
  echo "Invalid Configuration occurrences (device log + build log): $bad"
  if [[ $rc -eq 124 || $rc -ge 128 ]]; then
    echo "FAIL: xcodebuild timed out or was killed" >&2; return 1
  fi
  if [[ $rc -ne 0 ]]; then echo "FAIL: tests failed" >&2; return 1; fi
  if [[ "$bad" -ne 0 ]]; then
    echo "FAIL: SwiftUI Invalid Configuration detected" >&2; return 1
  fi
  echo "PASS: UI tests green, no navigation configuration warnings."
}

if [[ "${1:-}" == "--self-test" ]]; then
  echo "[self-test] timeout watchdog:"
  if run_with_timeout 2 sleep 30; then
    echo "FAIL: watchdog did not kill" >&2; exit 1
  else
    echo "  run_with_timeout 2 sleep 30 -> killed (nonzero rc), OK"
  fi
  if ! run_with_timeout 5 true; then
    echo "FAIL: clean command reported failure" >&2; exit 1
  fi
  echo "  run_with_timeout 5 true     -> rc=0, OK"
  TMPD=$(mktemp -d /tmp/plainphone-selftest.XXXXXX)
  echo "SwiftUI: Invalid Configuration detected!" > "$TMPD/dev.log"
  : > "$TMPD/build.log"
  if gate_check 0 "$TMPD/dev.log" "$TMPD/build.log" >/dev/null 2>&1; then
    echo "FAIL: gate missed Invalid Configuration" >&2; rm -rf "$TMPD"; exit 1
  fi
  echo "  gate correctly fails on Invalid Configuration"

  # Clean path must be real and asserted.
  : > "$TMPD/dev2.log"
  echo "TEST SUCCEEDED" > "$TMPD/build2.log"
  if ! gate_check 0 "$TMPD/dev2.log" "$TMPD/build2.log" >/dev/null 2>&1; then
    echo "FAIL: gate rejected a clean run" >&2; rm -rf "$TMPD"; exit 1
  fi
  echo "  gate passes clean run"
  rm -rf "$TMPD"

  # Stale-artifact sweep must reclaim BOTH aged mktemp kinds plus an aged
  # selftest DIRECTORY, while retaining a fresh artifact. Asserted, no silent pass.
  echo "[self-test] stale artifact sweep:"
  # (top-level block: plain variables, no `local`)
  failed=0
  aged_dir=$(mktemp -d /tmp/plainphone-selftest.XXXXXX)
aged_log=$(mktemp /tmp/plainphone-uilog.XXXXXXXXXX)
aged_build=$(mktemp /tmp/plainphone-buildlog.XXXXXXXXXX)
fresh_build=$(mktemp /tmp/plainphone-buildlog.XXXXXXXXXX)
  old_ts=$(date -v-2H +%Y%m%d%H%M)
  touch -t "$old_ts" "$aged_dir" "$aged_log" "$aged_build"
  LOG_AGE_LIMIT=3600 sweep_stale_artifacts
  for f in "$aged_dir" "$aged_log" "$aged_build"; do
    if [[ -e "$f" ]]; then
      echo "FAIL: stale artifact not swept: $f" >&2
      failed=1
    fi
  done
  if [[ ! -e "$fresh_build" ]]; then
    echo "FAIL: fresh artifact was wrongly swept: $fresh_build" >&2
    failed=1
  fi
  rm -rf "$fresh_build"
  if [[ $failed -ne 0 ]]; then exit 1; fi
  echo "  aged dir/log/buildlog swept; fresh buildlog retained, OK"
  echo "SELF-TEST PASS"
  exit 0
fi

sweep_stale_artifacts

SIM="${1:-}"
if [[ -z "$SIM" ]]; then
  SIM=$(xcrun simctl list devices \
       | awk '/\(Booted\)/' \
       | grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
       | head -1)
fi
# Validate UDID shape regardless of source.
if [[ ! "$SIM" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "Usage: $0 [SIM_UDID] (no valid booted simulator found)" >&2
  exit 2
fi
echo "Simulator: $SIM (xcodebuild timeout: ${TIMEOUT}s)"
xcrun simctl bootstatus "$SIM" -b >/dev/null

LOGFILE=$(mktemp /tmp/plainphone-uilog.XXXXXXXXXX)
BUILDLOG=$(mktemp /tmp/plainphone-buildlog.XXXXXXXXXX)
trap 'rm -f "$LOGFILE" "$BUILDLOG"' EXIT

xcrun simctl spawn "$SIM" log stream --style compact >"$LOGFILE" 2>&1 &
LOGPID=$!
sleep 2

cd "$PROJECT_DIR"
TEST_RC=0
run_with_timeout "$TIMEOUT" \
  xcodebuild -project PlainPhone.xcodeproj -scheme PlainPhone \
    -destination "platform=iOS Simulator,id=$SIM" \
    -configuration Debug CODE_SIGNING_ALLOWED=NO test \
    -only-testing:PlainPhoneUITests \
    >"$BUILDLOG" 2>&1 || TEST_RC=$?
kill "$LOGPID" 2>/dev/null || true
sleep 1

grep -E "Test Suite '(All tests|NavigationUITests)' (passed|failed)|TEST (SUCCEEDED|FAILED)" \
  "$BUILDLOG" | tail -4 || true

gate_check "$TEST_RC" "$LOGFILE" "$BUILDLOG"
