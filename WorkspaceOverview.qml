// =============================================================================
//  WORKSPACEOVERVIEW.QML — Interactive Exposé / Mission Control Workspace Overview
// =============================================================================
//  When triggered from the Workstation pill icon or Hyprland keybind:
//  • Current workspace smoothly shrinks down into a layout alongside all other
//    occupied workspaces across all connected monitors.
//  • Occupied workspaces only (empty workspaces are filtered out).
//  • Multi-monitor support: displays workspaces from both monitors and switches
//    focus cleanly to the appropriate monitor when selected.
//  • Arrow keys to navigate, Enter to switch, Esc to cancel.
//  • Direct click to switch.
// =============================================================================
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    visible: WorkspaceOverviewState.active
    color: "transparent"

    onVisibleChanged: {
        if (visible) {
            keyHandler.forceActiveFocus()
        }
    }

    // ─── Keyboard Focus & Shortcut Controller ────────────────────────────────────
    FocusScope {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                WorkspaceOverviewState.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                WorkspaceOverviewState.selectPrev()
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                WorkspaceOverviewState.selectNext()
                event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                WorkspaceOverviewState.selectPrevRow()
                event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                WorkspaceOverviewState.selectNextRow()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                WorkspaceOverviewState.activateSelected()
                event.accepted = true
            }
        }
    }

    // ─── Dark Frosted Backdrop (Click outside to cancel) ─────────────────────────
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.02, 0.08, 0.88)
        opacity: WorkspaceOverviewState.active ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: WorkspaceOverviewState.close()
        }
    }

    // ─── Main Shrinking Overview Canvas ──────────────────────────────────────────
    Item {
        id: galleryContainer
        anchors.fill: parent
        anchors.margins: 40

        scale: WorkspaceOverviewState.active ? 1.0 : 1.10
        opacity: WorkspaceOverviewState.active ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 20, 1140)
            spacing: 24

            // ─── 1. TOP HEADER / INSTRUCTION BAR ─────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Header Pill
                Rectangle {
                    implicitHeight: 34
                    implicitWidth: headerRow.implicitWidth + 24
                    radius: 17
                    color: Theme.cardBg
                    border.width: 1
                    border.color: Theme.pillBorder

                    RowLayout {
                        id: headerRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "grid_view"
                            font.family: Theme.fontIcons
                            font.pixelSize: 16
                            color: Theme.attention
                        }

                        Text {
                            text: "WORKSPACES OVERVIEW"
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            font.bold: true
                            color: Theme.ink
                        }
                    }
                }

                // Keyboard Hints Tag
                Rectangle {
                    implicitHeight: 28
                    implicitWidth: hintsRow.implicitWidth + 20
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.06)

                    RowLayout {
                        id: hintsRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "← / → Arrow keys"
                            font.family: Theme.fontText
                            font.pixelSize: 11
                            color: Theme.lavender
                        }

                        Text {
                            text: "•"
                            color: Qt.rgba(1, 1, 1, 0.25)
                        }

                        Text {
                            text: "Enter to switch"
                            font.family: Theme.fontText
                            font.pixelSize: 11
                            color: Theme.attention
                        }

                        Text {
                            text: "•"
                            color: Qt.rgba(1, 1, 1, 0.25)
                        }

                        Text {
                            text: "Esc to cancel"
                            font.family: Theme.fontText
                            font.pixelSize: 11
                            color: Theme.qsTextMuted
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Workspace count pill
                Rectangle {
                    implicitHeight: 28
                    implicitWidth: wsCountTxt.implicitWidth + 20
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.06)

                    Text {
                        id: wsCountTxt
                        anchors.centerIn: parent
                        text: WorkspaceOverviewState.workspaces.length + " Occupied Workspaces"
                        font.family: Theme.fontText
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.lavender
                    }
                }

                // Close Button (X)
                Rectangle {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 16
                    color: closeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: Theme.fontIcons
                        font.pixelSize: 16
                        color: Theme.ink
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WorkspaceOverviewState.close()
                    }
                }
            }

            // ─── 2. WORKSPACES GALLERY GRID ──────────────────────────────────────
            Flow {
                Layout.fillWidth: true
                spacing: 20
                Layout.alignment: Qt.AlignHCenter

                Repeater {
                    model: WorkspaceOverviewState.workspaces

                    // ─── INDIVIDUAL WORKSPACE PREVIEW CARD ───────────────────────
                    Rectangle {
                        id: wsCard
                        readonly property var wsData: modelData
                        readonly property bool isSelected: WorkspaceOverviewState.selectedIndex === index
                        readonly property bool isCurrentActive: wsData.id === WorkspaceOverviewState.activeWorkspaceId

                        width: 340
                        height: 215
                        radius: 16
                        color: isSelected ? Theme.cardBgAlt : Theme.cardBg

                        border.width: isSelected ? 2.5 : 1
                        border.color: isSelected ? Theme.attention
                                    : (cardMouse.containsMouse ? Theme.lavender : Theme.pillBorder)

                        scale: isSelected ? 1.04 : (cardMouse.containsMouse ? 1.02 : 1.0)

                        Behavior on scale {
                            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            // ─── Card Header: Workspace Badge + Monitor & Active State ───
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Workspace Capsule Pill
                                Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: wsNumPill.width + wsNamePill.width
                                    radius: 12
                                    color: "transparent"

                                    Rectangle {
                                        id: wsNumPill
                                        width: 26
                                        height: parent.height
                                        color: wsCard.isCurrentActive ? Theme.attention : Theme.plum
                                        topLeftRadius: 12
                                        bottomLeftRadius: 12
                                        topRightRadius: 0
                                        bottomRightRadius: 0

                                        Text {
                                            anchors.centerIn: parent
                                            text: wsData.name || wsData.id
                                            font.family: Theme.fontText
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: wsCard.isCurrentActive ? Theme.qsOnAccent : Theme.ink
                                        }
                                    }

                                    Rectangle {
                                        id: wsNamePill
                                        width: 80
                                        height: parent.height
                                        anchors.left: wsNumPill.right
                                        color: Theme.primary
                                        topLeftRadius: 0
                                        bottomLeftRadius: 0
                                        topRightRadius: 12
                                        bottomRightRadius: 12

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Workspace " + (wsData.name || wsData.id)
                                            font.family: Theme.fontText
                                            font.pixelSize: 11
                                            color: Theme.ink
                                        }
                                    }
                                }

                                // Monitor Badge
                                Rectangle {
                                    visible: wsData.monitor !== ""
                                    implicitHeight: 20
                                    implicitWidth: monTxt.implicitWidth + 12
                                    radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.08)

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 3

                                        Text {
                                            text: "desktop_windows"
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 11
                                            color: Theme.lavender
                                        }

                                        Text {
                                            id: monTxt
                                            text: wsData.monitor
                                            font.family: Theme.fontText
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: Theme.lavender
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Active indicator badge
                                Rectangle {
                                    visible: wsCard.isCurrentActive
                                    implicitHeight: 20
                                    implicitWidth: activeTxt.implicitWidth + 12
                                    radius: 10
                                    color: Theme.attention

                                    Text {
                                        id: activeTxt
                                        anchors.centerIn: parent
                                        text: "CURRENT"
                                        font.family: Theme.fontText
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: Theme.qsOnAccent
                                    }
                                }

                                // Windows count tag
                                Text {
                                    text: wsData.windowsCount + (wsData.windowsCount === 1 ? " win" : " wins")
                                    font.family: Theme.fontText
                                    font.pixelSize: 11
                                    color: Theme.qsTextMuted
                                }
                            }

                            // ─── Card Body: Miniature Desktop Layout Canvas ───────────
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 10
                                color: Qt.rgba(0.04, 0.02, 0.12, 0.65)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)
                                clip: true

                                // Miniature Window Grid (representing open windows)
                                Flow {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    Repeater {
                                        model: (wsData.clients && wsData.clients.length > 0) ? wsData.clients.slice(0, 4) : wsData.windowsCount

                                        Rectangle {
                                            readonly property var clientData: (typeof modelData === "object") ? modelData : null
                                            readonly property string appClass: clientData ? (clientData.class || clientData.initialClass || "") : "app"
                                            readonly property string winTitle: clientData ? (clientData.title || appClass) : "Window"

                                            width: (parent.width - 6) / 2
                                            height: (parent.height - 6) / 2
                                            radius: 6
                                            color: Qt.rgba(1, 1, 1, 0.08)
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.12)

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                spacing: 2

                                                // Window mini titlebar with 3 dots
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    Rectangle { width: 5; height: 5; radius: 2.5; color: "#ff5f56" }
                                                    Rectangle { width: 5; height: 5; radius: 2.5; color: "#ffbd2e" }
                                                    Rectangle { width: 5; height: 5; radius: 2.5; color: "#27c93f" }

                                                    Item { Layout.fillWidth: true }

                                                    Text {
                                                        text: NotificationState.resolveIcon(appClass, appClass)
                                                        font.family: Theme.fontIcons
                                                        font.pixelSize: 11
                                                        color: Theme.lavender
                                                    }
                                                }

                                                // Mini title text
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: winTitle
                                                    font.family: Theme.fontText
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: Theme.ink
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }

                                                Item { Layout.fillHeight: true }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─── Card Footer: App Badges ──────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                clip: true

                                Repeater {
                                    model: {
                                        if (!wsData.clients) return []
                                        let seen = {}
                                        let list = []
                                        for (let i = 0; i < wsData.clients.length; i++) {
                                            let cls = wsData.clients[i].class || wsData.clients[i].initialClass || ""
                                            if (cls && !seen[cls]) {
                                                seen[cls] = true
                                                list.push(cls)
                                            }
                                        }
                                        return list.slice(0, 4)
                                    }

                                    Rectangle {
                                        implicitHeight: 18
                                        implicitWidth: tagRow.implicitWidth + 8
                                        radius: 9
                                        color: Qt.rgba(1, 1, 1, 0.08)

                                        RowLayout {
                                            id: tagRow
                                            anchors.centerIn: parent
                                            spacing: 3

                                            Text {
                                                text: NotificationState.resolveIcon(modelData, modelData)
                                                font.family: Theme.fontIcons
                                                font.pixelSize: 10
                                                color: Theme.attention
                                            }

                                            Text {
                                                text: modelData
                                                font.family: Theme.fontText
                                                font.pixelSize: 9
                                                color: Theme.ink
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }

                        // ─── Interactive Click / Hover Area ──────────────────────────
                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: WorkspaceOverviewState.selectedIndex = index
                            onClicked: WorkspaceOverviewState.switchToWorkspace(wsData.id, wsData.monitor)
                        }
                    }
                }
            }
        }
    }
}
