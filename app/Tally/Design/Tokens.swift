// Tokens.swift — Tally Design System v2: the spatial, type, radius and
// elevation scales. Colour is the scheme's (Theme.swift). Transcribed from mobile/src/constants/tokens.ts, keeping
// the names, so the handoff and the code still share one vocabulary.
//
// Notes on fidelity, carried over from the original:
//   • Every spacing and metric in the app sits on the 4pt grid — padding,
//     margins, gaps, icon point sizes, corner radii, control dimensions. Where
//     an off-grid number is unavoidable it needs a comment saying which system
//     constant it is cancelling.
//   • Two things are outside the grid by design: the type scale, which is its
//     own progression (13.5pt note text is deliberate), and the elevation
//     shadows, whose radii and offsets are not layout quantities.
//   • The families are Geist / Geist Mono rather than the design's System (SF)
//     and Spline Sans Mono — a deliberate divergence. See Fonts.swift.
import SwiftUI

/// Type scale — size in points. Hierarchy leans on weight, not size.
enum TextScale {
  static let displayXl: CGFloat = 34  // hero statement
  static let displayLg: CGFloat = 28  // screen title (≈ iOS Large Title)
  static let displayMd: CGFloat = 20  // tab name
  static let numXl: CGFloat = 36  // live draft amount — mono
  static let numLg: CGFloat = 22  // running total — mono
  static let bodyLg: CGFloat = 16  // primary body / note
  static let bodyMd: CGFloat = 14  // default UI text
  static let bodySm: CGFloat = 13  // secondary / buttons
  static let caption: CGFloat = 12  // chips, fine print
  static let label: CGFloat = 11  // mono eyebrow / meta (uppercase, tracked)
  static let labelSm: CGFloat = 10  // mono micro-label
  static let micro: CGFloat = 9  // badges
}

/// Letter spacing. `label` and `eyebrow` are ems — multiply by the font size.
enum Tracking {
  static let tight = -0.02  // display, as a ratio of font size
  static let label = 0.14  // mono labels (em)
  static let eyebrow = 0.22  // mono eyebrows (em)

  /// An em value at a given size, which is what SwiftUI's `.tracking` wants.
  static func pt(_ em: Double, at size: CGFloat) -> CGFloat { CGFloat(em) * size }
}

/// Spacing — the 4pt grid.
enum Space {
  static let s0: CGFloat = 0
  static let s1: CGFloat = 4
  static let s2: CGFloat = 8
  static let s3: CGFloat = 12
  static let s4: CGFloat = 16
  static let s5: CGFloat = 20
  static let s6: CGFloat = 24
  static let s7: CGFloat = 28
  static let s8: CGFloat = 32
  static let s10: CGFloat = 40
  static let s12: CGFloat = 48
}

/// Corner radii, on the same 4pt grid.
enum Radius {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 24  // glass cards / keypad keys
  /// Fully rounded. In SwiftUI this is `Capsule()`, not a number — kept for
  /// the places that still take a radius.
  static let pill: CGFloat = 999
}

/**
 Elevation — the three lifts the design uses.

 `glass` is the floating card lift, `cta` the tinted press under a deep-ink
 button (the caller supplies the colour), `pop` the popover float. The React
 Native version spread these as shadow props; here they are a modifier, so the
 call sites read the same but the numbers live in one place.

 `glass` is the scheme's own `shadow`, so it is read from the theme rather
 than fixed here: a lift tuned for a white card on Lilac is wrong on Midnight.
 */
enum Elevation {
  case glass, cta(Color), pop

  func lift(in t: Theme) -> Lift {
    switch self {
    case .glass: return t.shadow
    case .cta(let tint): return Lift(color: tint.opacity(0.40), radius: 16, y: 6)
    case .pop: return Lift(color: Color(hex: "#0c0c14").opacity(0.42), radius: 30, y: 18)
    }
  }
}

extension View {
  func elevation(_ e: Elevation) -> some View {
    modifier(ElevationModifier(elevation: e))
  }
}

private struct ElevationModifier: ViewModifier {
  @Environment(\.theme) private var t
  let elevation: Elevation

  func body(content: Content) -> some View {
    content.shadow(elevation.lift(in: t))
  }
}

// MARK: - Hex colours

extension Color {
  /**
   A `#rrggbb` (or `#rrggbbaa`) string, as the design tokens spell them.

   Kept because the palette crosses a boundary: `TallyKit.Scheme` stores hex so
   the store can resolve and migrate a persisted scheme without depending on
   SwiftUI. This is where those strings become colours.
   */
  init(hex: String) {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    let r: Double
    let g: Double
    let b: Double
    var a: Double = 1
    switch s.count {
    case 8:
      r = Double((v >> 24) & 0xff) / 255
      g = Double((v >> 16) & 0xff) / 255
      b = Double((v >> 8) & 0xff) / 255
      a = Double(v & 0xff) / 255
    default:
      r = Double((v >> 16) & 0xff) / 255
      g = Double((v >> 8) & 0xff) / 255
      b = Double(v & 0xff) / 255
    }
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
  }
}
