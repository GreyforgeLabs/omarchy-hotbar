#!/usr/bin/env bash
# Warp tests for `hotbar warp status|off|on` and the `doctor` warp check.
#
# Isolated: a temporary $HOME plus mocked `hyprctl` (canned getoption
# answers) and `omarchy-shell` (healthy). The real CLI is exercised
# (HOTBAR_BIN). Never touches the real ~/.config/hypr.
set -euo pipefail

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "ok   $*"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOTBAR_BIN="$REPO/bin/hotbar"

setup_home() {
  HOME_TMP="$(mktemp -d)"
  export HOME="$HOME_TMP"
  MOCKBIN="$(mktemp -d)"
  # shellcheck disable=SC2086
  export PATH="$MOCKBIN:/usr/bin:/bin"
  mkdir -p "$HOME/.config/hypr"
}

teardown_home() { rm -rf "$HOME_TMP" "$MOCKBIN"; }

# mock_hyprctl <no_warps> <workspace> [special] — canned getoption answers.
# Use "missing" as $1 to simulate hyprctl absent.
mock_hyprctl() {
  if [[ "${1:-}" == "missing" ]]; then return 0; fi
  local no_warps="$1" ws="$2" special="${3:-0}"
  cat >"$MOCKBIN/hyprctl" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "getoption" ]]; then
  case "\$2" in
    cursor:no_warps) echo "bool: $no_warps"; echo "set: true"; exit 0 ;;
    cursor:warp_on_change_workspace) echo "int: $ws"; echo "set: true"; exit 0 ;;
    cursor:warp_on_toggle_special) echo "int: $special"; echo "set: true"; exit 0 ;;
  esac
  exit 0
fi
if [[ "\$1" == "reload" ]]; then echo ok; exit 0; fi
if [[ "\$1" == "configerrors" ]]; then exit 0; fi
exit 0
EOF
  chmod +x "$MOCKBIN/hyprctl"
}

mock_shell_healthy() {
  cat >"$MOCKBIN/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "shell" && "$2" == "ping" ]]; then exit 0; fi
if [[ "$1" == "hotbar" && "$2" == "ping" ]]; then echo ok; exit 0; fi
if [[ "$1" == "hotbar" && "$2" == "state" ]]; then
  echo '{"region":"left","pins":["foot"],"windows":1}'
  exit 0
fi
exit 0
EOF
  chmod +x "$MOCKBIN/omarchy-shell"
  mkdir -p "$HOME/.config/omarchy/plugins/greyforge.hotbar"
  touch "$HOME/.config/omarchy/plugins/greyforge.hotbar/manifest.json"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(realpath "$HOTBAR_BIN")" "$HOME/.local/bin/hotbar"
}

# A mock hyprctl that answers nothing simulates an unreadable compositor
# (real /usr/bin/hyprctl may still exist, so removal alone is not hermetic).
mock_hyprctl_broken() {
  cat >"$MOCKBIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$MOCKBIN/hyprctl"
}

# 1. warp off creates a managed block and preserves surrounding content
setup_home
mock_hyprctl true 0 0
printf '%s\n' "-- my header" "" "hl.config({ general = { gaps_in = 5 } })" >"$HOME/.config/hypr/looknfeel.lua"
"$HOTBAR_BIN" warp off >/dev/null || fail "warp off failed"
grep -q "BEGIN greyforge.hotbar warp" "$HOME/.config/hypr/looknfeel.lua" || fail "managed begin marker missing"
grep -q "END greyforge.hotbar warp" "$HOME/.config/hypr/looknfeel.lua" || fail "managed end marker missing"
grep -q "no_warps = true" "$HOME/.config/hypr/looknfeel.lua" || fail "warp off did not disable warps"
grep -q "warp_on_change_workspace = 0" "$HOME/.config/hypr/looknfeel.lua" || fail "warp off workspace value wrong"
grep -q "my header" "$HOME/.config/hypr/looknfeel.lua" || fail "surrounding content lost"
grep -q "gaps_in = 5" "$HOME/.config/hypr/looknfeel.lua" || fail "surrounding config lost"
pass "warp off creates a managed disabled block and preserves content"
teardown_home

