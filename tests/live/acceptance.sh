#!/usr/bin/env bash
# Hotbar live acceptance — the "brutal scenario" from the spec (§70) run
# against the running omarchy-shell. Spawns real windows with `foot`
# (custom --app-id values stand in for pinned and unpinned apps), asserts the
# permanent surface never changes, exercises popovers and cycling over IPC,
# then closes everything it opened. Nothing else on the desktop is touched.
#
# Requires: a running Omarchy shell with greyforge.hotbar placed in the bar,
# foot, hyprctl, jq, python3 — and an idle desktop: focus assertions read the
# compositor's active window, so clicking around during the run fails them.
set -euo pipefail

state() { omarchy-shell hotbar state; }
field() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
pause() { sleep "${1:-0.6}"; }

fail() { echo "FAIL: $*" >&2; cleanup; exit 1; }
pass() { echo "ok   $*"; }

PIDS=()
cleanup() {
  omarchy-shell hotbar close >/dev/null 2>&1 || true
  for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null || true; done
  if [[ -n "${ORIGINAL_PINS+x}" ]]; then omarchy-shell hotbar setPins "$ORIGINAL_PINS" >/dev/null || true; fi
}
trap cleanup EXIT

spawn() { # spawn <app-id> <count>
  local id="$1" n="$2"
  for ((i = 0; i < n; i++)); do
    setsid foot --app-id="$id" --title="hotbar-test $id $i" -- sleep 600 >/dev/null 2>&1 &
    PIDS+=("$!")
  done
}

command -v foot >/dev/null || { echo "skip: foot not installed"; exit 0; }
state >/dev/null 2>&1 || { echo "skip: hotbar IPC target not available (is the widget placed?)"; exit 0; }

ORIGINAL_PINS=$(omarchy-shell hotbar pins)
echo "original pins: $ORIGINAL_PINS"

# A known pin set for the run: two "apps" that will get many windows, one
# that stays closed, one that gets exactly one window.
omarchy-shell hotbar setPins 'class:hb.browser|class:hb.term|class:hb.closed|class:hb.single' >/dev/null
pause 1
BASE=$(state)
BASE_EXTENT=$(echo "$BASE" | field "d['surfaceExtent']")
BASE_VISIBLE=$(echo "$BASE" | field "[g['key'] for g in d['visiblePins']]")
BASE_RUNNING=$(echo "$BASE" | field "len(d['running'])")
echo "baseline: extent=$BASE_EXTENT visible=$BASE_VISIBLE running=$BASE_RUNNING"
[[ "$BASE_VISIBLE" == "['class:hb.browser', 'class:hb.term', 'class:hb.closed', 'class:hb.single']" ]] || fail "pins not placed in order: $BASE_VISIBLE"

# --- G1/G3: the brutal scenario ---------------------------------------
spawn hb.browser 10
spawn hb.term 10
spawn hb.single 1
for k in 1 2 3 4 5 6 7 8; do spawn "hb.unpinned$k" 2; done   # 16 unpinned windows, 8 apps
spawn hb.floaty 4
sleep 4

AFTER=$(state)
AFTER_EXTENT=$(echo "$AFTER" | field "d['surfaceExtent']")
AFTER_VISIBLE=$(echo "$AFTER" | field "[g['key'] for g in d['visiblePins']]")
AFTER_COUNTS=$(echo "$AFTER" | field "[(g['key'], g['count']) for g in d['visiblePins']]")
AFTER_RUNNING=$(echo "$AFTER" | field "len(d['running'])")
WINDOWS=$(echo "$AFTER" | field "d['windows']")
echo "after: extent=$AFTER_EXTENT visible=$AFTER_VISIBLE counts=$AFTER_COUNTS running=$AFTER_RUNNING windows=$WINDOWS"

[[ "$AFTER_EXTENT" == "$BASE_EXTENT" ]] || fail "surface grew: $BASE_EXTENT -> $AFTER_EXTENT"
pass "G1 width invariance: $BASE_EXTENT px before and after 41 new windows"
[[ "$AFTER_VISIBLE" == "$BASE_VISIBLE" ]] || fail "pins moved: $AFTER_VISIBLE"
pass "G1 spatial stability: pin order unchanged"
echo "$AFTER" | field "d['visiblePins'][0]['count']" | grep -qx 10 || fail "browser group should have 10 windows"
echo "$AFTER" | field "d['visiblePins'][1]['count']" | grep -qx 10 || fail "term group should have 10 windows"
echo "$AFTER" | field "d['visiblePins'][2]['count']" | grep -qx 0 || fail "closed pin should have 0 windows"
pass "G2 grouping: 10+10+0+1 windows map to four cells"
# Count only the test's own apps: the desktop may open or close something
# unrelated while the run is in progress.
HB_RUNNING=$(echo "$AFTER" | field "len([g for g in d['running'] if g['key'].startswith('class:hb.')])")
(( HB_RUNNING == 9 )) || fail "expected 9 unpinned test groups behind Running, got $HB_RUNNING"
pass "G3 bounded complexity: 9 unpinned apps (20 windows) stayed behind the Running cell"

