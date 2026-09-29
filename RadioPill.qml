// =============================================================================
//  RADIOPILL.QML — the RESPONSIVE Wi-Fi / Bluetooth tile for the Hub
// =============================================================================
//  WHAT THIS IS
//  ------------
//  A drop-in replacement for the hand-built Wi-Fi / Bluetooth capsules in the
//  Hub's Settings tab. It keeps the bar's two-segment pill silhouette
//      [ (icon) | title / status            (chevron) ]
//  but the state change is now a small performance instead of a single colour
//  swap. Everything it reads is bound by Hub.qml, so this file never runs a
//  command itself (UI = dumb display, Process blocks = data collection).
//
//  THE FEEDBACK MAP (what happens on each interaction)
//  --------------------------------------------------
//    INTERACTION        WHAT THE TILE DOES
//    -----------------  ------------------------------------------------------
//    press              squashes to 94% (spring easing, OutBack)
//    release            soft ink flash ripples across the icon cap
//    hover              tile lifts to 103%, the body + icon brighten, the
//                       chevron slides right and turns bright
//    on → off           glyph swaps INSTANTLY (wifi → wifi_off / bluetooth →
//                       bluetooth_disabled) — no pop, no spin, no scale; the
//                       icon cap slowly DIMS OUT (its light-up overlay fades
//                       over 700 ms), the body tint fades out, the live status
//                       pip stops breathing and dims
//    off → on           the reverse — the icon cap slowly LIGHTS UP, then
//                       starts breathing — and the pip pulses its halo again
//    busy (command in   the glyph does not move AT ALL — it just shows the
//     flight)           state the flip put it in — while the cap hovers
//                       half-lit ("warming up") and the status line reads
//                       "Turning on… / Turning off…"
//
//  THE GLYPH IS STATIC (two fixed symbols, no animation ever)
//  ----------------------------------------------------------
//  The tile shows exactly ONE glyph per state: `icon` when on, `iconOff` when
//  off — and it never moves: no spinner, no rotation, no scale pop, in ANY
//  state (all three were unwanted — the icon is meant to be a plain symbol).
//  It is also deliberately NOT derived from signal strength — a 0–100 reading
//  wobbles by a few points on every refresh, so picking wifi / wifi_2_bar /
//  wifi_1_bar from it made the tile flicker between unrelated symbols. The live
//  detail belongs on the second line (SSID / device name), not in the icon.
//
//  THE LEFT CAP LIGHTS UP LIKE THE STATUS DOT
//  ------------------------------------------
//  The cap is not colour-swapped from "accent" to "plum". It keeps a constant
//  plum base and an accent overlay fades in over it, so the left side warms up
//  gradually (700 ms, in-out sine) as the radio comes on and cools down just as
//  gradually as it goes off — the same feel as the status dot lighting. While a
//  command is in flight the overlay waits at ~55 % ("warming up"), and once the
//  radio has settled the cap pulses a soft bloom outward on the SAME 1300 ms
//  rhythm as the dot's halo — so the left side reads as "lit and alive".
//
//  PUBLIC API
//  ----------
//    icon           glyph while the radio is ON            (e.g. "wifi")
//    iconOff        glyph while the radio is OFF           (e.g. "wifi_off")
//    title          bold first line                        ("Wi-Fi")
//    status         small second line                      (SSID / "Off")
//    active         radio on/off                           → drives all colour
//    busy           a system command is in flight  → half-lit cap + status line
//    toggled()      icon cap OR body clicked
//    openDetails()  chevron clicked
// =============================================================================
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Public API ------------------------------------------------------------
    property string icon: "wifi"        // glyph shown while ON        (fixed)
    property string iconOff: ""         // glyph while OFF ("" → reuse `icon`)
    property string title: ""           // bold first line, e.g. "Wi-Fi"
    property string status: ""          // small second line: SSID / device / "Off"
    property bool active: false         // radio on or off
    property bool busy: false           // a system command is in flight

    // --- Signals: the two interaction outcomes ---------------------------------
    signal toggled()                    // switch the radio
    signal openDetails()                // open the detail sub-page

    // --- Internal interaction state --------------------------------------------
    // Hover is OR'd from three sensors (see `hoverSensor` + the two MouseAreas)
    // so the highlight can never be swallowed by a click zone.
    property bool hoverIcon: false      // pointer is over the icon cap
    property bool hoverBody: false      // pointer is over the body
    property bool hovered: hoverSensor.hovered || root.hoverIcon || root.hoverBody
    property bool pressedAny: false     // true while EITHER click zone is held

    // --- Derived look -----------------------------------------------------------
    // ONE glyph, resolved in priority order: off → on — that is ALL. No busy
    // branch (a spinning icon was unwanted) and no signal-strength branch (see
    // the header), so the symbol can only ever change when the radio really
    // changes state.
    // Because it is a single Text we can animate the swap in place (see iconTxt).
    readonly property string glyph: root.active
        ? root.icon
        : (root.iconOff !== "" ? root.iconOff : root.icon)

    // `lit` = "the radio is really up and settled" — gates the glow + pip pulse.
    readonly property bool lit: root.active && !root.busy

    // How long the big surfaces take to light up / dim down. Long on purpose:
    // the cap should WARM UP like the status dot, not snap to a new colour.
    readonly property int lightMs: 700

    implicitHeight: 34
    Layout.fillWidth: true              // spread across the row the tile lives in
    radius: 0
    color: "transparent"

    // --- Tactile physics --------------------------------------------------------
    // Squash while held, lift while hovered. transformOrigin keeps the squash
    // centred so the tile doesn't crawl out of its slot in the row.
    scale: root.pressedAny ? 0.94 : (root.hovered ? 1.03 : 1.0)
    transformOrigin: Item.Center
    Behavior on scale {
        NumberAnimation { duration: 160; easing.type: Easing.OutBack }
    }

    // --- HOVER SENSORS (passive) ------------------------------------------------
    // ONE handler for the whole tile + the two click zones' own hover flags
    // (see `hoverIcon` / `hoverBody`). Any of the three lights the highlight,
    // so the tile still reacts even if a MouseArea swallows the hover event.
    HoverHandler { id: hoverSensor }

    // =========================================================================
    //  LEFT ZONE — icon cap (toggles the radio)
    // =========================================================================
    Rectangle {
        id: iconSeg
        width: 30                       // FIXED so the glyph swap never shifts layout
        height: parent.height
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        // The DORMANT base colour is CONSTANT. The cap never snaps between two
        // colours: `litFill` below fades an accent wash in over this base, which
        // is what makes the left side light up gradually.
        color: Theme.plum
        topLeftRadius: height / 2       // left cap
        bottomLeftRadius: height / 2
        topRightRadius: 0               // flat edge meets the body
        bottomRightRadius: 0

        // ── Breathing bloom (the cap's version of the status dot's halo) ──────
        // A soft accent glow that sits BEHIND the cap (negative z + negative
        // margins) and pulses outward on the SAME 1300 ms rhythm as the pip's
        // halo, so the left side visibly "stays lit" while the radio is up:
        // bright → gone, over and over, exactly like the dot next to the title.
        // It parks at 0 opacity whenever the radio is not settled.
        Rectangle {
            id: capGlow
            anchors.fill: parent
            anchors.margins: -2
            z: -1
            radius: height / 2
            color: Theme.attention
            opacity: 0

            SequentialAnimation {
                id: capGlowAnim
                running: root.lit
                loops: Animation.Infinite
                NumberAnimation {
                    target: capGlow
                    property: "opacity"
                    from: 0.30
                    to: 0.0
                    duration: 1300
                    easing.type: Easing.OutCubic
                }
                // Stopping mid-pulse must never strand a bright halo behind an
                // OFF cap (same guard as the pip's `visible: lit`).
                onStopped: capGlow.opacity = 0
            }
        }

        // ── The SLOW LIGHT-UP ────────────────────────────────────────────────
        // 0 %     off            → plum base, cap asleep
        // ~55 %   command in air → "warming up", dimly lit
        // 100 %   radio settled  → fully lit accent cap
        // Both directions run for `lightMs` (700 ms), so switching the radio off
        // dims the cap down just as gradually as switching it on brightens it.
        Rectangle {
            id: litFill
            anchors.fill: parent
            color: Theme.attention
            opacity: root.active ? (root.busy ? 0.55 : 1.0) : 0.0
            topLeftRadius: parent.topLeftRadius
            bottomLeftRadius: parent.bottomLeftRadius
            Behavior on opacity {
                NumberAnimation { duration: root.lightMs; easing.type: Easing.InOutSine }
            }
        }

        // Hover haze — a faint ink wash inside the cap.
        Rectangle {
            anchors.fill: parent
            color: Theme.ink
            opacity: root.hovered ? 0.10 : 0.0
            topLeftRadius: parent.topLeftRadius
            bottomLeftRadius: parent.bottomLeftRadius
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        // Click flash — brightened on click, then faded out by `flashAnim`.
        // Declared BEFORE the glyph so the glyph stays readable during the flash.
        Rectangle {
            id: flash
            anchors.fill: parent
            color: Theme.ink
            opacity: 0
            topLeftRadius: parent.topLeftRadius
            bottomLeftRadius: parent.bottomLeftRadius

            SequentialAnimation {
                id: flashAnim
                NumberAnimation {
                    target: flash
                    property: "opacity"
                    to: 0
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }
        }

        // The glyph itself: a PLAIN, completely static Text. No pop, no scale,
        // no rotation — the only thing that changes is WHICH of the two fixed
        // symbols is shown, and the swap is instant on the on/off flip. All the
        // "something is happening" feedback lives in the cap's light-up, the
        // flash and the status line instead of in the icon.
        Text {
            id: iconTxt
            anchors.centerIn: parent
            text: root.glyph
            font.family: Theme.fontIcons
            font.pixelSize: 17
            color: Theme.ink
        }

        // Click = switch the radio. Also fires the flash + squash feedback.
        // `hoverEnabled` also feeds the tile's hover highlight (see root.hoverIcon).
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: root.hoverIcon = true
            onExited: root.hoverIcon = false
            onPressed: root.pressedAny = true
            onReleased: root.pressedAny = false
            onCanceled: root.pressedAny = false
            onClicked: {
                flash.opacity = 0.45
                flashAnim.restart()
                root.toggled()
            }
        }
    }

    // =========================================================================
    //  RIGHT ZONE — body: title / live status + chevron (opens the sub-page)
    // =========================================================================
    Rectangle {
        id: bodySeg
        anchors.left: iconSeg.right
        anchors.right: parent.right
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.primary
        clip: true
        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: height / 2      // right cap
        bottomRightRadius: height / 2

        // Fluid accent fill: tinted while the radio is on, a little brighter
        // while hovered. Radii match the parent so the caps stay round. Timed
        // with the cap's light-up (`lightMs`) so the whole tile warms together.
        Rectangle {
            anchors.fill: parent
            color: Theme.attention
            opacity: (root.active ? 0.16 : 0.0) + (root.hovered ? 0.08 : 0.0)
            topRightRadius: parent.topRightRadius
            bottomRightRadius: parent.bottomRightRadius
            Behavior on opacity {
                NumberAnimation { duration: root.lightMs; easing.type: Easing.OutCubic }
            }
        }

        // Whole-body tap zone (click = switch the radio). Declared HERE,
        // before the RowLayout, so the chevron's own hit-box (inside the
        // layout, i.e. stacked ABOVE this) wins where the two overlap.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: root.hoverBody = true
            onExited: root.hoverBody = false
            onPressed: root.pressedAny = true
            onReleased: root.pressedAny = false
            onCanceled: root.pressedAny = false
            onClicked: root.toggled()
        }

        // ---- Title + status, two tight lines -------------------------------
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 4

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    // ---- Live status pip ------------------------------------
                    // A solid core dot (colour = state) with an expanding halo
                    // behind it that only breathes while the radio is up.
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 5
                        implicitHeight: 5

                        // Breathing halo — hidden entirely when not lit so a
                        // stopped animation can never leave a ghost dot behind.
                        Rectangle {
                            visible: root.lit
                            anchors.centerIn: parent
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Theme.attention
                            SequentialAnimation on opacity {
                                running: root.lit
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 0.55; to: 0.0
                                    duration: 1300
                                    easing.type: Easing.OutCubic
                                }
                            }
                            SequentialAnimation on scale {
                                running: root.lit
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 1.0; to: 2.2
                                    duration: 1300
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // Solid core.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 5
                            height: 5
                            radius: 2.5
                            color: root.lit ? Theme.attention : Theme.qsTextMuted
                            opacity: root.lit ? 1.0 : 0.55
                            Behavior on color { ColorAnimation { duration: 240 } }
                            Behavior on opacity { NumberAnimation { duration: 240 } }
                        }
                    }

                    // ---- Title line ------------------------------------------
                    Text {
                        text: root.title
                        font.family: Theme.fontText
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.ink
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // ---- Status line (SSID / device / "Off"), dims when off -----
                Text {
                    text: root.status
                    font.family: Theme.fontText
                    font.pixelSize: 9
                    color: root.active ? Theme.cream : Theme.qsTextMuted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Behavior on color {
                        ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                }
            }

            // ---- Chevron: opens the detail sub-page -------------------------
            Item {
                id: chevBox
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 16
                implicitHeight: 16

                Text {
                    id: chev
                    anchors.centerIn: parent
                    text: "chevron_right"
                    font.family: Theme.fontIcons
                    font.pixelSize: 15
                    color: root.hovered ? Theme.ink : Theme.qsTextMuted
                    Behavior on color { ColorAnimation { duration: 180 } }

                    // Slide right on hover (Translate, NOT x — the item is
                    // anchored, and `x` would fight the anchor).
                    transform: Translate {
                        x: root.hovered ? 2 : 0
                        Behavior on x {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // Keep the tile highlighted while the pointer is on the
                    // chevron too (this zone sits above the body tap zone).
                    hoverEnabled: true
                    onEntered: root.hoverBody = true
                    onExited: root.hoverBody = false
                    onClicked: root.openDetails()
                }
            }
        }
    }
}
