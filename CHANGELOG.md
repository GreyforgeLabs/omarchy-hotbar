# Changelog

## 0.2.4 — 2026-09-16

- **Fixed: 0.2.3 did not load.** Quickshell 0.3.1's `Process` has no
  `errorOccurred` signal, so the two `onErrorOccurred` handlers added for
  the warp helpers made the whole widget fail with "Cannot assign to
  non-existent property" (the installed 0.2.2 kept working, which hid it).
  Helper failures are now caught by one-shot watchdog timers that clear
  the busy state and report `unknown` / the inline apply error;
  `tests/test_warp_ui.js` rejects the handler from now on.
- Greyforge Labs identity throughout: the Places cell is the steel hexagon
  mark holding the three pin slots (amber core on the middle pin, cyan seams
  on hover and while a popover is open); every popover opens with the mark,
  a "HOTBAR · GREYFORGE LABS" eyebrow, the title, an amber count chip, and
  a steel rule, and closes with the Greyforge Labs wordmark. The app menu
  shows the app's own icon inside the mark. Settings shows the version in
  its eyebrow and `hotbar doctor` in its footer. Empty drawers show the
  mark instead of bare text. Brand components live in `brand/`.
- Cells press in briefly on click.
- Screenshots in `docs/screenshots/`.

## 0.2.3 — 2026-09-12

- Expose the 0.2.2 cursor-warp control in Hotbar Settings as
  **Keep pointer in place**.
- The toggle reflects the real Hyprland state whenever Settings opens,
  uses the existing safe `hotbar warp off|on` backend, and confirms the
  resulting state after changes.
- Clearly indicates that the setting applies system-wide to Hyprland.
- `hotbar warp off|on` is now a true no-op when the managed block already
  holds the requested mode: it reports `already off|on` and skips the
  backup, the rewrite, and the `hyprctl reload` (repeat runs used to add
  another timestamped backup and disturb the live session for zero
  change). Covered by a new `tests/test_warp.sh` regression test
  (12 tests).

## 0.2.2 — 2026-09-12

- Cursor warps: `hotbar warp status|off|on` plus a `hotbar doctor` warp
  check. Omarchy enables `warp_on_change_workspace` by default and Hyprland
  warps to window center on focus, so every Hotbar click yanked the
  pointer. `warp off` writes one managed block in
  `~/.config/hypr/looknfeel.lua` (backup first, `hyprctl reload`,
  warns on hand-edit duplicates); `warp on` restores Omarchy defaults.
  Covered by `tests/test_warp.sh` (11 tests).

## 0.2.1 — 2026-09-12

- Safe installer: `hotbar install` never overwrites a file it does not own,
  and reports the exact conflicting path. New `hotbar uninstall` removes the
  owned CLI link, the HOTBAR state mirror, and the plugin; both are covered
  by isolated lifecycle tests.
- Validation hardening: one canonical pin-key check (rejects `|`, control
  characters, overlong keys), settings enforce the manifest ranges and enums,
  lists are capped, and command-bearing favourites are dropped.
- IPC reload resilience: new `hotbar ping` target plus a bounded CLI
  preflight, so state-changing commands run exactly once after a hot-reload.
- Bounded overflow: unknown layout budget keeps the last good pin count, or
  at most 6 pins on a cold start — never every pin. Scan retries reset on
  layout, position, and screen changes.
- Offline CI (`.github/workflows/test.yml`) with model, lifecycle, retry,
  manifest-parity, ShellCheck, and syntax gates.
- Qualification refreshed for 0.2.1, including a two-screen live run.

- Hotbar Settings popover: every toggle the widget honours, flipped from
  the bar (appearance, behaviour, visible cells, Places sections).
  Reachable from Places right-click, the Places/App popover rows, the
  `settings` IPC target and `hotbar open settings`.
- Multi-screen IPC: each bar instance registers by screen name
  (`HotbarRegistry.js`); `openOn`/`closeOn`/`screens` forward to the
  sibling on the addressed monitor. CLI gains `--screen <name>`.
- Places cell reworked as a miniature hotbar glyph; active while Places
  or Settings is open.

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
