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
    property string activeSlot: "plum"

    // Live working palette being tuned
    property var workingPalette: ({})

    // Revision counter to trigger reactive QML updates
    property int revision: 0

    // Auto-tune mode signal for wallpaper analysis
    signal requestAutoExtract(string mode)

    // Complete list of theme color slots named strictly by the ACTUAL UI OBJECTS they are attached to.
    // Redundant slots (like duplicate secondary text "cream") have been eliminated.
    readonly property var slots: [
        { id: "plum",      name: "Pill Icon Segment",        objectCategory: "Top Bar",      desc: "Left icon square of bar pills",          icon: "token" },
        { id: "primary",   name: "Pill Body / Capsule",      objectCategory: "Top Bar",      desc: "Main label & body of bar pills",         icon: "category" },
        { id: "violet",    name: "Menu Card Background",     objectCategory: "Popup Window", desc: "Hub & Quick Settings window cards",      icon: "dashboard" },
        { id: "attention", name: "Active Workspace & Accent", objectCategory: "Highlights",   desc: "Focused workspace pip & slider fills",   icon: "stars" },
        { id: "indigo",    name: "Occupied Workspace",       objectCategory: "Workspaces",   desc: "Workspace pips with open windows",       icon: "layers" },
        { id: "bg",        name: "Empty Workspace",          objectCategory: "Workspaces",   desc: "Inactive workspace pips",                icon: "radio_button_unchecked" },
        { id: "ink",       name: "Text & Icons",             objectCategory: "Typography",   desc: "Main text labels & icon glyphs",         icon: "title" },
        { id: "lavender",  name: "Muted Text",               objectCategory: "Typography",   desc: "Secondary/dim text & subtitles",         icon: "format_color_text" }
    ]

    function open(path) {
        wallpaperPath = path || WallpaperState.current || ""
        let pal = {}
        for (let i = 0; i < slots.length; i++) {
            let s = slots[i].id
            pal[s] = PaletteState.colorFor(wallpaperPath, s)
        }
        workingPalette = pal
        activeSlot = "plum"
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
        let formattedHex = hex.toString().toUpperCase()
        workingPalette[slot] = formattedHex
        // Instantly update Theme so all components in the simulated workstation live-recolor
        if (Theme[slot] !== undefined) {
            Theme[slot] = formattedHex
        }
        // If updating lavender (muted text), keep cream in sync for legacy components
        if (slot === "lavender" && Theme.cream !== undefined) {
            Theme.cream = formattedHex
        }
        revision++
    }

    function applyFullPalette(newPalette) {
        if (!newPalette) return
        for (let key in newPalette) {
            let hex = newPalette[key].toString().toUpperCase()
            workingPalette[key] = hex
            if (Theme[key] !== undefined) {
                Theme[key] = hex
            }
        }
        if (Theme.cream !== undefined && workingPalette["lavender"]) {
            Theme.cream = workingPalette["lavender"]
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
