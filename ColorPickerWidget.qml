// =============================================================================
//  COLORPICKERWIDGET.QML — Floating, draggable color palette studio widget
// =============================================================================
//  Layout:
//     • Top drag handle pill (click & drag anywhere across the screen)
//     • Title & instructions
//     • List of color role pills (Background, Primary, Accent, Highlight, etc.)
//       - Left segment of pill = live color swatch of currently picked color
//       - Right segment = role name
//       - Active pill has glowing/pulsing indication
//     • Hue/Saturation fine-tune spectrum strip
//     • Save & Apply Changes button + Cancel button
// =============================================================================
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    width: 320
    implicitHeight: mainCol.implicitHeight + 28
    radius: 18
    color: Theme.qsBg !== "transparent" ? Theme.qsBg : Qt.rgba(0.07, 0.05, 0.16, 0.94)
    border.width: 1.5
    border.color: Theme.pillBorder !== "transparent" ? Theme.pillBorder : Qt.rgba(1, 1, 1, 0.12)
    z: 200

    // Elevated shadow ring
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        radius: parent.radius + 1
        color: "transparent"
        border.color: Theme.attention
        border.width: 1
        opacity: 0.35
        z: -1
    }

    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ─── 1. TOP DRAG HANDLE BUTTON ──────────────────────────────────────────
        // Centered button at the top where user clicks and drags the whole widget
        Rectangle {
            id: dragPill
            Layout.alignment: Qt.AlignHCenter
            width: 130
            height: 24
            radius: 12
            color: Theme.plum
            border.width: 1
            border.color: Theme.pillBorder

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "drag_indicator"
                    font.family: Theme.fontIcons
                    font.pixelSize: 14
                    color: Theme.ink
                }

                Text {
                    text: "DRAG WIDGET"
                    font.family: Theme.fontText
                    font.pixelSize: 9
                    font.bold: true
                    color: Theme.ink
                }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                drag.target: root
                drag.axis: Drag.XAndYAxis
            }

            HoverLift {}
        }

        // ─── 2. HEADER & WALLPAPER INFO ─────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: "Theme Color Studio"
                font.family: Theme.fontText
                font.pixelSize: 14
                font.bold: true
                color: Theme.qsText
            }

            Text {
                text: "Select a color role · move crosshair over wallpaper to sample"
                font.family: Theme.fontText
                font.pixelSize: 9
                color: Theme.qsTextMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.pillBorder
        }

        // ─── 3. THE COLOR ROLE PILLS LIST ───────────────────────────────────────
        // Each button is a 2-segment pill:
        // [ (swatch: current color) | (Role Name: "Background", "Primary", etc.) ]
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: ThemeStudioState.slots

                Rectangle {
                    id: rolePill
                    required property var modelData
                    Layout.fillWidth: true
                    height: 32
                    radius: height / 2
                    color: "transparent"

                    readonly property bool isSelected: ThemeStudioState.activeSlot === modelData.id
                    readonly property color currentColor: ThemeStudioState.colorForSlot(modelData.id)

                    // Outer active glowing border
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: rolePill.isSelected ? 2 : 1
                        border.color: rolePill.isSelected ? Theme.attention : (pillMouse.containsMouse ? Theme.ink : Theme.pillBorder)

                        // Pulsing neon animation on the active pill
                        SequentialAnimation on opacity {
                            running: rolePill.isSelected
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.55; duration: 650; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
                        }
                    }

                    // ── Left Segment: Live Swatch of the currently picked color ──
                    Rectangle {
                        id: swatchSeg
                        width: parent.height
                        height: parent.height
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: rolePill.currentColor
                        topLeftRadius: height / 2
                        bottomLeftRadius: height / 2
                        topRightRadius: 0
                        bottomRightRadius: 0

                        // Inner border to separate from dark or light backgrounds
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.25)

                        // Center indicator dot
                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.ink
                            opacity: rolePill.isSelected ? 0.9 : 0.4
                        }
                    }

                    // ── Right Segment: Respectable Color Role Name ─────────────
                    Rectangle {
                        id: labelSeg
                        anchors.left: swatchSeg.right
                        anchors.right: parent.right
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter
                        color: rolePill.isSelected ? Theme.primary : (pillMouse.containsMouse ? Theme.plum : Theme.qsBgAlt)
                        topLeftRadius: 0
                        bottomLeftRadius: 0
                        topRightRadius: height / 2
                        bottomRightRadius: height / 2

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Text {
                                text: rolePill.modelData.name
                                font.family: Theme.fontText
                                font.pixelSize: 11
                                font.bold: rolePill.isSelected
                                color: rolePill.isSelected ? Theme.attention : Theme.qsText
                            }

                            Item { Layout.fillWidth: true }

                            // Active indicator badge
                            Rectangle {
                                visible: rolePill.isSelected
                                implicitHeight: 14
                                implicitWidth: tuningTxt.implicitWidth + 8
                                radius: 3
                                color: Theme.attention

                                Text {
                                    id: tuningTxt
                                    anchors.centerIn: parent
                                    text: "TUNING"
                                    font.family: Theme.fontText
                                    font.pixelSize: 7.5
                                    font.bold: true
                                    color: Theme.ink
                                }
                            }

                            // Hex code readout
                            Text {
                                text: rolePill.currentColor.toString().toUpperCase()
                                font.family: Theme.fontText
                                font.pixelSize: 10
                                color: Theme.qsTextMuted
                            }
                        }
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ThemeStudioState.activeSlot = rolePill.modelData.id
                    }
                }
            }
        }

        // ─── 4. HUE & BRIGHTNESS SPECTRUM STRIP ──────────────────────────────────
        // Quick color strip where you can also slide across hues to fine-tune
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "Color Spectrum Fine-Tune:"
                font.family: Theme.fontText
                font.pixelSize: 9
                color: Theme.qsTextMuted
            }

            Rectangle {
                id: spectrumBar
                Layout.fillWidth: true
                height: 18
                radius: 9
                border.width: 1
                border.color: Theme.pillBorder
                clip: true

                // Full rainbow spectrum gradient
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.00; color: "#ff0000" }
                    GradientStop { position: 0.17; color: "#ffff00" }
                    GradientStop { position: 0.33; color: "#00ff00" }
                    GradientStop { position: 0.50; color: "#00ffff" }
                    GradientStop { position: 0.67; color: "#0000ff" }
                    GradientStop { position: 0.83; color: "#ff00ff" }
                    GradientStop { position: 1.00; color: "#ff0000" }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    function pickFromSpectrum(mouse) {
                        let frac = Math.max(0, Math.min(1.0, mouse.x / width))
                        let hueColor = Qt.hsva(frac, 0.85, 0.90, 1.0)
                        ThemeStudioState.setSlotColor(ThemeStudioState.activeSlot, hueColor)
                    }
                    onPressed: mouse => pickFromSpectrum(mouse)
                    onPositionChanged: mouse => { if (pressed) pickFromSpectrum(mouse) }
                }
            }

            // Monochrome / lightness strip (black to white)
            Rectangle {
                Layout.fillWidth: true
                height: 14
                radius: 7
                border.width: 1
                border.color: Theme.pillBorder
                clip: true

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#000000" }
                    GradientStop { position: 0.5; color: "#777777" }
                    GradientStop { position: 1.0; color: "#ffffff" }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    function pickMono(mouse) {
                        let frac = Math.max(0, Math.min(1.0, mouse.x / width))
                        let monoColor = Qt.rgba(frac, frac, frac, 1.0)
                        ThemeStudioState.setSlotColor(ThemeStudioState.activeSlot, monoColor)
                    }
                    onPressed: mouse => pickMono(mouse)
                    onPositionChanged: mouse => { if (pressed) pickMono(mouse) }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.pillBorder
        }

        // ─── 5. BOTTOM ACTION BUTTONS: SAVE & APPLY / CANCEL ────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Cancel Button
            Rectangle {
                Layout.preferredWidth: 80
                height: 34
                radius: height / 2
                color: Theme.qsBgAlt
                border.width: 1
                border.color: Theme.pillBorder

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: "close"
                        font.family: Theme.fontIcons
                        font.pixelSize: 14
                        color: Theme.qsTextMuted
                    }
                    Text {
                        text: "Cancel"
                        font.family: Theme.fontText
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.qsTextMuted
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ThemeStudioState.cancelAndRevert()
                }

                HoverLift {}
            }

            // Save and Apply Changes Button
            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: height / 2
                color: Theme.attention
                border.width: 1
                border.color: Theme.pillBorder

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "check_circle"
                        font.family: Theme.fontIcons
                        font.pixelSize: 16
                        color: Theme.ink
                    }
                    Text {
                        text: "Save & Apply Changes"
                        font.family: Theme.fontText
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.ink
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ThemeStudioState.saveAndApply()
                }

                HoverLift {}
            }
        }
    }
}
