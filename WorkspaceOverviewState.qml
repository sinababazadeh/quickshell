// =============================================================================
//  WORKSPACEOVERVIEWSTATE.QML — Singleton state manager for Workspace Overview
// =============================================================================
//  Provides:
//  • Real-time occupied workspaces across all physical monitors
//  • Keyboard navigation (arrow keys, Enter to select, Esc to cancel)
//  • FIFO IPC listener at /tmp/quickshell-overview.fifo for Hyprland keybinds
//  • Monitor-aware switching (focuses target monitor + brings up workspace)
// =============================================================================
pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

Item {
    id: root

    property bool active: false
    property var workspaces: []
    property int activeWorkspaceId: 1
    property int selectedIndex: 0
    property var monitors: []

    // ─── FIFO IPC Listener for Hyprland Keybind ──────────────────────────────────
    Process {
        id: fifoListener
        command: [
            "bash", "-c",
            "FIFO=/tmp/quickshell-overview.fifo; " +
            "rm -f \"$FIFO\" 2>/dev/null; mkfifo \"$FIFO\" 2>/dev/null; " +
            "while true; do " +
            "  if read -r line < \"$FIFO\"; then " +
            "    echo \"$line\"; " +
            "  fi; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: data => {
                let cmd = data.trim().toLowerCase()
                if (cmd === "open") {
                    root.open()
                } else if (cmd === "close") {
                    root.close()
                } else {
                    root.toggle()
                }
            }
        }
    }

    // ─── Fetch Detailed Workspaces + Windows from Hyprland ───────────────────────
    Process {
        id: fetchProc
        command: [
            "bash", "-c",
            "for p in \"$HOME/.config/quickshell/get-workspaces.py\" \"/app/applet/quickshell/get-workspaces.py\" \"$(pwd)/get-workspaces.py\"; do " +
            "  if [ -x \"$p\" ]; then " +
            "    python3 \"$p\" 2>/dev/null; " +
            "    exit 0; " +
            "  fi; " +
            "done; " +
            "python3 -c 'import json; print(json.dumps({\"workspaces\": [], \"monitors\": []}))'"
        ]
        stdout: StdioCollector {
            onTextFinished: {
                try {
                    let data = JSON.parse(text.trim())
                    let wsList = data.workspaces || []
                    if (wsList.length > 0) {
                        root.workspaces = wsList
                    }
                    if (data.activeWorkspaceId !== null && data.activeWorkspaceId !== undefined) {
                        root.activeWorkspaceId = data.activeWorkspaceId
                    }
                    root.monitors = data.monitors || []

                    // Match initial selectedIndex to current active workspace
                    for (let i = 0; i < root.workspaces.length; i++) {
                        if (root.workspaces[i].id === root.activeWorkspaceId) {
                            root.selectedIndex = i
                            break
                        }
                    }
                } catch (e) {
                    console.warn("[WorkspaceOverviewState] Error parsing JSON from get-workspaces.py:", e)
                }
            }
        }
    }

    // Live refresh timer while overview is open
    Timer {
        id: pollTimer
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: {
            if (!fetchProc.running) fetchProc.running = true
        }
    }

    function refreshFallbackWorkspaces() {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) return
        let list = []
        let actId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
        let vals = Hyprland.workspaces.values
        for (let i = 0; i < vals.length; i++) {
            let w = vals[i]
            if (!w) continue
            let winCount = (typeof w.windows === "number") ? w.windows : 1
            // ONLY occupied workspaces or currently focused workspace
            if (winCount > 0 || w.id === actId) {
                list.push({
                    id: w.id,
                    name: (w.name || w.id.toString()),
                    monitor: (w.monitor ? (w.monitor.name || w.monitor.toString()) : ""),
                    windowsCount: winCount,
                    isActive: (w.id === actId),
                    clients: []
                })
            }
        }
        list.sort((a, b) => a.id - b.id)
        if (list.length > 0) {
            root.workspaces = list
            for (let j = 0; j < list.length; j++) {
                if (list[j].id === actId) {
                    root.selectedIndex = j
                    break
                }
            }
        }
    }

    function open() {
        root.refreshFallbackWorkspaces()
        root.active = true
        if (!fetchProc.running) fetchProc.running = true
    }

    function close() {
        root.active = false
    }

    function toggle() {
        if (root.active) {
            root.close()
        } else {
            root.open()
        }
    }

    function selectNext() {
        if (root.workspaces.length <= 1) return
        root.selectedIndex = (root.selectedIndex + 1) % root.workspaces.length
    }

    function selectPrev() {
        if (root.workspaces.length <= 1) return
        root.selectedIndex = (root.selectedIndex - 1 + root.workspaces.length) % root.workspaces.length
    }

    function selectNextRow() {
        // Step forward by 3 or next element
        if (root.workspaces.length <= 1) return
        root.selectedIndex = Math.min(root.workspaces.length - 1, root.selectedIndex + 3)
    }

    function selectPrevRow() {
        // Step backward by 3 or previous element
        if (root.workspaces.length <= 1) return
        root.selectedIndex = Math.max(0, root.selectedIndex - 3)
    }

    function activateSelected() {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.workspaces.length) {
            let ws = root.workspaces[root.selectedIndex]
            root.switchToWorkspace(ws.id, ws.monitor)
        } else {
            root.close()
        }
    }

    function switchToWorkspace(wsId, monitorName) {
        root.close()

        let wsStr = wsId.toString()
        let monStr = (monitorName || "").toString().trim()

        // 1. If monitor is specified and we have multiple monitors, focus monitor first
        if (monStr !== "") {
            Quickshell.execDetached(["hyprctl", "dispatch", "focusmonitor", monStr])
        }

        // 2. Dispatch workspace switch via hyprctl CLI + safe Lua fallback
        Quickshell.execDetached(["hyprctl", "dispatch", "workspace", wsStr])
        try {
            Hyprland.dispatch("hl.dispatch('workspace', '" + wsStr + "')")
        } catch (e) {}
    }
}
