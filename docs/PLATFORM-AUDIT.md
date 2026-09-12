# Hotbar — Platform Audit (Phase 0)

Audited on greyarch, 2026-09-12, against the *installed* host — not remembered
API details.

| Component | Version |
|---|---|
| Omarchy | 4.0.3-1 |
| Hyprland | 0.56.2 (Lua config, `Hyprland.usingLua` = true) |
| Quickshell | 0.3.1 |
| Qt | 6.x with `QtQuick.Effects` (MultiEffect) available |

Everything below was verified by reading `/usr/share/omarchy/shell/**` or by
running a throwaway Quickshell config that dumped live objects.

## 1. Bar-widget contract

* Manifest: `schemaVersion: 1`, `kinds: ["bar-widget"]`,
  `entryPoints.barWidget`, `barWidget.{displayName,category,defaultSection,
  allowMultiple,defaults,schema}`. Validated by `omarchy plugin validate`.
* The widget is instantiated once **per bar window (per monitor)** inside a
  `ModuleSlot` with `bar`, `moduleName`, `settings` injected. `qs.Ui.BarWidget`
  is the base to extend (`setting(name, fallback)`, `vertical`, `barSize`).
* `settings` is the raw `shell.json` layout entry minus `id`. **Manifest
  `defaults` are not merged in** — the widget applies its own defaults.
  Values may be nested JSON (arrays/objects); `omarchy bar set <id> <key>
  <value> --json` writes JSON values.
* Third-party widgets get a `PluginBarApi` facade as `bar`:
  `foreground`, `barForeground`, `background`, `urgent`, `fontFamily`,
  `position`, `vertical`, `barSize`, `transparent`,
  `foregroundAnimationEnabled`, `activePopout`, `clickTargets`,
  `showTooltip/hideTooltip(target, text)`, `registerClickTarget/unregister`,
  `requestPopout/releasePopout(owner)`, `switchPanelFrom`, `moduleWidgets`,
  `run(command)` (bash string — avoided by Hotbar), and `shell`.
* `bar.shell` is a `PluginShellApi` scoped to our id. The relevant call is
  `updateEntryInline(moduleName, settings)`: it **replaces** the whole layout
  entry (all keys must be passed) and persists atomically through the host's
  own writer. There is **no `shell.shellConfig`** for third parties. This is
  how pins are persisted — no private state store.
* Plugin dir: `Qt.resolvedUrl(".")` (the host strips `__sourceDir` from
  third-party manifests).

## 2. Layout / width budget

`Bar.qml` performs **no overflow handling**: `left` is a `Row` anchored left,
`right` a `Row` anchored right, `center` is centred (optionally around
`centerAnchor`). Sections simply overlap when they collide. Therefore Hotbar
computes its own budget: it locates the three section lists in its bar window
(items carrying `region` + `entries`), reads their geometry, subtracts its own
siblings, and derives how many pinned cells fit. If the sections cannot be
found the budget is "unbounded" (fail soft: show all pins).

Bar sizes: 26 px horizontal, 28 px vertical (`Style.bar.sizeHorizontal /
sizeVertical`, themeable). `Style.bar.iconSlot` = 27, `iconCanvas` = 16.

## 3. Popout coordination

* `bar.requestPopout(owner)` closes the previous owner (`closeForPopoutSwitch()`
  or `close()`) and records the new one; `bar.releasePopout(owner)` clears it.
* `qs.Ui.KeyboardPanel` — the base every first-party click panel uses — is a
  full-screen overlay layer window with outside-click dismissal, bar-strip
  click forwarding (`bar.clickTargets` + `target.triggerPress(button)`), a
  keyboard-focus prime, correct multi-monitor screen selection
  (`anchorWindow.screen`) and inward placement for all four bar positions.
  Hotbar uses it for Places / App / Running popovers.
* `qs.Ui.PopupCard` with `triggerMode: "hover"` is the passive overlay used for
  hover previews (no focus grab). Hotbar gives it a proxy `bar` so hovering
  never steals the coordinator from another widget's open panel.
* `qs.Ui.PanelKeyCatcher` provides Up/Down/j/k/Enter/Space/Esc/x/Tab.

## 4. Window data (Quickshell.Hyprland)

`Hyprland.toplevels` (ObjectModel of `HyprlandToplevel`):

