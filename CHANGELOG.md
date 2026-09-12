# Changelog

## 0.1.1 — 2026-09-12

Audit release: same surface, less work per event.

- Pinned cells are keyed by identity and persist across model rebuilds.
  They were being destroyed and recreated on every focus change (a JS
  array model resets its Repeater), which also dropped hover state,
  tooltips and popover anchors mid-interaction. Shell CPU per focus
  change with 12 windows and 5 pins: ~5 ms → ~0.9 ms (−82 %).
- Icon theme lookups are cached per identity; cache drops on desktop-entry,
  override or theme changes.
- The width budget is recomputed only when the bar's geometry or the pin
  count changes, and its change detector can no longer be fooled by a
  neighbour shifting left exactly as much as it grows.
- Places helper spawns one `jq` instead of one per path and reads the
  mimeapps lists directly instead of running `xdg-mime` (70 ms → 14 ms);
  a 3 s watchdog covers `test -d` on a dead network mount.
- Fixed: an unpinned app's menu now closes when its last window goes
  (the live lookup fell back to the stale group, so it never did).
- Fixed: `setPins`/`pin` reported "could not persist" when the host saw no
  change; two settings writes in quick succession could lose the first.
- Fixed: hover previews no longer reorder under the pointer after a
  thumbnail is clicked; the strip keeps its opening order.
- Hardening: only desktop ids the host can resolve reach `gtk-launch`, and
  an id can never be a path or an option (`../x`, `--foo`).
- `hotbar pins set` with no arguments is an error instead of clearing.
- Menus drop their rows (and thumbnails) when closed; the mono icon shader
  is only instantiated when `iconStyle` is `mono`.

## 0.1.0 — 2026-09-12

First release.

- Places: Home + XDG folders (locale-aware, missing ones omitted),
  favourites, mounted drives (labels preferred, pseudo/system mounts and
  subvolumes filtered, deduplicated), Trash, default file manager.
- Pinned apps: stable order, launch / focus / MRU cycle / wheel cycle /
  middle-click new window / right-click menu with thumbnails / hover
  previews.
- Running drawer: pinned overflow + unpinned apps behind one cell.
- Identity engine: overrides, desktop ids, StartupWMClass, Omarchy web apps
  by host, bounded heuristics, exec names, class fallback, Steam games.
- Responsive width budget computed against the neighbouring bar sections;
  trailing pins collapse into Running.
- All four bar orientations, per-monitor popovers, live theme updates.
- `hotbar` CLI and `omarchy-shell hotbar …` IPC (pin, setPins, setSetting,
  open, activate, identify, state).
- Node test suite for the model; live acceptance script for the §70
  scenario.
