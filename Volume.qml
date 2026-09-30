// =============================================================================
//  VOLUME.QML — the audio volume control pill on the top bar
// =============================================================================
//  Built on top of the Pill component:
//     [ (icon) | label ]
//
//  CONTROLS:
//  ---------
//  • Left Click   → Toggle Mute (unmutes when scrolling up)
//  • Scroll Wheel → Step volume 5-by-5 cleanly rounded to nearest multiple of 5
//                   (e.g. 95 -> 100, 99 -> 100, 91 -> 90)
//  • Right Click  → Windows-style context menu with one-click access to:
//                   1. PulseAudio Volume Control (pavucontrol - inputs, outputs, config)
//                   2. Easy Effects (easyeffects - audio effects & equalizer)
// =============================================================================
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Pill {
    id: root

    // Monitor reference passed from the bar
    property var screen: null

    // Keep our references to the default sink alive & up to date.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // --- Live audio state (re-read whenever anything changes) -------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null

    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false
    readonly property int volumePercent: Math.round(volume * 100)

    // --- Dynamic icon + label (bindings, re-evaluate on every change) -----------
    icon: muted ? "volume_off"
                : (volumePercent > 50 ? "volume_up"
                : (volumePercent > 0 ? "volume_down" : "volume_mute"))
    label: muted ? "Muted" : volumePercent + "%"

    // --- Volume stepping with 5-to-5 rounding logic -------------------------------
    function stepVolume(direction) {
        if (!root.audio) return
        let currentPct = Math.round(root.audio.volume * 100)
        let nextPct = currentPct

        if (direction > 0) {
            // Round / step up to the next multiple of 5 (e.g. 99 -> 100, 95 -> 100, 91 -> 95)
            let snapped = Math.round(currentPct / 5) * 5
            if (snapped > currentPct) {
                nextPct = snapped
            } else {
                nextPct = snapped + 5
            }
        } else if (direction < 0) {
            // Round / step down to the previous multiple of 5 (e.g. 91 -> 90, 100 -> 95, 99 -> 95)
            let snapped = Math.round(currentPct / 5) * 5
            if (snapped < currentPct) {
                nextPct = snapped
            } else {
                nextPct = snapped - 5
            }
        }

        // Clamp to whole range 0 - 100%
        nextPct = Math.max(0, Math.min(100, nextPct))

        // Set floating volume without precision drift (e.g. 0.95, 1.0, 0.90)
        root.audio.volume = Number((nextPct / 100).toFixed(2))

        // Unmute automatically when raising volume
        if (direction > 0 && root.muted) {
            root.audio.muted = false
        }
    }

    // --- Mouse interaction --------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // Left click = toggle mute; Right click = show audio context menu
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                contextMenu.visible = !contextMenu.visible
            } else {
                if (root.audio) {
                    root.audio.muted = !root.audio.muted
                }
            }
        }

        // Scroll wheel = step volume by 5% with rounding
        onWheel: wheel => {
            root.stepVolume(wheel.angleDelta.y > 0 ? 1 : -1)
        }
    }

    // --- Right-click Windows-style Audio Context Menu ---------------------------
    PanelWindow {
        id: contextMenu
        screen: root.screen
        visible: false
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            right: true
        }
        margins {
            top: Theme.barHeight + 6
            right: 12
        }

        implicitWidth: 260
        implicitHeight: menuCard.implicitHeight

        // Dismiss when clicking outside on Hyprland
        HyprlandFocusGrab {
            windows: [contextMenu]
            active: contextMenu.visible
            onCleared: contextMenu.visible = false
        }

        Rectangle {
            id: menuCard
            anchors.fill: parent
            radius: 12
            color: Theme.qsBg !== "transparent" ? Theme.qsBg : Qt.rgba(0.08, 0.06, 0.18, 0.96)
            border.width: 1
            border.color: Theme.pillBorder !== "transparent" ? Theme.pillBorder : Qt.rgba(1, 1, 1, 0.12)

            // Outer glow / shadow ring
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: parent.radius + 1
                color: "transparent"
                border.color: Theme.attention
                border.width: 1
                opacity: 0.25
                z: -1
            }

            ColumnLayout {
                id: menuCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 4
                    spacing: 6

                    Text {
                        text: "volume_up"
                        font.family: Theme.fontIcons
                        font.pixelSize: 14
                        color: Theme.attention
                    }
                    Text {
                        text: "AUDIO TOOLS"
                        font.family: Theme.fontText
                        font.pixelSize: 9
                        font.bold: true
                        color: Theme.qsTextMuted
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.pillBorder
                }

                // 1. Pavucontrol (PulseAudio / Power Audio Volume Control)
                Rectangle {
                    id: pavuBtn
                    Layout.fillWidth: true
                    height: 44
                    radius: 8
                    color: pavuMouse.containsMouse ? Theme.primary : "transparent"

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: Theme.plum
                            Text {
                                anchors.centerIn: parent
                                text: "tune"
                                font.family: Theme.fontIcons
                                font.pixelSize: 16
                                color: Theme.ink
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Volume Control (Pavucontrol)"
                                font.family: Theme.fontText
                                font.pixelSize: 11
                                font.bold: true
                                color: Theme.ink
                            }

                            Text {
                                text: "Inputs, outputs, configuration & playback"
                                font.family: Theme.fontText
                                font.pixelSize: 8.5
                                color: Theme.qsTextMuted
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    MouseArea {
                        id: pavuMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            contextMenu.visible = false
                            Quickshell.execDetached(["bash", "-c", "pavucontrol || pavucontrol-qt || pwvucontrol"])
                        }
                    }
                }

                // 2. Easy Effects
                Rectangle {
                    id: eeBtn
                    Layout.fillWidth: true
                    height: 44
                    radius: 8
                    color: eeMouse.containsMouse ? Theme.primary : "transparent"

                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: Theme.plum
                            Text {
                                anchors.centerIn: parent
                                text: "graphic_eq"
                                font.family: Theme.fontIcons
                                font.pixelSize: 16
                                color: Theme.ink
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Easy Effects"
                                font.family: Theme.fontText
                                font.pixelSize: 11
                                font.bold: true
                                color: Theme.ink
                            }

                            Text {
                                text: "Audio effects, equalizer & filters"
                                font.family: Theme.fontText
                                font.pixelSize: 8.5
                                color: Theme.qsTextMuted
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    MouseArea {
                        id: eeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            contextMenu.visible = false
                            Quickshell.execDetached(["bash", "-c", "easyeffects || flatpak run com.github.wwmm.easyeffects"])
                        }
                    }
                }
            }
        }
    }
}
