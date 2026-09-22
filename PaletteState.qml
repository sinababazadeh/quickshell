// =============================================================================
//  PALESTATE.QML — per-wallpaper color palettes (a singleton, like Theme.qml)
// =============================================================================
//  WHAT THIS IS
//  ------------
//  Every wallpaper can have a COLOR PALETTE attached to it. When the wallpaper
//  changes, this singleton looks up the new wallpaper's palette and writes it
//  into Theme's 10 color slots — the whole UI recolors (and fades, thanks to
//  the Behaviors on those slots).
//
//  STORAGE
//  -------
//  One JSON file:  ~/.config/quickshell/theme.json
//      { "version": 1,
//        "wallpapers": [ { "path": "...", "name": "...",
//                          "palette": { "bg": "#...", "ink": "#...", ... } } ] }
//  Palette keys are the NAMES of Theme's color slots, so new slots can be
//  added later without breaking saved palettes.
//
//  LIFECYCLE
//  ---------
//  • At startup the registry is loaded and the active wallpaper's palette is
//    applied (restoring your theme across reboots).
//  • When Hub scans the wallpapers folder it calls ensureRegistered(), which
//    adds any unknown wallpaper with a copy of the current palette.
//  • The theme tab's manage view calls assignColor() to edit one slot of one
//    wallpaper — saved immediately, and applied live if that wallpaper is
//    the active one (instant preview).
// =============================================================================

pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root

    // Where the registry lives (relative to $HOME).
    readonly property string registryFile: ".config/quickshell/theme.json"

    // The parsed registry (see the JSON shape above).
    property var registry: { "version": 1, "wallpapers": [] }

    // Revision counter to notify QML bindings when palettes change
    property int revision: 0

    // The Theme color slots a palette defines ("border" is left alone — it is
    // decorative transparency everywhere in this config).
    readonly property var slotNames: [
        "bg", "indigo", "violet", "primary", "attention",
        "plum", "ink", "cream", "lavender"
    ]

    // ─── Startup: load the registry, then apply the active wallpaper's palette ──
    Process {
        id: registryReader
        running: true
        command: ["bash", "-c",
                  "cat \"$HOME/" + root.registryFile + "\" 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            id: registryCollector
            waitForEnd: true
            onDataChanged: root.loadRegistry(registryCollector.text)
        }
    }

    function normalizePath(p) {
        if (!p) return ""
        let home = Quickshell.env("HOME") || ""
        if (home && p.startsWith("/home/")) {
            p = p.replace(/^\/home\/[^\/]+\/\.config\/quickshell/, home + "/.config/quickshell")
        }
        return p
    }

    function loadRegistry(text) {
        try {
            let obj = JSON.parse(text)
            if (obj && obj.wallpapers && Array.isArray(obj.wallpapers)) {
                for (let i = 0; i < obj.wallpapers.length; i++) {
                    if (obj.wallpapers[i].path) {
                        obj.wallpapers[i].path = normalizePath(obj.wallpapers[i].path)
                    }
                }
                root.registry = obj
                root.revision++
            }
        } catch (e) {
            // Absent/corrupt file → keep the empty registry; it is rewritten
            // on the first save.
        }
        root.applyFor(WallpaperState.current)
    }

    // ─── Lookup ──────────────────────────────────────────────────────────────────
    function entryFor(path) {
        let list = root.registry.wallpapers || []
        for (let i = 0; i < list.length; i++)
            if (list[i].path === path) return list[i]
        return null
    }

    // The color currently shown for one slot of one wallpaper (registry value,
    // falling back to Theme's live slot — this keeps the dots in sync even for
    // wallpapers that are not registered yet).
    // Accessing root.revision ensures QML bindings re-evaluate whenever any slot is assigned.
    function colorFor(path, slot) {
        let _rev = root.revision
        let entry = entryFor(path)
        if (entry && entry.palette && entry.palette[slot]) return entry.palette[slot]
        return Theme[slot] !== undefined ? Theme[slot].toString() : "transparent"
    }

    // Accepts #rgb, #rgba, #rrggbb and #aarrggbb — everything QML colors accept.
    function isValidHex(s) {
        return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(s)
    }

    // ─── Apply a wallpaper's palette to Theme's slots ────────────────────────────
    function applyFor(path) {
        let entry = entryFor(path)
        if (!entry || !entry.palette) return
        for (let i = 0; i < root.slotNames.length; i++) {
            let name = root.slotNames[i]
            if (entry.palette[name]) Theme[name] = entry.palette[name]
        }
    }

    // ─── Register unknown wallpapers (called by Hub after a folder scan) ─────────
    // New entries start from a copy of the CURRENT palette.
    function ensureRegistered(paths) {
        let added = false
        for (let i = 0; i < paths.length; i++) {
            if (entryFor(paths[i])) continue
            let palette = {}
            for (let s = 0; s < root.slotNames.length; s++) {
                let name = root.slotNames[s]
                palette[name] = Theme[name].toString()
            }
            root.registry.wallpapers.push({
                path: paths[i],
                name: paths[i].split("/").pop(),
                palette: palette
            })
            added = true
        }
        if (added) {
            root.revision++
            root.save()
        }
    }

    // ─── Assign one slot color for one wallpaper (the chip grid) ─────────────────
    function assignColor(path, slot, hex) {
        let entry = entryFor(path)
        if (!entry) return
        entry.palette[slot] = hex
        root.revision++
        if (path === WallpaperState.current) applyFor(path)   // live preview
        root.save()
    }

    // ─── Reset wallpaper palette to current Theme defaults ─────────────────────
    function resetPalette(path) {
        let entry = entryFor(path)
        if (!entry) return
        for (let s = 0; s < root.slotNames.length; s++) {
            let name = root.slotNames[s]
            entry.palette[name] = Theme[name].toString()
        }
        root.revision++
        if (path === WallpaperState.current) applyFor(path)
        root.save()
    }

    // ─── Persist the registry (single JSON file, written via a quoted heredoc
    //     so nothing in the JSON can be mangled by the shell) ────────────────────
    Process {
        id: registryWriter
        property string payload: ""
        command: ["bash", "-c",
                  "mkdir -p \"$(dirname \"$HOME/" + root.registryFile + "\")\" && "
                  + "cat > \"$HOME/" + root.registryFile + "\" <<'QS_THEME_EOF'\n"
                  + payload + "\nQS_THEME_EOF"]
    }

    Timer {
        id: saveDebounceTimer
        interval: 250
        repeat: false
        onTriggered: {
            registryWriter.payload = JSON.stringify(root.registry, null, 2)
            if (!registryWriter.running) {
                registryWriter.running = true
            }
        }
    }

    function save() {
        saveDebounceTimer.restart()
    }

    // ─── Follow wallpaper switches ───────────────────────────────────────────────
    Connections {
        target: WallpaperState
        function onCurrentChanged() { root.applyFor(WallpaperState.current) }
    }
}