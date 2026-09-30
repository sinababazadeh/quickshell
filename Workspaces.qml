// =============================================================================
//  WORKSPACES.QML — workspace pips + overview button (Hyprland Lua compatible)
// =============================================================================
//  Layout (the same two-segment capsule used all over this config):
//     [ (grid icon) | 1 ▮ 2 ▮ 3 ▮ 4 ▮ 5 ]
//        plum       |      primary
//
//  WHAT'S A WORKSPACE PIP?
//  ------------------------
//  Hyprland gives every monitor a numbered set of workspaces (virtual
//  desktops). This widget shows one small capsule per workspace in the
//  segment. Number sits on a plum square; the colored bar behind it is the
//  workspace STATE:
//     • focused   → Theme.wsActive   (accent, the one you're on)
//     • occupied  → Theme.wsOccupied (indigo, has windows open)
//     • empty     → Theme.wsEmpty    (dark, nothing open)
//  Clicking a pip tells Hyprland to switch to that workspace.
// =============================================================================
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    implicitHeight: Theme.pillHeight
    implicitWidth: iconSeg.width + pipsSeg.width   // both halves of the capsule
    radius: height / 2
    color: "transparent"

    // Helper: switch to workspace using Hyprland Lua syntax + standard fallbacks
    function switchToWorkspace(ws) {
        let wsStr = ws.toString()
        // 1. Hyprland Lua dispatcher syntax (v0.55+):
        Hyprland.dispatch("hl.dsp.focus({ workspace = '" + wsStr + "' })")
        // 2. Standard single-string dispatcher format ("workspace <id>"):
        Hyprland.dispatch("workspace " + wsStr)
        // 3. Direct hyprctl CLI IPC to guarantee execution:
        Quickshell.execDetached(["hyprctl", "dispatch", "workspace", wsStr])
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = '" + wsStr + "' })"])
    }

    // --- LEFT ZONE: overview trigger icon (the grid_view button) -----------------
    // Opens the interactive workspace overview layout.
    Rectangle {
        id: iconSeg
        width: iconTxt.width + 14
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: WorkspaceOverviewState.active ? Theme.attention
             : (iconMouse.containsMouse ? Theme.attention : Theme.plum)

        topLeftRadius: height / 2
        bottomLeftRadius: height / 2
        topRightRadius: 0
        bottomRightRadius: 0

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Text {
            id: iconTxt
            anchors.centerIn: parent
            text: "grid_view"
            font.family: Theme.fontIcons
            font.pixelSize: 16
            color: WorkspaceOverviewState.active ? Theme.qsOnAccent : Theme.ink
            leftPadding: 4
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                WorkspaceOverviewState.toggle()
            }
        }
    }

    // --- RIGHT ZONE: the workspace pips (one capsule per workspace) ---------------
    Rectangle {
        id: pipsSeg
        implicitWidth: 246
        height: parent.height
        anchors.left: iconSeg.right
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.primary

        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: height / 2
        bottomRightRadius: height / 2

        // Mouse wheel over workspace row to scroll next/prev workspace
        MouseArea {
            anchors.fill: parent
            z: 0
            onWheel: wheel => {
                let target = wheel.angleDelta.y > 0 ? "e-1" : "e+1"
                root.switchToWorkspace(target)
            }
        }

        RowLayout {
            id: contentRow
            anchors.left: parent.left  // start at the left edge of the segment
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4                // gap between neighboring pips
            z: 1

            // One pip per workspace: model 5 → workspaces 1–5.
            Repeater {
                model: 5

                // ─── ONE WORKSPACE PIP ─────────────────────────────────────────
                Rectangle {
                    id: wsPill

                    property int wsId: index + 1

                    // Live state (checks id and name compatibility)
                    property bool isFocused: Hyprland.focusedWorkspace
                                              && (Hyprland.focusedWorkspace.id === wsId
                                                  || Hyprland.focusedWorkspace.name === wsId.toString())
                    property bool exists: Hyprland.workspaces
                                          && Hyprland.workspaces.values.some(w => w.id === wsPill.wsId || w.name === wsPill.wsId.toString())

                    Layout.leftMargin: 7
                    implicitWidth: innerIconSeg.width + innerTextSeg.width
                    implicitHeight: 18
                    radius: height / 2
                    Layout.alignment: Qt.AlignVCenter
                    color: Theme.border

                    // ── Left half: the workspace NUMBER on a plum square ──────
                    Rectangle {
                        id: innerIconSeg
                        width: 20
                        height: parent.height
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.plum

                        topLeftRadius: height / 2
                        bottomLeftRadius: height / 2
                        topRightRadius: 0
                        bottomRightRadius: 0

                        Text {
                            id: pipNumber
                            anchors.centerIn: parent
                            text: index + 1
                            color: Theme.ink
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            leftPadding: 1
                        }
                    }

                    // ── Right half: the STATE-colored bar ──────────────────────
                    Rectangle {
                        id: innerTextSeg
                        width: 18
                        height: parent.height
                        anchors.left: innerIconSeg.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: isFocused ? Theme.wsActive
                               : (exists ? Theme.wsOccupied : Theme.wsEmpty)

                        topLeftRadius: 0
                        bottomLeftRadius: 0
                        topRightRadius: height / 2
                        bottomRightRadius: height / 2
                    }

                    // ── Click to switch Hyprland to this workspace ────────────
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.switchToWorkspace(wsPill.wsId)
                    }
                }
            }
        }
    }
}
