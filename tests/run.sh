#!/usr/bin/env bash
# Offline test suite: pure models only. `omarchy plugin validate` runs when
# the CLI is available.
set -euo pipefail
cd "$(dirname "$0")/.."
node tests/test_model.js
node tests/test_places.js
bash -n bin/hotbar
bash -n bin/hotbar-places
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
fi
echo "ok"
