# Changelog

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
