// =============================================================================
//  CUSTOMSLIDER.QML — icon pill + draggable slider track
// =============================================================================
//  Layout:
//     [ (icon) | ───────●──────── ]
//     plum       primary  track
//
//  HOW IT WORKS
//  ------------
//  The track is a thin rail. A MouseArea covers the whole track area and
//  reports where the pointer is; we convert that X position to a 0.0–1.0
//  value and emit it. The round "handle" is positioned at `value * width`,
//  and the filled portion of the rail extends up to the handle — both are
//  BINDINGS that follow `root.value` automatically.
//
//  CONNECTING IT TO REAL THINGS
//  ----------------------------
//  This component never touches the system itself. QuickSettings.qml uses it
//  like so:
//      CustomSlider { value: sink.audio.volume
//                     onValueChangedByUser: v => sink.audio.volume = v }
//  `value` pulls the current system state in; `valueChangedByUser` pushes
//  changes out. Clean two-way data flow.
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

    // --- Signal: fired when the USER drags, with the new 0.0–1.0 value -----------
    signal valueChangedByUser(real newValue)

    // Internal drag state to prevent destroying the parent's QML property binding
    property bool isDragging: false
    property real dragValue: 0.0
    readonly property real effectiveValue: isDragging ? dragValue : root.value

    implicitHeight: 38
    Layout.fillWidth: true
    radius: 0
    color: "transparent"

    // --- LEFT ZONE: icon segment --------------------------------------------------
    Rectangle {
        id: iconSeg
        width: iconTxt.width + 16
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.plum
        // Left cap, flat right edge (meets the track segment)
        topLeftRadius: height / 2
        bottomLeftRadius: height / 2
        topRightRadius: 0
        bottomRightRadius: 0

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
        // Flat left edge, right cap
        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: height / 2
        bottomRightRadius: height / 2

        // Area the actual controls live in (inset from both edges).
        Item {
            id: sliderBox
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14

            // --- The rail: a thin rounded strip -------------------------------------
            Rectangle {
                id: rail
                height: 6
                radius: 3
                color: Theme.qsBg
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }

            // --- Filled portion: from the left up to the handle -----------------------
            // BINDING: follows `handle.x` live, so it re-draws on every drag.
            Rectangle {
                width: Math.max(0, Math.min(rail.width, handle.x + handle.width / 2))
                height: 6
                radius: 3
                color: Theme.attention
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            // --- The draggable handle (a ball) -----------------------------------------
            // x = (value/maxValue) × (rail width − ball width) parks the ball so
            // its CENTER reaches value% of the way along the rail — without ever
            // falling off. maxValue lets a slider go past 1.0 (e.g. volume boost).
            Rectangle {
                id: handle
                width: 16
                height: 16
                radius: height / 2
                color: Theme.attention
                anchors.verticalCenter: parent.verticalCenter
                x: ((root.maxValue > 0 ? root.effectiveValue / root.maxValue : 0)) * Math.max(0, rail.width - width)
            }

            // --- Optional value text (right-aligned in the track) -----------------------
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.displayText !== ""
                text: root.displayText
                font.family: Theme.fontText
                font.pixelSize: 10
                font.bold: true
                color: Theme.ink
            }

            // --- Interaction: press anywhere, drag anywhere ------------------------------
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                // Convert a mouse X to a value in the 0.0–maxValue range.
                //   clampedX = mouse.x clamped between 0 and rail.width
                //   newVal   = (clampedX / rail.width) × maxValue
                function updateVal(mouse) {
                    let clampedX = Math.max(0, Math.min(rail.width, mouse.x))
                    let newVal = rail.width > 0 ? (clampedX / rail.width) * root.maxValue : 0
                    root.dragValue = newVal
                    root.valueChangedByUser(newVal)   // notify listeners without breaking property binding
                }

                onPressed: mouse => {
                    root.isDragging = true
                    updateVal(mouse)
                }
                onPositionChanged: mouse => {
                    if (pressed) updateVal(mouse)
                }
                onReleased: root.isDragging = false
                onCanceled: root.isDragging = false
                onWheel: wheel => {                               // scroll to adjust
                    let step = root.maxValue * 0.05               // 5% of the range
                    let delta = wheel.angleDelta.y > 0 ? step : -step
                    let newVal = Math.max(0, Math.min(root.maxValue, root.value + delta))
                    root.valueChangedByUser(newVal)
                }
            }
        }
    }
}