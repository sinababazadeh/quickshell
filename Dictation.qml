// =============================================================================
//  DICTATION.QML — speech-to-text record pill (hyprwhspr)
// =============================================================================
//  The smallest widget in the bar. It is just a Pill with a mic glyph and a
//  click action. The real logic lives in the `hyprwhspr` program.
//
//  execDetached vs exec:
//    • execDetached()  → fire-and-forget, shell never waits (used everywhere
//                        in this config so the UI never blocks).
//    • exec()          → would wait for the command to finish.
//
//  PROGRAM-CREATED NOTE: hyprwhspr "record toggle" starts/stops the system
//  speech-to-text. If the binary/script isn't on PATH nothing happens silently,
//  so you can swap in any tool by editing the command array.
// =============================================================================
import Quickshell
import QtQuick

Pill {
    icon: "mic"
    label: ""
    onClicked: Quickshell.execDetached(["hyprwhspr", "record", "toggle"])
}