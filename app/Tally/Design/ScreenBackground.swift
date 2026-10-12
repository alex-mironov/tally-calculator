// ScreenBackground.swift — the flat screen colour behind every screen.
//
// This used to be the accent "bloom": two radial washes of the accent off the
// top-right and bottom-left corners. Calculator v2 retires it — one mood colour
// fills the screen, and colour is never sprinkled on top — so all that is left
// is `t.screen`, edge to edge.
//
// Kept as a view rather than inlined at its call sites so that every screen
// still asks for its background in one way, and whatever v2 does to the screen
// later happens here once.
import SwiftUI
import TallyKit

struct ScreenBackground: View {
  @Environment(\.theme) private var t

  var body: some View {
    t.screen
      .ignoresSafeArea()
      .allowsHitTesting(false)
  }
}

#Preview("Every scheme") {
  VStack(spacing: 0) {
    ForEach(Scheme.all) { scheme in
      let theme = Theme.resolve(scheme: scheme)
      ScreenBackground()
        .environment(\.theme, theme)
        .frame(height: 120)
        .overlay(alignment: .topLeading) {
          Text(scheme.name)
            .tallyFont(TallyFont.mono, TextScale.label)
            .foregroundStyle(theme.ink2)
            .padding(Space.s2)
        }
    }
  }
}
