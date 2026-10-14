#!/usr/bin/env bash
# The QML side, offline and headless: every .qml file parses (a syntax error
# once kept a release from loading at all), and the JS models run their key
# checks inside QML's own engine (tests/qml/models.qml), which differs from
# node (no TextDecoder, for one). Uses Qt's `qml` runtime on the offscreen
# platform with no display variables, so nothing can reach a live session.
# Skips when the Qt 6 qml runtime is not installed.
set -euo pipefail
cd "$(dirname "$0")/.."

QML="${QML:-}"
if [[ -z "$QML" ]]; then
  for c in /usr/lib/qt6/bin/qml /usr/lib/qt6/qml-bin /usr/bin/qml6; do [[ -x "$c" ]] && { QML="$c"; break; }; done
fi
if [[ -z "$QML" ]]; then
  echo "QML: skipped (no Qt 6 qml runtime)"
  exit 0
fi

run_qml() {
  env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 "$QML" "$@" 2>&1
}

files=(Hotbar.qml components/*.qml)
out="$(run_qml tests/qml/parse.qml -- "${files[@]}")" || { echo "$out" >&2; echo "FAIL: QML parse" >&2; exit 1; }
grep -E '^qml: parse:' <<<"$out" | sed 's/^qml: parse: /ok   /'

out="$(run_qml tests/qml/models.qml)" || { echo "$out" >&2; echo "FAIL: models in the QML engine" >&2; exit 1; }
grep -E '^qml: V4:' <<<"$out" | sed 's/^qml: /ok   /'
echo "QML: 2 tests passed"