| Property | Notes |
|---|---|
| `address` | hex without `0x` |
| `title` | live |
| `activated` | live focus flag |
| `urgent` | live (from `urgent` event) |
| `workspace` | `HyprlandWorkspace` (`id`, `name`, `monitor`) |
| `monitor` | `HyprlandMonitor` (`name`, `description`) |
| `wayland` | foreign-toplevel handle: **`appId`** (live), `title`, `activate()`, `close()`, `screens` |
| `lastIpcObject` | `hyprctl clients` JSON: `class`, `initialClass`, `pid`, `xwayland`, `floating`, `focusHistoryID`, `stableId` … refreshed only on some events — treat as initial snapshot |

Focus is done with `toplevel.wayland.activate()` (the first-party
`ActiveWindow` widget does the same); it switches workspace/monitor in the
compositor without shell strings. Close = `wayland.close()`.
`Hyprland.rawEvent` delivers `openwindow`, `closewindow`, `activewindowv2`,
`urgent`, `movewindowv2`, `workspacev2`, etc. (`event.name`, `event.data`,
`event.parse(n)`). MRU is seeded from `focusHistoryID` at startup.

## 5. Desktop entries

`DesktopEntries.applications.values` (loads ~1 s after shell start; watch
`valuesChanged`), `DesktopEntries.byId(id)` (exact, with or without
`.desktop`), `DesktopEntries.heuristicLookup(name)`.

`DesktopEntry`: `id`, `name`, `icon`, `execString`, `command` (argv, field
codes removed), `startupClass`, `noDisplay`, `runInTerminal`, `actions[]`
(`id`, `name`, `command`, `execute()`), `execute()`.

Launching: the host uses `uwsm-app -- gtk-launch <id>.desktop`; Hotbar does the
same through `Quickshell.execDetached(argv)` (no shell). Desktop actions run
as `uwsm-app -- <action.command…>`.

Omarchy web apps launch `chromium --app=<url>` → Wayland app id
`chrome-<host>__<path>-<profile>`; their `.desktop` files carry no
`StartupWMClass`, so Hotbar indexes entries by the URL host found in
`--app=` / `omarchy-launch-webapp` Exec lines.

Omarchy TUIs launch as `xdg-terminal-exec --app-id=<id>` (`TUI.float`,
`TUI.tile`, or a custom id) — a custom class *is* the identity.

## 6. Icons

`Quickshell.iconPath(name, true)` → `image://icon/<name>` (empty when the
theme has no such icon). Absolute paths and `file://` are used as-is. The
host's `AppLibrary.iconIndex` fallback is only exposed to `menu` plugins, so
Hotbar falls back through: entry icon → app id → class → generic.

## 7. Theme primitives (qs.Commons)

`Color.foreground/background/accent/urgent/muted`, `Color.bar.*`,
`Color.popups.{background,text,border}`, `Color.tooltip.*`,
`Style.font.{family,caption,bodySmall,body,subtitle,title}`,
`Style.cornerRadius`, `Style.gapsOut`, `Style.space(px)`, `Style.spacing.*`,
`Style.hoverFillFor/selectedFillFor(fg, accent)`, `Border.controlSpec(...)`.
All update live on theme change (FileView-watched).

## 8. Places inputs

* `~/.config/user-dirs.dirs` (`XDG_*_DIR="$HOME/…"`), plus `XDG_PROJECTS_DIR`
  on this machine. `XDG_DESKTOP_DIR="$HOME/"` resolves to Home → omitted.
* `findmnt -J --real -o TARGET,SOURCE,FSTYPE,LABEL,PARTLABEL,OPTIONS` works
  unprivileged and returns labels; output is a nested tree that is flattened.
* Default directory handler here: `com.thisisgm.flea.desktop` (`flea --gui
  %f`, no URI support). No `x-scheme-handler/trash` handler is registered, so
  Trash degrades to opening `~/.local/share/Trash/files`.
* `xdg-open`, `gio`, `gtk-launch`, `uwsm-app`, `jq` are all present.

## 9. Testing

No `qmltestrunner` on the machine; `node` is. Pure logic lives in `.js`
files with a CommonJS export shim (same pattern as Reprieve) and is tested
with node. Live behaviour is exercised against the running shell.

## 10. Competitors

`atagulalan.omapanel` 1.11.0 and `rosakodu.dock` 1.8.17 were installed and
inspected (per-window chips, workspace separators, ~80 settings; a floating
dock with magnification). Useful isolated techniques confirmed:
`ScreencopyView { captureSource: toplevel.wayland }` for thumbnails and
`DesktopEntries.heuristicLookup` for identity. No code was copied. Both were
removed from this machine at the owner's request after the audit.
