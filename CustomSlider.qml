// =============================================================================
//  CUSTOMSLIDER.QML — icon pill + draggable slider track with physics
// =============================================================================
//  Layout:
//     [ (icon / lock dial) | ───────●──────── ]
//     plum                   primary  track
//
//  TRANSFORMATION & INTERACTION:
//  -----------------------------
//  1. Morphing Icon to Safe-Lock Dial:
//     In the idle state, the left slot displays the standard icon (volume,
//     mic, brightness). As soon as the user clicks and holds the slider, the
//     icon transforms into a rotating combination lock dial with precision
//     tick marks, a pulsing 12 o'clock index notch, and live numeric value.
//     As long as the track is held, the dial tracks live adjustments.
//     Upon release, it smoothly transforms back into the icon.
//
//  2. Robbery / Elastic Yank:
//     Dragging or yanking past the limits stretches the knob outside the track
//     with elastic tension, then snaps back into the boundary slot with a
//     satisfying rubber bounce.
//
//  3. Locked Vertical Scroll & Zero Clipping:
//     MouseArea has `preventStealing: true` so dragging the slider never
//     triggers parent Flickables. Handle is elevated to root level with high z
//     so it always overlays cleanly without clipping.
// =============================================================================
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Public properties ------------------------------------------------------
    property string icon: "volume_up"   // Material glyph, e.g. brightness_6
    property real value: 0.5            // 0.0 to maxValue — where the handle sits
    property real maxValue: 1.0         // upper end of the range (1.5 = 150% boost)
    property string displayText: ""     // optional text drawn at the right end of the track

    // --- Signal: fired when the USER drags, with the new 0.0–maxValue value ------
    signal valueChangedByUser(real newValue)

    // Internal drag & hold state
    property bool isDragging: false
    property bool wheelActive: false
    readonly property bool isHolding: isDragging || wheelActive
    property real dragValue: 0.0
    readonly property real effectiveValue: isDragging ? dragValue : root.value

    // Elastic rubber yank physics ("robbery" mode)
    property real rubberOffset: 0.0

    // Safe combination dial rotation & mechanical ticks
    readonly property real dialRotation: (root.maxValue > 0 ? (root.effectiveValue / root.maxValue) : 0) * 720
    readonly property int currentTick: Math.floor(dialRotation / 18)

    implicitHeight: 38
    Layout.fillWidth: true
    radius: 0
    color: "transparent"

    // Elevate z-index while dragging so knob overlays over neighbor widgets
    z: isHolding ? 50 : 1

    // Micro mechanical pulse on each dial tick
    onCurrentTickChanged: {
        if (root.isHolding) {
            tickPulse.restart()
        }
    }

    // Timer to keep the lock dial visible briefly on mouse wheel adjustments
    Timer {
        id: wheelTimer
        interval: 650
        repeat: false
        onTriggered: {
            root.wheelActive = false
        }
    }

    // Elastic snap-back animation when letting go of an out-of-bounds yank
    NumberAnimation {
        id: snapBackAnim
        target: root
        property: "rubberOffset"
        to: 0
        duration: 420
        easing.type: Easing.OutElastic
        easing.amplitude: 2.0
        easing.period: 0.32
    }

    // --- LEFT ZONE: icon segment (morphs into safe combination dial on hold) -------
    Rectangle {
        id: iconSeg
        width: Math.max(38, iconTxt.width + 18)
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.plum
        topLeftRadius: height / 2
        bottomLeftRadius: height / 2
        topRightRadius: 0
        bottomRightRadius: 0
        z: 1

        // Default: Material Icon Glyph (fades & shrinks when holding)
        Text {
            id: iconTxt
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.fontIcons
            font.pixelSize: 17
            color: Theme.ink
            leftPadding: 2
            scale: root.isHolding ? 0.3 : 1.0
            opacity: root.isHolding ? 0.0 : 1.0

            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }

        // Active: Safe Combination Lock Dial (transforms in on hold)
        Item {
            id: lockDial
            anchors.centerIn: parent
            width: 32
            height: 32
            scale: root.isHolding ? 1.0 : 0.3
            opacity: root.isHolding ? 1.0 : 0.0

            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutBack }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180 }
            }

            // Outer dial rim
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.qsBg
                border.color: Theme.pillBorder
                border.width: 1

                // Subtle inner shadow ring
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 2
                    height: parent.height - 2
                    radius: width / 2
                    color: "transparent"
                    border.color: Theme.ink
                    opacity: 0.15
                    border.width: 1
                }

                // Rotating Tick Disc (The Safe Combination Dial)
                Item {
                    id: tickDisc
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    rotation: root.dialRotation

                    // 20 radial tick marks
                    Repeater {
                        model: 20
                        Item {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            rotation: index * 18

                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: (index % 5 === 0) ? 1.5 : 1
                                height: (index % 5 === 0) ? 3.5 : 2
                                radius: 0.5
                                color: (index % 5 === 0) ? Theme.attention : Theme.ink
                                opacity: (index % 5 === 0) ? 0.95 : 0.45
                            }
                        }
                    }
                }

                // 12 o'clock Safe Index Notch Pointer
                Rectangle {
                    id: notchIndicator
                    width: 2.5
                    height: 4
                    radius: 1
                    color: Theme.attention
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    z: 10

                    // Micro pulse animation on each mechanical tick
                    SequentialAnimation {
                        id: tickPulse
                        NumberAnimation {
                            target: notchIndicator
                            property: "scale"
                            to: 1.45
                            duration: 35
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: notchIndicator
                            property: "scale"
                            to: 1.0
                            duration: 55
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                // Center Core Bezel with Numeric Percentage Value
                Rectangle {
                    id: centerHub
                    width: 20
                    height: 20
                    radius: 10
                    color: Theme.primary
                    border.color: Theme.pillBorder
                    border.width: 1
                    anchors.centerIn: parent
                    z: 15

                    Text {
                        anchors.centerIn: parent
                        text: Math.round(root.effectiveValue * 100) + "%"
                        font.family: Theme.fontText
                        font.pixelSize: 8
                        font.bold: true
                        color: Theme.ink
                    }
                }
            }
        }
    }

    // --- RIGHT ZONE: track segment -------------------------------------------------
    Rectangle {
        id: trackSeg
        anchors.left: iconSeg.right
        anchors.right: parent.right
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.primary
        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: height / 2
        bottomRightRadius: height / 2
        z: 2

        // Area the actual controls live in (inset from both edges)
        Item {
            id: sliderBox
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14

            // --- The rail: thin rounded strip ---------------------------------------
            Rectangle {
                id: rail
                height: 6
                radius: 3
                color: Theme.qsBg
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                z: 1
            }

            // --- Filled portion: stretches from left up to the handle ---------------
            Rectangle {
                id: fillBar
                height: 6
                radius: 3
                color: Theme.attention
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                z: 2
                // Follows the handle's center point, extending seamlessly
                width: Math.max(0, Math.min(rail.width + Math.max(0, root.rubberOffset), (handle.x - trackSeg.x - 14) + handle.width / 2))
            }

            // --- Optional value text (right-aligned in the track) -------------------
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.displayText !== ""
                text: root.displayText
                font.family: Theme.fontText
                font.pixelSize: 10
                font.bold: true
                color: Theme.ink
                z: 3
            }

            // --- Interaction MouseArea ---------------------------------------------
            // Direct fit over sliderBox: mouse.x = 0 is start of rail,
            // mouse.x = rail.width is end of rail.
            MouseArea {
                id: mouseArea
                anchors.fill: parent
                anchors.topMargin: -8
                anchors.bottomMargin: -8
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                preventStealing: true
                z: 10

                function updateVal(mouse) {
                    // Rubber-band calculation beyond limits with 5px cushion
                    if (mouse.x > rail.width + 5) {
                        let over = mouse.x - (rail.width + 5)
                        root.rubberOffset = Math.min(26, Math.pow(over, 0.70) * 1.3)
                        root.dragValue = root.maxValue
                        root.valueChangedByUser(root.maxValue)
                    } else if (mouse.x < -5) {
                        let under = -5 - mouse.x
                        root.rubberOffset = -Math.min(26, Math.pow(under, 0.70) * 1.3)
                        root.dragValue = 0
                        root.valueChangedByUser(0)
                    } else {
                        // Normal slider range
                        root.rubberOffset = 0
                        let clampedX = Math.max(0, Math.min(rail.width, mouse.x))
                        let newVal = rail.width > 0 ? (clampedX / rail.width) * root.maxValue : 0
                        root.dragValue = newVal
                        root.valueChangedByUser(newVal)
                    }
                }

                onPressed: mouse => {
                    snapBackAnim.stop()
                    root.isDragging = true
                    updateVal(mouse)
                }

                onPositionChanged: mouse => {
                    if (pressed) {
                        updateVal(mouse)
                    }
                }

                onReleased: {
                    root.isDragging = false
                    if (root.rubberOffset !== 0) {
                        snapBackAnim.restart()
                    }
                }

                onCanceled: {
                    root.isDragging = false
                    if (root.rubberOffset !== 0) {
                        snapBackAnim.restart()
                    }
                }

                onWheel: wheel => {
                    let step = root.maxValue * 0.05
                    let delta = wheel.angleDelta.y > 0 ? step : -step
                    let newVal = Math.max(0, Math.min(root.maxValue, root.value + delta))
                    root.wheelActive = true
                    wheelTimer.restart()
                    root.valueChangedByUser(newVal)
                }
            }
        }
    }

    // --- The draggable knob/handle: elevated to root level with z: 50 --------------
    // Direct child of root with high z ensures it overlays cleanly above pill segments.
    Rectangle {
        id: handle
        width: mouseArea.containsMouse || root.isDragging ? 18 : 16
        height: width
        radius: height / 2
        color: Theme.attention
        y: Math.round((root.height - height) / 2)
        z: 50

        // Base slot position inside rail + rubber yank offset
        readonly property real maxTravel: Math.max(0, rail.width - width)
        readonly property real baseSlotX: (root.maxValue > 0 ? (root.effectiveValue / root.maxValue) : 0) * maxTravel
        x: trackSeg.x + 14 + baseSlotX + root.rubberOffset

        Behavior on width {
            NumberAnimation { duration: 120 }
        }

        // Rubber squash & stretch transform when pulled taut
        transform: Scale {
            origin.x: handle.width / 2
            origin.y: handle.height / 2
            xScale: 1.0 + Math.min(0.35, Math.abs(root.rubberOffset) / 60)
            yScale: 1.0 - Math.min(0.20, Math.abs(root.rubberOffset) / 120)
        }

        // Inner core dot for precision feel
        Rectangle {
            anchors.centerIn: parent
            width: 6
            height: 6
            radius: 3
            color: Theme.qsBg
            opacity: root.isDragging ? 0.9 : 0.4
        }
    }
}