# 2. warp off is idempotent (single block after two runs)
setup_home
mock_hyprctl true 0 0
printf '%s\n' "-- header" >"$HOME/.config/hypr/looknfeel.lua"
"$HOTBAR_BIN" warp off >/dev/null || fail "first warp off failed"
"$HOTBAR_BIN" warp off >/dev/null || fail "second warp off failed"
(( $(grep -c "BEGIN greyforge.hotbar warp" "$HOME/.config/hypr/looknfeel.lua") == 1 )) || fail "duplicate managed blocks after repeat warp off"
pass "warp off is idempotent"
teardown_home

# 3. warp on replaces the block with Omarchy defaults, still single
setup_home
mock_hyprctl true 0 0
printf '%s\n' "-- header" >"$HOME/.config/hypr/looknfeel.lua"
"$HOTBAR_BIN" warp off >/dev/null || fail "warp off (setup) failed"
mock_hyprctl false 1 0
"$HOTBAR_BIN" warp on >/dev/null || fail "warp on failed"
grep -q "no_warps = false" "$HOME/.config/hypr/looknfeel.lua" || fail "warp on did not restore no_warps=false"
grep -q "warp_on_change_workspace = 1" "$HOME/.config/hypr/looknfeel.lua" || fail "warp on workspace value wrong"
(( $(grep -c "BEGIN greyforge.hotbar warp" "$HOME/.config/hypr/looknfeel.lua") == 1 )) || fail "duplicate blocks after warp on"
pass "warp on restores Omarchy defaults in the same single block"
teardown_home

# 4. warp writes a backup of the previous file
setup_home
mock_hyprctl true 0 0
printf '%s\n' "-- original" >"$HOME/.config/hypr/looknfeel.lua"
"$HOTBAR_BIN" warp off >/dev/null || fail "warp off (backup test) failed"
if ! ls "$HOME"/.config/hypr/looknfeel.lua.bak.* >/dev/null 2>&1; then
  fail "no backup file written"
fi
pass "warp off writes a timestamped backup"
teardown_home

# 5. warp status exit codes: 0 disabled, 1 enabled, 2 unknown
setup_home
mock_hyprctl true 0 0
out="$("$HOTBAR_BIN" warp status)" || fail "warp status (disabled) exited non-zero"
[[ "$out" == *"warps disabled"* ]] || fail "warp status (disabled) wrong text: $out"
pass "warp status reports disabled with exit 0"
mock_hyprctl false 1 0
if out="$("$HOTBAR_BIN" warp status 2>&1)"; then fail "warp status (enabled) exited 0"; fi
[[ "$out" == *"warps enabled"* ]] || fail "warp status (enabled) wrong text: $out"
pass "warp status reports enabled with non-zero exit"
mock_hyprctl_broken
if out="$("$HOTBAR_BIN" warp status 2>&1)"; then fail "warp status (no hyprctl) exited 0"; fi
[[ "$out" == *"unknown"* ]] || fail "warp status (no hyprctl) wrong text: $out"
pass "warp status reports unknown without hyprctl"
teardown_home

# 6. hand-edit outside the block warns but still applies
setup_home
mock_hyprctl true 0 0
printf '%s\n' "hl.config({ cursor = { no_warps = true } })" >"$HOME/.config/hypr/looknfeel.lua"
err="$("$HOTBAR_BIN" warp off 2>&1 >/dev/null)" || fail "warp off with hand-edit failed"
[[ "$err" == *"more than once"* ]] || fail "duplicate hand-edit did not warn: $err"
pass "unmanaged duplicate cursor settings warn"
teardown_home

# 7. doctor: ok when disabled, warn when enabled, note without hyprctl
setup_home
mock_shell_healthy
mock_hyprctl true 0 0
out="$("$HOTBAR_BIN" doctor 2>&1)" || fail "doctor failed when disabled"
[[ "$out" == *"cursor warps disabled"* ]] || fail "doctor did not report disabled warps: $out"
pass "doctor reports ok when warps disabled"
mock_hyprctl false 1 0
out="$("$HOTBAR_BIN" doctor 2>&1)" || fail "doctor failed when enabled"
[[ "$out" == *"cursor warps enabled"* && "$out" == *"hotbar warp off"* ]] || fail "doctor did not warn with fix hint: $out"
pass "doctor warns with fix hint when warps enabled"
mock_hyprctl_broken
out="$("$HOTBAR_BIN" doctor 2>&1)" || fail "doctor failed without hyprctl"
[[ "$out" == *"cannot read Hyprland cursor options"* ]] || fail "doctor did not note unreadable options: $out"
pass "doctor notes unreadable options without hyprctl"
teardown_home

echo "Warp: $PASS tests passed"
