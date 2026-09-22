// =============================================================================
//  VOLUME.QML — the audio volume control pill on the top bar
// =============================================================================
//  Built on top of the Pill component:
//     [ (icon) | label ]
//  We just feed Pill dynamic icon/text and add mouse interaction.
//
//  PIPE WIRE (the audio system this config uses)
//  ---------------------------------------------
//  Quickshell ships a Pipewire service. `Pipewire.defaultAudioSink` is the
//  currently used speaker output; `.audio.volume` is 0.0–1.0, `.audio.muted`
//  is a bool. Everything below is just *binding* to those live values, so the
//  pill updates the instant the volume changes anywhere.
//
//  PwObjectTracker — tells the service "here are the objects I care about";
//  if the default sink switches, the bindings re-evaluate automatically.
// =============================================================================
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Pill {
    id: root

    // Keep our references to the default sink alive & up to date.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // --- Live audio state (re-read whenever anything changes) -------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    // `sink ? sink.audio : null` → "if there is a sink, give me its audio,
    // otherwise give me null". The `? :` guard stops crashes when no sink.

    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false
    readonly property int volumePercent: Math.round(volume * 100)

    // --- Dynamic icon + label (bindings, re-evaluate on every change) -----------
    icon: muted ? "volume_off"
                : (volumePercent > 50 ? "volume_up"
                : (volumePercent > 0 ? "volume_down" : "volume_mute"))
    label: muted ? "Muted" : volumePercent + "%"

    // --- Mouse controls -----------------------------------------------------------
    // NOTE: Pill already has a MouseArea that emits `clicked`. We draw ANOTHER
    // MouseArea on top so click does something volume-specific (toggle mute).
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        // Left click → toggle mute.
        onClicked: {
            if (root.audio) {
                root.audio.muted = !root.audio.muted
            }
        }

        // Scroll wheel → raise / lower volume by 5% steps.
        onWheel: wheel => {
            if (root.audio) {
                let step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                // clamp between 0.0 and 1.5 (1.5 = +50% boost allowed)
                root.audio.volume = Math.max(0, Math.min(1.5, root.audio.volume + step))
            }
        }
    }
}