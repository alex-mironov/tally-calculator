// SavedOverlay.swift — the archive on an iPad in portrait: a 360pt panel slid
// in from the leading edge over a scrim (tally-app-v2.jsx, the portrait
// `savedOpen` panel).
//
// Portrait has no room for a permanent column beside a calculator worth using,
// and a push would throw the whole window away to show a list a third of its
// width. So the archive comes over the calculator and goes again: tap the scrim,
// or open or start a calculation, and it is gone — the calculator never moved.
//
// Not a sheet or a popover: neither comes from the leading edge, and a popover
// has an arrow pointing at a button the design does not draw it from.
import SwiftUI

struct SavedOverlay: View {
  @Binding var isOpen: Bool

  @Environment(\.theme) private var t

  /// The design's panel width.
  private static let width: CGFloat = 360

  var body: some View {
    // The panel is a surface over the screen, so on Midnight it takes the
    // sheet's raised palette: black on black would have no edge.
    let s = t.sheet

    ZStack(alignment: .leading) {
      if isOpen {
        // Heavier on the dark scheme, where a light veil over black barely
        // reads as one.
        Color.black.opacity(t.isDark ? 0.6 : 0.26)
          .ignoresSafeArea()
          .contentShape(.rect)
          .onTapGesture(perform: close)
          .accessibilityLabel("Close saved calculations")
          .accessibilityAddTraits(.isButton)
          .transition(.opacity)

        NavigationStack {
          SavedScreen(placement: .overlay, close: close)
            .tallyRoutes()
        }
        .environment(\.theme, s)
        .frame(width: Self.width)
        // The design's `20px 0 60px -30px` shadow, cast across the scrim
        // towards the calculator — the spread folded into the blur, as Lift
        // does.
        .background {
          s.screen
            .ignoresSafeArea()
            .shadow(color: .black.opacity(0.5), radius: 16, x: 20)
        }
        .accessibilityAction(.escape, close)
        .transition(.move(edge: .leading))
      }
    }
    // The design's ease-out curve, over 0.32s, for the panel and its scrim.
    .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.32), value: isOpen)
  }

  private func close() { isOpen = false }
}
