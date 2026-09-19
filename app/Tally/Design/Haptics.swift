// Haptics.swift — Tally's haptic vocabulary. One name per meaning, so every
// screen speaks the same tactile language. Ported from mobile/src/lib/haptics.ts.
//
// Haptics mark *outcomes*, not touches. A key, a row, a bar button or a menu
// item gives no haptic of its own: the keypad has the system click sound for
// that (the way the system keyboard and Calculator do), and for everything else
// the screen changing under the finger is feedback enough. What is left is
// deliberately sparse and light, so the few that remain still register — a tick
// on every one of twenty keys had turned the phone into a buzzer and made the
// commit, the one moment worth feeling, indistinguishable from it.
import UIKit

enum Haptic {
  /// Light tick — an entry committed, a fresh tab started.
  case tap
  /// The selection tick — something toggled on or off: a line in a selection,
  /// a tag, an accent swatch, the keypad stowed or brought back.
  case select
  /// Medium knock — something was removed (a line, a saved tab).
  case impact
  /// A completed save. The same light tick as `tap`, deliberately *not* the
  /// system "success" notification: its two-beat buzz is far too much for an
  /// action that happens every few seconds.
  case success
  /// One firm, rigid knock — a commit the engine rejected. Again not the
  /// notification pattern: the flash on the card already says "no", the haptic
  /// only underlines it.
  case error

  @MainActor
  func play() {
    switch self {
    case .tap, .success: UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .select: UISelectionFeedbackGenerator().selectionChanged()
    case .impact: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .error: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
  }
}

/**
 The system keyboard click, for the keypad.

 HIG asks a custom input view to sound like the system keyboard, so every key
 gets the standard click — silent if the user has keyboard sounds off — and,
 like the system keyboard, nothing tactile.

 `playInputClick()` only makes a sound for a responder that says it wants input
 clicks, which is what the protocol conformance below is for. The React Native
 build needed a whole native module (modules/key-click) to reach this; here it
 is a few lines.
 */
@MainActor
enum KeyClick {
  private final class ClickingView: UIView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
  }

  private static let view = ClickingView()

  static func play() {
    UIDevice.current.playInputClick()
    _ = view  // keep the feedback-enabled responder alive
  }
}
