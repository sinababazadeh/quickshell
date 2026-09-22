// =============================================================================
//  WORKSPACES.QML — workspace pips + overview button (Hyprland)
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
//
//  REPEATER / index (a QML superpower, used a lot in this config)
//  -------------------------------------------------------------
//  `Repeater { model: 5 }` creates the child element 5 times, once per model
//  entry. Inside each copy, `index` is the copy number (0‑based for the data,
//  so workspace number = index + 1). Whatever element sits inside the Repeater
//  gets instantiated repeatedly with the `index` value of that copy.
//  #CHANGE-ME: set `model` to your number of workspaces.
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

    // --- LEFT ZONE: overview trigger icon (the grid_view button) -----------------
    // Opens the Hyprland "expo" overview (hyprexpo plugin). Click = dispatch an
    // IPC command to the running Hyprland instance through `Hyprland.dispatch`.
    Rectangle {
        id: iconSeg
        width: iconTxt.width + 14
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.plum

        topLeftRadius: height / 2
        bottomLeftRadius: height / 2
        topRightRadius: 0
        bottomRightRadius: 0

        Text {
            id: iconTxt
            anchors.centerIn: parent
            text: "grid_view"
            font.family: Theme.fontIcons
            font.pixelSize: 16
            color: Theme.ink
            leftPadding: 4
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Hyprland.dispatch('hl.plugin.hyprexpo.expo')
        }
    }

    // --- RIGHT ZONE: the workspace pips (one capsule per workspace) ---------------
    Rectangle {
        id: pipsSeg
        // Width sized so all 5 pips fit: (5 × 38px pip) + (5 × 7px margin)
        // + (4 × 4px spacing) ≈ 246. #CHANGE-ME: adjust if you change `model`.
        implicitWidth: 246
        height: parent.height
        anchors.left: iconSeg.right
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.primary

        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: height / 2
        bottomRightRadius: height / 2

        RowLayout {
            id: contentRow
            anchors.left: parent.left  // start at the left edge of the segment
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4                // gap between neighboring pips

            // One pip per workspace: model 5 → workspaces 1–5.
            Repeater {
                model: 5

                // ─── ONE WORKSPACE PIP ─────────────────────────────────────────
                Rectangle {
                    id: wsPill

                    // The workspace this copy represents (index is 0-based,
                    // workspaces are 1-based).
                    property int wsId: index + 1

                    // Live state, re-evaluated by the engine whenever Hyprland
                    // reports a change (focus switch, window open/close).
                    property bool isFocused: Hyprland.focusedWorkspace
                                              && Hyprland.focusedWorkspace.id === wsId
                    property bool exists: Hyprland.workspaces.values.some(w => w.id === wsPill.wsId)

                    Layout.leftMargin: 7
                    // Honest width: number segment + state segment must MATCH
                    // the child widths below (else pips overlap or leave gaps).
                    implicitWidth: innerIconSeg.width + innerTextSeg.width
                    implicitHeight: 18
                    radius: height / 2
                    Layout.alignment: Qt.AlignVCenter
                    color: Theme.border   // transparent root; children draw

                    // ── Left half: the workspace NUMBER on a plum square ──────
                    // ## FIXED (was a bug): the old code was
                    // `visible: root.hasIcon` — but this component's root has
                    // no `hasIcon` property, so it was always FALSE and the
                    // number NEVER displayed. Now the segment always shows.
                    Rectangle {
                        id: innerIconSeg
                        width: 20
                        height: parent.height
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.plum

                        topLeftRadius: height / 2   // left cap of the pip
                        bottomLeftRadius: height / 2
                        topRightRadius: 0           // flat at the seam
                        bottomRightRadius: 0

                        Text {
                            id: pipNumber
                            anchors.centerIn: parent
                            text: index + 1         // 1-based workspace number
                            color: Theme.ink
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            leftPadding: 1
                        }
                    }

                    // ── Right half: the STATE-colored bar ──────────────────────
                    // The color encodes the workspace state (see file header).
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
                        topRightRadius: height / 2   // right cap of the pip
                        bottomRightRadius: height / 2
                    }

                    // ── Click to switch Hyprland to this workspace ────────────
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsPill.wsId + " })")
                    }
                }
            }
        }
    }
}