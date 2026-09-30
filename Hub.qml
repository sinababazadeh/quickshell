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
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Pill {
    id: root

    // ─── Public surface ─────────────────────────────────────────────────────────
    property var screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    readonly property bool open: popup.visible
    property bool closing: false              // true while the close animation plays

    // Which "expand" animation to use: "island" | "drop" | "pop" | "curtain" | "stagger" | "swing".
    property string animStyle: "island"

    // Window geometry — the card FILLS the window (no dead click zones around it).
    readonly property int hubW: 630
    readonly property int hubH: 288

    // ─── Apple Dynamic Island Morphing Engine ──────────────────────────────────
    property real islandProgress: 0.0
    readonly property real pillW: Math.max(110, root.implicitWidth)
    readonly property real pillH: Theme.pillHeight

    readonly property real islandW: root.animStyle === "island"
        ? Math.min(root.hubW, root.pillW + (root.hubW - root.pillW) * root.islandProgress)
        : root.hubW

    readonly property real islandH: root.animStyle === "island"
        ? (root.pillH + (root.hubH - root.pillH) * root.islandProgress)
        : root.hubH

    readonly property real islandX: (root.hubW - islandW) / 2

    // Resting top gap from screen top when fully expanded (0 = flush to screen top)
    property int hubTopGap: 0

    readonly property real islandY: root.animStyle === "island"
        ? Math.round(((Theme.barHeight - Theme.pillHeight) / 2) - (((Theme.barHeight - Theme.pillHeight) / 2) - root.hubTopGap) * Math.min(1.0, Math.max(0.0, root.islandProgress)))
        : root.hubTopGap

    readonly property real islandRadius: root.animStyle === "island"
        ? Math.max(14, (root.pillH / 2) + (24 - (root.pillH / 2)) * Math.min(1.0, Math.max(0.0, root.islandProgress)))
        : 24

    // ─── Tabs ───────────────────────────────────────────────────────────────────
    // The hub ALWAYS opens on the calendar tab by default.
    property string currentTab: "calendar"

    // ─── Wallpaper Carousel State & Navigation ─────────────────────────────────
    property int wallIndex: 0

    function currentWallIdx() {
        if (!root.wallpapers || root.wallpapers.length === 0) return 0
        let cur = WallpaperState.current
        let idx = root.wallpapers.indexOf(cur)
        if (idx >= 0) return idx
        let curBase = cur ? cur.split("/").pop() : ""
        for (let i = 0; i < root.wallpapers.length; i++) {
            if (root.wallpapers[i].split("/").pop() === curBase) return i
        }
        return 0
    }

    function selectPrevWallpaper() {
        if (!root.wallpapers || root.wallpapers.length === 0) return
        let count = root.wallpapers.length
        let cur = root.currentWallIdx()
        let nextIdx = (cur - 1 + count) % count
        root.wallIndex = nextIdx
        WallpaperState.setWallpaper(root.wallpapers[nextIdx])
    }

    function selectNextWallpaper() {
        if (!root.wallpapers || root.wallpapers.length === 0) return
        let count = root.wallpapers.length
        let cur = root.currentWallIdx()
        let nextIdx = (cur + 1) % count
        root.wallIndex = nextIdx
        WallpaperState.setWallpaper(root.wallpapers[nextIdx])
    }

    Connections {
        target: WallpaperState
        function onCurrentChanged() {
            root.wallIndex = root.currentWallIdx()
        }
    }

    // ─── Dynamic Island Notification Banner ────────────────────────────────────
    property bool bannerActive: false
    property string bannerIcon: "notifications"
    property string bannerText: ""
    property var currentBannerNotif: null

    Timer {
        id: bannerTimer
        interval: 6500   // banner stays open for 6.5 seconds (within 5-7s)
        repeat: false
        onTriggered: {
            root.bannerActive = false
        }
    }

    Connections {
        target: NotificationState
        function onNotificationReceived(notif) {
            root.mediaExtended = false
            // When a notification arrives:
            // If the Hub window is NOT open, morph the bar pill into a Dynamic Island banner
            if (!popup.visible) {
                root.currentBannerNotif = notif
                root.bannerIcon = NotificationState.resolveIcon(notif.appName, notif.appIcon)
                let prefix = notif.appName ? (notif.appName + ": ") : ""
                let group = NotificationState.getGroup(notif.appName)
                if (group && group.count > 1) {
                    prefix = notif.appName + " (" + group.count + "): "
                }
                let title = (notif.summary || "").trim()
                let body = (notif.body || "").trim()
                let fullContent = ""
                if (title && body && title !== body) {
                    fullContent = title + " — " + body
                } else {
                    fullContent = title || body || "New alert"
                }
                root.bannerText = prefix + fullContent
                root.bannerActive = true
                bannerTimer.restart()
            }
        }
    }

    // ─── Settings sub-pages (opened by the toggle ">" chevrons) ──────────────────
    // "main" = sliders/toggles · "wifi"/"bluetooth" = the detail lists.
    // The pages live as extra children of the tab StackLayout (see below).
    //
    // The Wi-Fi / Bluetooth controls at the top of "main" are RadioPill.qml
    // tiles (see that file). Each one animates press/hover and shows LIVE state
    // on its second line — the SSID we're on for Wi-Fi, the connected device
    // name for Bluetooth. The glyph itself is a plain FIXED symbol on/off: it
    // never spins, pops or signal-flickers. That live text comes from the
    // `wifiStatusText` / `btStatusText` one-liners built from the state
    // collectors below (`wifiStateProc` / `btStateProc`).
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
            case "plum":      return "Pill Icon Segment"
            case "primary":   return "Pill Body / Capsule"
            case "violet":    return "Menu Card Background"
            case "attention": return "Active Workspace & Accent"
            case "indigo":    return "Occupied Workspace"
            case "bg":        return "Empty Workspace"
            case "ink":       return "Text & Icons"
            case "lavender":  return "Muted Text"
            case "cream":     return "Muted Text (Legacy)"
            default:          return slot || "Color Role"
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

    // ─── Live audio sink volume & mute helpers ──────────────────────────────────
    readonly property var audio: sink ? sink.audio : null
    readonly property real audioVolume: audio ? audio.volume : 0.0
    readonly property bool audioMuted: audio ? audio.muted : false
    readonly property int audioVolumePct: Math.round(audioVolume * 100)

    function toggleAudioMute() {
        if (root.audio) {
            root.audio.muted = !root.audio.muted
        }
    }

    function stepAudioVolume(dir) {
        if (!root.audio) return
        let next = Math.max(0.0, Math.min(1.0, root.audioVolume + (dir > 0 ? 0.05 : -0.05)))
        root.audio.volume = Number(next.toFixed(2))
        if (dir > 0 && root.audioMuted) root.audio.muted = false
    }

    // ─── MPRIS / Spotify Live State & Playback ───────────────────────────────────
    readonly property var activeSpotifyPlayer: {
        let players = (typeof Mpris !== "undefined" && Mpris.players && Mpris.players.values) ? Mpris.players.values : []
        let spot = null
        let anyPlaying = null
        for (let i = 0; i < players.length; i++) {
            let p = players[i]
            if (!p) continue
            let id = ((p.identity || "") + " " + (p.dbusName || "")).toLowerCase()
            let playing = (p.isPlaying === true) || (p.playbackState === MprisPlaybackState.Playing)
            if (id.includes("spotify")) {
                if (playing) return p
                if (!spot) spot = p
            } else if (playing && !anyPlaying) {
                anyPlaying = p
            }
        }
        return spot || anyPlaying || null
    }

    readonly property bool isMusicPlaying: {
        if (root.activeSpotifyPlayer) {
            return (root.activeSpotifyPlayer.isPlaying === true) || (root.activeSpotifyPlayer.playbackState === MprisPlaybackState.Playing)
        }
        return root.externalPlayerStatus.toLowerCase() === "playing"
    }

    readonly property string spotifyTrackTitle: {
        if (root.activeSpotifyPlayer && root.activeSpotifyPlayer.trackTitle) {
            return root.activeSpotifyPlayer.trackTitle
        }
        return root.externalTrackTitle || "Spotify Music"
    }

    readonly property string spotifyTrackArtist: {
        if (root.activeSpotifyPlayer && root.activeSpotifyPlayer.trackArtist) {
            return root.activeSpotifyPlayer.trackArtist
        }
        return root.externalTrackArtist || ""
    }

    property string externalPlayerStatus: "Stopped"
    property string externalTrackTitle: ""
    property string externalTrackArtist: ""
    property bool mediaExtended: false

    onIsMusicPlayingChanged: {
        if (!isMusicPlaying) {
            mediaExtended = false
        }
    }

    Process {
        id: spotifyCliProc
        command: ["bash", "-c", "STATUS=$(playerctl --player=spotify,%any metadata --format '{{status}}|||{{title}}|||{{artist}}' 2>/dev/null || echo ''); VOL=$(playerctl --player=spotify,%any volume 2>/dev/null || echo ''); echo \"$STATUS|||$VOL\""]
        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split("|||")
                if (parts.length >= 2 && parts[0].trim() !== "") {
                    root.externalPlayerStatus = parts[0].trim()
                    root.externalTrackTitle = parts[1].trim()
                    root.externalTrackArtist = (parts.length >= 3 ? parts[2].trim() : "")
                    if (parts.length >= 4 && parts[3].trim() !== "") {
                        let parsedVol = parseFloat(parts[3].trim())
                        if (!isNaN(parsedVol) && parsedVol >= 0) {
                            root.externalSpotifyVolume = Math.max(0.0, Math.min(1.0, parsedVol))
                        }
                    }
                } else if (data.trim() === "" || data.trim() === "|||") {
                    root.externalPlayerStatus = "Stopped"
                }
            }
        }
    }

    Timer {
        id: spotifyPollTimer
        interval: 1500
        running: true
        repeat: true
        onTriggered: {
            if (!spotifyCliProc.running) spotifyCliProc.running = true
        }
    }

    function spotifyTogglePlay() {
        if (root.activeSpotifyPlayer && typeof root.activeSpotifyPlayer.togglePlaying === "function") {
            root.activeSpotifyPlayer.togglePlaying()
        } else {
            Quickshell.execDetached(["playerctl", "--player=spotify,%any", "play-pause"])
        }
        spotifyPollTimer.restart()
        if (!spotifyCliProc.running) spotifyCliProc.running = true
    }

    function spotifyNext() {
        if (root.activeSpotifyPlayer && typeof root.activeSpotifyPlayer.next === "function") {
            root.activeSpotifyPlayer.next()
        } else {
            Quickshell.execDetached(["playerctl", "--player=spotify,%any", "next"])
        }
        spotifyPollTimer.restart()
        if (!spotifyCliProc.running) spotifyCliProc.running = true
    }

    function spotifyPrevious() {
        if (root.activeSpotifyPlayer && typeof root.activeSpotifyPlayer.previous === "function") {
            root.activeSpotifyPlayer.previous()
        } else {
            Quickshell.execDetached(["playerctl", "--player=spotify,%any", "previous"])
        }
        spotifyPollTimer.restart()
        if (!spotifyCliProc.running) spotifyCliProc.running = true
    }

    // ─── Spotify / Media Volume State & Controls ─────────────────────────────────
    property real savedSpotifyVolume: 0.8
    property real externalSpotifyVolume: 0.8

    readonly property real spotifyVolume: {
        if (root.activeSpotifyPlayer && typeof root.activeSpotifyPlayer.volume === "number" && root.activeSpotifyPlayer.volume >= 0) {
            return Math.max(0.0, Math.min(1.0, root.activeSpotifyPlayer.volume))
        }
        return Math.max(0.0, Math.min(1.0, root.externalSpotifyVolume))
    }

    readonly property bool spotifyMuted: root.spotifyVolume <= 0.001
    readonly property int spotifyVolumePct: Math.round(root.spotifyVolume * 100)

    function setSpotifyVolume(val) {
        let clamped = Math.max(0.0, Math.min(1.0, val))
        clamped = Number(clamped.toFixed(2))
        root.externalSpotifyVolume = clamped
        if (clamped > 0.01) {
            root.savedSpotifyVolume = clamped
        }
        if (root.activeSpotifyPlayer) {
            try {
                root.activeSpotifyPlayer.volume = clamped
            } catch (e) {}
        }
        Quickshell.execDetached(["playerctl", "--player=spotify,%any", "volume", clamped.toString()])
        if (!spotifyCliProc.running) spotifyCliProc.running = true
    }

    function toggleSpotifyMute() {
        if (root.spotifyMuted) {
            let target = (root.savedSpotifyVolume > 0.05) ? root.savedSpotifyVolume : 0.8
            root.setSpotifyVolume(target)
        } else {
            root.savedSpotifyVolume = (root.spotifyVolume > 0.05) ? root.spotifyVolume : 0.8
            root.setSpotifyVolume(0.0)
        }
    }

    function stepSpotifyVolume(dir) {
        let current = root.spotifyVolume
        let next = Math.max(0.0, Math.min(1.0, current + (dir > 0 ? 0.05 : -0.05)))
        root.setSpotifyVolume(next)
    }

    // ─── Device state (brightness / radios) ─────────────────────────────────────
    property real brightnessVal: 0.8
    property real brightnessMax: 937
    property bool wifiActive: true
    property bool btActive: true

    // ─── Radio detail state (feeds the responsive Wi-Fi / BT tiles) ──────────────
    // The tiles read these; the Process blocks below keep them fresh.
    property string wifiSsid: ""            // SSID we are joined to ("" = none)
    property bool wifiBusy: false           // an nmcli command is in flight
    property string btDevice: ""            // name of the connected BT device ("" = none)
    property int btConnected: 0             // how many BT devices are connected
    property bool btBusy: false             // a bluetoothctl command is in flight

    // ─── Derived one-liners shown on the second line of each tile ────────────────
    readonly property string wifiStatusText: root.wifiBusy
        ? (root.wifiActive ? "Turning on…" : "Turning off…")
        : (!root.wifiActive ? "Off" : (root.wifiSsid !== "" ? root.wifiSsid : "Not connected"))

    readonly property string btStatusText: root.btBusy
        ? (root.btActive ? "Turning on…" : "Turning off…")
        : (!root.btActive ? "Off" : (root.btConnected > 0 ? root.btDevice : "Not connected"))

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

    //  2. Wi-Fi state + live connection  (radio | "*:SSID")
    //  One shell call answers BOTH "is the radio on?" and "what am I joined
    //  to?" — the tile needs the second half for its status line. SIGNAL is
    //  deliberately NOT requested: the tile's glyph is fixed (see RadioPill),
    //  so the reading would only be an unused number that wobbles.
    //  Example output:   enabled|*:My WiFi
    Process {
        id: wifiStateProc
        command: ["bash", "-c",
                  "r=$(nmcli radio wifi); "
                  + "i=$(nmcli -t -f IN-USE,SSID device wifi list 2>/dev/null | grep '^\\*' | head -n1); "
                  + "echo \"$r|$i\""]

        stdout: SplitParser {
            onRead: data => {
                let raw = data.trim()
                let bar = raw.indexOf("|")
                if (bar < 0) return

                // Left of the "|" → the radio state.
                root.wifiActive = raw.slice(0, bar).toLowerCase().startsWith("enabled")

                // Right of the "|" → "*:SSID" for the network we are joined to,
                // or "" when nothing is connected. nmcli escapes a ":" inside
                // an SSID as "\:", so undo that before showing the name.
                root.wifiSsid = raw.slice(bar + 1)
                                   .replace(/^\*:/, "")
                                   .replace(/\\:/g, ":")
            }
        }

        // The command has answered → the tile may leave its busy state.
        onExited: root.wifiBusy = false
    }

    //  3. Bluetooth state + live connection  (on/off | count | first device)
    //  Example output:   on|1|QCY-T13 ANC
    Process {
        id: btStateProc
        command: ["bash", "-c",
                  "p=$(bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off); "
                  + "c=$(bluetoothctl devices Connected 2>/dev/null | grep -c . ); "
                  + "d=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-); "
                  + "echo \"$p|$c|$d\""]

        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split("|")
                if (parts.length < 3) return
                root.btActive = (parts[0] === "on")
                root.btConnected = parseInt(parts[1]) || 0
                root.btDevice = parts[2] || ""
            }
        }

        onExited: root.btBusy = false
    }

    // ─── Radio follow-up timers (shared by the Wi-Fi / BT tiles) ────────────────
    // After a radio command we WAIT a moment before re-reading: nmcli and
    // bluetoothctl answer asynchronously, so asking instantly would read the OLD
    // state and make the tile snap straight back.
    Timer {
        id: wifiSettle
        interval: 900
        repeat: false
        onTriggered: if (!wifiStateProc.running) wifiStateProc.running = true
    }

    Timer {
        id: btSettle
        interval: 900
        repeat: false
        onTriggered: if (!btStateProc.running) btStateProc.running = true
    }

    // Safety nets: if a reader never runs (or its `onExited` never lands), clear
    // `busy` anyway so a tile can't be left stuck in its half-lit working state.
    Timer {
        id: wifiWatchdog
        interval: 6000
        repeat: false
        onTriggered: {
            root.wifiBusy = false
            if (!wifiStateProc.running) wifiStateProc.running = true
        }
    }

    Timer {
        id: btWatchdog
        interval: 6000
        repeat: false
        onTriggered: {
            root.btBusy = false
            if (!btStateProc.running) btStateProc.running = true
        }
    }

    // Keep both tiles LIVE while the Settings page is on screen (radio state,
    // SSID, connected device). Cheap: two short reads every 5 s, and never
    // while a toggle is already waiting on its own read.
    Timer {
        id: radioPollTimer
        interval: 5000
        running: popup.visible && root.currentTab === "settings"
        repeat: true
        onTriggered: {
            if (!root.wifiBusy && !wifiStateProc.running) wifiStateProc.running = true
            if (!root.btBusy && !btStateProc.running) btStateProc.running = true
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
    //  Top level of the config's wallpapers folder only. Automatically sanitizes
    //  and converts any WebP, AVIF, or renamed images into standard JPEG first.
    Process {
        id: wallScanProc
        command: ["bash", "-c",
                  "if [ -x \"$HOME/.config/quickshell/sanitize-wallpapers.sh\" ]; then "
                  + "\"$HOME/.config/quickshell/sanitize-wallpapers.sh\" \"$HOME/.config/quickshell/wallpapers\" 2>/dev/null; "
                  + "fi; "
                  + "find \"$HOME/.config/quickshell/wallpapers\" -maxdepth 1 -type f "
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
                root.wallIndex = root.currentWallIdx()
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
    //     wallpapers folder, sanitizes format, then rescans so it shows up everywhere.
    Process {
        id: importProc
        property string source: ""
        command: ["bash", "-c",
                  "cp -n \"$1\" \"$HOME/.config/quickshell/wallpapers/\" && "
                  + "if [ -x \"$HOME/.config/quickshell/sanitize-wallpapers.sh\" ]; then "
                  + "\"$HOME/.config/quickshell/sanitize-wallpapers.sh\" \"$HOME/.config/quickshell/wallpapers\" 2>/dev/null; "
                  + "fi",
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

    // ─── Priority 1 & 2 State Detection ──────────────────────────────────────────
    readonly property bool hasPendingNotifs: NotificationState.totalCount > 0

    // Priority 1: Ringing animation - swinging like a bell giving out sound
    SequentialAnimation {
        id: bellRingAnim
        running: !root.open && root.hasPendingNotifs && !root.bannerActive
        loops: Animation.Infinite

        NumberAnimation { target: root; property: "iconRotation"; to: -18; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "iconRotation"; to: 18; duration: 130; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "iconRotation"; to: -14; duration: 110; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "iconRotation"; to: 14; duration: 100; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "iconRotation"; to: -8; duration: 90; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "iconRotation"; to: 8; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "iconRotation"; to: 0; duration: 70; easing.type: Easing.InOutQuad }

        PauseAnimation { duration: 1400 }

        onRunningChanged: {
            if (!running) root.iconRotation = 0
        }
    }

    // Priority 2: Music beat pulse animation - pulsing rhythmically to the beat (~120 BPM)
    SequentialAnimation {
        id: musicBeatPulseAnim
        running: !root.open && root.isMusicPlaying && !root.hasPendingNotifs && !root.bannerActive
        loops: Animation.Infinite

        NumberAnimation { target: root; property: "iconScale"; to: 1.24; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "iconScale"; to: 1.0; duration: 390; easing.type: Easing.InOutQuad }

        onRunningChanged: {
            if (!running) root.iconScale = 1.0
        }
    }

    // ─── The idle face: a plain clock pill, ringing bell, music note, or active banner ──
    icon: root.bannerActive ? root.bannerIcon
        : (!root.open && root.hasPendingNotifs ? "notifications"
        : (!root.open && root.isMusicPlaying ? "music_note"
        : "nest_clock_farsight_analog"))

    label: root.bannerActive ? root.bannerText
         : Qt.formatDateTime(clock.date, "hh:mm AP")

    bgColor: root.bannerActive ? Theme.attention
           : (!root.open && root.hasPendingNotifs ? Theme.attention
           : (!root.open && root.isMusicPlaying ? "#1db954"
           : Theme.plum))

    iconColor: root.bannerActive ? Theme.qsOnAccent
             : (!root.open && root.hasPendingNotifs ? Theme.qsOnAccent
             : (!root.open && root.isMusicPlaying ? "#ffffff"
             : Theme.ink))

    labelBg: root.open ? Theme.indigo : Theme.primary

    textColor: root.bannerActive ? Theme.attention : Theme.ink

    maxLabelWidth: root.bannerActive ? 520 : 150

    iconTransformOrigin: (!root.open && root.hasPendingNotifs) ? Item.Top : Item.Center

    customBody: (!root.open && root.isMusicPlaying && root.mediaExtended && !root.hasPendingNotifs && !root.bannerActive)
        ? mediaControlsBar
        : null

    // ─── Extended Dynamic Island Media Controls Bar ──────────────────────────────
    Item {
        id: mediaControlsBar
        implicitHeight: Theme.pillHeight
        implicitWidth: mediaLayout.implicitWidth + 8

        RowLayout {
            id: mediaLayout
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // 1. Song Title & Artist text
            RowLayout {
                spacing: 4
                Layout.maximumWidth: 160
                clip: true

                Text {
                    id: songTitleTxt
                    text: root.spotifyTrackTitle
                    font.family: Theme.fontText
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.ink
                    elide: Text.ElideRight
                    Layout.maximumWidth: 100
                }

                Text {
                    visible: root.spotifyTrackArtist !== ""
                    text: "• " + root.spotifyTrackArtist
                    font.family: Theme.fontText
                    font.pixelSize: 11
                    color: Theme.lavender
                    elide: Text.ElideRight
                    Layout.maximumWidth: 55
                }
            }

            // Divider
            Rectangle {
                implicitWidth: 1
                implicitHeight: 14
                color: Theme.pillBorder !== "transparent" ? Theme.pillBorder : Qt.rgba(1, 1, 1, 0.15)
            }

            // 2. Playback Controls: Previous, Play/Pause, Next
            RowLayout {
                spacing: 4

                // Previous Button
                Rectangle {
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: prevArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "skip_previous"
                        font.family: Theme.fontIcons
                        font.pixelSize: 15
                        color: Theme.ink
                    }

                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.spotifyPrevious()
                    }
                }

                // Play / Pause Button
                Rectangle {
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: playArea.containsMouse ? "#1ed760" : "#1db954"

                    Text {
                        anchors.centerIn: parent
                        text: root.isMusicPlaying ? "pause" : "play_arrow"
                        font.family: Theme.fontIcons
                        font.pixelSize: 15
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.spotifyTogglePlay()
                    }
                }

                // Next Button
                Rectangle {
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: nextArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "skip_next"
                        font.family: Theme.fontIcons
                        font.pixelSize: 15
                        color: Theme.ink
                    }

                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.spotifyNext()
                    }
                }
            }

            // Divider
            Rectangle {
                implicitWidth: 1
                implicitHeight: 14
                color: Theme.pillBorder !== "transparent" ? Theme.pillBorder : Qt.rgba(1, 1, 1, 0.15)
            }

            // 3. Spotify Audio / Volume Controls (controls Spotify volume, NOT global system volume)
            RowLayout {
                spacing: 5

                // Volume / Mute button (Click = mute/unmute Spotify, Wheel = step Spotify volume)
                Rectangle {
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 11
                    color: volArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: root.spotifyMuted ? "volume_off"
                            : (root.spotifyVolumePct > 50 ? "volume_up"
                            : (root.spotifyVolumePct > 0 ? "volume_down" : "volume_mute"))
                        font.family: Theme.fontIcons
                        font.pixelSize: 14
                        color: root.spotifyMuted ? Theme.attention : Theme.ink
                    }

                    MouseArea {
                        id: volArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleSpotifyMute()
                        onWheel: wheel => {
                            root.stepSpotifyVolume(wheel.angleDelta.y > 0 ? 1 : -1)
                        }
                    }
                }

                // Interactive Mini Volume Slider Bar for Spotify
                Rectangle {
                    id: miniVolTrack
                    implicitWidth: 46
                    implicitHeight: 6
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.18)

                    Rectangle {
                        id: miniVolFill
                        height: parent.height
                        width: Math.max(0, Math.min(parent.width, parent.width * root.spotifyVolume))
                        radius: 3
                        color: root.spotifyMuted ? Theme.lavender : "#1db954"

                        Behavior on width {
                            enabled: !sliderDragArea.drag.active
                            NumberAnimation { duration: 80 }
                        }
                    }

                    // Thumb indicator
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, (parent.width * root.spotifyVolume) - (width / 2)))
                        width: 10
                        height: 10
                        radius: 5
                        color: "#ffffff"
                        visible: sliderDragArea.containsMouse || sliderDragArea.drag.active

                        Behavior on x {
                            enabled: !sliderDragArea.drag.active
                            NumberAnimation { duration: 80 }
                        }
                    }

                    MouseArea {
                        id: sliderDragArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        function updateVolFromMouse(mouseX) {
                            let relX = Math.max(0, Math.min(miniVolTrack.width, mouseX - 4))
                            let ratio = relX / miniVolTrack.width
                            root.setSpotifyVolume(ratio)
                        }

                        onPressed: mouse => updateVolFromMouse(mouse.x)
                        onPositionChanged: mouse => {
                            if (pressed) updateVolFromMouse(mouse.x)
                        }
                        onWheel: wheel => {
                            root.stepSpotifyVolume(wheel.angleDelta.y > 0 ? 1 : -1)
                        }
                    }
                }

                Text {
                    text: root.spotifyMuted ? "Mute" : (root.spotifyVolumePct + "%")
                    font.family: Theme.fontText
                    font.pixelSize: 10
                    font.bold: true
                    color: root.spotifyMuted ? Theme.attention : Theme.lavender

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleSpotifyMute()
                        onWheel: wheel => {
                            root.stepSpotifyVolume(wheel.angleDelta.y > 0 ? 1 : -1)
                        }
                    }
                }
            }

            // 4. Open full Hub Window Button
            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: expandBtnArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "open_in_full"
                    font.family: Theme.fontIcons
                    font.pixelSize: 12
                    color: Theme.lavender
                }

                MouseArea {
                    id: expandBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.expand()
                }
            }

            // 5. Retract / Close Button
            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: closeBtnArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "close"
                    font.family: Theme.fontIcons
                    font.pixelSize: 13
                    color: Theme.lavender
                }

                MouseArea {
                    id: closeBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.mediaExtended = false
                    }
                }
            }
        }
    }

    // ─── Click = expand / collapse / notification / media ─────────────────────────
    MouseArea {
        id: clickArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.toggle()
                return
            }

            if (root.bannerActive) {
                if (root.currentBannerNotif) {
                    NotificationState.dismissNotification(root.currentBannerNotif)
                    root.currentBannerNotif = null
                }
                bannerTimer.stop()
                root.bannerActive = false
                root.collapse()
                return
            } else if (!root.open && root.hasPendingNotifs) {
                // Priority #1: Click on ringing bell opens notifications tab in hub!
                root.openTab("notifications")
            } else if (!root.open && root.isMusicPlaying) {
                // Priority #2: Click on pulsing music note extends/retracts media controls!
                root.mediaExtended = !root.mediaExtended
            } else {
                root.toggle()
            }
        }
    }

    // Same hover lift the Wi-Fi/BT tiles use — the bar pill is a button too.
    HoverLift { }

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
            root.expand(tab)
            root.setTab(tab)
        }
    }

    function openTab(tab) {
        if (!popup.visible) root.expand(tab)
        root.setTab(tab)
    }

    function expand(initialTab) {
        root.mediaExtended = false
        root.bannerActive = false
        bannerTimer.stop()
        closeDelay.stop()               // cancel a close that's mid-flight
        openDelay.stop()
        closing = false
        stopAllAnims()
        prepareFace()                   // undo whatever a previous close left behind
        root.currentTab = initialTab || "calendar"    // default to calendar or requested tab on open
        root.hubPage = "main"
        root.themePage = "picker"
        root.wallIndex = root.currentWallIdx()
        if (root.animStyle === "island") {
            root.contentOpacity = 0.0
            root.islandProgress = 0.0
        }
        popup.visible = true
        grab.active = true              // arm click-outside-to-close
        root.refreshData()
        openDelay.restart()             // let the surface map BEFORE animating
    }

    function collapse() {
        grab.active = false             // release the focus grab
        openDelay.stop()                // don't let a pending open animation fire
        if (closing) return             // already animating out — don't restart it
        closing = true
        root.currentTab = "calendar"    // reset back to calendar on close
        root.hubPage = "main"
        root.themePage = "picker"
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

    // ─── Radio toggles (called by the Wi-Fi / BT tiles) ─────────────────────────
    // The FLIP IS OPTIMISTIC: the boolean flips immediately so the tile can
    // animate right away, then `settle`/`watchdog` re-read the real state and
    // correct us if the command failed. `busy` holds the half-lit "working"
    // state (and blocks re-clicks) until then.
    function toggleWifi() {
        if (root.wifiBusy) return                       // ignore re-clicks mid-flight
        root.wifiBusy = true
        root.wifiActive = !root.wifiActive
        Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiActive ? "on" : "off"])
        wifiSettle.restart()
        wifiWatchdog.restart()
    }

    function toggleBt() {
        if (root.btBusy) return
        root.btBusy = true
        root.btActive = !root.btActive
        Quickshell.execDetached(["bluetoothctl", "power", root.btActive ? "on" : "off"])
        btSettle.restart()
        btWatchdog.restart()
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
        // (never on a stale wifi/bluetooth sub-page) and re-reads the radios,
        // so the Wi-Fi / BT tiles never show a stale SSID or device name.
        if (tab === "settings") {
            root.hubPage = "main"
            if (!wifiStateProc.running) wifiStateProc.running = true
            if (!btStateProc.running) btStateProc.running = true
        }
        // Opening the theme tab refreshes the wallpaper list.
        if (tab === "theme") {
            root.themePage = "picker"
            root.refreshWallpapers()
            root.wallIndex = root.currentWallIdx()
        }
        // The calendar shows weather, so make sure it's freshly fetched.
        if (tab === "calendar" && !weatherProc.running) weatherProc.running = true
    }

    function startOpen() {
        resetContent()                            // clear leftovers from a stagger close
        switch (root.animStyle) {
            case "island":  animIslandOpen.start();  break
            case "pop":     animPopOpen.start();     break
            case "curtain": animCurtainOpen.start(); break
            case "stagger":
                // Pre-hide the chrome + content so each stagger step is visible.
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
            case "island":  animIslandClose.start();  break
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
            case "island":  return 250
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
            root.contentOpacity = 1.0
            root.islandProgress = 0.0
        }
    }

    // Stops every open/close group, so two animations can never fight over
    // the same property when the hub flips state mid-animation.
    function stopAllAnims() {
        animIslandOpen.stop();  animIslandClose.stop()
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
        if (root.animStyle !== "island") {
            face.opacity = 0                // open animations fade it back in
            faceScale.xScale = 1; faceScale.yScale = 1
            faceShift.y = 0
            faceSpin.angle = 0
        } else {
            face.opacity = 1
            root.islandProgress = 0.0
        }
    }

    // =============================================================================
    //  THE FLOATING WINDOW  (the expanded state)
    // =============================================================================
    PanelWindow {
        id: popup

        screen: root.screen
        visible: false
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        // When the window hides (close animation finished), stop everything
        // and rest every animated property, so reopening always starts fresh.
        onVisibleChanged: if (!visible) {
            grab.active = false
            stopAllAnims()
            prepareFace()
            root.currentTab = "calendar"
            root.hubPage = "main"
            root.themePage = "picker"
            root.contentOpacity = 1.0
            root.islandProgress = 0.0
        }

        anchors { top: true; left: true }
        margins {
            top: 0
            left: Math.max(0, Math.round((popup.screen.width - root.hubW) / 2))
        }

        // Window size — transparent surface accommodating the island's expansion and top resting position.
        implicitWidth: root.hubW
        implicitHeight: root.hubH + 20

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
        // The card (`stage`) fills the window. In Dynamic Island mode, the `face`
        // morphs from the top bar pill down to the full card with Apple spring physics.
        Item {
            id: stage
            anchors.fill: parent   // card fills the window — no dead zones

            // Dismiss when clicking anywhere outside the island surface
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: root.collapse()
            }

            Item {
                id: reveal
                anchors.fill: parent
                clip: root.animStyle !== "island"

                Rectangle {
                    id: face
                    x: root.animStyle === "island" ? root.islandX : 0
                    y: root.animStyle === "island" ? root.islandY : 0
                    width: root.animStyle === "island" ? root.islandW : parent.width
                    height: root.animStyle === "island" ? root.islandH : reveal.height
                    radius: root.animStyle === "island" ? root.islandRadius : 14
                    color: Theme.qsBg
                    clip: true
                    opacity: root.animStyle === "island" ? 1 : 0
                    border.width: 1
                    border.color: Theme.pillBorder !== "transparent" ? Theme.pillBorder : Qt.rgba(1, 1, 1, 0.08)

                    transform: [
                        Translate { id: faceShift; y: 0 },
                        Rotation  { id: faceSpin;  origin.x: face.width / 2; origin.y: 0; angle: 0 },
                        Scale     { id: faceScale; origin.x: face.width / 2; origin.y: 0; xScale: 1; yScale: 1 }
                    ]

                    // ─── Apple Dynamic Island Animations ────────────────────
                    ParallelAnimation {
                        id: animIslandOpen
                        running: false
                        NumberAnimation {
                            target: root
                            property: "islandProgress"
                            from: root.islandProgress
                            to: 1.0
                            duration: 380
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.15
                        }
                    }

                    ParallelAnimation {
                        id: animIslandClose
                        running: false
                        NumberAnimation {
                            target: root
                            property: "islandProgress"
                            from: root.islandProgress
                            to: 0.0
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                        onFinished: {
                            popup.visible = false
                            closing = false
                            root.contentOpacity = 1.0
                            root.islandProgress = 0.0
                        }
                    }

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

                    // ─── Apple Dynamic Island: Collapsed Pill Face (Phase 1) ───
                    Item {
                        id: morphPillFace
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.max(0, (Math.min(face.height, root.pillH) - root.pillH) / 2)
                        width: root.pillW
                        height: root.pillH
                        visible: opacity > 0.001
                        opacity: root.animStyle === "island" ? Math.max(0.0, 1.0 - root.islandProgress * 3.5) : 0.0

                        Rectangle {
                            id: morphIconSeg
                            width: root.iconSegWidth > 0 ? root.iconSegWidth : 36
                            height: parent.height
                            anchors.left: parent.left
                            color: root.bgColor
                            topLeftRadius: height / 2
                            bottomLeftRadius: height / 2
                            topRightRadius: 0
                            bottomRightRadius: 0

                            Text {
                                anchors.centerIn: parent
                                text: root.icon
                                color: root.iconColor
                                font.family: Theme.fontIcons
                                font.pixelSize: 17
                                leftPadding: 4
                            }
                        }

                        Rectangle {
                            id: morphTextSeg
                            width: Math.max(0, parent.width - morphIconSeg.width)
                            height: parent.height
                            anchors.left: morphIconSeg.right
                            color: root.open ? Theme.indigo : Theme.primary
                            topLeftRadius: 0
                            bottomLeftRadius: 0
                            topRightRadius: height / 2
                            bottomRightRadius: height / 2

                            Text {
                                anchors.centerIn: parent
                                width: Math.max(0, parent.width - 16)
                                elide: Text.ElideRight
                                text: root.label
                                color: root.textColor
                                font.family: Theme.fontText
                                font.pixelSize: 14
                            }
                        }
                    }

                    // ─── Apple Dynamic Island: Expanded Hub Content (Phase 2) ───
                    Item {
                        id: cardContent
                        width: root.hubW
                        height: root.hubH
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        clip: false
                        visible: opacity > 0.001
                        opacity: root.animStyle === "island"
                            ? Math.min(1.0, Math.max(0.0, (root.islandProgress - 0.20) / 0.60))
                            : 1.0
                        transform: Translate {
                            y: root.animStyle === "island" ? (1.0 - Math.min(1.0, root.islandProgress)) * 14 : 0
                        }

                        // =============================================================
                        //  THE CARD CONTENT  (browser-style top tabs & views)
                        // =============================================================
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                        // ─── BROWSER-STYLE TOP TABS: Calendar | Theme | Settings ─────
                        // Each tab = an icon pill + a name pill. The name pill EXPANDS
                        // (showing the tab name) while you're inside that tab and
                        // RETRACTS to match the icon width (26px) when the tab is closed,
                        // giving a balanced, equal-sized pill when collapsed. Same 320ms
                        // OutCubic expand/compact motion as the notification banner
                        // in Pill.qml.
                        RowLayout {
                            id: tabBarRow
                            opacity: 1
                            transform: Translate { id: tabBarLift; y: 0 }
                            Layout.fillWidth: true
                            spacing: 8

                            // ── Calendar tab ──
                            Rectangle {
                                height: 26
                                implicitWidth: tabCalIcon.width + tabCalLabel.width
                                color: "transparent"

                                Rectangle {
                                    id: tabCalIcon
                                    width: 26
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "calendar" ? Theme.attention : Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "calendar_month"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 13
                                        color: root.currentTab === "calendar" ? Theme.qsOnAccent : Theme.ink
                                        leftPadding: 1
                                    }
                                }

                                Rectangle {
                                    id: tabCalLabel
                                    height: parent.height
                                    width: root.currentTab === "calendar" ? tabCalTxt.implicitWidth + 14 : tabCalIcon.width
                                    clip: true   // name is clipped away while the pill retracts
                                    anchors.left: tabCalIcon.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "calendar" ? Theme.attention : Theme.primary
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2

                                    // Expand/compact motion - identical to the notification banner's
                                    // expansion/compaction in Pill.qml (320ms OutCubic).
                                    Behavior on width {
                                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                    }

                                    Text {
                                        id: tabCalTxt
                                        opacity: root.currentTab === "calendar" ? 1 : 0   // fades as the pill grows/retracts
                                        Behavior on opacity {
                                            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                        }
                                        anchors.centerIn: parent
                                        text: "Calendar"
                                        font.family: Theme.fontText
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: root.currentTab === "calendar" ? Theme.qsOnAccent : Theme.ink
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTab("calendar")
                                }

                                HoverLift { }
                            }

                            // ── Theme tab ──
                            Rectangle {
                                height: 26
                                implicitWidth: tabThemeIcon.width + tabThemeLabel.width
                                color: "transparent"

                                Rectangle {
                                    id: tabThemeIcon
                                    width: 26
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "theme" ? Theme.attention : Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "palette"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 13
                                        color: root.currentTab === "theme" ? Theme.qsOnAccent : Theme.ink
                                        leftPadding: 1
                                    }
                                }

                                Rectangle {
                                    id: tabThemeLabel
                                    height: parent.height
                                    width: root.currentTab === "theme" ? tabThemeTxt.implicitWidth + 14 : tabThemeIcon.width
                                    clip: true   // name is clipped away while the pill retracts
                                    anchors.left: tabThemeIcon.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "theme" ? Theme.attention : Theme.primary
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2

                                    // Expand/compact motion - identical to the notification banner's
                                    // expansion/compaction in Pill.qml (320ms OutCubic).
                                    Behavior on width {
                                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                    }

                                    Text {
                                        id: tabThemeTxt
                                        opacity: root.currentTab === "theme" ? 1 : 0   // fades as the pill grows/retracts
                                        Behavior on opacity {
                                            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                        }
                                        anchors.centerIn: parent
                                        text: "Theme"
                                        font.family: Theme.fontText
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: root.currentTab === "theme" ? Theme.qsOnAccent : Theme.ink
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTab("theme")
                                }

                                HoverLift { }
                            }

                            // ── Notifications tab ──
                            Rectangle {
                                height: 26
                                implicitWidth: tabNotifIcon.width + tabNotifLabel.width
                                color: "transparent"

                                Rectangle {
                                    id: tabNotifIcon
                                    width: 26
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "notifications" ? Theme.attention : Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "notifications"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 13
                                        color: root.currentTab === "notifications" ? Theme.qsOnAccent : Theme.ink
                                        leftPadding: 1
                                    }
                                }

                                Rectangle {
                                    id: tabNotifLabel
                                    height: parent.height
                                    width: root.currentTab === "notifications" ? tabNotifRow.implicitWidth + 14 : tabNotifIcon.width
                                    clip: true   // name is clipped away while the pill retracts
                                    anchors.left: tabNotifIcon.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "notifications" ? Theme.attention : Theme.primary
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2

                                    // Expand/compact motion - identical to the notification banner's
                                    // expansion/compaction in Pill.qml (320ms OutCubic).
                                    Behavior on width {
                                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                    }

                                    RowLayout {
                                        id: tabNotifRow
                                        opacity: root.currentTab === "notifications" ? 1 : 0   // fades as the pill grows/retracts
                                        Behavior on opacity {
                                            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                        }
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            id: tabNotifTxt
                                            text: "Notifications"
                                            font.family: Theme.fontText
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: root.currentTab === "notifications" ? Theme.qsOnAccent : Theme.ink
                                        }

                                        Rectangle {
                                            id: notifBadge
                                            visible: NotificationState.totalCount > 0
                                            implicitHeight: 14
                                            implicitWidth: notifBadgeTxt.implicitWidth + 8
                                            radius: 7
                                            color: root.currentTab === "notifications" ? Theme.qsBg : Theme.attention

                                            Text {
                                                id: notifBadgeTxt
                                                anchors.centerIn: parent
                                                text: NotificationState.totalCount
                                                font.family: Theme.fontText
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: root.currentTab === "notifications" ? Theme.attention : Theme.qsOnAccent
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTab("notifications")
                                }

                                HoverLift { }
                            }

                            // ── Settings tab ──
                            Rectangle {
                                height: 26
                                implicitWidth: tabSettingsIcon.width + tabSettingsLabel.width
                                color: "transparent"

                                Rectangle {
                                    id: tabSettingsIcon
                                    width: 26
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "settings" ? Theme.attention : Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "tune"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 13
                                        color: root.currentTab === "settings" ? Theme.qsOnAccent : Theme.ink
                                        leftPadding: 1
                                    }
                                }

                                Rectangle {
                                    id: tabSettingsLabel
                                    height: parent.height
                                    width: root.currentTab === "settings" ? tabSettingsTxt.implicitWidth + 14 : tabSettingsIcon.width
                                    clip: true   // name is clipped away while the pill retracts
                                    anchors.left: tabSettingsIcon.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.currentTab === "settings" ? Theme.attention : Theme.primary
                                    topLeftRadius: 0
                                    bottomLeftRadius: 0
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2

                                    // Expand/compact motion - identical to the notification banner's
                                    // expansion/compaction in Pill.qml (320ms OutCubic).
                                    Behavior on width {
                                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                    }

                                    Text {
                                        id: tabSettingsTxt
                                        opacity: root.currentTab === "settings" ? 1 : 0   // fades as the pill grows/retracts
                                        Behavior on opacity {
                                            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                        }
                                        anchors.centerIn: parent
                                        text: "Settings"
                                        font.family: Theme.fontText
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: root.currentTab === "settings" ? Theme.qsOnAccent : Theme.ink
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setTab("settings")
                                }

                                HoverLift { }
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
                                currentIndex: root.currentTab === "notifications" ? 5
                                            : root.currentTab === "calendar" ? 4
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
                                    clip: false
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: contentHeight > height
                                    flickableDirection: Flickable.VerticalFlick
                                    contentWidth: width
                                    contentHeight: settingsCol.implicitHeight

                                    ColumnLayout {
                                        id: settingsCol
                                        width: settingsFlick.width
                                        spacing: 10

                                        // ── Compact Action Row: Wi-Fi, BT, Lock, Sleep, Power ──
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            // ── Wi-Fi Tile (responsive: press / hover / slow light-up / busy status) ──
                                            RadioPill {
                                                icon: "wifi"            // FIXED glyph (no morph, no spin)
                                                iconOff: "wifi_off"
                                                title: "Wi-Fi"
                                                status: root.wifiStatusText
                                                active: root.wifiActive
                                                busy: root.wifiBusy
                                                onToggled: root.toggleWifi()
                                                onOpenDetails: {
                                                    root.hubPage = "wifi"
                                                    root.refreshWifi()
                                                }
                                            }

                                            // ── Bluetooth Tile (same responsive treatment) ──
                                            RadioPill {
                                                icon: "bluetooth"
                                                iconOff: "bluetooth_disabled"
                                                title: "BT"
                                                status: root.btStatusText
                                                active: root.btActive
                                                busy: root.btBusy
                                                onToggled: root.toggleBt()
                                                onOpenDetails: {
                                                    root.hubPage = "bluetooth"
                                                    root.refreshBt()
                                                }
                                            }

                                            // ── Lock Pill ──
                                            ActionPill {
                                                Layout.fillWidth: true
                                                icon: "lock"
                                                label: "Lock"
                                                onClicked: { root.collapse(); Quickshell.execDetached(["hyprlock"]) }
                                            }

                                            // ── Sleep Pill ──
                                            ActionPill {
                                                Layout.fillWidth: true
                                                icon: "bedtime"
                                                label: "Sleep"
                                                onClicked: { root.collapse(); Quickshell.execDetached(["systemctl", "suspend"]) }
                                            }

                                            // ── Power Pill ──
                                            ActionPill {
                                                Layout.fillWidth: true
                                                icon: "power_settings_new"
                                                label: "Power"
                                                labelBg: Theme.primary
                                                onClicked: { root.collapse(); Quickshell.execDetached(["shutdown", "now"]) }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                                        // Spotify Application Volume Slider (when active)
                                        CustomSlider {
                                            visible: root.isMusicPlaying || (root.spotifyTrackTitle !== "" && root.spotifyTrackTitle !== "Spotify Music")
                                            icon: root.spotifyMuted ? "volume_off" : "music_note"
                                            value: root.spotifyVolume
                                            maxValue: 1.0
                                            displayText: root.spotifyMuted ? "Muted" : (root.spotifyVolumePct + "%")
                                            onValueChangedByUser: newVal => {
                                                root.setSpotifyVolume(newVal)
                                            }
                                        }

                                        // Volume — BOOST slider: goes up to 150%, no text percentage shown
                                        CustomSlider {
                                            icon: (root.sink && root.sink.audio && root.sink.audio.muted) ? "volume_off" : "volume_up"
                                            value: (root.sink && root.sink.audio) ? root.sink.audio.volume : 0.5
                                            maxValue: 1.5
                                            displayText: ""
                                            onValueChangedByUser: newVal => {
                                                if (root.sink && root.sink.audio) root.sink.audio.volume = newVal
                                            }
                                        }

                                        // Mic
                                        CustomSlider {
                                            icon: (root.source && root.source.audio && root.source.audio.muted) ? "mic_off" : "mic"
                                            value: (root.source && root.source.audio) ? root.source.audio.volume : 0.5
                                            displayText: ""
                                            onValueChangedByUser: newVal => {
                                                if (root.source && root.source.audio) root.source.audio.volume = newVal
                                            }
                                        }

                                        // Brightness
                                        CustomSlider {
                                            icon: "brightness_6"
                                            value: root.brightnessVal
                                            displayText: ""
                                            onValueChangedByUser: newVal => {
                                                root.brightnessVal = newVal
                                                let percent = Math.round(newVal * 100)
                                                Quickshell.execDetached(["brightnessctl", "set", percent + "%"])
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

                                            HoverLift { }
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

                                            HoverLift { }
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
                                                            // FIXED glyph on purpose: the list is already
                                                            // ordered by strength (connected first, then
                                                            // strongest), so a signal-derived icon would just
                                                            // flicker between bars as the scan refreshes.
                                                            text: "wifi"
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
                                                                            wifiSettle.restart() // …and refresh the Wi-Fi TILE (SSID)
                                                                        }
                                                                    }
                                                                }

                                                                HoverLift { }
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

                                            HoverLift { }
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

                                            HoverLift { }
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
                                                                        btSettle.restart()   // refresh the BT TILE (connected device name)
                                                                    }
                                                                }

                                                                HoverLift { }
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

                                            HoverLift { }
                                        }

                                        // Live Studio icon button — opens fullscreen workstation overlay
                                        Text {
                                            text: "colorize"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 18
                                            color: Theme.attention
                                            Layout.alignment: Qt.AlignVCenter

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let target = (root.themePage === "manage" && root.editingPath) ? root.editingPath : (WallpaperState.current || (root.wallpapers.length > 0 ? root.wallpapers[0] : ""))
                                                    root.collapse()
                                                    ThemeStudioState.open(target)
                                                }
                                            }

                                            HoverLift { }
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

                                            HoverLift { }
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

                                    // ── Carousel Coverflow View ──────────────────
                                    Item {
                                        id: wallCarousel
                                        visible: root.wallpapers.length > 0 && root.themePage === "picker"
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true

                                        readonly property int totalWps: root.wallpapers.length
                                        readonly property int activeIdx: root.currentWallIdx()
                                        readonly property int prevIdx: totalWps > 0 ? (activeIdx - 1 + totalWps) % totalWps : 0
                                        readonly property int nextIdx: totalWps > 0 ? (activeIdx + 1) % totalWps : 0

                                        readonly property string activeWp: totalWps > 0 ? root.wallpapers[activeIdx] : ""
                                        readonly property string prevWp: totalWps > 1 ? root.wallpapers[prevIdx] : ""
                                        readonly property string nextWp: totalWps > 1 ? root.wallpapers[nextIdx] : ""

                                        property real dragOffset: 0

                                        NumberAnimation {
                                            id: snapAnim
                                            target: wallCarousel
                                            property: "dragOffset"
                                            to: 0
                                            duration: 200
                                            easing.type: Easing.OutQuad
                                        }

                                        // Left peeking wallpaper card (previous)
                                        Rectangle {
                                            id: leftPeekCard
                                            visible: wallCarousel.totalWps > 1
                                            width: 240
                                            height: 136
                                            radius: 10
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder
                                            clip: true
                                            opacity: 0.5
                                            scale: 0.88
                                            z: 1

                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: -4
                                            anchors.right: centerCard.left
                                            anchors.rightMargin: -65

                                            Image {
                                                id: prevCardImg
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                source: wallCarousel.prevWp
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                            }

                                            Rectangle {
                                                visible: prevCardImg.status === Image.Error
                                                anchors.fill: parent
                                                color: Theme.qsBg
                                                opacity: 0.95
                                                Column {
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    Text {
                                                        text: "warning"
                                                        font.family: Theme.fontIcons
                                                        font.pixelSize: 18
                                                        color: Theme.attention
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                    }
                                                    Text {
                                                        text: "Format Error"
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 10
                                                        color: Theme.qsTextMuted
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectPrevWallpaper()
                                            }

                                            HoverLift { baseScale: 0.88 }
                                        }

                                        // Right peeking wallpaper card (next)
                                        Rectangle {
                                            id: rightPeekCard
                                            visible: wallCarousel.totalWps > 1
                                            width: 240
                                            height: 136
                                            radius: 10
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder
                                            clip: true
                                            opacity: 0.5
                                            scale: 0.88
                                            z: 1

                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: -4
                                            anchors.left: centerCard.right
                                            anchors.leftMargin: -65

                                            Image {
                                                id: nextCardImg
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                source: wallCarousel.nextWp
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                            }

                                            Rectangle {
                                                visible: nextCardImg.status === Image.Error
                                                anchors.fill: parent
                                                color: Theme.qsBg
                                                opacity: 0.95
                                                Column {
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    Text {
                                                        text: "warning"
                                                        font.family: Theme.fontIcons
                                                        font.pixelSize: 18
                                                        color: Theme.attention
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                    }
                                                    Text {
                                                        text: "Format Error"
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 10
                                                        color: Theme.qsTextMuted
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectNextWallpaper()
                                            }

                                            HoverLift { baseScale: 0.88 }
                                        }

                                        // Center card (currently active wallpaper)
                                        Rectangle {
                                            id: centerCard
                                            width: 270
                                            height: 152
                                            radius: 12
                                            color: Theme.qsBgAlt
                                            border.width: 2
                                            border.color: Theme.attention
                                            clip: true
                                            z: 3

                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.horizontalCenterOffset: wallCarousel.dragOffset
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: -4

                                            Image {
                                                id: centerCardImg
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                source: wallCarousel.activeWp
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                            }

                                            Rectangle {
                                                visible: centerCardImg.status === Image.Error
                                                anchors.fill: parent
                                                color: Theme.qsBg
                                                z: 2
                                                Column {
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    Text {
                                                        text: "broken_image"
                                                        font.family: Theme.fontIcons
                                                        font.pixelSize: 26
                                                        color: Theme.attention
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                    }
                                                    Text {
                                                        text: "Unsupported Format"
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        color: Theme.qsText
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                    }
                                                    Rectangle {
                                                        width: 110
                                                        height: 22
                                                        radius: 11
                                                        color: Theme.attention
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "Auto-Fix to JPG"
                                                            font.family: Theme.fontText
                                                            font.pixelSize: 10
                                                            font.weight: Font.Bold
                                                            color: Theme.qsBg
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (wallCarousel.activeWp) {
                                                                    WallpaperState.sanitizeFile(wallCarousel.activeWp)
                                                                    fixTimer.restart()
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Timer {
                                                id: fixTimer
                                                interval: 600
                                                repeat: false
                                                onTriggered: root.refreshWallpapers()
                                            }

                                            // Subtitle badge showing wallpaper filename
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                anchors.bottomMargin: 8
                                                width: Math.min(parent.width - 24, nameLabel.contentWidth + 16)
                                                height: 20
                                                radius: 10
                                                color: Theme.qsBg
                                                opacity: 0.85

                                                Text {
                                                    id: nameLabel
                                                    anchors.centerIn: parent
                                                    text: wallCarousel.activeWp ? wallCarousel.activeWp.split("/").pop() : ""
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                    color: Theme.attention
                                                    elide: Text.ElideMiddle
                                                    width: parent.width - 12
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                            }

                                            // Drag-and-pull mouse interaction
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true

                                                property real pressX: 0
                                                property bool dragging: false

                                                onPressed: mouse => {
                                                    pressX = mouse.x
                                                    dragging = true
                                                    snapAnim.stop()
                                                }

                                                onPositionChanged: mouse => {
                                                    if (dragging) {
                                                        let diff = mouse.x - pressX
                                                        wallCarousel.dragOffset = diff * 0.8
                                                    }
                                                }

                                                onReleased: mouse => {
                                                    if (dragging) {
                                                        dragging = false
                                                        let offset = wallCarousel.dragOffset
                                                        if (offset < -40) {
                                                            root.selectNextWallpaper()
                                                        } else if (offset > 40) {
                                                            root.selectPrevWallpaper()
                                                        }
                                                        snapAnim.start()
                                                    }
                                                }

                                                onCanceled: {
                                                    dragging = false
                                                    snapAnim.start()
                                                }
                                            }
                                        }

                                        // Left arrow button
                                        Rectangle {
                                            id: prevArrow
                                            visible: wallCarousel.totalWps > 1
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder
                                            z: 5

                                            anchors.left: parent.left
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: centerCard.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "chevron_left"
                                                font.family: Theme.fontIcons
                                                font.pixelSize: 18
                                                color: Theme.qsText
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectPrevWallpaper()
                                            }

                                            HoverLift { }
                                        }

                                        // Right arrow button
                                        Rectangle {
                                            id: nextArrow
                                            visible: wallCarousel.totalWps > 1
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder
                                            z: 5

                                            anchors.right: parent.right
                                            anchors.rightMargin: 12
                                            anchors.verticalCenter: centerCard.verticalCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "chevron_right"
                                                font.family: Theme.fontIcons
                                                font.pixelSize: 18
                                                color: Theme.qsText
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectNextWallpaper()
                                            }

                                            HoverLift { }
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

                                                HoverLift { }
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

                                            // Live Color Studio Button (opens fullscreen workstation with movable color picker)
                                            Rectangle {
                                                implicitHeight: 26
                                                implicitWidth: studioContentRow.implicitWidth + 14
                                                radius: 13
                                                color: Theme.plum
                                                border.width: 1
                                                border.color: Theme.attention

                                                RowLayout {
                                                    id: studioContentRow
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Text {
                                                        text: "colorize"
                                                        font.family: Theme.fontIcons
                                                        font.pixelSize: 13
                                                        color: Theme.ink
                                                    }

                                                    Text {
                                                        text: "Live Studio"
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        color: Theme.ink
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let targetPath = root.editingPath || WallpaperState.current
                                                        root.collapse()
                                                        ThemeStudioState.open(targetPath)
                                                    }
                                                }

                                                HoverLift { }
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

                                                HoverLift { }
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

                                                    HoverLift { }
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
                                        spacing: 6

                                        Text {
                                            text: Qt.formatDateTime(clock.date, "hh:mm")
                                            font.family: Theme.fontText
                                            font.pixelSize: 36
                                            font.bold: true
                                            color: Theme.qsText
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: Qt.formatDate(clock.date, "EEEE, MMMM d")
                                            font.family: Theme.fontText
                                            font.pixelSize: 12
                                            color: Theme.qsTextMuted
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 1
                                            color: Theme.pillBorder
                                            Layout.topMargin: 4
                                            Layout.bottomMargin: 4
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
                                            font.pixelSize: 32
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

                                // =====================================================
                                //  VIEW 5 — NOTIFICATIONS (Grouped by Application)
                                // =====================================================
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 6

                                    // ── Top Header Row ──
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        implicitHeight: 22

                                        Text {
                                            text: "Notifications"
                                            font.family: Theme.fontText
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: Theme.qsText
                                        }

                                        Rectangle {
                                            visible: NotificationState.totalCount > 0
                                            radius: 7
                                            color: Theme.attention
                                            implicitHeight: 16
                                            implicitWidth: totalBadgeTxt.implicitWidth + 8

                                            Text {
                                                id: totalBadgeTxt
                                                anchors.centerIn: parent
                                                text: NotificationState.totalCount + (NotificationState.totalCount === 1 ? " alert" : " alerts")
                                                font.family: Theme.fontText
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: Theme.qsOnAccent
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Notification chime toggle button
                                        Rectangle {
                                            implicitHeight: 20
                                            implicitWidth: chimeBtnRow.implicitWidth + 12
                                            radius: 10
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder

                                            RowLayout {
                                                id: chimeBtnRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: NotificationState.soundEnabled ? "volume_up" : "volume_off"
                                                    font.family: Theme.fontIcons
                                                    font.pixelSize: 11
                                                    color: NotificationState.soundEnabled ? Theme.qsText : Theme.qsTextMuted
                                                }
                                                Text {
                                                    text: NotificationState.soundEnabled ? "Chime" : "Muted"
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: NotificationState.soundEnabled ? Theme.qsText : Theme.qsTextMuted
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: NotificationState.soundEnabled = !NotificationState.soundEnabled
                                            }

                                            HoverLift { }
                                        }

                                        // Quick test simulation button
                                        Rectangle {
                                            implicitHeight: 20
                                            implicitWidth: testBtnRow.implicitWidth + 12
                                            radius: 10
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder

                                            RowLayout {
                                                id: testBtnRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: "terminal"
                                                    font.family: Theme.fontIcons
                                                    font.pixelSize: 11
                                                    color: Theme.attention
                                                }
                                                Text {
                                                    text: "Simulate Kitty"
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: Theme.qsText
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    NotificationState.sendTestNotification("kitty", "Command finished", "Build completed with 0 errors in 1.4s")
                                                }
                                            }

                                            HoverLift { }
                                        }

                                        // Clear all button
                                        Rectangle {
                                            visible: NotificationState.groups.length > 0
                                            implicitHeight: 20
                                            implicitWidth: clearAllRow.implicitWidth + 12
                                            radius: 10
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder

                                            RowLayout {
                                                id: clearAllRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: "delete_sweep"
                                                    font.family: Theme.fontIcons
                                                    font.pixelSize: 11
                                                    color: Theme.attention
                                                }
                                                Text {
                                                    text: "Clear all"
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: Theme.attention
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: NotificationState.clearAll()
                                            }

                                            HoverLift { }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 1
                                        color: Theme.pillBorder
                                        opacity: 0.5
                                    }

                                    // ── Empty State ──
                                    Item {
                                        visible: NotificationState.groups.length === 0
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Text {
                                                text: "notifications_paused"
                                                font.family: Theme.fontIcons
                                                font.pixelSize: 26
                                                color: Theme.qsTextMuted
                                                Layout.alignment: Qt.AlignHCenter
                                            }

                                            Text {
                                                text: "No unattended notifications"
                                                font.family: Theme.fontText
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: Theme.qsText
                                                Layout.alignment: Qt.AlignHCenter
                                            }

                                            Text {
                                                text: "Alerts will automatically be grouped by application"
                                                font.family: Theme.fontText
                                                font.pixelSize: 10
                                                color: Theme.qsTextMuted
                                                Layout.alignment: Qt.AlignHCenter
                                            }
                                        }
                                    }

                                    // ── Grouped Notifications List ──
                                    ListView {
                                        visible: NotificationState.groups.length > 0
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: 5
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: NotificationState.groups

                                        delegate: Rectangle {
                                            id: groupCard
                                            required property var modelData
                                            readonly property var group: modelData

                                            width: ListView.view ? ListView.view.width : parent.width
                                            implicitHeight: cardCol.implicitHeight + 10
                                            radius: 8
                                            color: Theme.qsBgAlt
                                            border.width: 1
                                            border.color: Theme.pillBorder

                                            ColumnLayout {
                                                id: cardCol
                                                anchors.fill: parent
                                                anchors.margins: 7
                                                spacing: 3

                                                // App header row
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    // App icon pill
                                                    Rectangle {
                                                        width: 20
                                                        height: 20
                                                        radius: 10
                                                        color: Theme.plum

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: groupCard.group.appIcon || "notifications"
                                                            font.family: Theme.fontIcons
                                                            font.pixelSize: 12
                                                            color: Theme.ink
                                                        }
                                                    }

                                                    // App Name
                                                    Text {
                                                        text: groupCard.group.appName
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                        color: Theme.qsText
                                                    }

                                                    // Distinct group count badge (e.g. "× 10" or "1")
                                                    Rectangle {
                                                        radius: 7
                                                        color: Theme.attention
                                                        implicitHeight: 15
                                                        implicitWidth: countBadgeTxt.implicitWidth + 8

                                                        Text {
                                                            id: countBadgeTxt
                                                            anchors.centerIn: parent
                                                            text: groupCard.group.count > 1 ? ("× " + groupCard.group.count) : "1"
                                                            font.family: Theme.fontText
                                                            font.pixelSize: 8
                                                            font.bold: true
                                                            color: Theme.qsOnAccent
                                                        }
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    // Timestamp of latest notification
                                                    Text {
                                                        text: groupCard.group.latestTime || ""
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 9
                                                        color: Theme.qsTextMuted
                                                    }

                                                    // Expand/collapse accordion button (if count > 1)
                                                    Rectangle {
                                                        visible: groupCard.group.count > 1
                                                        width: 20
                                                        height: 20
                                                        radius: 10
                                                        color: "transparent"

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: groupCard.group.expanded ? "expand_less" : "expand_more"
                                                            font.family: Theme.fontIcons
                                                            font.pixelSize: 14
                                                            color: Theme.qsTextMuted
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: NotificationState.toggleGroupExpanded(groupCard.group.appName)
                                                        }

                                                        HoverLift { }
                                                    }

                                                    // Dismiss this application's notifications
                                                    Rectangle {
                                                        width: 20
                                                        height: 20
                                                        radius: 10
                                                        color: "transparent"

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "close"
                                                            font.family: Theme.fontIcons
                                                            font.pixelSize: 12
                                                            color: Theme.qsTextMuted
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: NotificationState.clearGroup(groupCard.group.appName)
                                                        }

                                                        HoverLift { }
                                                    }
                                                }

                                                // Latest notification message
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1

                                                    Text {
                                                        visible: (groupCard.group.latestSummary || "") !== ""
                                                        text: groupCard.group.latestSummary || ""
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                        color: Theme.qsText
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }

                                                    Text {
                                                        visible: (groupCard.group.latestBody || "") !== ""
                                                        text: groupCard.group.latestBody || ""
                                                        font.family: Theme.fontText
                                                        font.pixelSize: 10
                                                        color: Theme.qsTextMuted
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }

                                                // Accordion: prior notifications list from this app
                                                ColumnLayout {
                                                    visible: groupCard.group.expanded && groupCard.group.count > 1
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 1
                                                        color: Theme.pillBorder
                                                        opacity: 0.4
                                                    }

                                                    Repeater {
                                                        model: (groupCard.group.items || []).slice(1)

                                                        delegate: RowLayout {
                                                            required property var modelData
                                                            readonly property var itemData: modelData
                                                            Layout.fillWidth: true
                                                            spacing: 4

                                                            Text {
                                                                text: "•"
                                                                font.family: Theme.fontText
                                                                font.pixelSize: 9
                                                                color: Theme.attention
                                                            }

                                                            Text {
                                                                text: (itemData.summary ? itemData.summary + ": " : "") + (itemData.body || "")
                                                                font.family: Theme.fontText
                                                                font.pixelSize: 9
                                                                color: Theme.qsTextMuted
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                            }

                                                            Text {
                                                                text: itemData.time || ""
                                                                font.family: Theme.fontText
                                                                font.pixelSize: 8
                                                                color: Theme.qsTextMuted
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }   // ── StackLayout
                        }       // ── contentStack
                    }           // ── content ColumnLayout
                }               // ── cardContent
            }                   // ── face
        }                       // ── reveal
    }                           // ── stage
}                               // ── popup
}                               // ── root (Pill)
