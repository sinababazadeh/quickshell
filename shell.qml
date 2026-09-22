// =============================================================================
//  SHELL.QML — the ENTRY POINT of the whole config
// =============================================================================
//  Quickshell looks for a file named `shell.qml` in the config directory and
//  runs it. Think of this as `main()` — everything else in this folder is a
//  reusable piece that this file assembles.
//
//  WHAT'S IN IT
//  ------------
//  • The Hub — a clock pill that expands into a floating window. It manages
//    calendar/weather, quick settings (audio, brightness, Wi-Fi, Bluetooth),
//    and theme/wallpapers (Hub.qml).
//  • A `Variants` loop that spawns ONE top bar per physical monitor.
//
//  THE BAR LAYOUT (three "islands", see ├─ graphics below)
//  -------------------------------------------------------
//     ┌──────────────┬──────────────────────┬────────────────────────────────┐
//     │ left island  │       center         │          right island          │
//     │ workspaces   │  hub (clock)         │  volume  dictation  ⚙ settings │
//     └──────────────┴──────────────────────┴────────────────────────────────┘
// =============================================================================
import Quickshell
import QtQuick
import QtQuick.Layouts

ShellRoot {
    // ─── THE WALLPAPER (one background surface per monitor) ─────────────────────
    // Quickshell draws the desktop wallpaper itself now (hyprpaper removed).
    // Wallpaper.qml is a background-layer surface; one per connected screen.
    // Which image is shown lives in the WallpaperState singleton, controlled
    // from the Hub's Theme tab.
    Variants {
        model: Quickshell.screens
        Wallpaper {}
    }

    // ─── ONE BAR PER MONITOR ────────────────────────────────────────────────────
    // `Variants` is Quickshell's way of saying "run this block once per item in
    // `model`". Quickshell.screens is the list of connected displays, so this
    // block is instantiated once per screen. Inside a Variants block, `modelData`
    // is the current screen object.
    Variants {
        model: Quickshell.screens

        // A PanelWindow = a bar layer drawn directly on the monitor. It is NOT
        // a normal window: it ignores focus and sits on the desktop's panel
        // layer (i.e. underneath your normal windows, like a real taskbar).
        PanelWindow {
            id: bar

            // `screen` tells this bar WHICH monitor it belongs to.
            property var modelData
            screen: modelData

            // Pin the window to the top edge and stretch it full width.
            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.barHeight
            color: Theme.barBg

            // ================================ LEFT ISLAND =========================
            RowLayout {
                anchors {
                    left: parent.left
                    leftMargin: 12      // breathing room from the screen edge
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8              // gap between the widgets in this island

                // Workspace pips + hyprexpo overview button.
                Workspaces {}
            }

            // ================================ CENTER ISLAND ======================
            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                // The Hub: it looks like the clock pill, but clicking it expands
                // it into its own floating window (see Hub.qml). This is the
                // single widget that will manage all of our windows going forward.
                Hub {
                    id: hub
                    screen: modelData   // popup rises on this bar's monitor
                }
            }

            // ================================ RIGHT ISLAND =======================
            RowLayout {
                anchors {
                    right: parent.right
                    rightMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                // Volume control pill (click = mute, wheel = level).
                Volume {}
                // Dictation / speech-to-text toggle.
                Dictation {}

                // Quick-Settings dropdown toggle button (toggles Hub to Settings tab)
                Pill {
                    icon: "tune"
                    label: ""
                    onClicked: hub.toggleTab("settings")
                }
            }
        }
    }
}