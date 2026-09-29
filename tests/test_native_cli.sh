#!/usr/bin/env bash
# The CLI's native transport: bin/hotbar talks to the widget socket through
# bin/hotbar-native when it answers, never launches omarchy-shell on that
# path, falls back to omarchy-shell exactly once when there is no socket, and
# never repeats a call the widget may have applied.
#
# A Python stand-in plays the widget socket (same wire format as Hotbar.qml's
# SocketServer). Skips when the native client is not built.
set -euo pipefail

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "ok   $*"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOTBAR_BIN="$REPO/bin/hotbar"
NATIVE="$REPO/bin/hotbar-native"

if [[ ! -x "$NATIVE" ]]; then
  echo "NativeCLI: skipped (run make native)"
  exit 0
fi

WORK="$(mktemp -d)"
MOCKBIN="$WORK/bin"
mkdir -p "$MOCKBIN"
export PATH="$MOCKBIN:/usr/bin:/bin"
export HOME="$WORK/home"
mkdir -p "$HOME"
export SHELL_LOG="$WORK/omarchy-shell.log"
: >"$SHELL_LOG"
export HOTBAR_SOCKET="$WORK/widget.sock"
export HOTBAR_NATIVE_TIMEOUT_MS=500
unset HOTBAR_NO_NATIVE

cat >"$MOCKBIN/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$SHELL_LOG"
if [[ "$1" == "shell" && "$2" == "ping" ]]; then exit 0; fi
if [[ "$1" == "hotbar" && "$2" == "ping" ]]; then echo ok; exit 0; fi
echo ok
exit 0
EOF
chmod +x "$MOCKBIN/omarchy-shell"

# Fake widget: answers on the socket, logs requests, and can be told to hang.
cat >"$WORK/widget.py" <<'EOF'
import os, socket, sys, time
path, log, mode = sys.argv[1], sys.argv[2], sys.argv[3]
if os.path.exists(path): os.unlink(path)
s = socket.socket(socket.AF_UNIX)
s.bind(path); s.listen(8)
while True:
    c, _ = s.accept()
    data = b""
    while not data.endswith(b"\n"):
        chunk = c.recv(4096)
        if not chunk: break
        data += chunk
    parts = data.rstrip(b"\n").split(b"\x1f")
    with open(log, "ab") as f: f.write(b"|".join(parts) + b"\n")
    method = parts[0].decode()
    if mode == "hang" and method != "ping":
        time.sleep(2)      # longer than the client timeout
        c.close(); continue
    if method == "ping": reply = b"ok"
    elif method == "pins": reply = b"a|b|c"
    elif method == "activateIndex": reply = b"ok"
    elif method == "state": reply = b'{"region":"left","pins":["a"],"windows":3}'
    else: reply = b"Function not found."
    c.sendall(reply + b"\n"); c.close()
EOF

start_widget() { # start_widget <mode>
  : >"$WORK/requests.log"
  python3 "$WORK/widget.py" "$HOTBAR_SOCKET" "$WORK/requests.log" "$1" &
  WIDGET_PID=$!
  for _ in $(seq 1 50); do [[ -S "$HOTBAR_SOCKET" ]] && break; sleep 0.02; done
  [[ -S "$HOTBAR_SOCKET" ]] || fail "fake widget did not create its socket"
}
stop_widget() { kill "$WIDGET_PID" 2>/dev/null || true; wait "$WIDGET_PID" 2>/dev/null || true; rm -f "$HOTBAR_SOCKET"; }
cleanup() { stop_widget; rm -rf "$WORK"; }
trap cleanup EXIT

# 1. native transport answers; omarchy-shell is never launched
start_widget normal
out="$("$HOTBAR_BIN" pins)"
[[ "$out" == $'a\nb\nc' ]] || fail "pins via native gave: $out"
[[ ! -s "$SHELL_LOG" ]] || fail "omarchy-shell was launched on the native path: $(cat "$SHELL_LOG")"
grep -qx 'pins' "$WORK/requests.log" || fail "pins did not reach the socket"
pass "native transport serves the CLI without launching omarchy-shell"

# 2. arguments travel as discrete fields
"$HOTBAR_BIN" activate 2 >/dev/null
grep -qx 'activateIndex|2' "$WORK/requests.log" || fail "activateIndex did not carry its argument: $(cat "$WORK/requests.log")"
pass "arguments are carried as separate fields"

# 3. the widget's refusal text is reported like qs's, exit 1
if "$HOTBAR_BIN" get nope >/dev/null 2>"$WORK/err"; then
  # getSetting is a real method on the widget; the fake answers "Function not found."
  fail "refused call exited 0"
fi
grep -q 'Function not found' "$WORK/err" || fail "refusal not reported: $(cat "$WORK/err")"
pass "a refusal from the widget is reported and exits nonzero"
stop_widget

# 4. no socket at all: portable path, action runs exactly once
: >"$SHELL_LOG"
"$HOTBAR_BIN" activate 1 >/dev/null || fail "portable fallback failed"
grep -c 'hotbar activateIndex 1' "$SHELL_LOG" | grep -qx 1 || fail "portable path ran the action $(grep -c 'activateIndex' "$SHELL_LOG") times"
pass "without a socket the CLI falls back to omarchy-shell and acts once"

# 5. HOTBAR_NO_NATIVE pins the portable path even when the socket answers
start_widget normal
: >"$SHELL_LOG"
HOTBAR_NO_NATIVE=1 "$HOTBAR_BIN" pins >/dev/null
grep -q 'hotbar pins' "$SHELL_LOG" || fail "HOTBAR_NO_NATIVE did not force omarchy-shell"
[[ ! -s "$WORK/requests.log" ]] || fail "socket was contacted despite HOTBAR_NO_NATIVE"
pass "HOTBAR_NO_NATIVE forces the portable transport"
stop_widget

# 6. a widget that stops answering mid-call is never retried through omarchy-shell
start_widget hang
: >"$SHELL_LOG"
if "$HOTBAR_BIN" activate 1 >/dev/null 2>&1; then fail "hung widget reported success"; fi
[[ ! -s "$SHELL_LOG" ]] || fail "a possibly-applied call was repeated through omarchy-shell"
grep -qx 'activateIndex|1' "$WORK/requests.log" || fail "the call never reached the socket"
pass "a call the widget may have applied is not repeated on the portable path"
stop_widget

# 7. the client itself: exit codes
HOTBAR_SOCKET=/nonexistent "$NATIVE" ping >/dev/null 2>&1 && fail "no socket should fail"
HOTBAR_SOCKET=/nonexistent "$NATIVE" ping >/dev/null 2>&1 || (( $? == 111 )) || fail "no socket should exit 111"
"$NATIVE" $'a\nb' >/dev/null 2>&1 || (( $? == 2 )) || fail "newline argument should exit 2"
"$NATIVE" >/dev/null 2>&1 || (( $? == 2 )) || fail "no method should exit 2"
pass "hotbar-native exit codes: 111 no socket, 2 usage"

echo "NativeCLI: $PASS tests passed"
