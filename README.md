# Quickshell Config — README (your personal guide)

This is the config for the Quickshell status bar + Quick Settings dropdown.
All the code is heavily commented to help you learn QML. This file explains the
bigger picture: what each file does, how to tweak it, and the QML vocabulary.

## Reloading / Restarting

Quickshell runs this config automatically when you log in (`autostart.lua`
launches `quickshell`). After editing ANY `.qml` file you must reload:

    qsctl reload        # reload the running config
    # or, if that tool is missing:
    pkill quickshell && quickshell &

## Map of this folder

    shell.qml           ENTRY POINT. Builds the whole thing: SystemClock,
                        the hidden QuickSettings window, and one bar per monitor
                        (Variants + PanelWindow). Three-island layout.
    Theme.qml           *THE* file for colors, fonts and sizes. Every other file
                        reads values like `Theme.pillBg` from here. Only file that
                        uses `pragma Singleton`.
    qmldir              Registers every .qml file as a component callable by its
                        filename, e.g. `Pill {}` / `Volume {}`.

    Pill.qml            Basic two-tone capsule: icon | label (bar widgets).
    ActionPill.qml      Same shape but stretches to fill width (QS buttons).
    QuickToggle.qml     Big on/off tile with chevron (Wi-Fi / Bluetooth).
    CustomSlider.qml    Slider tile: icon + draggable track (volume/mic/brightness).
                        Supports `maxValue` (volume boost to 150% — set in Hub.qml),
                        an in-track value label (`displayText`), and scroll-to-adjust.
    CalendarGrid.qml    Month calendar with month nav + today highlight (Hub tab).

    Workspaces.qml      Workspace pips + hyprexpo overview button.
    Volume.qml          Audio volume pill (click = mute, scroll = level).
    Dictation.qml       Speech-to-text (hyprwhspr) mic pill.
    NotificationState.qml Global notifications daemon & store singleton. Implements
                        freedesktop notifications via Quickshell.Services.Notifications,
                        groups alerts by application (e.g. Kitty ×10), and drives the
                        Dynamic Island banner alert.
    Hub.qml             Clock pill that expands into a floating 630×288 pill-shaped
                        window. Reclaims top screen space with a browser-style top tab bar
                        (Calendar, Theme, Notifications, Settings). Ships with:
                        - **Calendar**: Clock, Tabriz weather, and interactive month calendar. Always the default tab on open.
                        - **Theme**: Wallpaper coverflow carousel with peeking corner cards, left/right navigation arrows, and pull-to-drag.
                        - **Notifications**: Unattended alerts grouped by application with count badges (e.g. ×10), expand/collapse history accordion, and clear actions.
                        - **Dynamic Island Banner**: When an alert pops up, the bar clock pill expands smoothly in length, displays the app's icon and message, and automatically shrinks back to the clock pill after 4.5s.
                        - **Settings**: Inline action row (Wi-Fi, Bluetooth, Lock, Sleep, Power) and clean volume/mic/brightness sliders (volume boost to 150% without percentage text).

    QuickSettings.qml   The whole dropdown PanelWindow (3 sub-views).
    README.md           This file. Ignored by quickshell.

## #CHANGE-ME spots (fastest way to customize)

| Want to change…             | Go to…                                     |
|-----------------------------|--------------------------------------------|
| All colors everywhere       | `Theme.qml` — the 10 color slots & aliases |
| Fonts                       | `Theme.qml` — fontText / fontIcons         |
| Bar height / pill height    | `Theme.qml` — barHeight / pillHeight       |
| An icon on the bar          | any `icon: "name"` line                    |
| Material icon glyph set     | https://fonts.google.com/icons (copy the name) |
| Workspace count             | `Workspaces.qml` — the Repeater `model: 5` |
| Which buttons on the bar    | `shell.qml` — the three island RowLayouts  |
| The expanding center widget | `Hub.qml` — clock pill + its floating window |
| Which tab is open           | `Hub.qml` — `currentTab`: "calendar" (default) \| "theme" \| "settings" |
| Volume boost ceiling        | `Hub.qml` — volume `CustomSlider` `maxValue: 1.5` (=150%) |
| The expand animation style  | `Hub.qml` — `animStyle`: "island" (Dynamic Island) \| "drop" \| "pop" \| "curtain" \| "stagger" \| "swing" |
| QuickSettings width         | `QuickSettings.qml` — implicitWidth        |

A color is just hex: `#RRGGBB` or `#AARRGGBB` (AA = opacity 00–FF).
## Mini QML / Quickshell glossary

