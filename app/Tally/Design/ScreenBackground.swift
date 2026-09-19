// ScreenBackground.swift — the signature accent "bloom" behind every screen:
// two radial washes of the accent over the flat screen colour, one off the
// top-right corner and one off the bottom-left.
//
// ── The one place the rewrite is plainly better ─────────────────────────────
// The design always specified radial gradients. React Native has none, so the
// original approximated each bloom with a corner-anchored *linear* gradient,
// fading to the same colour at zero alpha — fading to `transparent` would tint
// toward black and dirty the wash. It was a good approximation of the wrong
// shape.
//
// SwiftUI has `RadialGradient`, so this is simply what was asked for. The
// zero-alpha trick is kept, for exactly the same reason: `.clear` is
// transparent *black*, and interpolating toward it greys the bloom out.
import SwiftUI
import TallyKit

struct ScreenBackground: View {
  @Environment(\.theme) private var t

  var body: some View {
    GeometryReader { geo in
      let side = max(geo.size.width, geo.size.height)
      // Wash strength: ~0.4 alpha in light, ~0.22 in dark (the design's tint).
      let bloom = t.accent2.opacity(t.mode == .dark ? 0.22 : 0.40)
      let fade = t.accent2.opacity(0)

      ZStack {
        t.screen

        // Top-right, then bottom-left. Each reaches a little past its corner so
        // the brightest part of the wash sits off-screen and only its falloff
        // is drawn — which is what keeps it reading as light in the room
        // rather than as a circle on the page.
        RadialGradient(
          colors: [bloom, fade],
          center: UnitPoint(x: 0.95, y: -0.02),
          startRadius: 0,
          endRadius: side * 0.95
        )
        RadialGradient(
          colors: [bloom, fade],
          center: UnitPoint(x: 0.02, y: 1.02),
          startRadius: 0,
          endRadius: side * 0.85
        )
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

#Preview("Blooms, both palettes, every accent") {
  ScrollView {
    VStack(spacing: 0) {
      ForEach(Accent.all) { accent in
        HStack(spacing: 0) {
          ForEach([ThemeMode.light, .dark], id: \.self) { mode in
            let theme = Theme.resolve(mode: mode, accent: accent)
            ScreenBackground()
              .environment(\.theme, theme)
              .frame(height: 120)
              .overlay(alignment: .topLeading) {
                Text("\(accent.name) · \(mode.rawValue)")
                  .font(.tally(TallyFont.mono, TextScale.label))
                  .foregroundStyle(theme.ink2)
                  .padding(Space.s2)
              }
          }
        }
      }
    }
  }
}