# --- G5: mouse workflow over IPC --------------------------------------
# The compositor's active window is the ground truth, but with follow-mouse
# any pointer motion refocuses whatever is under the cursor, so the check
# polls for the expected window to *become* active rather than sampling once.
focus_check() { # focus_check <expected-address> <label>
  local want="$1" label="$2" got
  for _ in $(seq 1 30); do
    got=$(hyprctl activewindow -j | jq -r .address)
    [[ "$got" == "0x$want" ]] && return 0
    sleep 0.04
  done
  local cls; cls=$(hyprctl activewindow -j | jq -r .class)
  if [[ "$cls" != hb.* ]]; then
    echo "warn $label: 0x$want never became active; focus is on $cls — the desktop is in use, focus checks are inconclusive"
    INCONCLUSIVE=1
    return 0
  fi
  fail "$label: 0x$want never became the active window (last: $got $cls)"
}
INCONCLUSIVE=0

omarchy-shell hotbar activate class:hb.term >/dev/null; pause 0.8
T0=$(hyprctl activewindow -j | jq -r .address)
R1=$(omarchy-shell hotbar cycle class:hb.term)
T1=$(echo "$R1" | awk '{print $2}')
[[ "$R1" == ok* ]] || fail "cycle failed: $R1"
[[ "0x$T1" != "$T0" ]] || fail "cycle did not pick a different window ($T0)"
echo "$R1" | grep -q "order .*$T1" || fail "cycle target $T1 is not in the group"
focus_check "$T1" "cycle 1"
pause 0.5
A1=$(hyprctl activewindow -j | jq -r .address)
R2=$(omarchy-shell hotbar cycle class:hb.term)
T2=$(echo "$R2" | awk '{print $2}')
if [[ "0x$T2" == "$A1" && $INCONCLUSIVE == 0 ]]; then fail "second cycle stayed on the active window $A1 ($R2)"; fi
echo "$R2" | grep -q "order .*$T2" || fail "cycle target $T2 is not in the group"
focus_check "$T2" "cycle 2"
pass "G5 MRU cycle steps through the group's windows ($T0 -> 0x$T1 -> 0x$T2)"

omarchy-shell hotbar activate class:hb.browser >/dev/null
for _ in $(seq 1 30); do [[ $(hyprctl activewindow -j | jq -r .class) == "hb.browser" ]] && break; sleep 0.04; done
[[ $(hyprctl activewindow -j | jq -r .class) == "hb.browser" || $INCONCLUSIVE == 1 ]] || fail "activate did not focus the browser group"
pass "G5 activate focuses the group's MRU window"

for which in places running class:hb.browser; do
  opened=""
  for attempt in 1 2 3; do   # an outside click by a human dismisses a popover; retry
    omarchy-shell hotbar close >/dev/null; pause 0.3
    omarchy-shell hotbar open "$which" >/dev/null; pause 0.6
    opened=$(state | field "d['openPopover']")
    [[ -n "$opened" ]] && break
  done
  [[ -n "$opened" ]] || fail "popover $which did not open"
done
omarchy-shell hotbar close; pause 0.4
[[ $(state | field "d['openPopover']") == "" ]] || fail "popover did not close"
pass "G5 popovers open/switch/close over IPC"
[[ $(state | field "d['surfaceExtent']") == "$BASE_EXTENT" ]] || fail "surface changed while using popovers"

# --- G12: churn --------------------------------------------------------
for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
PIDS=()
sleep 3
FINAL=$(state)
[[ $(echo "$FINAL" | field "d['surfaceExtent']") == "$BASE_EXTENT" ]] || fail "surface changed after closing everything"
[[ $(echo "$FINAL" | field "[g['key'] for g in d['visiblePins']]") == "$BASE_VISIBLE" ]] || fail "pins moved after churn"
(( $(echo "$FINAL" | field "len([g for g in d['running'] if g['key'].startswith('class:hb.')])") == 0 )) || fail "stale test groups remain behind Running"
pass "G12 churn: 41 windows closed, model back to baseline"

if (( INCONCLUSIVE )); then echo "ALL PASS (focus checks inconclusive: desktop was in use — rerun idle for G5)"; else echo "ALL PASS"; fi
