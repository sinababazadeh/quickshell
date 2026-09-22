// =============================================================================
//  QUICKTOGGLE.QML — big clickable "tile" for the Quick Settings dropdown
// =============================================================================
//  Layout (same two-segment trick as Pill, but bigger):
//     [ (icon) | title / status       (chevron) ]
//     └───────┴─────────────────────────────────┘
//     plum      primary           small circle
//     (or accent when active)
//
//  TWO ways to interact:
//    • Click the icon segment OR the body → `toggled()` (switch the setting)
//    • Click the chevron circle      → `openDetails()` (open a sub-view)
//
//  The `active` property drives both the icon-segment color and the status
//  text color, so flipping `active` visually turns the tile on or off.
// =============================================================================
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Public properties ----------------------------------------------------
    property string icon: "wifi"       // Material glyph name
    property string title: "Wi-Fi"     // big bold line
    property string status: "Connected"// small line under the title
    property bool active: true         // on/off state (drives colors)

    // --- Signals: the two interaction outcomes ---------------------------------
    signal toggled()
    signal openDetails()

    implicitHeight: 60
    Layout.fillWidth: true  // spread across the layout column the tile lives in
    radius: 0
    color: "transparent"

    // --- LEFT ZONE: icon segment ------------------------------------------------
    // Color follows `active`: accent (highlight) when on, plum when off.
    Rectangle {
        id: iconSeg
        width: iconTxt.width + 20
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.active ? Theme.attention : Theme.plum

        topLeftRadius: height / 2
        bottomLeftRadius: height / 2
        topRightRadius: 0
        bottomRightRadius: 0

        Text {
            id: iconTxt
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.fontIcons
            font.pixelSize: 20
            color: Theme.ink
            leftPadding: 4
        }

        // Clicking the icon toggles the setting directly.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    // --- RIGHT ZONE: content segment (title / status + chevron) ------------------
    Rectangle {
        id: contentSeg
        anchors.left: iconSeg.right
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
            anchors.rightMargin: 46  // keep clear of the chevron button
            spacing: 8

            ColumnLayout {
                spacing: 1
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true

                // Title line
                Text {
                    text: root.title
                    font.family: Theme.fontText
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.ink
                }

                // Status line (dims when the tile is off)
                Text {
                    text: root.status
                    font.family: Theme.fontText
                    font.pixelSize: 10
                    color: root.active ? Theme.ink : Theme.qsTextMuted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // Whole-body tap zone (under the chevron) → toggles the setting.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }

        // --- Chevron "details" button ---------------------------------------------
        // A small circle in the corner. Clicking it emits `openDetails`
        // (the QuickSettings handling navigates to the wifi/bluetooth view).
        Rectangle {
            width: 28
            height: 28
            radius: height / 2
            color: Theme.qsBg
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 10

            Text {
                anchors.centerIn: parent
                text: "chevron_right"
                font.family: Theme.fontIcons
                font.pixelSize: 16
                color: Theme.cream
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openDetails()
            }
        }
    }
}