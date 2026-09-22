// =============================================================================
//  WALLPAPERSTATE.QML — global wallpaper state (a singleton, like Theme.qml)
// =============================================================================
//  WHAT THIS IS
//  ------------
//  The single source of truth for "which wallpaper is on screen". It is a
//  SINGLETON (pragma Singleton + a `singleton` line in qmldir), so both the
//  renderer surfaces (Wallpaper.qml) and the Hub's theme tab (the picker)
//  talk to this one object instead of to each other.
//
//  PERSISTENCE
//  -----------
//  The chosen path is stored in  ~/.config/quickshell/.wallpaper-state  as a
//  single line of plain text. On startup we read it back (validated to still
//  exist on disk); on every change we rewrite it, so your pick survives
//  reboots — the renderer just follows `current` wherever it comes from.
// =============================================================================

pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root

    // The active wallpaper (absolute path). Dynamically resolves from $HOME;
    // replaced by the saved pick as soon as startup finishes.
    property string current: (Quickshell.env("HOME") ? Quickshell.env("HOME") + "/.config/quickshell/wallpapers/wallpaper3.jpg" : "")

    // Where the pick is persisted between sessions (relative to $HOME).
    readonly property string stateFile: ".config/quickshell/.wallpaper-state"

    // ─── Startup: restore the last pick ─────────────────────────────────────────
    // `cat || true`  → empty output instead of an error when no state file yet.
    // The `-f` test  → ignores a saved pick whose image was deleted afterwards.
    Process {
        id: stateReader
        running: true
        command: ["bash", "-c",
                  "p=$(cat \"$HOME/" + root.stateFile + "\" 2>/dev/null); "
                  + "[ -n \"$p\" ] && [ -f \"$p\" ] && echo \"$p\""]

        stdout: StdioCollector {
            id: stateCollector
            waitForEnd: true
            onDataChanged: {
                let p = stateCollector.text.trim()
                if (p !== "") {
                    let home = Quickshell.env("HOME") || ""
                    if (home && p.startsWith("/home/")) {
                        p = p.replace(/^\/home\/[^\/]+\/\.config\/quickshell/, home + "/.config/quickshell")
                    }
                    root.current = p
                }
            }
        }
    }

    Timer {
        id: saveWpDebounce
        interval: 200
        repeat: false
        property string pendingPath: ""
        onTriggered: {
            let safe = pendingPath.replace(/'/g, "'\\''")
            Quickshell.execDetached(["bash", "-c",
                                     "printf '%s' '" + safe + "' > \"$HOME/" + root.stateFile + "\""])
        }
    }

    // ─── Switch wallpaper (called by the Hub's picker) ──────────────────────────
    // Renderer surfaces react to `current` automatically; we just persist here.
    function setWallpaper(path) {
        if (path === root.current) return
        root.current = path
        saveWpDebounce.pendingPath = path
        saveWpDebounce.restart()
    }
}