// DraftLine.swift — the entry card's one-line draft: the sum being typed, on a
// single line that never wraps and never hides the digits being typed.
//
// The line is right-anchored. The tail — the part that changes on every key —
// stays put against the card's trailing edge, and a sum longer than the card
// runs off the *leading* edge under a short fade, so the cut reads as "there's
// more" rather than as a clipped glyph. The hidden head is a swipe away.
//
// ── What this replaces ──────────────────────────────────────────────────────
// Right-anchoring a growing line without it jumping on every keystroke is hard
// in React Native: the original used the inverted-list trick, mirroring the
// scroll view with `scaleX: -1` and mirroring its content back, so that offset
// zero *was* the tail. The fade was a `MaskedView` over an `expo-linear-gradient`.
// It also had to take its own tap, because on the new architecture a scroll
// view will not scroll while an ancestor holds the JS responder.
//
// Here it is `.defaultScrollAnchor(.trailing)` and a `.mask`. That is the whole
// mechanism.
import SwiftUI
import TallyKit

struct DraftLine<Content: View>: View {
  /// Changing this scrolls the line back to its tail — the draft was edited.
  let draft: String
  let onTap: () -> Void
  @ViewBuilder var content: Content

  /// The line box. Fixed at 44pt so the card does not resize as the draft
  /// steps between its two sizes (see `Draft.fontSize(forLength:)`).
  static var height: CGFloat { 44 }

  /// Width of the leading fade — the design's 36px mask.
  private let fadeWidth: CGFloat = 36

  @State private var scrolledToHead = false

  var body: some View {
    ScrollView(.horizontal) {
      content
        .frame(minWidth: 0, alignment: .trailing)
        .padding(.leading, fadeWidth)
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
    }
    .scrollIndicators(.hidden)
    // Offset zero is the tail, so content that grows pushes the *head* off the
    // leading edge instead of moving the digits being typed.
    .defaultScrollAnchor(.trailing)
    .frame(height: Self.height)
    .mask(alignment: .leading) {
      HStack(spacing: 0) {
        // A real mask rather than a painted-on colour: the card is Liquid Glass,
        // and a solid fade would have to match a material that changes with
        // whatever is behind it. The text simply goes transparent instead.
        LinearGradient(
          colors: [.black.opacity(0), .black],
          startPoint: .leading, endPoint: .trailing
        )
        .frame(width: fadeWidth)
        Color.black
      }
    }
    .onChange(of: draft) {
      // Typing returns the line to its tail; reading the head is a deliberate
      // swipe that the next keystroke undoes.
      scrolledToHead = false
    }
  }
}
