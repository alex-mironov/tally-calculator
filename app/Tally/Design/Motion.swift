// Motion.swift — Tally's motion vocabulary: the few curves the app moves on,
// and the rule that typing moves nothing.
//
// ── Typing lands in the frame ───────────────────────────────────────────────
// Nothing animates on a keystroke (docs/v2-design.md, Decisions): not the
// draft or its size steps, not the result beside it, not the operator key
// inverting, not the ring or the note when a commit takes them away. Motion
// marks outcomes, the same rule the haptics follow (Haptics.swift). A line
// committed, a mode entered, a toast — never the key that caused it.
//
// That was a convention, and conventions slip: an implicit `.animation` on the
// dock for `editing` faded the cleared draft on every edit-↵, so the next digit
// landed on a line still fading out. So it is a transaction key instead. Every
// keystroke's state changes run inside `withTransaction(\.typing, true)`
// (`CalculatorScreen.press`, `handleKey`, the hold-clear), and the dock drops
// the animation of any transaction that carries it (`InputDock.body`). The few
// things a key starts that should still move — link mode folding the pad, the
// shake on a refused commit — opt back out with `withTransaction(\.typing,
// false)` around their own change.
//
// Three more rules, for anything new:
//   · scope an animation to the view that changes, never to the dock or the
//     keypad around it, so that one state's motion can't sweep up another's;
//   · anything that can fire again within its own duration is a zero-bounce
//     spring, so a second change retargets it rather than queueing behind it;
//   · one event, one clock. What a single tap sets moving — the dock giving
//     way to select mode's footer and the keys stowing under it — changes in
//     one `withAnimation`, on one of the curves below, never on two.
//
// Every curve the app moves on is here. A duration written out at a call site
// is a second vocabulary starting; if none of these fits, the answer is a new
// name in this file with a sentence saying what it is for.
import SwiftUI

enum Motion {
  /// A key lifting: its press tint fading off. Press-in has no animation.
  static let release = Animation.easeOut(duration: 0.1)

  /// State changing in place: the editing ring, the note chip opening, a row
  /// lighting, a label changing.
  static let flip = Animation.easeOut(duration: 0.15)

  /**
   A surface changing shape: the pad folding to the link bar, the dock's top
   edge gliding with it. A spring with no bounce rather than a timing curve, so
   it cannot overshoot and a change mid-flight retargets with its velocity.
   */
  static let surface = Animation.smooth(duration: surfaceDuration)

  /**
   `surface`, picking up where a drag left it: the keys settling after the
   finger lets go of the dock, at the speed the finger was moving.

   `velocity` is in units of the distance still to go, per second — so 1 means
   "at this rate it would arrive in a second". It is capped at the spring's own
   natural pace: a zero-bounce spring thrown faster than that passes its target
   and comes back, and on a surface the size of the keypad that reads as a
   bounce, which is the one thing `surface` promises not to do.
   */
  static func surface(velocity: Double) -> Animation {
    let pace = 2 * Double.pi / surfaceDuration
    return .interpolatingSpring(
      duration: surfaceDuration, bounce: 0, initialVelocity: min(max(velocity, -pace), pace))
  }

  private static let surfaceDuration = 0.28

  /**
   What rides the system keyboard: the dock lifting over it for the note field.

   The keyboard's own curve, as near as SwiftUI can say it. Measured off a
   recording of the iOS 26 keyboard rising (10 Nov 2026), frame by frame: a
   spring with no bounce and a 0.26s period stays within 3pt of it the whole
   way up. The ease-out this replaces fell 36pt behind mid-rise, so the
   keyboard climbed over the foot of the dock and the dock caught up after.
   (UIKit's often-quoted mass 3 / stiffness 1000 / damping 500 is not it: that
   spring is still a third of the way down when the keyboard has landed.)
   */
  static let keyboard = Animation.smooth(duration: 0.26)

  /// Numbers turning over (`.contentTransition(.numericText)`): the total, a
  /// line's amount, the select footer. A little bounce, as the system's own
  /// counters have — and a spring, so ↵↵↵ lands on the latest total rather
  /// than queueing three rolls.
  static let roll = Animation.snappy(duration: 0.32)

  /// A toast arriving above the dock.
  static let toastIn = Animation.snappy(duration: 0.24)

  /// A toast leaving, or giving way to the next. A spring too: a copy that
  /// lands while the last toast is still going retargets it.
  static let toastOut = Animation.smooth(duration: 0.2)
}

extension Transaction {
  /// The change is a keystroke's, and lands without animation (see the header).
  @Entry var typing = false
}
