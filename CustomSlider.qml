// =============================================================================
//  CUSTOMSLIDER.QML — icon pill + draggable slider track with physics
// =============================================================================
//  Layout:
//     [ (icon) | ───────●──────── ]
//     plum       primary  track
//
//  MODES & ANIMATIONS:
//  -------------------
//  1. Robbery / Elastic Yank:
//     When yanking or dragging past the limit, the knob stretches outside
//     its boundary with elastic tension, overlaying on top of the pill and
//     adjacent segments, then violently snaps back into the maximum (or
//     minimum) slot on release with an elastic bounce.
//
//  2. Slow & Careful Tuning (Safe-Lock Dial Pip):
//     When fine-tuning slowly, a circular pip appears adjacent to the slider.
//     Inside is a rotating safe combination lock dial with engraved tick marks,
//     a 12 o'clock index notch that pulses on each mechanical tick, and a
//     crisp numeric percentage display in the center hub.
//
//  3. Locked Vertical Scroll & Zero Clipping:
//     MouseArea has `preventStealing: true` so dragging the slider never
//     triggers parent Flickables. Handle is elevated to root level with high z
//     so it always overlays above the pill segments instead of clipping behind.
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

    // Internal drag state
    property bool isDragging: false
    property real dragValue: 0.0
    readonly property real effectiveValue: isDragging ? dragValue : root.value

    // Elastic rubber yank physics ("robbery" mode)
    property real rubberOffset: 0.0
    property bool isFastYank: false
    property real lastMouseX: 0
    property real lastMouseTime: 0
    property real dragSpeed: 0

    // Fine-tuning state & safe-lock dial
    property bool fineTuningActive: false
    readonly property real dialRotation: (root.maxValue > 0 ? (root.effectiveValue / root.maxValue) : 0) * 720
    readonly property int currentTick: Math.floor(dialRotation / 15)

    implicitHeight: 38
    Layout.fillWidth: true
    radius: 0
    color: "transparent"

    // Elevate z-index while active so the entire slider and floating pip render on top of neighbor widgets
    z: (isDragging || fineTuningActive) ? 1000 : 1

    // Micro mechanical pulse on each dial tick
    onCurrentTickChanged: {
        if (root.isDragging || root.fineTuningActive) {
            tickPulse.restart()
        }
    }

    // Timer to keep the safe dial visible for a moment after gentle scrolling / release
    Timer {
        id: hideDialTimer
        interval: 380
        repeat: false
        onTriggered: {
            root.fineTuningActive = false
            root.isFastYank = false
        }
    }

    // Elastic snap-back animation when letting go of a yank
    NumberAnimation {
        id: snapBackAnim
        target: root
        property: "rubberOffset"
        to: 0
        duration: 420
        easing.type: Easing.OutElastic
        easing.amplitude: 2.0
        easing.period: 0.32
        onFinished: {
            root.isFastYank = false
        }
    }

    // --- LEFT ZONE: icon segment --------------------------------------------------
    Rectangle {
        id: iconSeg
        width: iconTxt.width + 16
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.plum
        topLeftRadius: height / 2
        bottomLeftRadius: height / 2
        topRightRadius: 0
        bottomRightRadius: 0
        z: 1

        Text {
            id: iconTxt
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.fontIcons
            font.pixelSize: 17
            color: Theme.ink
            leftPadding: 4
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
            MouseArea {
                id: mouseArea
                anchors.fill: parent
                anchors.topMargin: -8
                anchors.bottomMargin: -8
                anchors.leftMargin: -14
                anchors.rightMargin: -14
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                preventStealing: true
                z: 10

                function updateVal(mouse) {
                    let now = Date.now()
                    let dt = Math.max(1, now - root.lastMouseTime)
                    // adjustedX accounts for anchors.leftMargin: -14
                    let adjustedX = mouse.x - 14
                    let dx = adjustedX - root.lastMouseX
                    root.dragSpeed = Math.abs(dx) / (dt / 1000)
                    root.lastMouseX = adjustedX
                    root.lastMouseTime = now

                    // Detect fast yank velocity
                    if (root.dragSpeed > 550) {
                        root.isFastYank = true
                    } else if (root.dragSpeed < 200) {
                        root.isFastYank = false
                    }

                    // Rubber-band calculation beyond rail limits
                    if (adjustedX > rail.width) {
                        let over = adjustedX - rail.width
                        root.rubberOffset = Math.min(32, Math.pow(over, 0.72) * 1.5)
                        root.dragValue = root.maxValue
                        root.valueChangedByUser(root.maxValue)
                    } else if (adjustedX < 0) {
                        let under = -adjustedX
                        root.rubberOffset = -Math.min(32, Math.pow(under, 0.72) * 1.5)
                        root.dragValue = 0
                        root.valueChangedByUser(0)
                    } else {
                        root.rubberOffset = 0
                        let newVal = rail.width > 0 ? (adjustedX / rail.width) * root.maxValue : 0
                        root.dragValue = newVal
                        root.valueChangedByUser(newVal)
                    }
                }

                onPressed: mouse => {
                    snapBackAnim.stop()
                    hideDialTimer.stop()
                    root.isDragging = true
                    root.fineTuningActive = true
                    let adjustedX = mouse.x - 14
                    root.lastMouseX = adjustedX
                    root.lastMouseTime = Date.now()
                    root.dragSpeed = 0
                    root.isFastYank = false
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
                    hideDialTimer.restart()
                }

                onCanceled: {
                    root.isDragging = false
                    if (root.rubberOffset !== 0) {
                        snapBackAnim.restart()
                    }
                    hideDialTimer.restart()
                }

                onWheel: wheel => {
                    let step = root.maxValue * 0.05
                    let delta = wheel.angleDelta.y > 0 ? step : -step
                    let newVal = Math.max(0, Math.min(root.maxValue, root.value + delta))
                    root.fineTuningActive = true
                    hideDialTimer.restart()
                    root.valueChangedByUser(newVal)
                }
            }
        }
    }

    // --- The draggable knob/handle: elevated to root level with z: 50 --------------
    // Being a direct child of root with high z ensures it overlays ON TOP OF iconSeg
    // (when pulled left) and ON TOP OF trackSeg's end cap (when pulled right),
    // never clipping behind the pill widget!
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
            xScale: 1.0 + Math.min(0.40, Math.abs(root.rubberOffset) / 60)
            yScale: 1.0 - Math.min(0.25, Math.abs(root.rubberOffset) / 120)
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

    // =========================================================================
    //  SAFE-LOCK DIAL CIRCULAR PIP (Careful Fine-Tuning Mode)
    // =========================================================================
    //  Floats adjacent to the slider handle, tracking its X position smoothly.
    Item {
        id: safeDialPip
        width: 52
        height: 52
        z: 100

        // Center directly above the slider handle, clamped safely inside parent width
        x: Math.max(4, Math.min(root.width - width - 4, handle.x + handle.width / 2 - width / 2))
        y: -height - 8

        Behavior on x {
            NumberAnimation { duration: 60; easing.type: Easing.OutCubic }
        }

        // Active when tuning carefully; tucked away during violent yank outside limit
        readonly property bool shouldShow: (root.isDragging || root.fineTuningActive) && (!root.isFastYank || Math.abs(root.rubberOffset) < 6)

        scale: shouldShow ? 1.0 : 0.4
        opacity: shouldShow ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation { duration: 240; easing.type: Easing.OutBack }
        }
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // --- Downward stem pointing to the handle -------------------------------
        Rectangle {
            width: 10
            height: 10
            radius: 2
            rotation: 45
            color: Theme.qsBg
            border.color: Theme.pillBorder
            border.width: 1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -3
            z: 1
        }

        // --- Outer circular dial body -------------------------------------------
        Rectangle {
            id: dialBody
            anchors.fill: parent
            radius: width / 2
            color: Theme.qsBg
            border.color: Theme.pillBorder
            border.width: 1.5
            z: 2

            // Subtle inner bevel shadow ring
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 4
                height: parent.height - 4
                radius: width / 2
                color: "transparent"
                border.color: Theme.ink
                opacity: 0.15
                border.width: 1
            }

            // --- Rotating Tick Disc (The Safe Combination Dial) -----------------
            Item {
                id: tickDisc
                anchors.centerIn: parent
                width: 44
                height: 44
                rotation: root.dialRotation

                // 24 radial tick marks around the safe lock dial
                Repeater {
                    model: 24
                    Item {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        rotation: index * 15

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: (index % 4 === 0) ? 2 : 1
                            height: (index % 4 === 0) ? 5 : 3
                            radius: 0.5
                            color: (index % 4 === 0) ? Theme.attention : Theme.ink
                            opacity: (index % 4 === 0) ? 0.95 : 0.45
                        }
                    }
                }
            }

            // --- 12 o'clock Safe Index Notch Pointer ----------------------------
            Rectangle {
                id: notchIndicator
                width: 3
                height: 5
                radius: 1
                color: Theme.attention
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                z: 10

                // Quick bounce on every mechanical tick
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

            // --- Center Core Bezel with Numeric Percentage Value ----------------
            Rectangle {
                id: centerHub
                width: 28
                height: 28
                radius: 14
                color: Theme.primary
                border.color: Theme.pillBorder
                border.width: 1
                anchors.centerIn: parent
                z: 15

                Text {
                    id: numericValueTxt
                    anchors.centerIn: parent
                    text: Math.round(root.effectiveValue * 100) + "%"
                    font.family: Theme.fontText
                    font.pixelSize: 9
                    font.bold: true
                    color: Theme.ink
                }
            }
        }
    }
}
