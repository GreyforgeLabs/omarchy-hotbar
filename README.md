# Hotbar

**Hotbar gives Omarchy fixed app slots, filesystem Places, and one bounded drawer for everything else. Open fifty windows. Your bar stays put.**

```
[📁] │ [🌐] [>_] [T3] [🎵] │ [⋯]
```

Hotbar is a native Omarchy bar widget for people who reach for the mouse. It
is not a taskbar clone and not a dock. It is a small row of stable targets:

- **Places** — Home, your XDG folders, favourites, mounted drives, Trash, and
  the default file manager. One click to any of them.
- **Pinned apps** — apps you chose, in the order you chose. Launch, focus,
  cycle, preview. They never move because something else opened.
- **Running** — one cell holding every unpinned app and every pin that did
  not fit. Thirty stray windows cost you one icon.

One application is always one cell, whether it has zero windows or twenty.
Window titles never touch the bar. When the bar gets crowded, Hotbar gives
space back before it collides with anything else.

## Install

```bash
omarchy plugin add https://github.com/GreyforgeLabs/omarchy-hotbar.git --enable
omarchy bar move greyforge.hotbar --section left --index 1   # next to the Omarchy menu
```

First run shows `📁 ⋯`. Pin things from the Running drawer (right-click a
row, or right-click an app → *Pin to Hotbar*), or from a terminal:

```bash
~/.config/omarchy/plugins/greyforge.hotbar/bin/hotbar pin chromium
```

Requires Omarchy 4.x (Quattro) with Hyprland ≥ 0.53 in Lua-config mode.

## Using it

| Target | Left | Middle | Right | Wheel | Hover |
|---|---|---|---|---|---|
| Places | open Places | open Home in the file manager | — | — | tooltip |
| App | launch · focus MRU window · cycle windows | new window | app menu | cycle windows | tooltip, then live previews |
| Running | open drawer | — | open drawer | cycle drawer windows | tooltip |

**App menu** (right-click): every window with a thumbnail and its
workspace/monitor, then *New Window*, *Pin/Unpin*, *Move Left/Right*, *Close
Current Window*, *Close All*. Middle-click a window row to close it.

**Running drawer**: pinned overflow first, then unpinned apps. Left click
focuses (same MRU rules as a pin), right click or → opens that app's menu,
middle click pins it.

**Keyboard** inside any popover: ↑/↓ or j/k move, Enter opens, → opens a
submenu, x closes the window under the cursor, Home/End jump, Esc closes.

## Settings

Everything lives in the widget's entry in `~/.config/omarchy/shell.json`.
Change values with the CLI (it validates them) — `omarchy bar set` cannot
carry arrays through the shell's IPC:

```bash
hotbar set iconSize 20
hotbar set iconStyle mono
hotbar set favorites '[{"name":"Projects","path":"~/Projects"},{"name":"Forge","path":"/mnt/forge"}]'
hotbar set matches   '[{"name":"Discord","matchClass":"^chrome-discord\\.com.*$","desktopId":"discord"}]'
hotbar get pins
```

| Key | Default | Meaning |
|---|---|---|
| `pins` | `[]` | identity keys in order: desktop ids (`chromium`) or `class:<app id>` |
| `matches` | `[]` | identity overrides: `{ matchClass, desktopId?, name?, icon? }` (regex, case-insensitive) |
| `favorites` | `[]` | Places favourites: `{ name?, path }` — paths only, `~` allowed |
| `iconSize` | `18` | 12–24 px |
| `spacing` | `2` | px between pinned cells |
| `iconStyle` | `color` | `color` or `mono` (tinted with the bar foreground) |
| `runningIndicator` | `underline` | `underline`, `dot`, `none` |
| `separators` | `true` | thin rules between Places · pins · Running |
| `previews` | `true` | hover previews for multi-window apps |
| `previewDelay` | `450` | ms |
| `animations` | `true` | |
| `wheelCycle` | `true` | mouse wheel cycles windows |
| `middleClick` | `new-window` | or `none` |
| `showPlaces` / `showRunning` | `true` | |
| `responsive` | `true` | collapse trailing pins into Running before crowding other widgets |
| `showDesktop` … `showVideos`, `showTrash`, `showMounts` | `true` | Places sections |

There is deliberately no exec/command field anywhere. Favourites are paths;
overrides name a desktop id. Nothing in the configuration can run a command.

## How identity works

Every window is mapped to one *application group*, in this order:

1. your `matches` override
2. desktop id equal to the Wayland app id / class (case-insensitive)
3. a desktop entry's `StartupWMClass`
4. Chromium/Omarchy web apps: `chrome-<host>__…` → the desktop entry that
   opens that host (`omarchy-launch-webapp https://host/` or `--app=`)
5. Quickshell's heuristic lookup, accepted only when the hit plausibly
   names the app
6. the executable name in `Exec`
7. the entry name equal to the class
8. otherwise the class itself (`class:tui.float`) — a custom terminal
   class stays its own app; Steam games (`steam_app_*`) stay separate and
   are named by their title

`hotbar identify` prints the decision for every open window, which is what
you need to write an override.

## CLI

`bin/hotbar` — `pin`, `unpin`, `pins [set …|clear]`, `open`, `close`,
`activate`, `identify`, `set`, `get`, `state`, `install`, `doctor`. It only
talks to the widget's `hotbar` IPC target (`omarchy-shell hotbar …`).

## Behaviour guarantees

- One app = one cell. Window count, titles and tabs never change the bar.
- Pins never reorder on their own.
- Unpinned apps never take permanent space.
- Popovers open inward on the monitor whose bar you clicked; top, bottom,
  left and right bars all work.
- Idle cost is zero: no polling, no daemon, no filesystem crawling. Places
  runs one short helper (`findmnt` + `test -d`) when it opens.
- Security: no `sudo`, no network, no telemetry, no shell interpolation —
  every launch is an argv array, every window action is a Hyprland
  dispatcher with a sanitised hex address.
- Failure containment: a missing desktop entry, unplugged mount, dead
  favourite, malformed config or vanished window degrades to "not shown",
  never to a crash or a config rewrite.

## Uninstall

```bash
omarchy plugin remove greyforge.hotbar
```

Nothing else is left behind: no process, no service, no root files, no
Hyprland changes. The widget's settings live inside `shell.json` and follow
Omarchy's normal handling of removed widgets.

## Development

```bash
node tests/test_model.js && node tests/test_places.js   # pure model, no shell needed
tests/live/acceptance.sh                               # the §70 "brutal scenario" against the live shell
```

See `docs/PLATFORM-AUDIT.md` for what the host actually provides and
`docs/QUALIFICATION.md` for the release-gate record.

MIT — Hotbar by Greyforge Labs.
