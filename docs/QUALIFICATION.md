# Hotbar 0.1.0 — Qualification record

Machine: greyarch — Omarchy 4.0.3-1, Hyprland 0.56.2, Quickshell 0.3.1,
one monitor (DP-2, 2560×1440 @1.0), theme `greyforge` (dark) and
`flexoki-light` (light). Date: 2026-09-12.

Evidence comes from `tests/run.sh` (offline), `tests/live/acceptance.sh`
(live shell) and manual runs recorded below. "Manual" means a screenshot or
IPC read that was checked by hand during the session.

| Gate | Result | Evidence |
|---|---|---|
| G0 Architecture | PASS | normal `bar-widget` plugin, no daemon; renderer consumes `pinnedGroups` / `runningGroups` only; there is no per-window cell type anywhere in the tree |
| G1 Spatial stability | PASS | `acceptance.sh`: surface 246 px before and after 41 new windows; pin order identical; back to baseline after closing them |
| G2 Application identity | PASS (matrix) | 32 node tests over the identity engine covering native, XWayland-style class, Electron (`StartupWMClass`), Chromium, Omarchy web apps by host, installed PWAs (`crx_`), custom terminal classes, class ≠ initialClass, Steam games, missing entries, raw commands, overrides, invalid overrides. Live: `hotbar identify` shows `foot`, `chromium`, `com.thisisgm.flea` resolving by desktop id; test app ids fall back to `class:` keys |
| G3 Bounded complexity | PASS | `acceptance.sh`: 9 unpinned apps (20 windows) → Running only; 63 pins → 44 visible + 19 in the drawer with no growth beyond the budget |
| G4 Places | PASS | live: Home + 5 XDG folders (Desktop omitted because it resolves to `$HOME/`), three drives (`/home/greyforge`, `/mnt/greyforge-data`, NTFS USB stick with its label), Trash via the files directory (no `trash:` handler on this machine), Open File Manager; `xdg-open ~/Downloads` opened Flea; favourites with unicode + quotes, `exec` fields rejected, missing paths dropped |
| G5 Mouse UX | PASS / hover manual | IPC: launch-or-focus, MRU cycle, drawer cycle, popovers open/switch/close. Previews: logic exercised (timer → open) but the strip could only be observed while the pointer was in use by the owner; needs one idle-desktop hover check before tagging |
| G6 Responsive layout | PASS | budget derived from the real neighbouring sections; with 63 pins Hotbar stopped ~80 px short of the right-hand widgets and pushed nothing |
| G7 Orientation | PASS | screenshots for all four positions: indicators sit on the inner edge, popovers open inward, cells stack on vertical bars |
| G8 Multi-monitor | by construction | popovers are `KeyboardPanel`s bound to the anchor's own bar window (`anchorWindow.screen`); the machine has one monitor, so not exercised |
| G9 Theme | PASS | dark `greyforge` and light `flexoki-light`: bar cells, indicators, popover surface/border/text all followed the theme live without a restart |
| G10 Performance | PASS | shell CPU over 10 s idle: 8 ticks without Hotbar vs 2 ticks with it (noise); no timers run while idle; the Places helper runs once per open and exits |
| G11 Security | PASS | no `run()`/bash strings anywhere; launches are argv; window actions are `hl.dsp.*` dispatchers with a hex-validated address; `openArgv` refuses non-paths; favourites/overrides cannot carry commands (tests) |
| G12 Failure containment | PASS | 41-window churn; popover open while its group vanished closes itself; invalid regex/JSON/settings rejected with a message; missing icons fall back to a glyph; earlier crash (thumbnails recreated mid-frame) fixed by signature-gated row rebuilds and one-shot captures |
| G13 Removal | PASS | `omarchy plugin remove greyforge.hotbar --yes`: no process, no service, no plugin dir, no layout entry, Hyprland untouched. Only `~/.local/state/omarchy/hotbar-settings.json` (the pin mirror) remains, documented in README |
| G14 Competitive | PASS (design), see note | OmaPanel 1.11 (per-window chips, ~80 settings) and rosakodu.dock 1.8 were audited before removal; under the same 41-window load a per-window taskbar grows by >1000 px while Hotbar stays at 246 px. A same-day side-by-side screenshot was not recorded because the owner asked for both to be removed |

## Known limitations

- Hover previews were verified by logic and IPC state but not observed with a
  human pointer during this session (the desktop was in use).
- `omarchy bar set … --json` cannot carry arrays through the shell IPC; use
  `hotbar set` (hex-encoded JSON over Hotbar's own target).
- After a plugin hot-reload (`omarchy plugin update`) the shell's IPC target
  is re-registered after ~400 ms; scripts should not call it in that window.
- `Hyprland.activeToplevel` is null until the first focus change after the
  shell starts; Hotbar seeds focus from `wayland.activated` / focus history,
  so the first click still behaves correctly.