The concepts below appear over and over in this config. Learn these and you can
read all the files.

- **Component / object** — the `TypeName { ... }` blocks. Creating one means
  "an instance of that type now exists". Nested blocks = child objects.
- **Property** — a named slot of data on an object: `property int count: 5`.
  Reading a property (`Theme.pillHeight`) or setting one (`icon: "tune"`).
- **Binding (the MOST important QML idea)** — when a property's value is an
  *expression* that references other properties, QML re-evaluates it every time
  any of those other properties change. Example: `x: root.value * rail.width`
  keeps the slider ball glued to `value` forever, automatically.
- **id + `root`** — every file gives its top object `id: root`. Inside child
  objects, `root.x` means "go to the top of THIS file and read x". Referencing
  other objects by id (`popup.currentView`, `clock.date`) works across the same
  file or, for things like `Theme`, globally.
- **Signal** — an event: `signal clicked()`. Handling = a handler named
  `on<SignalName>`: `onClicked: { ... }`. This is how parents learn what
  children did.
- **MouseArea** — an invisible click layer. `anchors.fill: parent` makes it
  cover its parent 100%. `cursorShape: Qt.PointingHandCursor` = hand icon.
- **Anchors** — attach something to something else: `anchors.left:
  parent.left`, `anchors.centerIn: parent`, `anchors.fill: parent`. Offsets
  via `anchors.leftMargin: 12`.
- **The two-tone capsule trick (used everywhere)** — two Rectangles glued
  together with anchors; each rounds only its OUTER corners (`topLeftRadius:
  height/2` etc.) and keeps the shared edge flat, forming a split pill.
- **RowLayout / ColumnLayout / GridLayout** — layouts that arrange children.
  `Layout.fillWidth: true` = stretch to fill, `Layout.alignment` = position in
  the cell, `spacing` = gaps between children.
- **Repeater + modelData/index** — `Repeater { model: <list or count> { ... } }`
  clones its child once per item. Inside, `modelData` is the current item and
  `index` its 0-based position. Used for workspace pips and network lists.
- **Flickable** — a scroll area. `contentHeight` is the scrollable content
  height; `clip: true` hides anything that sticks out while scrolling.
- **PanelWindow** — a quickshell window in the panel layer (under normal
  windows). Its `anchors` target the SCREEN. Used for both the bar and the
  dropdown.
- **Process / StdioCollector / SplitParser** — quickshell wrappers for running
  external commands and reading output. StdioCollector = all at once after the
  process ends; SplitParser = line by line while it runs.
- **Quickshell.execDetached(["cmd", "arg"])** — run a command without waiting;
  the standard way to launch programs from the UI.
- **Hyprland.dispatch("...")** — send an IPC command to Hyprland (switch
  workspace, open expo, etc.).
- **States (`? :` and `&&`)** — QML uses JS expressions. `active ?
  Theme.attention : Theme.plum` = "if active then color A else color B".
  `sink ? sink.audio : null` = "if a sink exists give its audio, else null
  (don't crash)".

## File architecture notes

- The bar is built from tiny reusable pieces (`Pill`, `Workspaces`, `Volume`,
  …) assembled in `shell.qml`. Add a new widget like this:
  1. Write `MyWidget.qml` in this folder,
  2. register it in `qmldir` with `MyWidget 1.0 MyWidget.qml`,
  3. use it anywhere: `MyWidget {}`.
- `Theme.qml` is a singleton: no instance needed, just `Theme.valueName`.
- The QuickSettings dropdown is a whole window. It collects data using
  background `Process` blocks (top part of the file) and the UI below just
  displays that data. Change parsing there, not in the UI.
- Old cruft removed during the tidy-up: `Launcher.qml`, `Sandbox.qml` and
  `shell.qml.bak-2026-09-03` were deleted. A full backup lives in
  `/tmp/quickshell-backup-2026-09-06/`.

## Troubleshooting

- Nothing shows after editing? Run `quickshell --no-color` from a terminal:
  it prints errors instead of silently failing. `qmllint *.qml` also checks
  syntax quickly.
- Volume/wifi dropdown empty? Those depend on Pipewire / NetworkManager
  running. Check `systemctl --user status pipewire` and `nmcli device status`.
- Workspace click does nothing → your Hyprland uses different plugin dispatch
  names (`hl.dsp.focus`). Check `hyprctl dispatch docs` / your hypr config.
E.g. `#80FFFFFF` = white at ~50% opacity.