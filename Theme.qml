// =============================================================================
//  THEME.QML  —  the design "tokens" file (colors, fonts, sizes)
// =============================================================================
//  WHAT THIS FILE DOES
//  -------------------
//  This is a SINGLETON: quickshell instantiates it exactly once and lets every
//  other file read its named values, e.g. `color: Theme.pillBg`.
//
//  WHY IS THAT USEFUL?
//  -------------------
//  Central control. Change one color here and the whole bar + quick settings
//  update, instead of hunting through every file for hard-coded hex values.
//
//  HOW A SINGLETON WORKS IN QML
//  ----------------------------
//  1. `pragma Singleton` (below) tells Qt: "this file defines a shared object,
//     not a reusable component".
//  2. `qmldir` registers it:  `singleton Theme 1.0 Theme.qml`
//  3. Any file can then just write  Theme.someName  with NO import / NO instance.
//
//  RULES FOR THE 10 COLOR SLOTS
//  -----------------------------
//  Slots are the raw palette; the "semantic aliases" below point at specific
//  slots. NOTE: in the *current* palette, slots 1 & 3 happen to be the same
//  light lavender as slot 7 (ink), and slots 8/9 are near-black — the palette
//  was tuned that way (light surfaces + dark text). You can tweak the slots
//  themselves OR re-point an alias at a different slot.
// =============================================================================
pragma Singleton
import QtQuick

QtObject {
    // =========================================================================
    // 1. THE TEN COLOR SLOTS  (the raw palette this whole UI is built from)
    // =========================================================================

    property color bg:        "#0f0b26"  // 1  bg        darkest background / surfaces
    property color indigo:    "#1e0d8c"  // 2  indigo    elevated surfaces
    property color violet:    "#170973"  // 3  violet    deep secondary surfaces
    property color primary:   "#140a4e"  // 4  primary   dominant capsule color
    property color attention: "#f27289"  // 5  attention accent / active / danger
    property color plum:      "#2f1ea0"  // 6  plum      icon-segment background
    property color ink:       "#f5f5f5"  // 7  ink       main text & icon color
    property color cream:     "#d8d8ff"  // 8  cream     secondary text
    property color lavender:  "#a3a1f9"  // 9  lavender  muted / faint text
    property color border:    "transparent" // 10 border  outlines & dividers

    // ─── PALETTE TRANSITIONS ────────────────────────────────────────────────────
    // The slots above are WRITABLE on purpose: the palette engine
    // (PaletteState.qml) rewrites them whenever the wallpaper — and the color
    // palette attached to it — changes. The Behaviors below make every color
    // in the whole UI FADE to its new value instead of snapping, in sync with
    // the wallpaper's image crossfade. All semantic aliases below are bindings
    // onto these slots, so they follow the animated values frame by frame.
    Behavior on bg        { ColorAnimation { duration: 600 } }
    Behavior on indigo    { ColorAnimation { duration: 600 } }
    Behavior on violet    { ColorAnimation { duration: 600 } }
    Behavior on primary   { ColorAnimation { duration: 600 } }
    Behavior on attention { ColorAnimation { duration: 600 } }
    Behavior on plum      { ColorAnimation { duration: 600 } }
    Behavior on ink       { ColorAnimation { duration: 600 } }
    Behavior on cream     { ColorAnimation { duration: 600 } }
    Behavior on lavender  { ColorAnimation { duration: 600 } }
    Behavior on border    { ColorAnimation { duration: 600 } }

    // ─── Alternate palette (commented out — your "new colors" idea) ───────────
    // The 5 color scheme you sketched at the bottom of the old Theme.qml.
    // It was NOT activated during the tidy-up to avoid changing the look.
    // To try it, copy the hex values into the slots above (or swap them in).
    //   bg        → "#0F0B26"  (darkest purple-black)
    //   indigo    → "#1E0D8C"  (deeper indigo)
    //   violet    → "#170973"  (deep navy)
    //   primary   → "#7749A6"  (medium purple)
    //   attention → "#F27289"  (bright coral pink)
    //   plum / ink / cream / lavender / border  stay as above.
    // ⚠ CHANGING THESE MAKES THE OVERALL LOOK A LOT DARKER. If you also go
    //   dark, remember cream (#010101, near-black) is used as TEXT on the
    //   quick-settings card — near-black text on a dark card is hard to read,
    //   so you'd want to swap qsText to something light (e.g. ink).

    // =========================================================================
    // 2. SEMANTIC ALIASES  (what each *use* of a color is, in plain English)
    // =========================================================================
    // These names describe PURPOSE, not color. "wsActive" means "the workspace
    // that currently has focus". Point any alias at any slot above.

    // --- Top bar ---------------------------------------------------------------
    readonly property color barBg:        "transparent"   // the whole bar strip's backdrop
    readonly property color pillBg:       plum            // icon segment of a pill capsule
    readonly property color pillBorder:   border          // outlines around capsules

    readonly property color iconColor:    ink             // icons inside pill capsules
    readonly property color textPrimary:  ink             // main text (clock, labels)
    readonly property color textMuted:    cream           // secondary / soft text

    // --- Workspace pips ----------------------------------------------------------
    readonly property color wsActive:     attention       // currently FOCUSED workspace
    readonly property color wsActiveText: ink             // text on the focused pip
    readonly property color wsOccupied:   indigo          // workspace with open windows
    readonly property color wsEmpty:      bg              // workspace with nothing open
    readonly property color wsText:       cream           // text on un-focused pips
    // (wsActiveText/wsText feed the commented-out number styling in
    //  Workspaces.qml — kept here so you can re-enable that style easily.)

    // --- Quick-settings dropdown --------------------------------------------------
    readonly property color qsBg:         violet          // dropdown card + slider track
    readonly property color qsBgAlt:      violet          // rows / inactive tile bg
    readonly property color qsAccent:     attention       // active icons / fills
    readonly property color qsText:       cream           // primary panel text
    readonly property color qsTextMuted:  lavender        // secondary / empty-state text
    readonly property color qsOnAccent:   ink             // text/icon ON an accent area
    readonly property color qsSuccess:    attention       // "success"-y actions (refresh)
    readonly property color qsPurple:     lavender        // idle accents
    readonly property color qsDanger:     attention       // destructive actions (power)

    // =========================================================================
    // 3. FONTS
    // =========================================================================
    readonly property string fontText:  "JetBrainsMono Nerd Font"  // body / labels
    readonly property string fontIcons: "Material Symbols Rounded" // icon glyphs
    // Icons are ordinary TEXT here: a glyph from the Material font inside a
    // `Text` element. Change the font above to restyle the glyphs themselves.

    // =========================================================================
    // 4. GLOBAL SIZING & GEOMETRY
    // =========================================================================
    readonly property int barHeight:       40  // total height of the bar strip
    readonly property int pillHeight:      30  // height of each pill capsule
    readonly property int pillBorderWidth: 0  // set to 1/2 for visible borders
    readonly property int animDuration:   150  // animation speed, milliseconds
}