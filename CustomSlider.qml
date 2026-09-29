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
//     Normal sliding across the track is completely smooth. When forcefully
//     yanking or dragging past the limit, the knob stretches outside its
//     boundary with elastic tension, overlaying on top of the pill and adjacent
//     segments, then snaps back into the maximum (or minimum) slot on release
//     with a rubber bounce.
//
//  2. Slow & Careful Tuning Easter Egg (Safe-Lock Dial Pip):
//     Hidden by default during normal dragging. Only appears as an Easter egg
//     when the user deliberately moves slowly and carefully (fine-tuning).
//     Detects slow, delicate movement sustained over ~140ms and reveals a
//     circular safe-combination lock dial with 24 engraved tick marks,
//     mechanical ticking pulse on the 12 o'clock notch, and a live numeric
//     percentage readout. If the user speeds up, it tucks away immediately,
//     and re-appears whenever they slow down again anywhere on the track.
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
    property real lastMouseX: 0
    property real lastMouseTime: 0
    property real dragSpeed: 0

    // Fine-tuning Easter egg state & safe-lock dial
    // Only unlocks when the user deliberately moves slowly and carefully!
    property bool fineTuningUnlocked: false
    readonly property real dialRotation: (root.maxValue > 0 ? (root.effectiveValue / root.maxValue) : 0) * 720
    readonly property int currentTick: Math.floor(dialRotation / 15)

    implicitHeight: 38
    Layout.fillWidth: true
    radius: 0
    color: "transparent"

    // Elevate z-index while active so the entire slider and floating pip render on top of neighbor widgets
    z: (isDragging && fineTuningUnlocked) ? 1000 : (isDragging ? 50 : 1)

    // Micro mechanical pulse on each dial tick
    onCurrentTickChanged: {
        if (root.isDragging && root.fineTuningUnlocked) {
            tickPulse.restart()
        }
    }

    // Timer that unlocks the Easter egg after sustained slow, careful movement
    Timer {
        id: slowTuneTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (root.isDragging && root.dragSpeed < 180 && Math.abs(root.rubberOffset) < 2) {
                root.fineTuningUnlocked = true
            }
        }
    }

    // Timer to keep the safe dial visible for a brief moment after releasing slow tune
    Timer {
        id: hideDialTimer
        interval: 260
        repeat: false
        onTriggered: {
            root.fineTuningUnlocked = false
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
            // Covers sliderBox with zero confusing offsets: mouse.x = 0 is start of rail,
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
                    let now = Date.now()
                    let dt = Math.max(1, now - root.lastMouseTime)
                    let dx = mouse.x - root.lastMouseX
                    let instantSpeed = Math.abs(dx) / (dt / 1000)
                    // Smooth moving average for velocity
                    root.dragSpeed = (root.dragSpeed * 0.4) + (instantSpeed * 0.6)
                    root.lastMouseX = mouse.x
                    root.lastMouseTime = now

                    // --- Fine-tuning Easter egg detection ---
                    // Normal drag is 200-600 px/s.
                    // Fine-tuning is slow & careful (< 160 px/s).
                    // Fast motion / swiping (> 300 px/s) hides the dial immediately.
                    if (root.dragSpeed > 300 || Math.abs(root.rubberOffset) > 2) {
                        slowTuneTimer.stop()
                        root.fineTuningUnlocked = false
                    } else if (root.dragSpeed < 160 && Math.abs(root.rubberOffset) < 2) {
                        // Slow, careful tuning: start or maintain fine-tuning
                        if (!root.fineTuningUnlocked && !slowTuneTimer.running) {
                            slowTuneTimer.restart()
                        }
                    }

                    // --- Slider Value & Yank Mechanics ---
                    // Deadband of 5px past limits so reaching 0% or 100% is solid
                    // and doesn't prematurely trigger rubber stretch.
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
                        // Inside normal slider range: zero rubber offset, completely clean
                        root.rubberOffset = 0
                        let clampedX = Math.max(0, Math.min(rail.width, mouse.x))
                        let newVal = rail.width > 0 ? (clampedX / rail.width) * root.maxValue : 0
                        root.dragValue = newVal
                        root.valueChangedByUser(newVal)
                    }
                }

                onPressed: mouse => {
                    snapBackAnim.stop()
                    slowTuneTimer.stop()
                    hideDialTimer.stop()
                    root.isDragging = true
                    root.fineTuningUnlocked = false
                    root.lastMouseX = mouse.x
                    root.lastMouseTime = Date.now()
                    root.dragSpeed = 0
                    updateVal(mouse)
                }

                onPositionChanged: mouse => {
                    if (pressed) {
                        updateVal(mouse)
                    }
                }

                onReleased: {
                    root.isDragging = false
                    slowTuneTimer.stop()
                    if (root.rubberOffset !== 0) {
                        snapBackAnim.restart()
                    }
                    if (root.fineTuningUnlocked) {
                        hideDialTimer.restart()
                    } else {
                        root.fineTuningUnlocked = false
                    }
                }

                onCanceled: {
                    root.isDragging = false
                    slowTuneTimer.stop()
                    if (root.rubberOffset !== 0) {
                        snapBackAnim.restart()
                    }
                    root.fineTuningUnlocked = false
                }

                onWheel: wheel => {
                    let step = root.maxValue * 0.05
                    let delta = wheel.angleDelta.y > 0 ? step : -step
                    let newVal = Math.max(0, Math.min(root.maxValue, root.value + delta))
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

    // =========================================================================
    //  SAFE-LOCK DIAL CIRCULAR PIP (Careful Fine-Tuning Easter Egg)
    // =========================================================================
    //  Floats adjacent to the slider handle, tracking its X position smoothly.
    //  Only revealed when the user is moving slowly and fine-tuning carefully!
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

        // EASTER EGG: Only show when fine-tuning deliberately slow & careful
        readonly property bool shouldShow: root.fineTuningUnlocked && Math.abs(root.rubberOffset) < 3

        scale: shouldShow ? 1.0 : 0.35
        opacity: shouldShow ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
        }
        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
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
