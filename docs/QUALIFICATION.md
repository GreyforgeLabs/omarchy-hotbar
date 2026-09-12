# Hotbar 0.2.1 — Qualification record

Machine: greyarch — Omarchy 4.0.3-1, Hyprland 0.56.2, Quickshell 0.3.1,
two monitors (DP-2 2560×1440 @1.0, HD-1 1920×1080 @1.0). Date: 2026-09-12.

Evidence comes from `tests/run.sh` (offline), `tests/live/acceptance.sh`
(live shell), and the live runs recorded below.

| Gate | Result | Evidence |
|---|---|---|
| Static | PASS | `bash -n` on all scripts; ShellCheck 0.10.0 clean on `bin/hotbar`, `bin/hotbar-places`, `tests/run.sh`, `tests/test_lifecycle.sh`, `tests/test_retry.sh`, `tests/live/acceptance.sh` (two genuine findings fixed, nothing suppressed); `jq -e . manifest.json`; workflow YAML parses |
| Model | PASS | `test_model.js` 42 tests (identity, MRU, groups, pin-key validation, settings ranges/enums, array caps, favorites/matches, overflow fallback), `test_places.js` 9, `test_registry.js` 6, `test_manifest.js` 8 |
| CLI | PASS | `test_lifecycle.sh` 9 tests (clean/repeat install, regular-file and symlink conflicts preserved, owned uninstall, state cleanup, idempotency, noninteractive `--yes` removal); `test_retry.sh` 3 tests (transient outage retried then action runs once, permanent outage fails cleanly with zero actions, dead shell fails fast) |
| Live shell | PASS | `acceptance.sh`: ALL PASS — surface 246 px before/after 41 windows, pin order stable, 10+10+0+1 grouping, 9 unpinned apps behind Running, MRU cycle, activate, popovers open/switch/close, churn back to baseline |
| Overflow containment | PASS | unknown budget returns at most 6 pins (unit); `fallbackVisibleCount` retains last good budget (unit); cold-start `visiblePinCount` initializes bounded; live bar move showed empty-region transient with no expansion, region recovered to `left` |
| Install/remove/reinstall | PASS | real `hotbar install` idempotent over owned link; `hotbar doctor` all-ok; real `hotbar uninstall` removed owned link, state mirror, and plugin while `~/.local/bin` neighbours and `~/.local/state/omarchy` contents survived; fresh `plugin add` + reinstall re-linked, pins/settings IPC verified, user pins restored to `foot\|YouTube\|chromium` |
| Multi-monitor | PASS | two physical outputs; `screens` reports `DP-2\|HD-1`; `openOn HD-1 running` returned ok and changed 3.06% of HD-1 output pixels (grim before/after diff); `closeOn HD-1` ok; `openOn DP-2 places` confirmed via state; unknown screen rejected with the screen list |
| CI | PASS | `.github/workflows/test.yml` runs the full offline suite plus ShellCheck on push/PR; badge at top of README |

## Security

- No new shell interpolation or command execution: `grep` for `execDetached` shows only argv arrays (`launchArgv`, `actionArgv`, `openArgv` paths); favourites/overrides still cannot carry `exec`/`command`/`args`/`run` (unit-tested at both the model and validation layers).
- Dispatcher addresses still hex-validated (`safeAddress`); desktop ids still path/option-refused (`isDesktopId`).
- `pin`/`unpin`/`setPins` IPC now reject pipe, control-character, and overlong keys; live `pin 'a|b'` returns an error and stores nothing.
- Live `set iconSize 99` and `set iconStyle rainbow` rejected with the allowed range/options; valid values persist.
- Installer refuses unrelated files: live pre-existing link untouched by the old tree; isolated tests prove regular files and foreign symlinks are never overwritten, and uninstall never deletes a path it does not own.

## Functional

Pin/unpin, launch, focus, cycle, Running drawer, Places, Settings, favourites,
identity overrides, close window/close all (via menus), and responsive
overflow all exercised by the live acceptance run except close-all, which was
exercised in 0.2.0 and is unchanged in 0.2.1. `hotbar doctor` now reports CLI
ownership, conflicts, state file, PATH, and IPC liveness; full output all-ok
recorded above.

## Failure behavior

- Malformed settings rejected at the IPC boundary with a message (live).
- Missing desktop entries still get a bounded `class:` cell (unit).
- Invalid and overlong regexes skipped without crashing (unit).
- Vanished windows: popover closes itself (0.2.0 path, unchanged); MRU pruned to live addresses (unit).
- Broken layout discovery stays bounded at last-good-or-6 (unit + live transient observed).
- Plugin hot reload: `ping` answers `ok` after restart; CLI preflight polls ~800 ms and runs the action exactly once (mock tests + live commands succeeding through a restart gap).

## Performance

No new timers, no polling while idle, no daemon. Focus path unchanged:
`visiblePinKeys` still shields pinned cells from rebuilds; `budgetProbe` still
gates the budget. Added only a cache-size guard (drop past 1024 identity
entries). Acceptance timings match 0.2.0 behaviour (246 px surface, instant
recovery after churn). No precision claims beyond that.

## Removal

Real `hotbar uninstall`: owned symlink removed, `hotbar-settings.json`
removed, empty state dir removed only when empty, plugin removed via
`omarchy plugin remove greyforge.hotbar --yes`. Neighbouring `~/.local/bin`
entries and `~/.local/state/omarchy` contents verified untouched. Second and
third runs exit 0 (idempotent).

## Multi-monitor

Two physical outputs exercised (see gate table). Registry unit tests cover
register/lookup/unregister/refuse/same-name replacement.

## Known limitations

- `omarchy bar set … --json` still cannot carry arrays through the shell IPC; use `hotbar set` (unchanged from 0.2.0).
- After a plugin hot-reload the IPC target re-registers after ~400 ms; the CLI now waits this out, but external scripts calling `omarchy-shell hotbar …` directly in that window still need their own retry.
- Hover previews were observed with a warped (not hand-moved) pointer (carried over from 0.2.0).
