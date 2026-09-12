#!/usr/bin/env bash
# Retry/preflight tests for the HOTBAR IPC reload gap.
#
# A mocked `omarchy-shell` answers `shell ping` but only starts answering
# `hotbar ping` after N attempts (simulating the short window after a plugin
# reload where the shell is alive but the HOTBAR target is not registered).
# Verifies: preflight retries, the final action runs exactly once, and
# permanent unavailability fails cleanly without running the action.
set -euo pipefail

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "ok   $*"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOTBAR_BIN="$REPO/bin/hotbar"

setup_mock() { # setup_mock <ping-succeeds-after-N> — "never" for permanent outage
  HOME_TMP="$(mktemp -d)"
  export HOME="$HOME_TMP"
  MOCKBIN="$(mktemp -d)"
  export PATH="$MOCKBIN:/usr/bin:/bin"
  export MOCK_STATE="$HOME_TMP/state"
  mkdir -p "$MOCK_STATE"
  echo "$1" >"$MOCK_STATE/after"
  echo 0 >"$MOCK_STATE/pings"
  echo 0 >"$MOCK_STATE/actions"
  cat >"$MOCKBIN/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
state="$MOCK_STATE"
if [[ "$1" == "shell" && "$2" == "ping" ]]; then exit 0; fi
if [[ "$1" == "hotbar" && "$2" == "ping" ]]; then
  n=$(cat "$state/pings"); echo $((n + 1)) >"$state/pings"
  after=$(cat "$state/after")
  if [[ "$after" == "never" ]]; then exit 1; fi
  (( n + 1 >= after )) && { echo ok; exit 0; }
  exit 1
fi
if [[ "$1" == "hotbar" && "$2" == "activate" ]]; then
  n=$(cat "$state/actions"); echo $((n + 1)) >"$state/actions"
  echo ok; exit 0
fi
exit 0
EOF
  chmod +x "$MOCKBIN/omarchy-shell"
}

teardown_mock() { rm -rf "$HOME_TMP" "$MOCKBIN"; }

# 1. preflight retries while the target is briefly gone, then runs once
setup_mock 3
export HOTBAR_PREFLIGHT_INTERVAL=0.05 HOTBAR_PREFLIGHT_ATTEMPTS=10
"$HOTBAR_BIN" activate foot >/dev/null || fail "activate failed after transient outage"
pings=$(cat "$MOCK_STATE/pings"); actions=$(cat "$MOCK_STATE/actions")
(( pings >= 3 )) || fail "preflight did not retry (pings=$pings)"
(( actions == 1 )) || fail "action ran $actions times instead of once"
pass "preflight retries a transient outage and the action runs once (pings=$pings)"
teardown_mock

# 2. permanent unavailability fails cleanly and never runs the action
setup_mock never
export HOTBAR_PREFLIGHT_INTERVAL=0.05 HOTBAR_PREFLIGHT_ATTEMPTS=5
if "$HOTBAR_BIN" activate foot >/dev/null 2>&1; then fail "activate succeeded during a permanent outage"; fi
pings=$(cat "$MOCK_STATE/pings"); actions=$(cat "$MOCK_STATE/actions")
(( pings == 5 )) || fail "preflight did not poll the full bounded period (pings=$pings)"
(( actions == 0 )) || fail "action ran during an outage ($actions times)"
pass "permanent outage fails cleanly after a bounded wait, action never runs"
teardown_mock

# 3. shell itself down fails fast with a clear error
setup_mock 1
cat >"$MOCKBIN/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCKBIN/omarchy-shell"
export HOTBAR_PREFLIGHT_INTERVAL=0.05 HOTBAR_PREFLIGHT_ATTEMPTS=5
err=$("$HOTBAR_BIN" activate foot 2>&1 || true)
[[ "$err" == *"omarchy-shell is not running"* ]] || fail "wrong error for dead shell: $err"
pass "dead shell fails fast with a clear error"
teardown_mock

echo "Retry: $PASS tests passed"
