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
// Two more rules, for anything new:
//   · scope an animation to the view that changes, never to the dock or the
//     keypad around it, so that one state's motion can't sweep up another's;
//   · anything that can fire again within its own duration is a zero-bounce
//     spring, so a second change retargets it rather than queueing behind it.
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
  static let surface = Animation.smooth(duration: 0.28)

  /// Numbers turning over (`.contentTransition(.numericText)`): the total, the
  /// select footer. A little bounce, as the system's own counters have.
  static let roll = Animation.snappy(duration: 0.32)

  /// A toast arriving above the dock.
  static let toastIn = Animation.snappy(duration: 0.24)
}

extension Transaction {
  /// The change is a keystroke's, and lands without animation (see the header).
  @Entry var typing = false
}
