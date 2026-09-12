#!/usr/bin/env bash
# Offline test suite: pure models plus isolated CLI lifecycle tests.
# `omarchy plugin validate` runs when the CLI is available.
set -euo pipefail
cd "$(dirname "$0")/.."
node tests/test_model.js
node tests/test_places.js
node tests/test_registry.js
node tests/test_manifest.js
bash tests/test_lifecycle.sh
bash tests/test_retry.sh
bash tests/test_warp.sh
bash -n bin/hotbar
bash -n bin/hotbar-places
bash -n tests/test_warp.sh
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
fi
echo "ok"
