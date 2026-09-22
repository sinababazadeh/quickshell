// =============================================================================
//  ACTIONPILL.QML — Pill variant that stretches to fill its available width
// =============================================================================
//  SAME family as Pill.qml (icon | label, two flat edges meeting at a seam),
//  THREE differences:
//    1. It FILLS the width it is given (loaded inside layouts it expands).
//    2. Only its icon segment + label segment exist — no maxLabelWidth cap.
//    3. Default height is 34 (slightly taller than Pill's 30).
//  Used for the Lock / Sleep / Power buttons in the Quick Settings dropdown.
// =============================================================================
import QtQuick

Rectangle {
    id: root

    // --- Public properties -----------------------------------------------------
    property string icon: ""                     // Material glyph, e.g. "lock"
    property string label: ""                    // text on the right segment
    property color iconBg: Theme.plum            // LEFT segment color (icon)
    property color labelBg: Theme.primary        // RIGHT segment color (label)
    property color fgColor: Theme.ink            // color of icon AND label text

    signal clicked()

    implicitHeight: 34
    color: "transparent"
    radius: 0

    // --- LEFT ZONE: icon ---------------------------------------------------------
    Rectangle {
        id: iconSeg
        width: iconTxt.width + 12                // glyph width + horizontal pad
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.iconBg

        topLeftRadius: height / 2                // left cap
        bottomLeftRadius: height / 2
        topRightRadius: 0                        // flat edge meets label segment
        bottomRightRadius: 0

        Text {
            id: iconTxt
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.fontIcons
            font.pixelSize: 16
            color: root.fgColor
            leftPadding: 3
        }
    }

    // --- RIGHT ZONE: label (fills all remaining width) ----------------------------
    Rectangle {
        id: labelSeg
        anchors.left: iconSeg.right
        anchors.right: parent.right              // stretch to the root's right edge
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter
        color: root.labelBg

        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: height / 2               // right cap
        bottomRightRadius: height / 2

        Text {
            anchors.centerIn: parent
            text: root.label
            font.family: Theme.fontText
            font.pixelSize: 13
            font.bold: true
            color: root.fgColor
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}