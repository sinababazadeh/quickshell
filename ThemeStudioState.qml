// =============================================================================
//  THEMESTUDIOSTATE.QML — Singleton state manager for the Live Color Studio
// =============================================================================
pragma Singleton
import Quickshell
import QtQuick

Item {
    id: root

    // True when the Theme Studio fullscreen workstation overlay is open
    property bool active: false

    // Target wallpaper whose palette is being fine-tuned
    property string wallpaperPath: ""

    // Which color slot is currently selected for the crosshair picker
    property string activeSlot: "bg"

    // Live working palette being tuned
    property var workingPalette: ({})

    // Revision counter to trigger reactive QML updates
    property int revision: 0

    // Complete list of theme color slots with clean, descriptive labels
    readonly property var slots: [
        { id: "bg",        name: "Background",      icon: "wallpaper" },
        { id: "primary",   name: "Primary Capsule", icon: "category" },
        { id: "plum",      name: "Accent Pill",     icon: "token" },
        { id: "attention", name: "Highlight / WS",  icon: "stars" },
        { id: "indigo",    name: "Elevated Card",   icon: "layers" },
        { id: "violet",    name: "Deep Surface",    icon: "contrast" },
        { id: "ink",       name: "Text & Ink",      icon: "title" },
        { id: "cream",     name: "Secondary Text",  icon: "format_paint" },
        { id: "lavender",  name: "Muted Text",      icon: "blur_on" }
    ]

    function open(path) {
        wallpaperPath = path || WallpaperState.current || ""
        let pal = {}
        for (let i = 0; i < slots.length; i++) {
            let s = slots[i].id
            pal[s] = PaletteState.colorFor(wallpaperPath, s)
        }
        workingPalette = pal
        activeSlot = "bg"
        revision++
        active = true
    }

    function colorForSlot(slot) {
        let _ = revision
        if (workingPalette && workingPalette[slot]) return workingPalette[slot]
        return Theme[slot] !== undefined ? Theme[slot].toString() : "#ffffff"
    }

    function setSlotColor(slot, hex) {
        if (!slot || !hex) return
        workingPalette[slot] = hex.toString().toUpperCase()
        // Instantly update Theme so all components in the simulated workstation live-recolor
        if (Theme[slot] !== undefined) {
            Theme[slot] = hex
        }
        revision++
    }

    function saveAndApply() {
        if (wallpaperPath && workingPalette) {
            PaletteState.saveFullPalette(wallpaperPath, workingPalette)
        }
        active = false
    }

    function cancelAndRevert() {
        if (wallpaperPath) {
            PaletteState.applyFor(WallpaperState.current)
        }
        active = false
    }
}
