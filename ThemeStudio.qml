// =============================================================================
//  THEMESTUDIO.QML — Fullscreen Live Color Studio Workstation Overlay
// =============================================================================
//  When activated from Hub's Theme tab:
//  • Converts the entire screen into an interactive theme workstation
//  • Background = active wallpaper covering the whole page
//  • Live simulation of the Quickshell status bar & open Hub with quick settings
//  • Dynamic crosshair tool that samples colors anywhere across the screen
//  • Movable ColorPickerWidget with drag handle, selectable color role pills,
//    and Save & Apply Changes button.
// =============================================================================
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    visible: ThemeStudioState.active
    color: "black"

    onVisibleChanged: {
        if (visible) {
            sampleCanvas.requestPaint()
        }
    }

    // Crosshair target coordinates on the screen
    property real crosshairX: root.width * 0.35
    property real crosshairY: root.height * 0.45
    property color currentSampledColor: "#140A4E"

    // ─── 1. FULLSCREEN WALLPAPER BACKGROUND ─────────────────────────────────────
    Image {
        id: bgWallpaper
        anchors.fill: parent
        source: ThemeStudioState.wallpaperPath || WallpaperState.current
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        onStatusChanged: {
            if (status === Image.Ready) {
                sampleCanvas.requestPaint()
            } else if (status === Image.Error) {
                console.warn("[ThemeStudio] Active wallpaper failed to decode, trying fallback:", source)
                if (WallpaperState.fallbackWallpaper && source.toString() !== WallpaperState.fallbackWallpaper) {
                    source = WallpaperState.fallbackWallpaper
                }
            }
        }
    }

    // Active offscreen canvas used to sample pixel RGB data at screen coordinates
    Canvas {
        id: sampleCanvas
        width: 320
        height: 180
        visible: true
        opacity: 0.001
        z: -100
        property var ctx: null

        onPaint: {
            ctx = getContext("2d")
            if (bgWallpaper.status === Image.Ready) {
                ctx.clearRect(0, 0, width, height)
                ctx.drawImage(bgWallpaper, 0, 0, width, height)
            }
        }
    }

    // Samples color at (screenX, screenY) and applies it to active theme slot
    function samplePixelAt(screenX, screenY) {
        root.crosshairX = Math.max(10, Math.min(root.width - 10, screenX))
        root.crosshairY = Math.max(10, Math.min(root.height - 10, screenY))

        let sampledHex = ""

        if (sampleCanvas.ctx && bgWallpaper.status === Image.Ready) {
            let cx = Math.max(0, Math.min(sampleCanvas.width - 1, Math.round((root.crosshairX / root.width) * sampleCanvas.width)))
            let cy = Math.max(0, Math.min(sampleCanvas.height - 1, Math.round((root.crosshairY / root.height) * sampleCanvas.height)))
            try {
                let pixel = sampleCanvas.ctx.getImageData(cx, cy, 1, 1).data
                let r = pixel[0]
                let g = pixel[1]
                let b = pixel[2]
                sampledHex = "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1).toUpperCase()
            } catch (e) {
                sampledHex = ""
            }
        }

        if (sampledHex) {
            root.currentSampledColor = sampledHex
            ThemeStudioState.setSlotColor(ThemeStudioState.activeSlot, sampledHex)
        }
    }

    // Helper color math
    function rgbToHsv(r, g, b) {
        r /= 255; g /= 255; b /= 255;
        let max = Math.max(r, g, b), min = Math.min(r, g, b);
        let h = 0, s = 0, v = max;
        let d = max - min;
        s = max === 0 ? 0 : d / max;
        if (max === min) {
            h = 0;
        } else {
            switch (max) {
                case r: h = (g - b) / d + (g < b ? 6 : 0); break;
                case g: h = (b - r) / d + 2; break;
                case b: h = (r - g) / d + 4; break;
            }
            h /= 6;
        }
        return { h: h, s: s, v: v };
    }

    function hsvToHex(h, s, v) {
        let normH = ((h % 1.0) + 1.0) % 1.0;
        let normS = Math.max(0, Math.min(1.0, s));
        let normV = Math.max(0, Math.min(1.0, v));
        let c = Qt.hsva(normH, normS, normV, 1.0);
        return c.toString().toUpperCase();
    }

    function rgbToHex(r, g, b) {
        let ir = Math.max(0, Math.min(255, Math.round(r)))
        let ig = Math.max(0, Math.min(255, Math.round(g)))
        let ib = Math.max(0, Math.min(255, Math.round(b)))
        return "#" + ((1 << 24) + (ir << 16) + (ig << 8) + ib).toString(16).slice(1).toUpperCase()
    }

    // Native color extraction process reading directly from the image on disk
    Process {
        id: autoExtractor
        property string pendingMode: "balanced"
        command: []
        stdout: StdioCollector {
            id: extractorOut
            waitForEnd: true
            onDataChanged: {
                let txt = extractorOut.text.trim()
                if (txt.startsWith("{") && txt.endsWith("}")) {
                    try {
                        let pal = JSON.parse(txt)
                        if (pal && pal.plum && pal.primary && pal.violet) {
                            ThemeStudioState.applyFullPalette(pal)
                            return
                        }
                    } catch (e) {}
                }
                root.fallbackCanvasExtract(autoExtractor.pendingMode)
            }
        }
    }

    // Automated color extraction mapped to actual UI objects
    function autoExtractPalette(mode) {
        mode = mode || "balanced";
        let rawWp = (ThemeStudioState.wallpaperPath || WallpaperState.current || "").toString()
        if (rawWp.startsWith("file://")) {
            rawWp = rawWp.substring(7)
        }

        if (rawWp !== "") {
            autoExtractor.pendingMode = mode
            autoExtractor.command = [
                "bash", "-c",
                "for p in \"$HOME/.config/quickshell/extract-palette.py\" \"/app/applet/quickshell/extract-palette.py\" \"$(pwd)/extract-palette.py\"; do " +
                "  if [ -f \"$p\" ]; then python3 \"$p\" \"" + rawWp + "\" \"" + mode + "\" && exit 0; fi; " +
                "done; exit 1"
            ]
            autoExtractor.running = true
        } else {
            root.fallbackCanvasExtract(mode)
        }
    }

    // Pure in-memory fallback extract honoring true wallpaper colors (no artificial mud browns/oranges)
    function fallbackCanvasExtract(mode) {
        mode = mode || "balanced"
        let samples = []
        if (sampleCanvas.ctx && bgWallpaper.status === Image.Ready) {
            let cw = sampleCanvas.width
            let ch = sampleCanvas.height
            for (let gy = 1; gy <= 6; gy++) {
                for (let gx = 1; gx <= 6; gx++) {
                    let px = Math.round((gx / 7) * cw)
                    let py = Math.round((gy / 7) * ch)
                    try {
                        let d = sampleCanvas.ctx.getImageData(px, py, 1, 1).data
                        let hsv = rgbToHsv(d[0], d[1], d[2])
                        samples.push({ r: d[0], g: d[1], b: d[2], h: hsv.h, s: hsv.s, v: hsv.v })
                    } catch (e) {}
                }
            }
        }

        if (samples.length === 0) return

        let byVal = samples.slice().sort((a, b) => a.v - b.v)
        let bySat = samples.slice().sort((a, b) => b.s - a.s)
        let darkest = byVal[0]
        let brightest = byVal[byVal.length - 1]
        let nonDark = samples.filter(s => s.v >= 0.25)
        if (nonDark.length === 0) nonDark = samples
        let accent = nonDark[Math.floor(nonDark.length / 2)]
        let vibrant = bySat[0]

        let baseV = Math.min(0.12, Math.max(0.06, darkest.v))
        let violet = hsvToHex(darkest.h, Math.min(0.5, darkest.s), baseV)
        let primary = hsvToHex(darkest.h, Math.min(0.4, darkest.s), baseV + 0.10)
        let bgPip = hsvToHex(darkest.h, Math.min(0.3, darkest.s), baseV + 0.05)

        let plum = ""
        let attention = ""
        if (mode === "vibrant") {
            plum = rgbToHex(vibrant.r, vibrant.g, vibrant.b)
            attention = hsvToHex(vibrant.h, Math.min(1.0, vibrant.s + 0.15), Math.max(0.85, vibrant.v))
        } else if (mode === "deep") {
            plum = hsvToHex(accent.h, accent.s * 0.8, Math.min(0.65, accent.v))
            attention = rgbToHex(accent.r, accent.g, accent.b)
        } else {
            plum = rgbToHex(accent.r, accent.g, accent.b)
            attention = brightest.v > 0.6 ? rgbToHex(brightest.r, brightest.g, brightest.b) : hsvToHex(accent.h, Math.max(0.2, accent.s * 0.7), 0.95)
        }

        let indigo = hsvToHex(accent.h, Math.min(0.5, accent.s), 0.45)
        let lavender = hsvToHex(accent.h, Math.min(0.25, accent.s * 0.5), 0.82)
        let ink = "#FFFFFF"

        ThemeStudioState.applyFullPalette({
            plum: plum,
            primary: primary,
            violet: violet,
            attention: attention,
            indigo: indigo,
            bg: bgPip,
            ink: ink,
            lavender: lavender
        })
    }

    Connections {
        target: ThemeStudioState
        function onRequestAutoExtract(mode) {
            root.autoExtractPalette(mode);
        }
    }

    // ─── 2. SCREEN-WIDE SAMPLING MOUSEAREA ───────────────────────────────────────
    // Clicking or dragging anywhere on the wallpaper moves the crosshair and samples
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        z: 10
        onPressed: mouse => root.samplePixelAt(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            if (pressed) root.samplePixelAt(mouse.x, mouse.y)
        }
    }

    // ─── 3. SIMULATED STATUS BAR (TOP STRIP) ────────────────────────────────────
    Rectangle {
        id: simBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.barHeight
        color: Theme.barBg
        z: 50

        // Subtle gradient bar backdrop for realism
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.18)
        }

        // ── Left Island: Workspaces ──
        RowLayout {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                implicitHeight: Theme.pillHeight
                implicitWidth: wsIconSeg.width + wsPipsSeg.width
                radius: height / 2
                color: "transparent"

                Rectangle {
                    id: wsIconSeg
                    width: wsIconTxt.width + 14
                    height: parent.height
                    anchors.left: parent.left
                    color: Theme.plum
                    topLeftRadius: height / 2
                    bottomLeftRadius: height / 2

                    Text {
                        id: wsIconTxt
                        anchors.centerIn: parent
                        text: "grid_view"
                        font.family: Theme.fontIcons
                        font.pixelSize: 16
                        color: Theme.ink
                        leftPadding: 4
                    }
                }

                Rectangle {
                    id: wsPipsSeg
                    width: 246
                    height: parent.height
                    anchors.left: wsIconSeg.right
                    color: Theme.primary
                    topRightRadius: height / 2
                    bottomRightRadius: height / 2

                    RowLayout {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Repeater {
                            model: 5
                            Rectangle {
                                Layout.leftMargin: 7
                                implicitWidth: 38
                                implicitHeight: 18
                                radius: height / 2
                                color: Theme.border

                                Rectangle {
                                    id: numSeg
                                    width: 20
                                    height: parent.height
                                    anchors.left: parent.left
                                    color: Theme.plum
                                    topLeftRadius: height / 2
                                    bottomLeftRadius: height / 2

                                    Text {
                                        anchors.centerIn: parent
                                        text: index + 1
                                        color: Theme.ink
                                        font.family: Theme.fontText
                                        font.pixelSize: 12
                                    }
                                }

                                Rectangle {
                                    anchors.left: numSeg.right
                                    width: 18
                                    height: parent.height
                                    color: index === 0 ? Theme.wsActive : (index < 3 ? Theme.wsOccupied : Theme.wsEmpty)
                                    topRightRadius: height / 2
                                    bottomRightRadius: height / 2
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Center Island: Clock Pill ──
        RowLayout {
            anchors.centerIn: parent

            Rectangle {
                implicitHeight: Theme.pillHeight
                implicitWidth: clockIconSeg.width + clockLabelSeg.width
                radius: height / 2
                color: "transparent"

                Rectangle {
                    id: clockIconSeg
                    width: 36
                    height: parent.height
                    anchors.left: parent.left
                    color: Theme.plum
                    topLeftRadius: height / 2
                    bottomLeftRadius: height / 2

                    Text {
                        anchors.centerIn: parent
                        text: "schedule"
                        font.family: Theme.fontIcons
                        font.pixelSize: 16
                        color: Theme.ink
                    }
                }

                Rectangle {
                    id: clockLabelSeg
                    width: 100
                    height: parent.height
                    anchors.left: clockIconSeg.right
                    color: Theme.primary
                    topRightRadius: height / 2
                    bottomRightRadius: height / 2

                    Text {
                        anchors.centerIn: parent
                        text: "12:45 PM"
                        font.family: Theme.fontText
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.ink
                    }
                }
            }
        }

        // ── Right Island: Volume ──
        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Volume Pill
            Rectangle {
                implicitHeight: Theme.pillHeight
                implicitWidth: 78
                radius: height / 2
                color: "transparent"

                Rectangle {
                    id: volIcon
                    width: 36
                    height: parent.height
                    anchors.left: parent.left
                    color: Theme.plum
                    topLeftRadius: height / 2
                    bottomLeftRadius: height / 2
                    Text { anchors.centerIn: parent; text: "volume_up"; font.family: Theme.fontIcons; font.pixelSize: 16; color: Theme.ink }
                }
                Rectangle {
                    anchors.left: volIcon.right
                    anchors.right: parent.right
                    height: parent.height
                    color: Theme.primary
                    topRightRadius: height / 2
                    bottomRightRadius: height / 2
                    Text { anchors.centerIn: parent; text: "85%"; font.family: Theme.fontText; font.pixelSize: 12; font.bold: true; color: Theme.ink }
                }
            }
        }
    }

    // ─── 4. SIMULATED OPEN HUB CARD (UNDER CENTER ISLAND) ───────────────────────
    // As requested: "you should be able to see the hub and the hub itself inside menu"
    Rectangle {
        id: simHubCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: simBar.bottom
        anchors.topMargin: 10
        width: 610
        height: 290
        radius: 16
        color: Theme.qsBg !== "transparent" ? Theme.qsBg : Qt.rgba(0.06, 0.04, 0.15, 0.96)
        border.width: 1.5
        border.color: Theme.pillBorder !== "transparent" ? Theme.pillBorder : Qt.rgba(1, 1, 1, 0.12)
        z: 40

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── Top Browser-Style Tabs: Calendar | Theme | Notifications | Settings ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // Tab 1: Calendar
                Rectangle {
                    implicitHeight: 28
                    implicitWidth: 105
                    radius: height / 2
                    color: "transparent"
                    Rectangle {
                        id: tCalIcon
                        width: 28; height: 28; radius: 14; color: Theme.plum
                        Text { anchors.centerIn: parent; text: "calendar_month"; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.ink }
                    }
                    Rectangle {
                        anchors.left: tCalIcon.right; anchors.right: parent.right; height: 28
                        color: Theme.primary; topRightRadius: 14; bottomRightRadius: 14
                        Text { anchors.centerIn: parent; text: "Calendar"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.ink }
                    }
                }

                // Tab 2: Theme
                Rectangle {
                    implicitHeight: 28
                    implicitWidth: 90
                    radius: height / 2
                    color: "transparent"
                    Rectangle {
                        id: tThIcon
                        width: 28; height: 28; radius: 14; color: Theme.attention
                        Text { anchors.centerIn: parent; text: "palette"; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.ink }
                    }
                    Rectangle {
                        anchors.left: tThIcon.right; anchors.right: parent.right; height: 28
                        color: Theme.primary; topRightRadius: 14; bottomRightRadius: 14
                        Text { anchors.centerIn: parent; text: "Theme"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.attention }
                    }
                }

                // Tab 3: Notifications
                Rectangle {
                    implicitHeight: 28
                    implicitWidth: 70
                    radius: height / 2
                    color: "transparent"
                    Rectangle {
                        id: tNotIcon
                        width: 28; height: 28; radius: 14; color: Theme.plum
                        Text { anchors.centerIn: parent; text: "notifications"; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.ink }
                    }
                    Rectangle {
                        anchors.left: tNotIcon.right; anchors.right: parent.right; height: 28
                        color: Theme.primary; topRightRadius: 14; bottomRightRadius: 14
                        Text { anchors.centerIn: parent; text: "3"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.ink }
                    }
                }

                // Tab 4: Settings
                Rectangle {
                    implicitHeight: 28
                    implicitWidth: 100
                    radius: height / 2
                    color: "transparent"
                    Rectangle {
                        id: tSetIcon
                        width: 28; height: 28; radius: 14; color: Theme.plum
                        Text { anchors.centerIn: parent; text: "settings"; font.family: Theme.fontIcons; font.pixelSize: 14; color: Theme.ink }
                    }
                    Rectangle {
                        anchors.left: tSetIcon.right; anchors.right: parent.right; height: 28
                        color: Theme.primary; topRightRadius: 14; bottomRightRadius: 14
                        Text { anchors.centerIn: parent; text: "Settings"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.ink }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

            // ── Quick Settings Action Tiles Row ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Wi-Fi tile
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 16
                    color: Theme.primary
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "wifi"; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.attention }
                        Text { text: "Wi-Fi"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.ink }
                    }
                }

                // Bluetooth tile
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 16
                    color: Theme.primary
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "bluetooth"; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.ink }
                        Text { text: "Bluetooth"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.ink }
                    }
                }

                // Lock tile
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 16
                    color: Theme.primary
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "lock"; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.ink }
                        Text { text: "Lock"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.ink }
                    }
                }

                // Power tile
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 16
                    color: Theme.primary
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "power_settings_new"; font.family: Theme.fontIcons; font.pixelSize: 15; color: Theme.attention }
                        Text { text: "Power"; font.family: Theme.fontText; font.pixelSize: 11; font.bold: true; color: Theme.ink }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.pillBorder }

            // ── Sliders Simulation ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                // Volume slider
                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    color: "transparent"

                    Rectangle {
                        id: sVolIcon
                        width: 38; height: 36; color: Theme.plum
                        topLeftRadius: 18; bottomLeftRadius: 18
                        Text { anchors.centerIn: parent; text: "volume_up"; font.family: Theme.fontIcons; font.pixelSize: 16; color: Theme.ink }
                    }
                    Rectangle {
                        anchors.left: sVolIcon.right; anchors.right: parent.right; height: 36
                        color: Theme.primary; topRightRadius: 18; bottomRightRadius: 18

                        Rectangle {
                            height: 6; radius: 3; color: Theme.qsBg
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                width: parent.width * 0.75; height: 6; radius: 3; color: Theme.attention
                            }
                            Rectangle {
                                x: parent.width * 0.75 - 8; width: 16; height: 16; radius: 8
                                color: Theme.attention; anchors.verticalCenter: parent.verticalCenter
                                border.width: 2; border.color: Theme.ink
                            }
                        }
                    }
                }

                // Brightness slider
                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    color: "transparent"

                    Rectangle {
                        id: sBriIcon
                        width: 38; height: 36; color: Theme.plum
                        topLeftRadius: 18; bottomLeftRadius: 18
                        Text { anchors.centerIn: parent; text: "brightness_6"; font.family: Theme.fontIcons; font.pixelSize: 16; color: Theme.ink }
                    }
                    Rectangle {
                        anchors.left: sBriIcon.right; anchors.right: parent.right; height: 36
                        color: Theme.primary; topRightRadius: 18; bottomRightRadius: 18

                        Rectangle {
                            height: 6; radius: 3; color: Theme.qsBg
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                width: parent.width * 0.60; height: 6; radius: 3; color: Theme.attention
                            }
                            Rectangle {
                                x: parent.width * 0.60 - 8; width: 16; height: 16; radius: 8
                                color: Theme.attention; anchors.verticalCenter: parent.verticalCenter
                                border.width: 2; border.color: Theme.ink
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── 5. MOVABLE COLOR CROSSHAIR RETICLE TOOL ────────────────────────────────
    Item {
        id: crosshair
        x: root.crosshairX - width / 2
        y: root.crosshairY - height / 2
        width: 60
        height: 60
        z: 150

        // Reticle crosshair lines
        Rectangle {
            anchors.centerIn: parent
            width: 50
            height: 1.5
            color: Theme.ink
            opacity: 0.8
        }
        Rectangle {
            anchors.centerIn: parent
            width: 1.5
            height: 50
            color: Theme.ink
            opacity: 0.8
        }

        // Circular magnifying loupe
        Rectangle {
            id: loupeCircle
            anchors.centerIn: parent
            width: 32
            height: 32
            radius: 16
            color: root.currentSampledColor
            border.width: 2.5
            border.color: Theme.ink

            // Inner focus dot
            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: Theme.attention
            }
        }

        // Floating color info badge
        Rectangle {
            anchors.top: parent.bottom
            anchors.topMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            implicitHeight: 24
            implicitWidth: badgeRow.implicitWidth + 16
            radius: 12
            color: Qt.rgba(0.06, 0.04, 0.15, 0.94)
            border.width: 1
            border.color: Theme.attention

            RowLayout {
                id: badgeRow
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    color: root.currentSampledColor
                    border.width: 1
                    border.color: Theme.ink
                }

                Text {
                    text: root.currentSampledColor.toString().toUpperCase()
                    font.family: Theme.fontText
                    font.pixelSize: 10
                    font.bold: true
                    color: Theme.ink
                }
            }
        }

        // Crosshair can also be dragged directly
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            drag.target: crosshair
            onPositionChanged: {
                if (drag.active) {
                    root.samplePixelAt(crosshair.x + crosshair.width / 2, crosshair.y + crosshair.height / 2)
                }
            }
        }
    }

    // ─── 6. THE MOVABLE COLOR PICKER WIDGET ─────────────────────────────────────
    // As requested: "displays somewhere like under the right side. Make it actually movable
    // so I can click on a button and drag it across wherever I want."
    ColorPickerWidget {
        id: pickerWidget
        x: root.width - width - 40
        y: 80
        z: 200
    }
}
