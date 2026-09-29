// =============================================================================
//  HOVERLIFT.QML — the Hub's shared hover feedback (one drop-in handler)
// =============================================================================
//  WHAT THIS IS
//  ------------
//  The Wi-Fi / Bluetooth tiles (RadioPill.qml) lift to 103 % under the pointer
//  and spring back on the way out. This file is that EXACT hover feel, packaged
//  as a single passive HoverHandler, so every other button in the Hub can
//  borrow it in one line:
//
//      Rectangle {
//          ...
//          MouseArea { ... }
//          HoverLift { }          // ← that is the whole API
//      }
//
//  HOW IT WORKS
//  ------------
//  A HoverHandler never steals clicks from the button's own MouseArea — it only
//  reports `hovered`. On enter we animate `target.scale` up to `baseScale *
//  hoverScale`; on exit we animate it back to `baseScale`. The animation has
//  NO `from`, so it always starts wherever the scale currently is: flicking
//  the pointer in and out mid-spring reverses smoothly instead of snapping.
//
//  OPTIONAL PRESS SQUASH
//  ---------------------
//  RadioPill also squashes to 94 % while it is held. That is opt-in, because it
//  needs the button's MouseArea: give the MouseArea an id and feed it in.
//
//      MouseArea { id: tap; onClicked: ... }
//      HoverLift { pressed: tap.pressed }
//
//  Leave `pressed` alone and the handler only does the hover lift.
//
//  A BUTTON THAT IS ALREADY SCALED
//  -------------------------------
//  Buttons that rest at a scale other than 1.0 (the wallpaper peek cards sit
//  at 0.88) must say so, otherwise the lift would snap them up past their
//  resting size and back down to 1.0 on exit:
//
//      HoverLift { baseScale: 0.88 }
//
//  WHY `target` IS A PROPERTY
//  --------------------------
//  It defaults to `parent` (the button the handler was declared inside). A
//  button that scales a wrapper instead of itself can point it elsewhere.
// =============================================================================
import QtQuick

HoverHandler {
    id: root

    // What gets scaled. Defaults to the item this handler was declared in.
    property Item target: parent

    // The radio tiles' numbers, verbatim: 103 % hover lift, 94 % press squash,
    // 160 ms OutBack spring.
    property real hoverScale: 1.03
    property real pressScale: 0.94
    property int duration: 160

    // The button's resting scale. Default 1.0 (the normal case); buttons that
    // sit at another size when idle pass their own, so the lift is always
    // relative to where they actually rest instead of snapping to 1.03 / 1.0.
    property real baseScale: 1.0

    // Driven from the button's MouseArea when you want the press squash too.
    property bool pressed: false

    // Where the scale should settle given the current interaction state.
    // (Read it through `restingNow()` inside apply() — see the note there.)
    readonly property real restingScale: root.baseScale * (root.pressed ? root.pressScale
                                                                       : (root.hovered ? root.hoverScale : 1.0))

    // The SAME computation as a function. apply() must not read the
    // `restingScale` binding: Qt 6 refreshes dependent bindings AFTER the
    // changed-signal handler returns, so inside onHoveredChanged /
    // onPressedChanged the binding still holds the PREVIOUS state and the
    // lift would always animate one step behind. Calling this re-reads the
    // properties directly, so the value is always current.
    function restingNow() {
        return root.baseScale * (root.pressed ? root.pressScale
                                              : (root.hovered ? root.hoverScale : 1.0))
    }

    // Animate from wherever we are to `restingNow()` (no `from` on purpose).
    // NOTE: this lives in a PROPERTY, not as a bare child object — a
    // HoverHandler is not an Item and has no default (`data`) property, so a
    // plain child would be rejected with "non-existent default property".
    property NumberAnimation lift: NumberAnimation {
        target: root.target
        property: "scale"
        duration: root.duration
        easing.type: Easing.OutBack
    }

    function apply() {
        if (!root.target) return
        lift.stop()
        lift.to = root.restingNow()
        lift.restart()
    }

    onHoveredChanged: root.apply()
    onPressedChanged: root.apply()
}
