// =============================================================================
//  PILL.QML — the basic two-tone "capsule" widget (icon | label)
// =============================================================================
//  THE PILL SHAPE (understand this and you understand the whole config)
//  -------------------------------------------------------------------
//  A pill is TWO rectangles side by side:
//
//     [  ( icon )  |  ( label )  ]
//      └──────────┴──────────┘
//      left segment  |  right segment
//      (plum color)  |  (primary color)
//
//  Each rectangle rounds the corner on the OUTER edge and keeps the inner
//  edge FLAT, so the two segments meet along a straight seam. That gives the
//  "capsule split in two colors" look used everywhere.
//
//  WHY NOT ONE RECTANGLE WITH TWO COLORS?
//  QML rectangles have only a single color, so we cheat with two rectangles.
//
//  COMPONENT CONTRACT (what the rest of the config expects)
//  -------------------------------------------------------
//  By declaring `property string icon` + `signal clicked()` etc., any file
//  can instantiate a Pill and pass values:
//      Pill { icon: "tune"; label: ""; onClicked: ... }
//  The properties below ARE the public API of this component.
// =============================================================================
import QtQuick

Rectangle {
    id: root

    // --- Public properties (set these when using Pill { ... }) ---------------
    property string icon: ""           // Material Symbols glyph name, e.g. "tune"
    property string label: ""          // plain text; "" hides the label segment
    property color iconColor: Theme.ink      // color of the icon glyph
    property color textColor: Theme.ink      // color of the label text
    property color bgColor: Theme.plum       // LEFT segment color (icon side)
    property color labelBg: Theme.primary    // RIGHT segment color (label side)
    property int maxLabelWidth: 400          // labels longer than this get ...
    property real contentOpacity: 1.0        // opacity of rendered segments (for seamless transitions)

    // --- Signals (the component's "events") -----------------------------------
    // Other files write `onClicked: ...` to run code when the pill is pressed.
    signal clicked()

    // --- Derived conveniences (readonly = computed, not settable) -------------
    readonly property bool hasIcon:  root.icon !== ""   // true → draw icon segment
    readonly property bool hasLabel: root.label !== ""  // true → draw label segment
    readonly property real iconSegWidth: iconSeg.width
    readonly property real textSegWidth: textSeg.width

    // --- The Rectangle's own geometry ------------------------------------------
    implicitWidth: iconSeg.width + (root.hasLabel ? Math.min(root.maxLabelWidth, labelTxt.implicitWidth + 16) : 0)
    implicitHeight: Theme.pillHeight              // height comes from the theme
    radius: 0
    color: "transparent"  // the root itself paints nothing; children do

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    // --- LEFT ZONE: icon segment ------------------------------------------------
    // A colored rectangle holding the icon glyph or image. The LEFT corners are rounded
    // (a full half-circle cap); the RIGHT edge is flat so it butts cleanly
    // against the label segment. If there is no label, both sides round off
    // (so the icon segment becomes a complete capsule on its own).
    Rectangle {
        id: iconSeg
        visible: root.hasIcon
        opacity: root.contentOpacity
        width: visible ? Math.max(28, (isPathIcon ? 28 : iconTxt.width + 14)) : 0
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.bgColor

        readonly property bool isPathIcon: root.icon.startsWith("/") || root.icon.startsWith("file:")

        topLeftRadius: height / 2     // left cap (half-circle)
        bottomLeftRadius: height / 2
        topRightRadius: root.hasLabel ? 0 : height / 2  // flat when a label exists
        bottomRightRadius: root.hasLabel ? 0 : height / 2

        Image {
            anchors.centerIn: parent
            visible: root.hasIcon && iconSeg.isPathIcon
            source: iconSeg.isPathIcon ? root.icon : ""
            width: 16
            height: 16
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Text {
            id: iconTxt
            anchors.centerIn: parent
            visible: root.hasIcon && !iconSeg.isPathIcon
            text: root.icon
            color: root.iconColor
            font.family: Theme.fontIcons  // the Material icon glyph font
            font.pixelSize: 17
            leftPadding: root.hasLabel ? 4 : 0  // nudge glyph away from the seam
        }
    }

    // --- RIGHT ZONE: label segment -------------------------------------------------
    // Mirror of the icon segment: RIGHT corners capped, LEFT edge flat against
    // the icon segment. The text elides (turns into "...") past maxLabelWidth.
    Rectangle {
        id: textSeg
        visible: root.hasLabel
        opacity: root.contentOpacity
        height: parent.height
        anchors.left: iconSeg.right     // start exactly where the icon ends
        anchors.right: parent.right     // stretch with pill width
        anchors.verticalCenter: parent.verticalCenter
        color: root.labelBg
        clip: true

        topLeftRadius: root.hasIcon ? 0 : height / 2
        bottomLeftRadius: root.hasIcon ? 0 : height / 2
        topRightRadius: height / 2      // right cap
        bottomRightRadius: height / 2

        Text {
            id: labelTxt
            anchors.centerIn: parent
            visible: root.hasLabel
            text: root.label
            color: root.textColor
            font.family: Theme.fontText
            font.pixelSize: 14
            elide: Text.ElideRight                 // "…" if too long
            width: Math.min(implicitWidth, Math.max(0, parent.width - 12))
        }
    }

    // --- Interaction ---------------------------------------------------------------
    // A MouseArea is an invisible layer that reports presses. `anchors.fill`
    // makes it cover the whole pill. onClicked re-emits the component's own
    // `clicked` signal, so users of Pill can write `onClicked:`.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor  // show a hand cursor on hover
        onClicked: root.clicked()
    }
}