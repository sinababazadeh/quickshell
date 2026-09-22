// =============================================================================
//  HUB.QML — the ONE widget that owns the shell's floating windows
// =============================================================================
//  THE IDEA
//  --------
//  One bar widget, one floating window, MANY tabs. The Hub is the single
//  place every window we build plugs into. Right now it ships with two tabs:
//
//    • Settings  — the QuickSettings control-center (power actions, volume/mic/
//      brightness sliders, Wi-Fi / Bluetooth toggles), embedded right in the Hub.
//    • Calendar  — a live clock + Tabriz weather on the left, and a month
//      calendar on the right.
//
//  Tabs are little capsule "pips" at the top of the card, styled exactly like
//  the workspace pips on the bar.
//
//  THE SIZE
//  --------
//  630×450 window; the card fills it edge-to-edge (no dead click zones around
//  it), still centered under the bar via the computed margin in `popup.margins`.
//
//  THE TWO STATES
//  ----------------
//  • IDLE (bar)       — a clock pill; click to expand.
//  • EXPANDED (window)— the tabbed card. Opens on the CALENDAR tab by default;
//    click anywhere outside the window (HyprlandFocusGrab) or the pill again
//    to close. Five expand animations (drop/pop/curtain/stagger/swing) are
//    switchable via `animStyle`.
// =============================================================================
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Pill {
    id: root

    // ─── Public surface ─────────────────────────────────────────────────────────
    property var screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    readonly property bool open: popup.visible
    property bool closing: false              // true while the close animation plays

    // Which "expand" animation to use: "drop" | "pop" | "curtain" | "stagger" | "swing".
    property string animStyle: "drop"

    // Window geometry — the card FILLS the window (no dead click zones around it).
    readonly property int hubW: 630
    readonly property int hubH: 450

    // ─── Tabs ───────────────────────────────────────────────────────────────────
    // The hub opens on the calendar face by default; "settings" is the other tab.
    property string currentTab: "calendar"   // "settings" | "calendar"

    // ─── Settings sub-pages (opened by the toggle ">" chevrons) ──────────────────
    // "main" = sliders/toggles · "wifi"/"bluetooth" = the detail lists.
    // The pages live as extra children of the tab StackLayout (see below).
    property string hubPage: "main"
    property var wifiNetworks: []            // parsed nmcli scan: {active, ssid, signal, security}
    property var btDevices: []               // parsed bluetoothctl devices: {mac, name}
    property bool isScanning: false          // shared "please wait" flag for both scanners
    property var wallpapers: []              // image paths in the wallpapers folder (Theme tab)

    // ─── Theme tab: manage view (opened with the cog) ────────────────────────────
    property string themePage: "picker"      // "picker" | "manage"
    property string editingPath: ""          // wallpaper whose palette slot is being edited
    property string editingSlot: "attention" // which palette slot is being edited
    property string hoveredSlot: ""          // slot currently hovered over (for dynamic name reveal)

    function slotRoleName(slot) {
        switch (slot) {
            case "bg":        return "Base Background"
            case "indigo":    return "Elevated Surface"
            case "violet":    return "Secondary Surface"
            case "primary":   return "Primary Capsule"
            case "attention": return "Accent & Active"
            case "plum":      return "Icon Badge"
            case "ink":       return "Main Text / Ink"
            case "cream":     return "Secondary Text"
            case "lavender":  return "Muted Text"
            default:          return slot || "Color Slot"
        }
    }

    // ─── Weather ────────────────────────────────────────────────────────────────
    property string weatherLocation: ""      // empty = auto-detect by IP; or set e.g. "tabriz", "London"
    property string weatherCondition: "—"
    property string weatherTemp: "—"
    property string weatherHumidity: "—"
    property string weatherWind: "—"
    property bool weatherOK: false

    // ─── Live audio references (pipewire) ───────────────────────────────────────
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // ─── Device state (brightness / radios) ─────────────────────────────────────
    property real brightnessVal: 0.8
    property real brightnessMax: 937
    property bool wifiActive: true
    property bool btActive: true

    // ─── Self-contained clock ───────────────────────────────────────────────────
    SystemClock {
        id: clock
        precision: SystemClock.Minutes   // refresh once a minute, not every ms
    }

    // =============================================================================
    //  BACKGROUND DATA COLLECTORS  (same pattern as QuickSettings.qml)
    // =============================================================================
    //  1. Screen brightness reader — one shell call: "cur/max".
    Process {
        id: brightProc
        command: ["bash", "-c", "echo \"$(brightnessctl get)/$(brightnessctl max)\""]
        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split("/")
                if (parts.length >= 2) {
                    let current = parseInt(parts[0])
                    let max = parseInt(parts[1])
                    if (!isNaN(current) && !isNaN(max) && max > 0) {
                        root.brightnessMax = max
                        root.brightnessVal = Math.min(1.0, current / max)
                    }
                }
            }
        }
    }

    //  2. Wi-Fi radio state  ("enabled" | "disabled")
    Process {
        id: wifiStateProc
        command: ["bash", "-c", "nmcli radio wifi"]
        stdout: SplitParser {
            onRead: data => { root.wifiActive = data.trim().toLowerCase().startsWith("enabled") }
        }
    }

    //  3. Bluetooth powered state  ("on" | "off")
    Process {
        id: btStateProc
        command: ["bash", "-c", "bluetoothctl show | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: SplitParser {
            onRead: data => { root.btActive = (data.trim() === "on") }
        }
    }

    //  4. Wi-Fi scanner (nmcli) — feeds the Wi-Fi sub-page (">" on the tile).
    //  Rescans, then dumps a ":"-separated table, one network per line:
    //      *:My WiFi:75:WPA2     ("*" = currently connected)
    Process {
        id: wifiScanner
        command: ["bash", "-c", "nmcli device wifi rescan 2>/dev/null; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list"]

        // StdioCollector buffers ALL output and fires once — we need the whole
        // table before parsing, so waitForEnd is right for this one.
        stdout: StdioCollector {
            id: wifiListCollector
            waitForEnd: true
            onDataChanged: {
                let lines = wifiListCollector.text.trim().split("\n")
                let list = []
                for (let line of lines) {
                    if (!line.trim()) continue                 // skip blank lines
                    let parts = line.split(":")                // ":"-separated columns
                    if (parts.length >= 3) {
                        let active = parts[0].trim() === "*"   // "*" = connected
                        let ssid = parts[1].trim().replace(/\\:/g, ":")  // nmcli escapes ":" as "\:"
                        let signal = parseInt(parts[2]) || 0   // 0–100
                        let security = parts[3] || ""          // WPA2 / "" for open

                        // Skip hidden/empty SSIDs and duplicate entries.
                        if (ssid !== "" && !list.some(item => item.ssid === ssid)) {
                            list.push({ active: active, ssid: ssid, signal: signal, security: security })
                        }
                    }
                }
                // Connected network first, then strongest signal.
                list.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
                root.wifiNetworks = list
                root.isScanning = false
            }
        }
    }

    //  5. Bluetooth scanner (bluetoothctl) — feeds the Bluetooth sub-page.
    //  4 seconds of active discovery, then list known devices. `devices`
    //  prints lines like:  Device  AA:BB:CC:DD:EE:FF  My Headphones
    Process {
        id: btScanner
        command: ["bash", "-c", "bluetoothctl --timeout 4 scan on >/dev/null 2>&1; bluetoothctl devices"]
        stdout: StdioCollector {
            id: btListCollector
            waitForEnd: true
            onDataChanged: {
                let lines = btListCollector.text.trim().split("\n")
                let list = []
                for (let line of lines) {
                    let match = line.match(/^Device\s+([0-9A-Fa-f:]+)\s+(.+)$/)
                    if (match) {
                        let mac = match[1].trim()    // AA:BB:CC:DD:EE:FF
                        let name = match[2].trim()   // human-readable name
                        if (!list.some(item => item.mac === mac)) {
                            list.push({ mac: mac, name: name })
                        }
                    }
                }
                root.btDevices = list
                root.isScanning = false
            }
        }
    }

    //  6. Wallpaper scanner (find) — feeds the Theme tab's wallpaper picker.
    //  Top level of the config's wallpapers folder only.
    Process {
        id: wallScanProc
        command: ["bash", "-c",
                  "find \"$HOME/.config/quickshell/wallpapers\" -maxdepth 1 -type f "
                  + "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' "
                  + "-o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \\) | sort"]
        stdout: StdioCollector {
            id: wallCollector
            waitForEnd: true
            onDataChanged: {
                let lines = wallCollector.text.trim().split("\n")
                let list = []
                for (let line of lines) {
                    if (line.trim() !== "") list.push(line.trim())
                }
                root.wallpapers = list
                PaletteState.ensureRegistered(list)
            }
        }
    }

    //  7. ~/Pictures scanner — import candidates for the theme manage view.
    Process {
        id: picScanProc
        command: ["bash", "-c",
                  "find \"$HOME/Pictures\" -maxdepth 1 -type f "
                  + "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' "
                  + "-o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \\) | sort"]
        stdout: StdioCollector {
            id: picCollector
            waitForEnd: true
            onDataChanged: {
                let lines = picCollector.text.trim().split("\n")
                let list = []
                for (let line of lines) {
                    if (line.trim() !== "") list.push(line.trim())
                }
                root.picturesList = list
            }
        }
    }

    //  8. Wallpaper importer — copies a picked ~/Pictures image into the
    //     wallpapers folder, then rescans so it shows up everywhere.
    Process {
        id: importProc
        property string source: ""
        command: ["bash", "-c",
                  "cp -n \"$1\" \"$HOME/.config/quickshell/wallpapers/\"",
                  "bash",
                  source]
        onExited: root.refreshWallpapers()
    }

    //  9. Weather (wttr.in). One curl call, e.g.  "Sunny|+28°C|23%|←6km/h"
    Process {
        id: weatherProc
        command: ["bash", "-c", "loc=\"" + root.weatherLocation + "\"; curl -s --max-time 8 \"https://wttr.in/${loc}?format=%C|%t|%h|%w\""]
        stdout: StdioCollector {
            id: weatherCollector
            waitForEnd: true
            onDataChanged: root.parseWeather()
        }
    }

    // Refresh everything every 10 minutes while the window is open.
    Timer {
        id: hubTimer
        interval: 600000      // 10 min
        running: popup.visible
        repeat: true
        onTriggered: {
            root.refreshData()
            // Keep the Wi-Fi list fresh while you're staring at it.
            if (root.hubPage === "wifi" && !wifiScanner.running && !root.isScanning) wifiScanner.running = true
        }
    }

    // ─── The idle face: a plain clock pill ──────────────────────────────────────
    icon: "nest_clock_farsight_analog"
    label: Qt.formatDateTime(clock.date, "hh:mm AP")
    labelBg: root.open ? Theme.indigo : Theme.primary   // tint while open

    // ─── Click = expand / collapse ───────────────────────────────────────────────
    MouseArea {
        id: clickArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
    }

    function toggle() {
        if (popup.visible) root.collapse()
        else root.expand()
    }

    function toggleTab(tab) {
        if (popup.visible) {
            if (root.currentTab === tab) {
                root.collapse()
            } else {
                root.setTab(tab)
            }
        } else {
            root.setTab(tab)
            root.expand()
        }
    }

    function openTab(tab) {
        root.setTab(tab)
        if (!popup.visible) root.expand()
    }

    function expand() {
        closeDelay.stop()               // cancel a close that's mid-flight
        openDelay.stop()
        closing = false
        stopAllAnims()
        prepareFace()                   // undo whatever a previous close left behind
        popup.visible = true
        grab.active = true              // arm click-outside-to-close
        root.refreshData()
        root.hubPage = "main"           // always reopen on the main settings page
        openDelay.restart()             // let the surface map BEFORE animating
    }

    function collapse() {
        grab.active = false             // release the focus grab
        openDelay.stop()                // don't let a pending open animation fire
        if (closing) return             // already animating out — don't restart it
        closing = true
        stopAllAnims()
        startClose()                    // run the close animation…
        closeDelay.interval = closeMs() + 80   // …then hide AFTER it plays
        closeDelay.restart()
    }

    // Kick every data collector so the window opens fresh.
    function refreshData() {
        if (!brightProc.running) brightProc.running = true
        if (!wifiStateProc.running) wifiStateProc.running = true
        if (!btStateProc.running) btStateProc.running = true
        if (!weatherProc.running) weatherProc.running = true
    }

    // Kick the sub-page scanners (called by the ">" chevrons + refresh buttons).
    function refreshWifi() {
        root.isScanning = true
        wifiScanner.running = true
    }

    function refreshBt() {
        root.isScanning = true
        btScanner.running = true
    }

    function refreshWallpapers() {
        wallScanProc.running = true
    }

    function refreshPictures() {
        picScanProc.running = true
    }

    function parseWeather() {
        let raw = weatherCollector.text.trim()
        if (!raw || raw.includes("Unknown location") || raw.includes("<html") || raw.includes("502")) {
            root.weatherOK = false
            return
        }
        // curl format: %C|%t|%h|%w  →  "Sunny|+28°C|23%|←6 km/h"  (4 fields)
        let parts = raw.split("|")
        root.weatherOK = parts.length >= 4
        root.weatherCondition = parts.length > 0 ? parts[0] : "—"
        root.weatherTemp = parts.length > 1 ? parts[1].replace(/^\+/, "") : "—"
        root.weatherHumidity = parts.length > 2 ? parts[2] : "—"
        root.weatherWind = parts.length > 3 ? parts[3] : "—"
    }

    function setTab(tab) {
        root.currentTab = tab
        // Landing on settings always starts at its main page
        // (never on a stale wifi/bluetooth sub-page).
        if (tab === "settings") root.hubPage = "main"
        // Opening the theme tab refreshes the wallpaper list.
        if (tab === "theme") root.refreshWallpapers()
        // The calendar shows weather, so make sure it's freshly fetched.
        if (tab === "calendar" && !weatherProc.running) weatherProc.running = true
    }

    function startOpen() {
        resetContent()                            // clear leftovers from a stagger close
        switch (root.animStyle) {
            case "pop":     animPopOpen.start();     break
            case "curtain": animCurtainOpen.start(); break
            case "stagger":
                // Pre-hide the chrome + content so each stagger step is visible.
                headerRow.opacity = 0;      headerLift.y = 10
                tabBarRow.opacity = 0;      tabBarLift.y = 8
                dividerBar.opacity = 0;     dividerLift.y = 6
                contentStack.opacity = 0;   contentLift.y = 10
                animStaggerOpen.start()
                break
            case "swing":   animSwingOpen.start();   break
            default:        animDropOpen.start()     // "drop"
        }
    }

    function startClose() {
        switch (root.animStyle) {
            case "pop":     animPopClose.start();     break
            case "curtain": animCurtainClose.start(); break
            case "stagger": animStaggerClose.start(); break
            case "swing":   animSwingClose.start();   break
            default:        animDropClose.start()     // "drop"
        }
    }

    // Longest close animation of the active style — the window stays mapped at
    // least this long so the close animation is actually visible.
    function closeMs() {
        switch (root.animStyle) {
            case "pop":     return 380
            case "curtain": return 320
            case "stagger": return 620
            case "swing":   return 340
            default:        return 260   // drop
        }
    }

    // Forces every content element back to fully-visible so styles that don't
    // care about them aren't affected by whatever a previous stagger close left.
    function resetContent() {
        headerRow.opacity = 1;      headerLift.y = 0
        tabBarRow.opacity = 1;      tabBarLift.y = 0
        dividerBar.opacity = 0.35;  dividerLift.y = 0
        contentStack.opacity = 1;   contentLift.y = 0
    }

    // Waits one tick after the window is mapped so the open animation plays
    // fully on-screen, instead of half of it being gone by the first frame
    // the compositor actually shows.
    Timer {
        id: openDelay
        interval: 25
        repeat: false
        onTriggered: {
            closing = false
            startOpen()
        }
    }

    Timer {
        id: closeDelay
        interval: 300
        onTriggered: {
            popup.visible = false
            closing = false
        }
    }

    // Stops every open/close group, so two animations can never fight over
    // the same property when the hub flips state mid-animation.
    function stopAllAnims() {
        animDropOpen.stop();    animPopOpen.stop();     animCurtainOpen.stop()
        animStaggerOpen.stop(); animSwingOpen.stop()
        animDropClose.stop();   animPopClose.stop();    animCurtainClose.stop()
        animStaggerClose.stop(); animSwingClose.stop()
    }

    // Puts every animated property back at its "fully open" resting value so
    // the next open always starts clean, whatever ran last (fixes stale
    // stagger fades and the curtain style's un-bound reveal height).
    function prepareFace() {
        resetContent()
        // Re-declare the binding (a curtain close or a plain assignment
        // un-binds `reveal.height`, which would break the curtain style).
        reveal.height = Qt.binding(() => stage.height)
        face.opacity = 0                // open animations fade it back in
        faceScale.xScale = 1; faceScale.yScale = 1
        faceShift.y = 0
        faceSpin.angle = 0
    }

    // =============================================================================
    //  THE FLOATING WINDOW  (the expanded state)
    // =============================================================================
    PanelWindow {
        id: popup

        screen: root.screen
        visible: false
        color: "transparent"

        // When the window hides (close animation finished), stop everything
        // and rest every animated property, so reopening always starts fresh.
        onVisibleChanged: if (!visible) {
            grab.active = false
            stopAllAnims()
            prepareFace()
        }

        anchors { top: true; left: true }
        margins {
            // top: Theme.barHeight + 6                            // clears the bar
            left: Math.max(0, Math.round((popup.screen.width - root.hubW) / 2))
        }

        // +50% size bump: 420×300 → 630×450 (the card fills the whole window).
        implicitWidth: root.hubW
        implicitHeight: root.hubH

        // ─── CLICK-OUTSIDE-TO-CLOSE ─────────────────────────────────────────────
        // While the hub is open, Hyprland hands input focus to this window
        // alone. Clicking anywhere else — the bar, the desktop, any other
        // window — breaks the grab and fires `cleared`, which collapses the
        // hub. (Quietly does nothing on compositors other than Hyprland.)
        HyprlandFocusGrab {
            id: grab
            windows: [popup]
            active: false
            onCleared: root.collapse()
        }

        // ─── THE ANIMATION ENGINE ───────────────────────────────────────────────
        // The card (`stage`) fills the whole window and is wrapped in a
        // clipping `reveal`, so the "curtain" style can grow its height
        // without squishing the content inside.
        Item {
            id: stage
            anchors.fill: parent   // card fills the window — no dead zones

            Item {
                id: reveal
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: stage.height
                clip: true

                Rectangle {
                    id: face
                    anchors.fill: reveal
                    radius: 14
                    color: Theme.qsBg
                    clip: true
                    opacity: 0   // hidden until an open animation turns it on

                    transform: [
                        Translate { id: faceShift; y: 0 },
                        Rotation  { id: faceSpin;  origin.x: face.width / 2; origin.y: 0; angle: 0 },
                        Scale     { id: faceScale; origin.x: face.width / 2; origin.y: 0; xScale: 1; yScale: 1 }
                    ]

                    // ─── OPEN groups (one per style) ────────────────────────
                    ParallelAnimation {
                        id: animDropOpen
                        running: false
                        NumberAnimation { target: faceScale; property: "xScale"; from: 0.90; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { target: faceScale; property: "yScale"; from: 0.90; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { target: faceShift;  property: "y";       from: -28; to: 0; duration: 260; easing.type: Easing.OutQuart }
                        NumberAnimation { target: face;       property: "opacity"; from: 0;   to: 1; duration: 180; easing.type: Easing.OutCubic }
                    }
                    ParallelAnimation {
                        id: animPopOpen
                        running: false
                        NumberAnimation { target: faceScale; property: "xScale"; from: 0.82; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        NumberAnimation { target: faceScale; property: "yScale"; from: 0.82; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        NumberAnimation { target: face;      property: "opacity"; from: 0;  to: 1; duration: 150; easing.type: Easing.OutCubic }
                    }
                    ParallelAnimation {
                        id: animCurtainOpen
                        running: false
                        NumberAnimation { target: reveal;   property: "height";  from: 0; to: stage.height; duration: 320; easing.type: Easing.OutQuart }
                        NumberAnimation { target: face;     property: "opacity"; from: 0; to: 1;           duration: 160; easing.type: Easing.OutCubic }
                    }
                    SequentialAnimation {
                        id: animStaggerOpen
                        running: false
                        ParallelAnimation {
                            NumberAnimation { target: face;       property: "opacity"; from: 0; to: 1; duration: 100; easing.type: Easing.OutCubic }
                            NumberAnimation { target: faceScale;  property: "xScale";  from: 0.97; to: 1; duration: 130; easing.type: Easing.OutQuad }
                            NumberAnimation { target: faceScale;  property: "yScale";  from: 0.97; to: 1; duration: 130; easing.type: Easing.OutQuad }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: headerRow;  property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutQuad }
                            NumberAnimation { target: headerLift; property: "y";       from: 10; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            NumberAnimation { target: tabBarRow;  property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutQuad }
                            NumberAnimation { target: tabBarLift; property: "y";       from: 8; to: 0; duration: 150; easing.type: Easing.OutQuad }
                        }
                        PauseAnimation { duration: 40 }
                        ParallelAnimation {
                            NumberAnimation { target: dividerBar;  property: "opacity"; from: 0;   to: 0.35; duration: 120; easing.type: Easing.OutQuad }
                            NumberAnimation { target: dividerLift; property: "y";       from: 6;   to: 0;    duration: 120; easing.type: Easing.OutQuad }
                        }
                        PauseAnimation { duration: 40 }
                        ParallelAnimation {
                            NumberAnimation { target: contentStack;  property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutQuad }
                            NumberAnimation { target: contentLift;   property: "y";       from: 10; to: 0; duration: 140; easing.type: Easing.OutQuad }
                        }
                    }
                    ParallelAnimation {
                        id: animSwingOpen
                        running: false
                        NumberAnimation { target: faceSpin;  property: "angle";  from: -9; to: 0; duration: 340; easing.type: Easing.OutBack }
                        NumberAnimation { target: face;      property: "opacity"; from: 0;  to: 1; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { target: faceScale; property: "xScale";  from: 0.95; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        NumberAnimation { target: faceScale; property: "yScale";  from: 0.95; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    }

                    // ─── CLOSE groups (mirrored per style) ───────────────────
                    ParallelAnimation {
                        id: animDropClose
                        running: false
                        NumberAnimation { target: faceScale; property: "xScale"; to: 0.90; duration: 150; easing.type: Easing.InCubic }
                        NumberAnimation { target: faceScale; property: "yScale"; to: 0.90; duration: 150; easing.type: Easing.InCubic }
                        NumberAnimation { target: faceShift;  property: "y";       to: -24; duration: 180; easing.type: Easing.InQuad }
                        NumberAnimation { target: face;       property: "opacity"; to: 0;   duration: 140; easing.type: Easing.InQuad }
                    }
                    ParallelAnimation {
                        id: animPopClose
                        running: false
                        NumberAnimation { target: faceScale; property: "xScale"; to: 0.88; duration: 240; easing.type: Easing.InBack }
                        NumberAnimation { target: faceScale; property: "yScale"; to: 0.88; duration: 240; easing.type: Easing.InBack }
                        NumberAnimation { target: face;      property: "opacity"; to: 0;   duration: 140; easing.type: Easing.InQuad }
                    }
                    ParallelAnimation {
                        id: animCurtainClose
                        running: false
                        NumberAnimation { target: reveal;   property: "height";  to: 0; duration: 240; easing.type: Easing.InQuart }
                        NumberAnimation { target: face;     property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                    }
                    SequentialAnimation {
                        id: animStaggerClose
                        running: false
                        ParallelAnimation {
                            NumberAnimation { target: contentStack;  property: "opacity"; to: 0; duration: 110; easing.type: Easing.InQuad }
                            NumberAnimation { target: contentLift;   property: "y";       to: 8; duration: 120; easing.type: Easing.InQuad }
                        }
                        PauseAnimation { duration: 40 }
                        ParallelAnimation {
                            NumberAnimation { target: dividerBar;  property: "opacity"; to: 0; duration: 110; easing.type: Easing.InQuad }
                            NumberAnimation { target: dividerLift; property: "y";       to: 6; duration: 120; easing.type: Easing.InQuad }
                        }
                        PauseAnimation { duration: 40 }
                        ParallelAnimation {
                            NumberAnimation { target: headerRow;   property: "opacity"; to: 0;    duration: 120; easing.type: Easing.InQuad }
                            NumberAnimation { target: headerLift;  property: "y";       to: 10;   duration: 130; easing.type: Easing.InQuad }
                            NumberAnimation { target: tabBarRow;   property: "opacity"; to: 0;    duration: 120; easing.type: Easing.InQuad }
                            NumberAnimation { target: tabBarLift;  property: "y";       to: 8;    duration: 130; easing.type: Easing.InQuad }
                            NumberAnimation { target: face;        property: "opacity"; to: 0;    duration: 140; easing.type: Easing.InQuad }
                            NumberAnimation { target: faceScale;   property: "xScale";  to: 0.97; duration: 150; easing.type: Easing.InCubic }
                            NumberAnimation { target: faceScale;   property: "yScale";  to: 0.97; duration: 150; easing.type: Easing.InCubic }
                        }
                    }
                    ParallelAnimation {
                        id: animSwingClose
                        running: false
                        NumberAnimation { target: faceSpin;  property: "angle";  to: -9;   duration: 260; easing.type: Easing.InBack }
                        NumberAnimation { target: face;      property: "opacity"; to: 0;    duration: 150; easing.type: Easing.InQuad }
                        NumberAnimation { target: faceScale; property: "xScale";  to: 0.95; duration: 220; easing.type: Easing.InCubic }
                        NumberAnimation { target: faceScale; property: "yScale";  to: 0.95; duration: 220; easing.type: Easing.InCubic }
                    }

                    // =============================================================
                    //  THE CARD CONTENT  (header, tab bar, and the two tab views)
                    // =============================================================
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        // ─── HEADER: icon capsule | time + date | collapse ───────
                        RowLayout {
                            id: headerRow
                            opacity: 1
                            transform: Translate { id: headerLift; y: 0 }
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: Theme.plum

                                Text {
                                    anchors.centerIn: parent
                                    text: "nest_clock_farsight_analog"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 16
                                    color: Theme.ink
                                    leftPadding: 2
                                }
                            }

                            ColumnLayout {
                                spacing: 0
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    text: Qt.formatDateTime(clock.date, "hh:mm AP")
                                    font.family: Theme.fontText
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: Theme.qsText
                                }
                                Text {
                                    text: Qt.formatDate(clock.date, "dddd, MMMM d")
                                    font.family: Theme.fontText
                                    font.pixelSize: 11
                                    color: Theme.qsTextMuted
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Collapse button (also collapses the pill's state)
                            Rectangle {
                                width: 30
                                height: 30
                                radius: 15
                                color: Theme.qsBgAlt

                                Text {
                                    anchors.centerIn: parent
                                    text: "keyboard_arrow_up"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 16
                                    color: Theme.qsText
                                    leftPadding: 1
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.collapse()
                                }
                            }
                        }

                        // ─── TAB BAR: tiny capsule "pips", like the workspace pips ──
                        RowLayout {
                            id: tabBarRow
                            opacity: 1
                            transform: Translate { id: tabBarLift; y: 0 }
                            Layout.fillWidth: true
                            spacing: 8

                            // ── Calendar tab pip ──
                            Rectangle {
                                height: 22
                                implicitWidth: tabCalIcon.width + tabCalLabel.width
                                color: "transparent"

                                Rectangle {
                                    id: tabCalIcon
                                    width: 22
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "calendar_month"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 12
                                        color: Theme.ink
                                        leftPadding: 1
                                    }
                                }

                                Rectangle {
                                    id: tabCalLabel
                                    height: parent.height
                                    width: tabCalTxt.implicitWidth + 14
                                    anchors.left: tabCalIcon.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "calendar" ? Theme.attention : Theme.primary
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2

                                    Text {
                                        id: tabCalTxt
                                        anchors.centerIn: parent
                                        text: "Calendar"
                                        font.family: Theme.fontText
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Theme.ink
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTab("calendar")
                                }
                            }

                            // ── Theme tab pip ──
                            Rectangle {
                                height: 22
                                implicitWidth: tabThemeIcon.width + tabThemeLabel.width
                                color: "transparent"

                                Rectangle {
                                    id: tabThemeIcon
                                    width: 22
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "palette"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 12
                                        color: Theme.ink
                                        leftPadding: 1
                                    }
                                }

                                Rectangle {
                                    id: tabThemeLabel
                                    height: parent.height
                                    width: tabThemeTxt.implicitWidth + 14
                                    anchors.left: tabThemeIcon.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "theme" ? Theme.attention : Theme.primary
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2

                                    Text {
                                        id: tabThemeTxt
                                        anchors.centerIn: parent
                                        text: "Theme"
                                        font.family: Theme.fontText
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Theme.ink
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTab("theme")
                                }
                            }

                            // ── Settings tab pip ──
                            Rectangle {
                                height: 22
                                implicitWidth: tabSettingsIcon.width + tabSettingsLabel.width
                                color: "transparent"

                                Rectangle {
                                    id: tabSettingsIcon
                                    width: 22
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "settings"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 12
                                        color: Theme.ink
                                        leftPadding: 1
                                    }
                                }

                                Rectangle {
                                    id: tabSettingsLabel
                                    height: parent.height
                                    width: tabSettingsTxt.implicitWidth + 14
                                    anchors.left: tabSettingsIcon.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "settings" ? Theme.attention : Theme.primary
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2

                                    Text {
                                        id: tabSettingsTxt
                                        anchors.centerIn: parent
                                        text: "Settings"
                                        font.family: Theme.fontText
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Theme.ink
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTab("settings")
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Hairline separator
                        Rectangle {
                            id: dividerBar
                            opacity: 0.35
                            transform: Translate { id: dividerLift; y: 0 }
                            height: 1
                            Layout.fillWidth: true
                            color: Theme.lavender
                        }

                        // ─── CONTENT STACK: the two tab views ─────────────────────
                        Item {
                            id: contentStack
                            opacity: 1
                            transform: Translate { id: contentLift; y: 0 }
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            StackLayout {
                                anchors.fill: parent
                                // currentTab picks the TAB; while "settings" is
                                // active, hubPage picks the PAGE:
                                //   0 main · 1 wifi · 2 bluetooth · 3 theme · 4 calendar
                                currentIndex: root.currentTab === "calendar" ? 4
                                            : root.currentTab === "theme" ? 3
                                            : root.hubPage === "wifi" ? 1
                                            : root.hubPage === "bluetooth" ? 2 : 0

                                // =====================================================
                                //  VIEW 0 — SETTINGS (the QuickSettings format)
                                // =====================================================
                                Flickable {
                                    id: settingsFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    contentWidth: width
                                    contentHeight: settingsCol.implicitHeight

                                    ColumnLayout {
                                        id: settingsCol
                                        width: settingsFlick.width
                                        spacing: 12

                                        // Power / Sleep / Lock actions
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            ActionPill {
                                                Layout.fillWidth: true
                                                icon: "lock"
                                                label: "Lock"
                                                onClicked: { root.collapse(); Quickshell.execDetached(["hyprlock"]) }
                                            }
                                            ActionPill {
                                                Layout.fillWidth: true
                                                icon: "bedtime"
                                                label: "Sleep"
                                                onClicked: { root.collapse(); Quickshell.execDetached(["systemctl", "suspend"]) }
                                            }
                                            ActionPill {
                                                Layout.fillWidth: true
                                                icon: "power_settings_new"
                                                label: "Power"
                                                labelBg: Theme.primary
                                                onClicked: { root.collapse(); Quickshell.execDetached(["shutdown", "now"]) }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                                        // Volume — BOOST slider: goes up to 150%.
                                        CustomSlider {
                                            icon: (root.sink && root.sink.audio && root.sink.audio.muted) ? "volume_off" : "volume_up"
                                            value: (root.sink && root.sink.audio) ? root.sink.audio.volume : 0.5
                                            maxValue: 1.5
                                            displayText: (root.sink && root.sink.audio) ? Math.round(root.sink.audio.volume * 100) + "%" : "—"
                                            onValueChangedByUser: newVal => {
                                                if (root.sink && root.sink.audio) root.sink.audio.volume = newVal
                                            }
                                        }

                                        // Mic
                                        CustomSlider {
                                            icon: (root.source && root.source.audio && root.source.audio.muted) ? "mic_off" : "mic"
                                            value: (root.source && root.source.audio) ? root.source.audio.volume : 0.5
                                            onValueChangedByUser: newVal => {
                                                if (root.source && root.source.audio) root.source.audio.volume = newVal
                                            }
                                        }

                                        // Brightness
                                        CustomSlider {
                                            icon: "brightness_6"
                                            value: root.brightnessVal
                                            onValueChangedByUser: newVal => {
                                                root.brightnessVal = newVal
                                                let percent = Math.round(newVal * 100)
                                                Quickshell.execDetached(["brightnessctl", "set", percent + "%"])
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                                        // Toggles grid (Wi-Fi + Bluetooth)
                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 2
                                            columnSpacing: 10
                                            rowSpacing: 10

                                            QuickToggle {
                                                icon: "wifi"
                                                title: "Wi-Fi"
                                                // Status: connected SSID when known, else On/Off.
                                                status: root.wifiActive
                                                        ? (root.wifiNetworks.length > 0 && root.wifiNetworks[0].active ? root.wifiNetworks[0].ssid : "On")
                                                        : "Off"
                                                active: root.wifiActive
                                                onToggled: {
                                                    root.wifiActive = !root.wifiActive
                                                    Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiActive ? "on" : "off"])
                                                }
                                                // ">" chevron → full network list page.
                                                onOpenDetails: {
                                                    root.hubPage = "wifi"
                                                    root.refreshWifi()
                                                }
                                            }

                                            QuickToggle {
                                                icon: "bluetooth"
                                                title: "Bluetooth"
                                                status: root.btActive ? (root.isScanning ? "Scanning..." : "On") : "Off"
                                                active: root.btActive
                                                onToggled: {
                                                    root.btActive = !root.btActive
                                                    Quickshell.execDetached(["bluetoothctl", "power", root.btActive ? "on" : "off"])
                                                }
                                                // ">" chevron → device list page.
                                                onOpenDetails: {
                                                    root.hubPage = "bluetooth"
                                                    root.refreshBt()
                                                }
                                            }
                                        }
                                    }
                                }

                                // =====================================================
                                //  VIEW 0b — WI-FI NETWORKS  (">" on the Wi-Fi tile)
                                //  Back arrow returns to the main settings page.
                                // =====================================================
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 10

                                    // ── Header: back | title | refresh ──────────
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "arrow_back"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 20
                                            color: Theme.qsAccent
                                            Layout.alignment: Qt.AlignVCenter
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.hubPage = "main"
                                            }
                                        }

                                        Text {
                                            text: "Available Networks"
                                            font.family: Theme.fontText
                                            font.pixelSize: 14
                                            font.bold: true
                                            color: Theme.qsText
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        Text {
                                            text: "refresh"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 18
                                            color: root.isScanning ? Theme.qsSuccess : Theme.qsPurple
                                            Layout.alignment: Qt.AlignVCenter
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.refreshWifi()
                                            }
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                                    // ── Scrollable network list ──────────────────
                                    Flickable {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        contentWidth: width
                                        contentHeight: wifiListCol.implicitHeight
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        ColumnLayout {
                                            id: wifiListCol
                                            width: parent.width
                                            spacing: 6

                                            // Empty-state message.
                                            Text {
                                                visible: root.wifiNetworks.length === 0
                                                text: root.isScanning ? "Scanning for networks..." : "No networks found. Tap refresh."
                                                font.family: Theme.fontText
                                                font.pixelSize: 12
                                                color: Theme.qsTextMuted
                                                Layout.alignment: Qt.AlignCenter
                                                Layout.topMargin: 15
                                                Layout.bottomMargin: 15
                                            }

                                            // One row per network ({active, ssid, signal, security}).
                                            Repeater {
                                                model: root.wifiNetworks

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 38
                                                    radius: 0
                                                    color: "transparent"

                                                    // ── Left: icon segment (accent when connected) ──
                                                    Rectangle {
                                                        id: wifiRowIconSeg
                                                        width: wifiRowIcon.width + 14
                                                        height: parent.height
                                                        anchors.left: parent.left
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: modelData.active ? Theme.attention : Theme.plum
                                                        topLeftRadius: height / 2
                                                        bottomLeftRadius: height / 2
                                                        topRightRadius: 0
                                                        bottomRightRadius: 0

                                                        Text {
                                                            id: wifiRowIcon
                                                            anchors.centerIn: parent
                                                            // Icon chosen from signal strength.
                                                            text: modelData.signal > 60 ? "wifi" : (modelData.signal > 30 ? "wifi_2_bar" : "wifi_1_bar")
                                                            font.family: Theme.fontIcons
                                                            font.pixelSize: 18
                                                            color: Theme.ink
                                                            leftPadding: 4
                                                        }
                                                    }

                                                    // ── Right: SSID + lock + Connect action ──
                                                    Rectangle {
                                                        anchors.left: wifiRowIconSeg.right
                                                        anchors.right: parent.right
                                                        height: parent.height
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: modelData.active ? Theme.attention : Theme.primary
                                                        topLeftRadius: 0
                                                        bottomLeftRadius: 0
                                                        topRightRadius: height / 2
                                                        bottomRightRadius: height / 2

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 12
                                                            anchors.rightMargin: 10
                                                            spacing: 8

                                                            Text {
                                                                text: modelData.ssid
                                                                font.family: Theme.fontText
                                                                font.pixelSize: 12
                                                                font.bold: modelData.active
                                                                color: Theme.ink
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }

                                                            // Lock glyph if the network is secured.
                                                            Text {
                                                                visible: modelData.security !== ""
                                                                text: "lock"
                                                                font.family: Theme.fontIcons
                                                                font.pixelSize: 14
                                                                color: Theme.ink
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }

                                                            // "Connected" (plain) or clickable "Connect".
                                                            Text {
                                                                text: modelData.active ? "Connected" : "Connect"
                                                                font.family: Theme.fontText
                                                                font.pixelSize: 11
                                                                font.bold: true
                                                                color: modelData.active ? Theme.ink : Theme.attention
                                                                Layout.alignment: Qt.AlignVCenter

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        if (!modelData.active) {
                                                                            Quickshell.execDetached(["nmcli", "device", "wifi", "connect", modelData.ssid])
                                                                            root.refreshWifi()   // re-scan so it flips to "Connected"
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                        }
                                    }
                                }

                                // =====================================================
                                //  VIEW 0c — BLUETOOTH DEVICES  (">" on the BT tile)
                                //  Back arrow returns to the main settings page.
                                // =====================================================
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 10

                                    // ── Header: back | title | refresh ──────────
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "arrow_back"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 20
                                            color: Theme.qsAccent
                                            Layout.alignment: Qt.AlignVCenter
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.hubPage = "main"
                                            }
                                        }

                                        Text {
                                            text: root.isScanning ? "Discovering Nearby..." : "Bluetooth Devices"
                                            font.family: Theme.fontText
                                            font.pixelSize: 14
                                            font.bold: true
                                            color: Theme.qsText
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        Text {
                                            text: "refresh"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 18
                                            color: root.isScanning ? Theme.qsSuccess : Theme.qsPurple
                                            Layout.alignment: Qt.AlignVCenter
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.refreshBt()
                                            }
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                                    // ── Scrollable device list ───────────────────
                                    Flickable {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        contentWidth: width
                                        contentHeight: btListCol.implicitHeight
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        ColumnLayout {
                                            id: btListCol
                                            width: parent.width
                                            spacing: 6

                                            // Empty-state message.
                                            Text {
                                                visible: root.btDevices.length === 0
                                                text: root.isScanning ? "Scanning for nearby devices..." : "No devices found. Tap refresh to scan."
                                                font.family: Theme.fontText
                                                font.pixelSize: 12
                                                color: Theme.qsTextMuted
                                                Layout.alignment: Qt.AlignCenter
                                                Layout.topMargin: 15
                                                Layout.bottomMargin: 15
                                            }

                                            // One row per discovered device ({mac, name}).
                                            Repeater {
                                                model: root.btDevices

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 38
                                                    radius: 0
                                                    color: "transparent"

                                                    // ── Left: bluetooth icon segment ────────────
                                                    Rectangle {
                                                        id: btRowIconSeg
                                                        width: btRowIcon.width + 14
                                                        height: parent.height
                                                        anchors.left: parent.left
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: Theme.plum
                                                        topLeftRadius: height / 2
                                                        bottomLeftRadius: height / 2
                                                        topRightRadius: 0
                                                        bottomRightRadius: 0

                                                        Text {
                                                            id: btRowIcon
                                                            anchors.centerIn: parent
                                                            text: "bluetooth"
                                                            font.family: Theme.fontIcons
                                                            font.pixelSize: 18
                                                            color: Theme.ink
                                                            leftPadding: 4
                                                        }
                                                    }

                                                    // ── Right: device name + Pair/Connect ───────
                                                    Rectangle {
                                                        anchors.left: btRowIconSeg.right
                                                        anchors.right: parent.right
                                                        height: parent.height
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: Theme.primary
                                                        topLeftRadius: 0
                                                        bottomLeftRadius: 0
                                                        topRightRadius: height / 2
                                                        bottomRightRadius: height / 2

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 12
                                                            anchors.rightMargin: 10
                                                            spacing: 8

                                                            Text {
                                                                text: modelData.name
                                                                font.family: Theme.fontText
                                                                font.pixelSize: 12
                                                                color: Theme.ink
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }

                                                            // Pairs, then connects, then refreshes.
                                                            Text {
                                                                text: "Pair / Connect"
                                                                font.family: Theme.fontText
                                                                font.pixelSize: 11
                                                                font.bold: true
                                                                color: Theme.attention
                                                                Layout.alignment: Qt.AlignVCenter

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: {
                                                                        Quickshell.execDetached(["bluetoothctl", "pair", modelData.mac])
                                                                        Quickshell.execDetached(["bluetoothctl", "connect", modelData.mac])
                                                                        root.refreshBt()
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                        }
                                    }
                                }

                                // =====================================================
                                //  VIEW 2 — THEME  (wallpaper picker first; more later)
                                // =====================================================
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 10

                                    // ── Header: title | refresh ──────────────────
                                    RowLayout {
                                        visible: root.themePage === "picker"
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "Wallpaper"
                                            font.family: Theme.fontText
                                            font.pixelSize: 14
                                            font.bold: true
                                            color: Theme.qsText
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        Text {
                                            text: "refresh"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 18
                                            color: Theme.qsPurple
                                            Layout.alignment: Qt.AlignVCenter
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.refreshWallpapers()
                                            }
                                        }

                                        // Theme settings — opens the manage view for currently active wallpaper
                                        Text {
                                            text: "settings"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 18
                                            color: Theme.qsPurple
                                            Layout.alignment: Qt.AlignVCenter

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let target = WallpaperState.current || (root.wallpapers.length > 0 ? root.wallpapers[0] : "")
                                                    if (target) PaletteState.ensureRegistered(target)
                                                    root.editingPath = target
                                                    root.editingSlot = "attention"
                                                    root.hoveredSlot = ""
                                                    root.themePage = "manage"
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: root.themePage === "picker"
                                        Layout.fillWidth: true
                                        implicitHeight: 1
                                        color: Theme.pillBorder
                                    }

                                    // Empty state when the wallpapers folder has no images.
                                    Text {
                                        visible: root.wallpapers.length === 0 && root.themePage === "picker"
                                        text: "No images found in ~/.config/quickshell/wallpapers"
                                        font.family: Theme.fontText
                                        font.pixelSize: 12
                                        color: Theme.qsTextMuted
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.topMargin: 20
                                    }

                                    // ── Thumbnail grid ───────────────────────────
                                    GridView {
                                        id: wallGrid
                                        visible: root.wallpapers.length > 0 && root.themePage === "picker"
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: root.wallpapers
                                        cellWidth: Math.floor(width / 2)
                                        cellHeight: Math.round(cellWidth * 0.56) + 22

                                        // One cell per image. Clicking applies it
                                        // through the WallpaperState singleton.
                                        delegate: Item {
                                            id: wallCell
                                            required property string modelData
                                            readonly property bool isCurrent: WallpaperState.current === wallCell.modelData
                                            width: wallGrid.cellWidth
                                            height: wallGrid.cellHeight

                                            Rectangle {
                                                id: thumb
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                anchors.bottomMargin: 24   // leave room for the name
                                                radius: 8
                                                color: Theme.qsBgAlt
                                                border.width: wallCell.isCurrent ? 2 : 1
                                                border.color: wallCell.isCurrent ? Theme.attention : Theme.pillBorder
                                                clip: true

                                                Image {
                                                    anchors.fill: parent
                                                    anchors.margins: 2
                                                    source: wallCell.modelData
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    sourceSize.width: thumb.width   // decode at thumb size
                                                    sourceSize.height: thumb.height
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: WallpaperState.setWallpaper(wallCell.modelData)
                                                }
                                            }

                                            // File name under the thumbnail.
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                anchors.bottomMargin: 5
                                                width: parent.width - 12
                                                text: wallCell.modelData.split("/").pop()
                                                font.family: Theme.fontText
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                horizontalAlignment: Text.AlignHCenter
                                                color: wallCell.isCurrent ? Theme.attention : Theme.qsTextMuted
                                            }
                                        }
                                    }

                                    // ── MANAGE VIEW  (opened with the cog for active wallpaper) ───────
                                    ColumnLayout {
                                        id: manageViewCol
                                        visible: root.themePage === "manage"
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 10

                                        readonly property string inspectedSlot: root.hoveredSlot !== "" ? root.hoveredSlot : root.editingSlot
                                        readonly property color inspectedColor: root.editingPath ? PaletteState.colorFor(root.editingPath, inspectedSlot) : Theme.attention

                                        // ── 1. Header: Back button | Active wallpaper info | Reset ──
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Rectangle {
                                                width: 28
                                                height: 28
                                                radius: 14
                                                color: Theme.qsBgAlt
                                                border.width: 1
                                                border.color: Theme.pillBorder

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "arrow_back"
                                                    font.family: Theme.fontIcons
                                                    font.pixelSize: 17
                                                    color: Theme.attention
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.editingPath = ""
                                                        root.hoveredSlot = ""
                                                        root.themePage = "picker"
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: 44
                                                height: 26
                                                radius: 5
                                                color: Theme.qsBg
                                                border.width: 1
                                                border.color: Theme.pillBorder
                                                clip: true

                                                Image {
                                                    anchors.fill: parent
                                                    source: root.editingPath
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                }
                                            }

                                            ColumnLayout {
                                                spacing: 0
                                                Layout.fillWidth: true

                                                RowLayout {
                                                    spacing: 6
                                                    Text {
                                                        text: root.editingPath ? root.editingPath.split("/").pop() : "Active Theme"
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 12
                                                        font.bold: true
                                                        color: Theme.qsText
                                                        elide: Text.ElideRight
                                                        Layout.maximumWidth: 260
                                                    }

                                                    Rectangle {
                                                        radius: 4
                                                        color: Theme.attention
                                                        implicitHeight: 15
                                                        implicitWidth: activeBadgeText.implicitWidth + 8

                                                        Text {
                                                            id: activeBadgeText
                                                            anchors.centerIn: parent
                                                            text: "ACTIVE"
                                                            font.family: Theme.fontText
                                                            font.pixelSize: 8
                                                            font.bold: true
                                                            color: Theme.ink
                                                        }
                                                    }
                                                }

                                                Text {
                                                    text: "Hover over swatches to reveal color roles · click to edit"
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 9
                                                    color: Theme.qsTextMuted
                                                }
                                            }

                                            // Reset palette button
                                            Rectangle {
                                                implicitHeight: 26
                                                implicitWidth: resetContentRow.implicitWidth + 12
                                                radius: 13
                                                color: Theme.qsBgAlt
                                                border.width: 1
                                                border.color: Theme.pillBorder

                                                RowLayout {
                                                    id: resetContentRow
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Text {
                                                        text: "restart_alt"
                                                        font.family: Theme.fontIcons
                                                        font.pixelSize: 13
                                                        color: Theme.qsTextMuted
                                                    }

                                                    Text {
                                                        text: "Reset"
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        color: Theme.qsTextMuted
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (root.editingPath) {
                                                            PaletteState.resetPalette(root.editingPath)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                                        // ── 2. Dynamic Info Banner (Reveals slot name only on hover or selection) ──
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 36
                                            radius: 7
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: root.hoveredSlot !== "" ? Theme.attention : Theme.pillBorder

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Rectangle {
                                                    width: 18
                                                    height: 18
                                                    radius: 9
                                                    color: manageViewCol.inspectedColor
                                                    border.width: 1.5
                                                    border.color: Theme.ink
                                                }

                                                Text {
                                                    text: root.slotRoleName(manageViewCol.inspectedSlot)
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    color: root.hoveredSlot !== "" ? Theme.attention : Theme.qsText
                                                }

                                                Text {
                                                    text: "(" + manageViewCol.inspectedSlot + ")"
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 11
                                                    color: Theme.qsTextMuted
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: manageViewCol.inspectedColor.toString().toUpperCase()
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    color: Theme.qsText
                                                }

                                                Text {
                                                    visible: root.hoveredSlot !== "" && root.hoveredSlot !== root.editingSlot
                                                    text: "• click to select"
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 10
                                                    color: Theme.attention
                                                }
                                            }
                                        }

                                        // ── 3. Clean Color Swatches (No static text!) ──
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Repeater {
                                                model: PaletteState.slotNames

                                                Item {
                                                    id: swatchItem
                                                    required property string modelData
                                                    Layout.fillWidth: true
                                                    height: 48

                                                    readonly property bool isSelected: root.editingSlot === swatchItem.modelData
                                                    readonly property bool isHovered: root.hoveredSlot === swatchItem.modelData
                                                    readonly property color slotColor: root.editingPath ? PaletteState.colorFor(root.editingPath, swatchItem.modelData) : "#888888"

                                                    Rectangle {
                                                        id: swatchCircle
                                                        anchors.centerIn: parent
                                                        width: swatchItem.isHovered ? 42 : 36
                                                        height: width
                                                        radius: width / 2
                                                        color: swatchItem.slotColor

                                                        border.width: swatchItem.isSelected ? 2.5 : (swatchItem.isHovered ? 2 : 1)
                                                        border.color: swatchItem.isSelected ? Theme.attention : (swatchItem.isHovered ? Theme.ink : Theme.pillBorder)

                                                        Behavior on width { NumberAnimation { duration: 100 } }
                                                        Behavior on border.color { ColorAnimation { duration: 100 } }

                                                        Rectangle {
                                                            visible: swatchItem.isSelected
                                                            anchors.centerIn: parent
                                                            width: 8
                                                            height: 8
                                                            radius: 4
                                                            color: Theme.attention
                                                            border.width: 1
                                                            border.color: Theme.ink
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onEntered: root.hoveredSlot = swatchItem.modelData
                                                        onExited: {
                                                            if (root.hoveredSlot === swatchItem.modelData) {
                                                                root.hoveredSlot = ""
                                                            }
                                                        }
                                                        onClicked: {
                                                            root.editingSlot = swatchItem.modelData
                                                            hexInput.text = ""
                                                            hexInput.forceActiveFocus()
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                                        // ── 4. Hex Value Input & Apply Row (No static chip colors!) ──
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 48
                                            radius: 8
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 10

                                                Text {
                                                    text: "Hex:"
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    color: Theme.qsText
                                                }

                                                Rectangle {
                                                    id: hexBox
                                                    Layout.fillWidth: true
                                                    height: 30
                                                    radius: 6
                                                    color: Theme.qsBg
                                                    border.width: hexInput.activeFocus ? 2 : 1
                                                    border.color: hexInput.activeFocus ? Theme.attention : Theme.pillBorder

                                                    TextInput {
                                                        id: hexInput
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        color: Theme.qsText
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 12
                                                        font.bold: true
                                                        selectionColor: Theme.attention
                                                        selectedTextColor: Theme.ink
                                                        clip: true

                                                        property string normalized: {
                                                            let t = text.trim()
                                                            if (t === "") return ""
                                                            return t.charAt(0) === "#" ? t : "#" + t
                                                        }

                                                        readonly property bool valid: PaletteState.isValidHex(normalized)

                                                        function applyHex() {
                                                            if (!valid || !root.editingPath || !root.editingSlot) return
                                                            PaletteState.assignColor(root.editingPath, root.editingSlot, normalized)
                                                            text = ""
                                                        }

                                                        onAccepted: applyHex()
                                                    }

                                                    Text {
                                                        visible: hexInput.text === "" && !hexInput.activeFocus
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: root.editingPath && root.editingSlot ? PaletteState.colorFor(root.editingPath, root.editingSlot).toString().toUpperCase() : "#RRGGBB"
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 11
                                                        color: Theme.qsTextMuted
                                                    }
                                                }

                                                // Live preview circle
                                                Rectangle {
                                                    width: 28
                                                    height: 28
                                                    radius: 14
                                                    color: hexInput.valid ? hexInput.normalized : (root.editingPath && root.editingSlot ? PaletteState.colorFor(root.editingPath, root.editingSlot) : "transparent")
                                                    border.width: 1.5
                                                    border.color: hexInput.valid ? Theme.attention : Theme.pillBorder
                                                }

                                                // Apply Button
                                                Rectangle {
                                                    implicitHeight: 30
                                                    implicitWidth: applyButtonRow.implicitWidth + 14
                                                    radius: 15
                                                    color: hexInput.valid ? Theme.attention : Theme.primary
                                                    opacity: hexInput.valid ? 1.0 : 0.4

                                                    RowLayout {
                                                        id: applyButtonRow
                                                        anchors.centerIn: parent
                                                        spacing: 4

                                                        Text {
                                                            text: "check"
                                                            font.family: Theme.fontIcons
                                                            font.pixelSize: 14
                                                            color: hexInput.valid ? Theme.ink : Theme.qsTextMuted
                                                        }

                                                        Text {
                                                            text: "Apply"
                                                            font.family: Theme.fontText
                                                            font.pixelSize: 11
                                                            font.bold: true
                                                            color: hexInput.valid ? Theme.ink : Theme.qsTextMuted
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: hexInput.valid ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: hexInput.applyHex()
                                                    }
                                                }
                                            }
                                        }

                                        // ── 5. Full Palette Strip ──
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 8
                                            radius: 4
                                            clip: true
                                            border.width: 1
                                            border.color: Theme.pillBorder

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 0

                                                Repeater {
                                                    model: PaletteState.slotNames
                                                    Rectangle {
                                                        required property string modelData
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        color: root.editingPath ? PaletteState.colorFor(root.editingPath, modelData) : "#333333"
                                                    }
                                                }
                                            }
                                        }

                                        Item { Layout.fillHeight: true }
                                    }
                                }

                                // =====================================================
                                //  VIEW 1 — CALENDAR / WEATHER
                                //  Left: clock + Tabriz weather · Right: calendar
                                // =====================================================
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 12

                                    // ── LEFT: clock + weather ──
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 300
                                        Layout.fillHeight: true
                                        spacing: 8

                                        Text {
                                            text: Qt.formatDateTime(clock.date, "hh:mm")
                                            font.family: Theme.fontText
                                            font.pixelSize: 46
                                            font.bold: true
                                            color: Theme.qsText
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: Qt.formatDate(clock.date, "EEEE, MMMM d")
                                            font.family: Theme.fontText
                                            font.pixelSize: 13
                                            color: Theme.qsTextMuted
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 1
                                            color: Theme.pillBorder
                                            Layout.topMargin: 6
                                            Layout.bottomMargin: 6
                                        }

                                        Text {
                                            text: "Tabriz, Iran"
                                            font.family: Theme.fontText
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Theme.qsTextMuted
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: root.weatherOK ? root.weatherTemp : "—"
                                            font.family: Theme.fontText
                                            font.pixelSize: 40
                                            font.bold: true
                                            color: Theme.attention
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: root.weatherOK ? root.weatherCondition : "offline"
                                            font.family: Theme.fontText
                                            font.pixelSize: 13
                                            color: Theme.qsText
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        // Humidity + wind row (material icon glyphs)
                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 14

                                            Text {
                                                text: "water_drop"
                                                font.family: Theme.fontIcons
                                                font.pixelSize: 14
                                                color: Theme.qsTextMuted
                                            }
                                            Text {
                                                text: root.weatherOK ? root.weatherHumidity : "—"
                                                font.family: Theme.fontText
                                                font.pixelSize: 11
                                                color: Theme.qsTextMuted
                                            }
                                            Text {
                                                text: "air"
                                                font.family: Theme.fontIcons
                                                font.pixelSize: 14
                                                color: Theme.qsTextMuted
                                            }
                                            Text {
                                                text: root.weatherOK ? root.weatherWind : "—"
                                                font.family: Theme.fontText
                                                font.pixelSize: 11
                                                color: Theme.qsTextMuted
                                            }
                                        }

                                        Item { Layout.fillHeight: true }
                                    }

                                    // ── vertical divider ──
                                    Rectangle {
                                        implicitWidth: 1
                                        Layout.fillHeight: true
                                        color: Theme.lavender
                                        opacity: 0.35
                                    }

                                    // ── RIGHT: calendar ──
                                    CalendarGrid {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 210
                                        Layout.fillHeight: true
                                    }
                                }
                            }
                        }   // ── contentStack
                    }       // ── content ColumnLayout
                }           // ── face
            }               // ── reveal
        }                   // ── stage
    }                       // ── popup
}                           // ── root (Pill)
