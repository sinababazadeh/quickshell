// =============================================================================
//  CALENDARGRID.QML — a month calendar (reused by the Hub's calendar tab)
// =============================================================================
//  A compact month view with:
//    • month header + ‹ › navigation (`monthOffset` cursor, 0 = current month)
//    • Sunday–Saturday weekday labels
//    • a full 6×7 day grid, today highlighted in Theme.attention,
//      out-of-month days shown dimmed
//  It is a pure display component: the Hub just drops a `CalendarGrid {}`
//  into its layout and the component is self-contained.
// =============================================================================
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    color: "transparent"

    // 0 = this month, -1/+1 = previous/next month.
    property int monthOffset: 0

    // The first day of the displayed month (a JS Date).
    readonly property date monthStart: {
        let now = new Date()
        return new Date(now.getFullYear(), now.getMonth() + root.monthOffset, 1)
    }

    readonly property int daysInMonth: new Date(root.monthStart.getFullYear(), root.monthStart.getMonth() + 1, 0).getDate()
    readonly property int daysPrevMonth: new Date(root.monthStart.getFullYear(), root.monthStart.getMonth(), 0).getDate()
    readonly property int leadBlanks: new Date(root.monthStart.getFullYear(), root.monthStart.getMonth(), 1).getDay()  // 0 = Sunday

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // ─── Month header + navigation ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: Qt.formatDate(root.monthStart, "MMMM yyyy")
                font.family: Theme.fontText
                font.pixelSize: 13
                font.bold: true
                color: Theme.qsText
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Previous month
            Rectangle {
                width: 22
                height: 22
                radius: 11
                color: Theme.qsBgAlt

                Text {
                    anchors.centerIn: parent
                    text: "chevron_left"
                    font.family: Theme.fontIcons
                    font.pixelSize: 14
                    color: Theme.qsText
                    leftPadding: 1
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.monthOffset--
                }
            }

            // Next month
            Rectangle {
                width: 22
                height: 22
                radius: 11
                color: Theme.qsBgAlt

                Text {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    font.family: Theme.fontIcons
                    font.pixelSize: 14
                    color: Theme.qsText
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.monthOffset++
                }
            }
        }

        // ─── Weekday labels ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

                delegate: Text {
                    text: modelData
                    font.family: Theme.fontText
                    font.pixelSize: 10
                    font.bold: true
                    color: Theme.qsTextMuted
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ─── The day grid ───────────────────────────────────────────────────────
        Grid {
            id: dayGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7

            Repeater {
                model: 42   // (6 weeks × 7 days) always covers any month

                // 42 cells; `index` is the 0-based cell position.
                delegate: Rectangle {
                    id: cell

                    required property int index

                    readonly property int day: index - root.leadBlanks + 1
                    readonly property bool inMonth: day >= 1 && day <= root.daysInMonth
                    readonly property bool isToday: root.monthOffset === 0 && day === new Date().getDate()
                    // Number shown: dimmed previous/next-month days instead of blanks.
                    readonly property int shown: cell.day < 1 ? root.daysPrevMonth + cell.day
                                                    : (cell.day > root.daysInMonth ? cell.day - root.daysInMonth : cell.day)

                    width: dayGrid.width / 7
                    height: dayGrid.height / 6
                    color: isToday ? Theme.attention : "transparent"
                    radius: height / 2

                    Text {
                        anchors.centerIn: parent
                        text: cell.shown
                        font.family: Theme.fontText
                        font.pixelSize: 12
                        font.bold: cell.isToday
                        color: cell.isToday ? Theme.qsOnAccent
                              : (cell.inMonth ? Theme.qsText : Theme.qsTextMuted)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: cell.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }
    }
}