// =============================================================================
//  WALLPAPER.QML — one background-layer surface per monitor (the wallpaper)
// =============================================================================
//  HOW THE WALLPAPER WORKS NOW (hyprpaper is gone)
//  -----------------------------------------------
//  Quickshell draws the wallpaper ITSELF: this file creates a layer-shell
//  surface on the BACKGROUND layer of one monitor and paints the image there.
//  shell.qml spawns one of these per connected screen (Repeater over screens).
//
//  CROSSFADE
//  ---------
//  Two Image elements are stacked; only one is visible at a time. When the
//  wallpaper changes, the HIDDEN one loads the new file; the moment it has
//  decoded (status == Image.Ready) the two swap opacities — animated — so the
//  new image fades in over the old one. The very first load has nothing to
//  fade from, so it paints instantly.
//
//  All state (which file is active) lives in the WallpaperState singleton;
//  this file only renders it.
// =============================================================================
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    // One instance per screen (shell.qml's Variants feeds modelData = a screen).
    property var modelData
    screen: modelData

    // Full-screen background layer. PanelWindow IS a layer surface on Wayland;
    // the attached WlrLayershell type reaches its layer-specific knobs:
    //   Background  = lowest layer (behind every window, like hyprpaper was)
    //   Ignore      = the surface does NOT reserve space (the bar does that)
    // Anchored to all four edges → sized to the whole screen.
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    visible: true
    color: "black"   // what you see behind the image while it decodes

    // Which image layer is on top right now.
    property bool showA: true
    // The layer currently loading a new image (we only flip when IT finishes).
    property Image incoming: null

    // ─── Layer A ─────────────────────────────────────────────────────────────────
    Image {
        id: imgA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop   // "cover", like hyprpaper's fit_mode
        asynchronous: true                    // never block the compositor
        opacity: root.showA ? 1 : 0
        sourceSize.width: root.width          // decode at screen size, save memory
        sourceSize.height: root.height

        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
        onStatusChanged: root.checkLoaded(imgA)
    }

    // ─── Layer B ─────────────────────────────────────────────────────────────────
    Image {
        id: imgB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: root.showA ? 0 : 1
        sourceSize.width: root.width
        sourceSize.height: root.height

        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
        onStatusChanged: root.checkLoaded(imgB)
    }

    // ─── First paint ─────────────────────────────────────────────────────────────
    // On startup, paint the current wallpaper instantly into the visible layer
    // (nothing to fade from yet). Later changes go through swapTo()'s fade.
    Component.onCompleted: {
        if (WallpaperState.current !== "") imgA.source = WallpaperState.current
    }

    // Follow the singleton for the rest of the session.
    Connections {
        target: WallpaperState
        function onCurrentChanged() { root.swapTo(WallpaperState.current) }
    }

    // Load `path` into the hidden layer; when it finishes decoding, checkLoaded
    // flips `showA` and the two opacities crossfade. If the visible layer never
    // got an image (startup race with the state reader), just paint instantly.
    function swapTo(path) {
        let visible = root.showA ? imgA : imgB
        if (visible.source.toString() === path) return
        if (visible.source.toString() === "") {
            visible.source = path
            return
        }
        let hidden = root.showA ? imgB : imgA
        if (hidden.source.toString() === path) return
        root.incoming = hidden
        hidden.source = path
    }

    // Called by both images when their status changes.
    function checkLoaded(img) {
        if (root.incoming !== img) return
        if (img.status !== Image.Ready) return
        root.incoming = null
        root.showA = !root.showA   // opacities animate via the Behaviors above
    }
}