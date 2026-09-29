# Hotbar 0.3.0 — Qualification record (addendum over 0.2.5)

0.2.5 gates below remain valid: no change to what the widget shows or how it
is driven. 0.3.0 adds an optional native fast path — a Unix socket served by
the widget plus a C client for the CLI, a C Places helper, and the flame
shimmer as a fragment shader — each with a fallback to the previous
implementation.

Machine: greyarch — Omarchy 4.0.3, Hyprland 0.56.2, Quickshell 0.3.1,
Qt 6.11.2 (qsb from qt6-shadertools 6.11.2), gcc/cc 15. Date: 2026-09-29.
The live session was locked for most of the run, so the widget A/B ran in
an isolated sandbox shell (a real
`qs -p /usr/share/omarchy/shell` with a private HOME) inside a nested
Hyprland on a headless output, as in the 0.2.4/0.2.5 UI passes.

| Gate | Result | Evidence |
|---|---|---|
| Offline suite | PASS | `tests/run.sh` green: model 42, places 9, registry 9 (+3 socket ownership), manifest 8, warp-ui 14, places-native 5, lifecycle 9, retry 3, warp 12, native-cli 7; `bash -n` on every script; `omarchy plugin validate .` |
| Native build | PASS | `make native` with `-std=c11 -Wall -Wextra`, no warnings; `make shaders` regenerates `flame.frag.qsb` byte-identically (SPIR-V + GLSL 100es/120/150 + HLSL + MSL) |
| Static | PASS | ShellCheck 0.11.0 clean on `bin/hotbar`, `bin/hotbar-places`, `tests/run.sh`, `tests/test_lifecycle.sh`, `tests/test_retry.sh`, `tests/test_warp.sh`, `tests/test_native_cli.sh`, `tests/live/acceptance.sh` |
| Socket protocol | PASS | standalone Quickshell prototype: request → one-line reply → server closes; a stale socket file from a dead server is replaced (`quickshell.io.socket: Deleted existing file`); `hotbar-native` exit codes 0/1/2/111/112 exercised |
| Places equivalence | PASS | `tests/test_places_native.js` on this host: identical `exists`, identical `trashHandler`, every findmnt mount present with the same fstype/fsroot/label/partlabel/source and every kernel option; `PlacesModel.buildPlaces` deep-equal from either helper (9 real mounts incl. btrfs subvolumes, ext4 bind mounts, vfat EFI with LABEL and PARTLABEL) |
| Sandbox live | PASS | 0.3.0 loaded in the sandbox shell: `state` reports `nativeSocket` at `$XDG_RUNTIME_DIR/greyforge.hotbar-<sig>.sock` and `nativePlaces: true`, 5 cells; `hotbar-native ping` → `ok`; `setSetting`/`getSetting` through the socket round-trip; pins and Running drawer render as in 0.2.5 (grim from inside the nested session) |
| CLI fallback | PASS | `test_native_cli.sh`: no socket → one `omarchy-shell hotbar activateIndex` and nothing else; hung widget (no answer within the timeout) → error, zero omarchy-shell calls; `HOTBAR_NO_NATIVE=1` → socket never contacted |
| Shader | PASS | `FlamePill` grabbed offscreen from a standalone shell instance on the headless output: minimal and badge, horizontal and vertical, lit and unlit; pill outline, ember glow, amber bar, letter-spaced HOTBAR with the sweep. Sandbox bar crops of 0.2.5 and 0.3.0 match |

## Performance

`tests/bench_native.py` against the sandbox widget, medians of 40 launches,
wall = process lifetime, CPU = child rusage (user+sys):

| Path | 0.2.5 (portable) | 0.3.0 (native) | Ratio |
|---|---|---|---|
| `hotbar pins` end to end | 98.3 ms / 100.0 ms CPU | 7.3 ms / 9.2 ms CPU | 14× / 11× |
| `hotbar activate 1` (preflight + call) | 98.0 ms / 97.5 ms | 6.6 ms / 6.5 ms | 15× / 15× |
| one widget call (`omarchy-shell hotbar ping` → `hotbar-native ping`) | 30.4 ms / 30.1 ms | 0.6 ms / 0.5 ms | 49× / 64× |
| Places helper, 7 paths | 12.4 ms / 12.4 ms | 0.8 ms / 0.7 ms | 16× / 18× |

Shell CPU (`/proc/<pid>/stat` utime+stime over 20 s windows, ‰ of one core),
same sandbox shell, same nested output, same layout:

