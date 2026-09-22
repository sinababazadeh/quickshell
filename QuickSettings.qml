// =============================================================================
//  QUICKSETTINGS.QML  —  the dropdown control-panel window
// =============================================================================
//  WHAT THIS IS
//  ------------
//  The QuickSettings popup you open with the "tune" pill on the bar. It is a
//  PanelWindow (a separate floating layer), so it lives in its OWN file and is
//  toggled from shell.qml by setting `visible`.
//
//  THREE VIEWS, SWITCHED BY ONE PROPERTY
//  -------------------------------------
//  This window contains three stacked layouts; only ONE is visible at a time.
//  `currentView` decides which:
//      "main"       → sliders + Wi-Fi/Bluetooth toggles + power buttons
//      "wifi"       → full Wi-Fi network list (nmcli)
//      "bluetooth"  → full Bluetooth device list (bluetoothctl)
//  The back-arrow buttons set `popup.currentView = "main"`.
//
//  THE TWO SIDES OF THIS FILE (important for understanding)
//  --------------------------------------------------------
//  1. BACKGROUND JOBS  — three `Process` blocks near the top run system
//     commands (brightnessctl / nmcli / bluetoothctl), parse their output and
//     store results into properties like `popup.wifiNetworks`. They run
//     BEHIND the scenes; the UI below just *reads* those properties.
//  2. THE UI          — the big Rectangle at the bottom only displays state;
//     buttons trigger the Process blocks or dispatch commands.
//
//  This separation is the key to the design: UI = dumb display, Process
//  blocks = data collection. Change parsing there, not in the UI.
// =============================================================================
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: popup

    // ─── State & navigation ─────────────────────────────────────────────────────
    property string currentView: "main"        // "main" | "wifi" | "bluetooth"
    property var wifiNetworks: []              // parsed Wi-Fi results (a list)
    property var btDevices: []                 // parsed Bluetooth results (a list)

    // ─── Live audio references (pipewire) ───────────────────────────────────────
    // PwObjectTracker subscribes us to the default devices so the bindings
    // below stay fresh if the sink/source changes.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property var sink: Pipewire.defaultAudioSink     // speakers
    readonly property var source: Pipewire.defaultAudioSource // microphone

    // ─── UI state flags ───────────────────────────────────────────────────────────
    property real brightnessVal: 0.8       // 0.0–1.0 slider position
    property real brightnessMax: 937       // fallback if `brightnessctl max` fails
    property bool wifiActive: true         // Wi-Fi radio on or off
    property bool btActive: true           // Bluetooth adapter on or off
    property bool isScanning: false        // shared "please wait" indicator

    // ─── Window geometry & anchoring ───────────────────────────────────────────────
    // Anchors on a PanelWindow are relative to the SCREEN: top+right means
    // "hang from the top-right corner of the monitor". `margins` offset it.
    anchors {
        top: true
        right: true
    }

    margins {
        top: 46      // clears the 40px bar + a little air
        right: 12
    }

    implicitWidth: 360
    implicitHeight: mainCard.implicitHeight  // window height = card height
    color: "transparent"
    visible: false                           // hidden until the bar button toggles it

    // =========================================================================
    //  BACKGROUND PROCESSES  —  the "data collectors" that feed the UI below
    // =========================================================================
    //  A QML `Process` runs an external command, captures its output and lets
    //  us react to it. The UI itself never runs commands; it reads the
    //  properties these blocks write.

    // ─── 1. SCREEN BRIGHTNESS READER ─────────────────────────────────────────────
    // Reads current and max brightness in ONE shell call: echo "cur/max".
    Process {
        id: brightProc
        command: ["bash", "-c", "echo \"$(brightnessctl get)/$(brightnessctl max)\""]

        // SplitParser feeds `onRead` one LINE at a time as it arrives.
        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split("/")
                if (parts.length >= 2) {              // got "cur/max", both halves
                    let current = parseInt(parts[0])
                    let max = parseInt(parts[1])
                    if (!isNaN(current) && !isNaN(max) && max > 0) {
                        popup.brightnessMax = max
                        // Store as a 0.0–1.0 ratio: 400/937 → ~0.43
                        popup.brightnessVal = Math.min(1.0, current / max)
                    }
                }
            }
        }
    }

    // ─── 2. WI-FI SCANNER (nmcli) ─────────────────────────────────────────────────
    // Ask nmcli for a fresh scan, then dump a machine-readable table. The
    // `rescan` runs first; the list command follows. Example line:
    //     *:My WiFi:75:WPA2
    Process {
        id: wifiScanner
        command: ["bash", "-c", "nmcli device wifi rescan 2>/dev/null; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list"]

        // StdioCollector buffers ALL output and fires once. We need the whole
        // table before parsing, so waitForEnd is right for this one.
        stdout: StdioCollector {
            id: wifiCollector
            waitForEnd: true
            onDataChanged: {
                let lines = wifiCollector.text.trim().split("\n")
                let list = []
                for (let line of lines) {
                    if (!line.trim()) continue          // skip blank lines
                    let parts = line.split(":")          // ":"-separated columns
                    if (parts.length >= 3) {
                        let active = parts[0].trim() === "*"   // "*" = connected
                        let ssid = parts[1].trim().replace(/\\:/g, ":")
                        let signal = parseInt(parts[2]) || 0    // 0–100
                        let security = parts[3] || ""           // WPA2 / "" / ""

                        // Skip hidden/empty SSIDs and duplicate entries
                        if (ssid !== "" && !list.some(item => item.ssid === ssid)) {
                            list.push({
                                active: active,
                                ssid: ssid,
                                signal: signal,
                                security: security
                            })
                        }
                    }
                }
                // Connected network wins, then strongest signal first.
                list.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
                popup.wifiNetworks = list
                popup.isScanning = false
            }
        }
    }

    // ─── 3. BLUETOOTH SCANNER (bluetoothctl) ─────────────────────────────────────
    // 4 seconds of active discovery, then list known devices. `devices` prints
    // lines like:  Device  AA:BB:CC:DD:EE:FF  My Headphones
    Process {
        id: btScanner
        command: ["bash", "-c", "bluetoothctl --timeout 4 scan on >/dev/null 2>&1; bluetoothctl devices"]
        stdout: StdioCollector {
            id: btCollector
            waitForEnd: true
            onDataChanged: {
                let lines = btCollector.text.trim().split("\n")
                let list = []
                for (let line of lines) {
                    let match = line.match(/^Device\s+([0-9A-Fa-f:]+)\s+(.+)$/)
                    if (match) {
                        let mac = match[1].trim()   // AA:BB:CC:DD:EE:FF
                        let name = match[2].trim()  // human-readable name
                        if (!list.some(item => item.mac === mac)) {
                            list.push({ mac: mac, name: name })
                        }
                    }
                }
                popup.btDevices = list
                popup.isScanning = false
            }
        }
    }

    // ─── Manual refresh helpers (called by the UI buttons) ─────────────────────────
    function refreshWifi() {
        popup.isScanning = true
        wifiScanner.running = true   // kick the process off again
    }

    function refreshBt() {
        popup.isScanning = true
        btScanner.running = true
    }

    // ─── Auto-refresh while the popup is open ───────────────────────────────────────
    // A Timer that only runs while visible: refreshes brightness every cycle
    // and re-scans Wi-Fi IF you're on the wifi view and nothing is running.
    Timer {
        interval: 4000
        running: popup.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!brightProc.running) brightProc.running = true
            if (popup.currentView === "wifi" && !wifiScanner.running && !popup.isScanning) wifiScanner.running = true
        }
    }

    // =========================================================================
    //  THE DROPDOWN CARD  (the visible window content)
    // =========================================================================
    //  A single rounded Rectangle = the card. Inside it, a ColumnLayout stacks
    //  the three views; only the one matching `popup.currentView` is visible.
    Rectangle {
        id: mainCard
        anchors.fill: parent
        // Card height = content height + 14px padding top and bottom (28 total).
        implicitHeight: cardContent.implicitHeight + 28
        radius: 14
        color: Theme.qsBg
        border.color: Theme.pillBorder
        border.width: 1

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 14    // inner padding around all views
            spacing: 12

            // =============================================================
            //  VIEW 1  —  MAIN CONTROL CENTER
            // =============================================================
            ColumnLayout {
                visible: popup.currentView === "main"
                Layout.fillWidth: true
                spacing: 12

                // --- Power / Sleep / Lock action buttons ------------------
                // A row of ActionPills that share the width equally.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ActionPill {
                        Layout.fillWidth: true
                        icon: "lock"
                        label: "Lock"
                        // Close the popup first, then launch the command.
                        onClicked: { popup.visible = false; Quickshell.execDetached(["hyprlock"]) }
                    }

                    ActionPill {
                        Layout.fillWidth: true
                        icon: "bedtime"
                        label: "Sleep"
                        onClicked: { popup.visible = false; Quickshell.execDetached(["systemctl", "suspend"]) }
                    }

                    ActionPill {
                        Layout.fillWidth: true
                        icon: "power_settings_new"
                        label: "Power"
                        labelBg: Theme.primary
                        onClicked: { popup.visible = false; Quickshell.execDetached(["shutdown", "now"]) }
                    }
                }

                // Thin divider line between sections.
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                // --- Sliders (volume / mic / brightness) -------------------
                // Each CustomSlider binds `value` FROM the system state and
                // feeds changes BACK through `onValueChangedByUser`.
                CustomSlider {
                    icon: (popup.sink && popup.sink.audio && popup.sink.audio.muted) ? "volume_off" : "volume_up"
                    value: (popup.sink && popup.sink.audio) ? popup.sink.audio.volume : 0.5
                    onValueChangedByUser: newVal => {
                        if (popup.sink && popup.sink.audio) popup.sink.audio.volume = newVal
                    }
                }

                CustomSlider {
                    icon: (popup.source && popup.source.audio && popup.source.audio.muted) ? "mic_off" : "mic"
                    value: (popup.source && popup.source.audio) ? popup.source.audio.volume : 0.5
                    onValueChangedByUser: newVal => {
                        if (popup.source && popup.source.audio) popup.source.audio.volume = newVal
                    }
                }

                CustomSlider {
                    icon: "brightness_6"
                    value: popup.brightnessVal
                    onValueChangedByUser: newVal => {
                        popup.brightnessVal = newVal
                        let percent = Math.round(newVal * 100)
                        Quickshell.execDetached(["brightnessctl", "set", percent + "%"])
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                // --- Toggles grid (Wi-Fi + Bluetooth) -----------------------
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2        // side by side
                    columnSpacing: 10
                    rowSpacing: 10

                    // Wi-Fi tile -------------------------------------------
                    QuickToggle {
                        icon: "wifi"
                        title: "Wi-Fi"
                        // Status line: connected network name, "On", or "Off".
                        status: popup.wifiActive ? (popup.wifiNetworks.length > 0 && popup.wifiNetworks[0].active ? popup.wifiNetworks[0].ssid : "On") : "Off"
                        active: popup.wifiActive
                        onToggled: {   // tile body/icon clicked
                            popup.wifiActive = !popup.wifiActive
                            Quickshell.execDetached(["nmcli", "radio", "wifi", popup.wifiActive ? "on" : "off"])
                        }
                        onOpenDetails: { // chevron clicked → full network list
                            popup.currentView = "wifi"
                            popup.refreshWifi()
                        }
                    }

                    // Bluetooth tile ----------------------------------------
                    QuickToggle {
                        icon: "bluetooth"
                        title: "Bluetooth"
                        status: popup.btActive ? (popup.isScanning ? "Scanning..." : "On") : "Off"
                        active: popup.btActive
                        onToggled: {
                            popup.btActive = !popup.btActive
                            Quickshell.execDetached(["bluetoothctl", "power", popup.btActive ? "on" : "off"])
                        }
                        onOpenDetails: { // chevron clicked → full device list
                            popup.currentView = "bluetooth"
                            popup.refreshBt()
                        }
                    }
                }
            }

            // =============================================================
            //  VIEW 2  —  SCROLLABLE WI-FI NETWORK MANAGER
            // =============================================================
            ColumnLayout {
                visible: popup.currentView === "wifi"
                Layout.fillWidth: true
                spacing: 10

                // --- Header row: back arrow | title | refresh --------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Back arrow → home view.
                    Text {
                        text: "arrow_back"
                        font.family: Theme.fontIcons
                        font.pixelSize: 20
                        color: Theme.qsAccent
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.currentView = "main"
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

                    // Refresh button; color shifts while scanning.
                    Text {
                        text: "refresh"
                        font.family: Theme.fontIcons
                        font.pixelSize: 18
                        color: popup.isScanning ? Theme.qsSuccess : Theme.qsPurple
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.refreshWifi()
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                // --- The scrollable network list ----------------------------
                // Flickable = a scrollable surface. The ColumnLayout inside is
                // the CONTENT; it may be taller than the window and gets cut
                // off (`clip: true`) so it scrolls instead of overflowing.
                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(260, wifiListCol.implicitHeight)
                    contentHeight: wifiListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: wifiListCol
                        width: parent.width
                        spacing: 6

                        // Empty-state message (only when the list is empty).
                        Text {
                            visible: popup.wifiNetworks.length === 0
                            text: popup.isScanning ? "Scanning for networks..." : "No networks found. Tap refresh."
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            color: Theme.qsTextMuted
                            Layout.alignment: Qt.AlignCenter
                            Layout.topMargin: 15
                            Layout.bottomMargin: 15
                        }

                        // One row per network. `popup.wifiNetworks` is the
                        // MODEL; inside the Repeater, `modelData` is the
                        // current item (ssid/signal/security/active).
                        Repeater {
                            model: popup.wifiNetworks

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: 0
                                color: "transparent"

                                // ── Left: signal-strength icon segment ─────
                                Rectangle {
                                    id: wifiIconSeg
                                    width: wifiIcon.width + 14
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        id: wifiIcon
                                        anchors.centerIn: parent
                                        // Icon chosen from signal strength.
                                        text: modelData.signal > 60 ? "wifi" : (modelData.signal > 30 ? "wifi_2_bar" : "wifi_1_bar")
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 18
                                        color: Theme.ink
                                        leftPadding: 4
                                    }
                                }

                                // ── Right: name + lock + Connect action ─────
                                Rectangle {
                                    anchors.left: wifiIconSeg.right
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

                                        // "Connected" (inactive text) or a
                                        // clickable "Connect" action.
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
                                                        popup.refreshWifi()   // re-scan so it flips to "Connected"
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

            // =============================================================
            //  VIEW 3  —  BLUETOOTH WITH ACTIVE DISCOVERY
            // =============================================================
            ColumnLayout {
                visible: popup.currentView === "bluetooth"
                Layout.fillWidth: true
                spacing: 10

                // --- Header row: back arrow | title | refresh --------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Back arrow → home view.
                    Text {
                        text: "arrow_back"
                        font.family: Theme.fontIcons
                        font.pixelSize: 20
                        color: Theme.qsAccent
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.currentView = "main"
                        }
                    }

                    Text {
                        text: popup.isScanning ? "Discovering Nearby..." : "Bluetooth Devices"
                        font.family: Theme.fontText
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.qsText
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Refresh button; color shifts while scanning.
                    Text {
                        text: "refresh"
                        font.family: Theme.fontIcons
                        font.pixelSize: 18
                        color: popup.isScanning ? Theme.qsSuccess : Theme.qsPurple
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.refreshBt()
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

                // --- The scrollable device list ----------------------------
                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(260, btListCol.implicitHeight)
                    contentHeight: btListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: btListCol
                        width: parent.width
                        spacing: 6

                        // Empty-state message.
                        Text {
                            visible: popup.btDevices.length === 0
                            text: popup.isScanning ? "Scanning for nearby devices..." : "No devices found. Tap refresh to scan."
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            color: Theme.qsTextMuted
                            Layout.alignment: Qt.AlignCenter
                            Layout.topMargin: 15
                            Layout.bottomMargin: 15
                        }

                        // One row per discovered device.
                        Repeater {
                            model: popup.btDevices

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: 0
                                color: "transparent"

                                // ── Left: bluetooth icon segment ───────────
                                Rectangle {
                                    id: btIconSeg
                                    width: btIcon.width + 14
                                    height: parent.height
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2
                                    topRightRadius: 0
                                    bottomRightRadius: 0

                                    Text {
                                        id: btIcon
                                        anchors.centerIn: parent
                                        text: "bluetooth"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 18
                                        color: Theme.ink
                                        leftPadding: 4
                                    }
                                }

                                // ── Right: device name + Pair/Connect ──────
                                Rectangle {
                                    anchors.left: btIconSeg.right
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
                                                    popup.refreshBt()
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
    }
}
