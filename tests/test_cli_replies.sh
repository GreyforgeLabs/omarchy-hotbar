#!/usr/bin/env bash
# CLI argument handling and exit codes against a mocked widget.
#
# A mocked `omarchy-shell` answers the HOTBAR IPC methods the way the widget
# does (including its refusal texts) and logs every call. Verifies that a
# refused call exits 1 with the reason printed, that idempotent answers stay
# successes, and that `--screen` works in any position and is never ignored.
set -euo pipefail

# The portable transport with mocks only; never the live widget socket.
export HOTBAR_NO_NATIVE=1

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "ok   $*"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOTBAR_BIN="$REPO/bin/hotbar"

HOME_TMP="$(mktemp -d)"
MOCKBIN="$(mktemp -d)"
trap 'rm -rf "$HOME_TMP" "$MOCKBIN"' EXIT
export HOME="$HOME_TMP"
export PATH="$MOCKBIN:/usr/bin:/bin"
export MOCK_LOG="$HOME_TMP/calls"

cat >"$MOCKBIN/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "shell" && "$2" == "ping" ]]; then exit 0; fi
[[ "$1" == "hotbar" ]] || exit 0
shift
[[ "$1" == "ping" ]] && { echo ok; exit 0; }
printf '%s\n' "$*" >>"$MOCK_LOG"
case "$1" in
  activate) case "$2" in foot) echo ok ;; boom) exit 3 ;; *) echo unknown ;; esac ;;
  activateIndex) [[ "$2" == 1 ]] && echo ok || echo "no pin $2" ;;
  newWindow) [[ "$2" == foot ]] && echo ok || echo unknown ;;
  pin) [[ "$2" == foot ]] && echo "already pinned" || echo "error: invalid key" ;;
  unpin) echo "not pinned" ;;
  setPins) echo ok ;;
  setSetting) [[ "$2" == iconSize && "$3" == 3138 ]] && echo ok || echo "error: iconSize must be 12..24" ;;
  getSetting) [[ "$2" == iconSize ]] && echo 18 || echo "error: unknown setting: $2" ;;
  open) [[ "$2" == places ]] && echo ok || echo unknown ;;
  openOn) [[ "$2" == DP-2 ]] && echo ok || echo "unknown screen $2 (DP-1, DP-2)" ;;
  closeOn) [[ "$2" == DP-2 ]] && echo ok || echo "unknown screen $2" ;;
  close) ;;
  screens) echo "DP-1|DP-2" ;;
esac
exit 0
EOF
chmod +x "$MOCKBIN/omarchy-shell"

# run <expected-rc> <args...>: runs the CLI, captures stdout+stderr in $OUT.
run() {
  local want="$1"; shift
  : >"$MOCK_LOG"
  local rc=0
  OUT="$("$HOTBAR_BIN" "$@" 2>&1)" || rc=$?
  [[ "$rc" == "$want" ]] || fail "hotbar $* exited $rc, expected $want (output: $OUT)"
}
calls() { cat "$MOCK_LOG"; }

run 0 activate foot
[[ "$OUT" == ok ]] || fail "activate output: $OUT"
run 1 activate nothing-like-it
[[ "$OUT" == unknown ]] || fail "unknown app should print the reply: $OUT"
pass "activate: ok exits 0, an unknown app exits 1 and says so"

run 1 activate 7
[[ "$OUT" == "no pin 7" ]] || fail "activate 7 output: $OUT"
[[ "$(calls)" == "activateIndex 7" ]] || fail "activate 7 called: $(calls)"
run 0 activate 1
pass "activate <n>: an empty slot exits 1"

run 3 activate boom
pass "a transport failure keeps its own exit code"

run 0 new foot
run 1 new nope
pass "new: unknown app exits 1"

run 0 pin foot
[[ "$OUT" == "already pinned" ]] || fail "pin output: $OUT"
run 1 pin 'bad key'
run 0 unpin foot
[[ "$OUT" == "not pinned" ]] || fail "unpin output: $OUT"
pass "pin/unpin: idempotent answers succeed, refusals exit 1"

run 0 set iconSize 18
run 1 set iconSize 99
[[ "$OUT" == "error: iconSize must be 12..24" ]] || fail "set output: $OUT"
run 0 get iconSize
[[ "$OUT" == 18 ]] || fail "get output: $OUT"
run 1 get bogus
pass "set/get: an invalid value or unknown setting exits 1"

run 0 open places
[[ "$(calls)" == "open places" ]] || fail "open places called: $(calls)"
run 1 open nothing
pass "open: unknown app exits 1"

run 0 open places --screen DP-2
[[ "$(calls)" == "openOn DP-2 places" ]] || fail "trailing --screen called: $(calls)"
run 0 open --screen DP-2 places
[[ "$(calls)" == "openOn DP-2 places" ]] || fail "leading --screen called: $(calls)"
run 0 open --screen=DP-2 places
[[ "$(calls)" == "openOn DP-2 places" ]] || fail "--screen= called: $(calls)"
run 1 open places --screen HDMI-9
[[ "$OUT" == "unknown screen HDMI-9 (DP-1, DP-2)" ]] || fail "unknown screen output: $OUT"
pass "open --screen works before or after the popover name"

run 1 open places --screen
[[ -z "$(calls)" ]] || fail "open with a bare --screen reached the widget: $(calls)"
run 1 close --screen
[[ -z "$(calls)" ]] || fail "close with a bare --screen reached the widget: $(calls)"
run 1 open places running
[[ -z "$(calls)" ]] || fail "open with two names reached the widget: $(calls)"
run 1 open
pass "a bare --screen or a stray argument is an error, never ignored"

run 0 close
[[ "$(calls)" == "close" ]] || fail "close called: $(calls)"
run 0 close --screen DP-2
[[ "$(calls)" == "closeOn DP-2" ]] || fail "close --screen called: $(calls)"
run 1 close --screen HDMI-9
pass "close: current bar, a named screen, an unknown screen exits 1"

run 0 screens
[[ "$OUT" == $'DP-1\nDP-2' ]] || fail "screens output: $OUT"
pass "screens lists one monitor per line"

echo "CLIReplies: $PASS tests passed"
