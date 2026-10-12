// DraftLine.swift — the dock's one-line draft: the sum being typed, on a single
// line that never wraps and never hides the digits being typed.
//
// The line is right-anchored and always shows its tail. A sum longer than the
// dock runs off the *leading* edge under a short fade, so the cut reads as
// "there's more" rather than as a clipped glyph. There is no scrolling back to
// the head: Calculator v2 gives the horizontal swipe to the Calculator gesture
// instead — a swipe across the display deletes the last character, one per
// 28pt travelled — and a line that scrolled would have fought it for the drag.
//
// Then the caret, which blinks after the last character, and the shake an
// invalid commit gets in place of the old card's border flash.
//
// ── What this replaces ──────────────────────────────────────────────────────
// Right-anchoring a growing line without it jumping on every keystroke is hard
// in React Native: the original used the inverted-list trick, mirroring the
// scroll view with `scaleX: -1` and mirroring its content back, so that offset
// zero *was* the tail. The fade was a `MaskedView` over an `expo-linear-gradient`.
//
// Here it is a trailing-aligned frame that clips, and a `.mask`.
import SwiftUI
import TallyKit

struct DraftLine<Content: View>: View {
  /// Draw the caret. Off while the note field has its own.
  var caret = true
  /// The draft's current type size, which the caret is drawn against.
  var typeSize: CGFloat = Draft.fontSize
  /// Bumped on every refused commit; each bump shakes the line once.
  var shakes = 0
  let onTap: () -> Void
  /// One character's worth of swipe — delete the last character.
  let onSwipeDelete: () -> Void
  @ViewBuilder var content: Content

  /// The line box: the design's 58, on the grid. Fixed, so the dock does not
  /// resize as the draft steps between its sizes (`Draft.fontSize(forLength:)`).
  static var height: CGFloat { 56 }

  /// Width of the leading fade — the design's 28px mask.
  private let fadeWidth: CGFloat = Space.s7
  /// How far a swipe travels per character it deletes (the design's 28px).
  private let swipeStep: CGFloat = Space.s7

  @Environment(\.theme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Where the swipe last deleted a character, in the gesture's own space;
  /// nil until the drag has proved to be horizontal.
  @State private var swipeAnchor: CGFloat?
  @State private var swipeDecided = false
  /// Fixed for the line's life. It used to be reset on every keystroke, to
  /// hold the caret solid while typing — which cost a second pass of this
  /// body per key and restarted the timeline each time. Typing is unanimated
  /// (docs/v2-design.md, Decisions), so the caret keeps a steady blink instead.
  @State private var blinkEpoch = Date.now

  var body: some View {
    HStack(spacing: Space.s1) {
      content
      // Hidden rather than removed, so the digits do not shift when it goes.
      caretView.opacity(caret ? 1 : 0)
    }
    .fixedSize(horizontal: true, vertical: false)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.horizontal, Space.s2)
    .frame(height: Self.height)
    .clipped()
    .mask(alignment: .leading) {
      HStack(spacing: 0) {
        LinearGradient(
          colors: [.black.opacity(0), .black],
          startPoint: .leading, endPoint: .trailing
        )
        .frame(width: fadeWidth)
        Color.black
      }
    }
    .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { line, x in
      line.offset(x: reduceMotion ? 0 : x)
    } keyframes: { _ in
      // The design's tk2Shake: −6, 5, −3, 2 at fifths of 0.32s, then home.
      KeyframeTrack {
        LinearKeyframe(-6, duration: 0.064)
        LinearKeyframe(5, duration: 0.064)
        LinearKeyframe(-3, duration: 0.064)
        LinearKeyframe(2, duration: 0.064)
        LinearKeyframe(0, duration: 0.064)
      }
    }
    .contentShape(.rect)
    .onTapGesture(perform: onTap)
    .gesture(swipe)
  }

  /**
   The caret: 2pt wide and 0.82 of the type size tall, in the call to action on
   the dark scheme (where a white bar beside white digits is lost) and the ink
   on the light ones.

   It blinks on the design's 1.06s step — on for the first half — at a steady
   pace that typing does not touch: only the bar's opacity changes on a tick,
   inside the timeline, so the blink never invalidates the line or the dock.
   Reduce Motion holds it steady.
   */
  private var caretView: some View {
    TimelineView(.periodic(from: blinkEpoch, by: 0.53)) { context in
      let ticks = Int(context.date.timeIntervalSince(blinkEpoch) / 0.53)
      // Type-relative, not a layout metric: the design's 0.82em.
      RoundedRectangle(cornerRadius: 1)
        .fill(t.isDark ? t.cta : t.dockInk)
        .frame(width: 2, height: (typeSize * 0.82).rounded())
        .opacity(reduceMotion || ticks % 2 == 0 ? 1 : 0)
    }
    .accessibilityHidden(true)
  }

  private var swipe: some Gesture {
    DragGesture(minimumDistance: Space.s2)
      .onChanged { value in
        if !swipeDecided {
          swipeDecided = true
          // Decide the axis once. A vertical drag is not this gesture's to
          // take — and a delete is not something to trigger by accident.
          if abs(value.translation.width) > abs(value.translation.height) {
            swipeAnchor = value.startLocation.x
          }
        }
        guard let anchor = swipeAnchor else { return }
        // Either direction counts, as in Calculator. The anchor moves to where
        // the finger is, as the design's does, so a slow drag and a fast one
        // delete the same amount for the same distance.
        if abs(value.location.x - anchor) > swipeStep {
          swipeAnchor = value.location.x
          onSwipeDelete()
        }
      }
      .onEnded { _ in
        swipeAnchor = nil
        swipeDecided = false
      }
  }
}