| Widget | flame on | flame off |
|---|---|---|
| 0.2.5 Canvas, 30 fps | 29, 32, 34 | 0 |
| 0.3.0 shader, 30 fps (intermediate) | 15, 14, 15 | 0 |
| 0.3.0 shader, 24 fps (shipped) | 9, 12, 11 | 0 |

The live shell (DP-2 2560×1440, full widget set) measured 52, 47, 50 ‰ with
0.2.5 and 2–4 ‰ with the flame off before this work. 0.3.0 was loaded into
the live shell with `omarchy restart shell` at 00:37 (socket served,
`hotbar doctor` all ok, live `bench_native.py` within noise of the sandbox
numbers below), but the live flame reading afterwards (1–2 ‰) is **not
comparable**: the session had re-locked with the display DPMS-off, so the
bar was hardly rendering at all. The controlled comparison is the sandbox
table above. What remains with the shader is the bar window re-rendering
per tick; the frame rate is the knob.

Live `bench_native.py` (30 launches, 0.3.0 widget): `hotbar pins`
98.3 → 7.3 ms (13×), `hotbar activate` 97.2 → 6.5 ms (15×), one call
30.1 → 0.6 ms (48×), Places 12.3 → 0.8 ms (16×).

## Security

- The socket lives in the 0700 runtime directory and is served by one
  instance per shell. `serveRequest` dispatches only names in the
  `socketMethods` allowlist to the IpcHandler's own functions, with the
  exact arity qs enforces; unknown names answer `Function not found.`
- The C client refuses arguments containing a newline or 0x1f (the field
  separator) and never interprets the reply beyond passing it through.
- `hotbar-places-native` runs no commands: paths are only ever `stat`ed,
  mount data comes from `/proc/self/mountinfo`, `/run/mount/utab` and
  `readlink` of the udev symlink farms; all strings are JSON-escaped.
- The fallback never repeats a call that may have reached the widget.

# Hotbar 0.2.3 — Qualification record (addendum over 0.2.2)

0.2.2 gates below remain valid: the 0.2.2 CLI/backend behaviour is
unchanged in 0.2.3 except that `warp off|on` short-circuits when the
managed block already holds the requested mode (no backup, no rewrite,
no reload; `tests/test_warp.sh` now 12 tests, still green). 0.2.3 adds
the Settings toggle (`WarpModel.js`, Hotbar.qml warp bridge,
SettingsPopover row), its boundary tests, and docs.

| Gate | Result | Evidence |
|---|---|---|
| UI boundary | PASS | `tests/test_warp_ui.js` 14 tests (disabled→ON, enabled→OFF, unknown indeterminate, toggle ON→`warp off`, toggle OFF→`warp on`, failure restores actual, re-read on open, no polling, existing rows intact, no QML config duplication, inline error, CLI surface unchanged) |
| Regression | PASS | Full `tests/run.sh` green (model, places, registry, manifest, warp-ui, lifecycle, retry, warp) |
| Warp no-op | PASS | Repeat `warp off` with no change reports `already off`, writes no new backup, leaves the file byte-identical, skips `hyprctl reload` (new test 8 in `tests/test_warp.sh`; verified to fail on the pre-fix backend with backup+reload output) |
| Live | PASS | Both directions through the real backend the toggle invokes: `warp on` → `warps enabled` exit 1 (`hyprctl getoption` agrees: no_warps=false, workspace=1); `warp off` → `warps disabled` exit 0; `warp on` again → enabled; `warp off` again for the preferred local config (single managed block, `hotbar doctor` all-ok with `cursor warps disabled`, `hyprctl configerrors` empty). GUI mapping disabled→ON / enabled→OFF is pinned by `test_warp_ui.js`; the popover sends the same argv verified here |

## 0.2.2 record (addendum over 0.2.1)

0.2.1 gates below remain valid: no QML/model changes in 0.2.2, only the
`hotbar` CLI (`warp status|off|on`, `doctor` warp check), docs, and tests.

| Gate | Result | Evidence |
|---|---|---|
| Warp CLI | PASS | `tests/test_warp.sh` 11 tests (managed-block create/idempotent/replace, backup, status exit codes 0/1/2, hand-edit duplicate warning, doctor ok/warn/note) |
| Regression | PASS | Full `tests/run.sh` green (model 42, places 9, registry 6, manifest 8, lifecycle 9, retry 3, warp 11) |
| Live | PASS | `hotbar warp status` → `warps disabled` exit 0 on greyarch; `hotbar doctor` all-ok including `cursor warps disabled` line |

## 0.2.1 record

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
