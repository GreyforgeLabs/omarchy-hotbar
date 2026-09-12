#!/usr/bin/env bash
# Lifecycle tests for `hotbar install` / `hotbar uninstall`.
#
# Isolated: a temporary $HOME, mocked `omarchy` / `omarchy-shell`, and an
# isolated $PATH. The real CLI is exercised (HOTBAR_BIN), never the
# ornament in ~/.local/bin.
set -euo pipefail

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "ok   $*"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOTBAR_BIN="$REPO/bin/hotbar"

export HOME_TMP
HOME_TMP="$(mktemp -d)"
export HOME="$HOME_TMP"
export XDG_STATE_HOME="$HOME/.local/state"

MOCKBIN="$(mktemp -d)"
export PATH="$MOCKBIN:/usr/bin:/bin"

# Mock omarchy: record plugin removals, pretend bar moves work.
cat >"$MOCKBIN/omarchy" <<'EOF'
#!/usr/bin/env bash
echo "omarchy $*" >>"$MOCK_HOME_LOG"
if [[ "$1" == "plugin" && "$2" == "remove" ]]; then
  # noninteractive flag required
  [[ "$*" == *"--yes"* ]] || { echo "mock omarchy: missing --yes" >&2; exit 1; }
  rm -rf "$HOME/.config/omarchy/plugins/greyforge.hotbar"
fi
exit 0
EOF
# Mock omarchy-shell: healthy shell + answering HOTBAR target.
cat >"$MOCKBIN/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "shell" && "$2" == "ping" ]]; then exit 0; fi
if [[ "$1" == "hotbar" && "$2" == "ping" ]]; then echo ok; exit 0; fi
if [[ "$1" == "shell" && "$2" == "setPluginEnabled" ]]; then exit 0; fi
exit 0
EOF
chmod +x "$MOCKBIN/omarchy" "$MOCKBIN/omarchy-shell"
export MOCK_HOME_LOG="$HOME_TMP/mock.log"
touch "$MOCK_HOME_LOG"

# A fake "installed" HOTBAR plugin dir so uninstall has something to remove.
PLUGIN_DIR="$HOME/.config/omarchy/plugins/greyforge.hotbar"
mkdir -p "$PLUGIN_DIR"

run_hotbar() { "$HOTBAR_BIN" "$@"; }

# 1. clean install creates the symlink
run_hotbar install >/dev/null
[[ -L "$HOME/.local/bin/hotbar" ]] || fail "install did not create the symlink"
[[ "$(readlink "$HOME/.local/bin/hotbar")" == "$(realpath "$HOTBAR_BIN")" ]] || fail "symlink points elsewhere"
pass "clean install creates the symlink"

# 2. repeated install succeeds (idempotent)
run_hotbar install >/dev/null || fail "repeated install failed"
[[ -L "$HOME/.local/bin/hotbar" ]] || fail "repeated install lost the symlink"
pass "repeated install succeeds"

# 3. unrelated regular file is never overwritten
rm "$HOME/.local/bin/hotbar"
echo "mine" >"$HOME/.local/bin/hotbar"
if run_hotbar install >/dev/null 2>&1; then fail "install overwrote an unrelated regular file"; fi
[[ "$(cat "$HOME/.local/bin/hotbar")" == "mine" ]] || fail "unrelated file was modified"
pass "unrelated regular file is never overwritten"

# 4. unrelated symlink is never overwritten
rm "$HOME/.local/bin/hotbar"
ln -s /bin/true "$HOME/.local/bin/hotbar"
if run_hotbar install >/dev/null 2>&1; then fail "install overwrote an unrelated symlink"; fi
[[ "$(readlink "$HOME/.local/bin/hotbar")" == "/bin/true" ]] || fail "unrelated symlink was modified"
pass "unrelated symlink is never overwritten"

# 5. uninstall removes an owned HOTBAR symlink
rm "$HOME/.local/bin/hotbar"
ln -s "$(realpath "$HOTBAR_BIN")" "$HOME/.local/bin/hotbar"
mkdir -p "$(dirname "$(XDG_STATE_HOME="$HOME/.local/state" "$HOTBAR_BIN" doctor >/dev/null 2>&1; echo "$HOME/.local/state/omarchy/hotbar-settings.json")")"
echo '{"pins":["foot"]}' >"$HOME/.local/state/omarchy/hotbar-settings.json"
# neighbouring state that must survive
mkdir -p "$HOME/.local/state/omarchy"
echo '{"other":true}' >"$HOME/.local/state/omarchy/other-plugin.json"
run_hotbar uninstall >/dev/null || fail "uninstall of owned resources failed"
[[ ! -e "$HOME/.local/bin/hotbar" && ! -L "$HOME/.local/bin/hotbar" ]] || fail "uninstall did not remove the owned symlink"
pass "uninstall removes an owned HOTBAR symlink"

# 6. uninstall preserves an unrelated path
ln -s /bin/true "$HOME/.local/bin/hotbar"
mkdir -p "$PLUGIN_DIR"
run_hotbar uninstall >/dev/null || fail "uninstall with unrelated path failed"
[[ "$(readlink "$HOME/.local/bin/hotbar")" == "/bin/true" ]] || fail "uninstall removed an unrelated path"
pass "uninstall preserves an unrelated path"
rm "$HOME/.local/bin/hotbar"

# 7. uninstall removes HOTBAR state but keeps the shared dir contents
echo '{"pins":["foot"]}' >"$HOME/.local/state/omarchy/hotbar-settings.json"
mkdir -p "$PLUGIN_DIR"
run_hotbar uninstall >/dev/null || fail "uninstall (state removal) failed"
[[ ! -e "$HOME/.local/state/omarchy/hotbar-settings.json" ]] || fail "HOTBAR state file survived uninstall"
[[ -f "$HOME/.local/state/omarchy/other-plugin.json" ]] || fail "uninstall touched a neighbour's state"
pass "uninstall removes HOTBAR state"

# 8. uninstall is idempotent
run_hotbar uninstall >/dev/null || fail "second uninstall failed"
run_hotbar uninstall >/dev/null || fail "third uninstall failed"
pass "uninstall is idempotent"

# plugin removal used the noninteractive flag and removed the plugin dir
mkdir -p "$PLUGIN_DIR"
run_hotbar uninstall >/dev/null || fail "uninstall (plugin removal) failed"
[[ ! -e "$PLUGIN_DIR" ]] || fail "plugin dir survived uninstall"
grep -q "plugin remove greyforge.hotbar.*--yes" "$MOCK_HOME_LOG" || fail "plugin removal did not use --yes"
pass "plugin removal is noninteractive and removes the plugin"

rm -rf "$HOME_TMP" "$MOCKBIN"
echo "Lifecycle: $PASS tests passed"
