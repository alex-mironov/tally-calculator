// Fonts.swift — the app's typefaces.
//
// The whole app runs on the system font, SF Pro — Calculator v2's own "SF Pro"
// option (docs/v2-design.md, "Fonts"). Nothing is bundled. v2 names three
// families, and here they are three roles over the one typeface:
//
//   · text    → SF, proportional figures          (v2 `--font-ui`: UI text)
//   · display → SF, tabular figures               (v2 `--font-display`, the
//               design's Urbanist slot: keys, the total, the draft, amounts,
//               row badges)
//   · mono    → SF, tabular figures               (v2 `--font-mono`, which is
//               the system font plus tabular-nums: labels, workings, tags)
//
// `display` and `mono` resolve to the same face today. They are kept apart
// because the design keeps them apart: a later restyle reads the role off the
// design and picks the name, and if the display role ever gets a face of its own
// again the call sites already say which numbers it covers.
//
// The weights are the design's. Where v2 sets Urbanist, the display weight is
// the one it gives Urbanist (keys 400, total 500, draft 400, amounts 500).
//
// Geist and Geist Mono, which the app used up to v2, are retired. Bundling
// Urbanist for the display role was considered and declined.
//
// ── Dynamic Type ────────────────────────────────────────────────────────────
// Every face scales with the user's text size by default. The size a call site
// passes is the size at the default setting, so at that setting nothing changes;
// each size is paired with the system text style nearest it, which decides how
// steeply it grows (a large title grows less than body text).
//
// SwiftUI has no `Font.system(size:relativeTo:)` — only custom fonts get that
// initialiser — so `.tallyFont` is a view modifier that does the scaling itself:
// it reads `dynamicTypeSize` from the environment and asks UIFontMetrics what
// the style's curve makes of the size. Reading the *environment* rather than the
// app-wide setting is what keeps the caps below working.
//
// Regions with fixed geometry — the 44pt draft line, the 48pt keys, the total
// bar — cap the growth at the *container*, with `.dynamicTypeSize(...)`. That
// is the SwiftUI counterpart of the React Native build's per-call-site
// `maxFontSizeMultiplier`, and it uses the same limits (see `TypeCap`).
//
// The first version of this file got the default backwards: fixed sizes
// everywhere, with scaling as the opt-in. Fifty call sites were fixed and two
// scaled, which quietly made the app *less* accessible than the React Native
// build it replaced — that one scaled almost everything, with caps.
import SwiftUI
import UIKit

/// One face of the system font: a weight, and whether its figures are tabular.
struct TallyFace: Hashable {
  let weight: Font.Weight
  /// Tabular (fixed-width) figures, so a column of amounts lines up and a
  /// number does not shift sideways as its digits change.
  let tabular: Bool

  func font(size: CGFloat) -> Font {
    let font = Font.system(size: size, weight: weight)
    return tabular ? font.monospacedDigit() : font
  }
}

enum TallyFont {
  // UI text — v2's `--font-ui`.
  static let text = TallyFace(weight: .regular, tabular: false)
  static let textMedium = TallyFace(weight: .medium, tabular: false)
  static let textSemi = TallyFace(weight: .semibold, tabular: false)
  static let textBold = TallyFace(weight: .bold, tabular: false)

  // Numbers that carry the screen — v2's `--font-display` (Urbanist in the
  // design). Keys and the draft are `display`; the total and amounts are
  // `displayMedium`; the row's position badge is `displaySemi`.
  static let display = TallyFace(weight: .regular, tabular: true)
  static let displayMedium = TallyFace(weight: .medium, tabular: true)
  static let displaySemi = TallyFace(weight: .semibold, tabular: true)

  // Labels, workings and tags — v2's `--font-mono`, which is the system font
  // with tabular figures, not a monospaced face.
  static let mono = TallyFace(weight: .regular, tabular: true)
  static let monoMedium = TallyFace(weight: .medium, tabular: true)
  static let monoSemi = TallyFace(weight: .semibold, tabular: true)
}

extension View {
  /// A Tally face that scales with Dynamic Type. `size` is the size at the
  /// default text setting; it grows along the curve of `style`, or of the system
  /// style nearest `size` when none is given.
  func tallyFont(
    _ face: TallyFace, _ size: CGFloat, relativeTo style: Font.TextStyle? = nil
  ) -> some View {
    modifier(
      TallyFontModifier(face: face, size: size, style: style ?? TallyFont.style(nearest: size)))
  }
}

private struct TallyFontModifier: ViewModifier {
  let face: TallyFace
  let size: CGFloat
  let style: Font.TextStyle

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    content.font(face.font(size: TallyFont.scaled(size, along: style, at: dynamicTypeSize)))
  }
}

extension TallyFont {
  /// The system text style whose default size is nearest `size`, and so whose
  /// growth curve a face of that size should follow.
  static func style(nearest size: CGFloat) -> Font.TextStyle {
    switch size {
    case ..<11.5: return .caption2  // 11
    case ..<12.75: return .caption  // 12
    case ..<13.75: return .footnote  // 13
    case ..<15.5: return .subheadline  // 15
    case ..<16.5: return .callout  // 16
    case ..<18.5: return .body  // 17
    case ..<21: return .title3  // 20
    case ..<25: return .title2  // 22
    case ..<31: return .title  // 28
    default: return .largeTitle  // 34
    }
  }

  /// `size` at the default text setting, grown the way `style` grows at
  /// `dynamicTypeSize` — what `Font.custom(_:size:relativeTo:)` does for a
  /// custom face.
  static func scaled(
    _ size: CGFloat, along style: Font.TextStyle, at dynamicTypeSize: DynamicTypeSize
  ) -> CGFloat {
    let traits = UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
    return UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size, compatibleWith: traits)
  }
}

extension Font.TextStyle {
  fileprivate var uiKit: UIFont.TextStyle {
    switch self {
    case .largeTitle: return .largeTitle
    case .title: return .title1
    case .title2: return .title2
    case .title3: return .title3
    case .headline: return .headline
    case .subheadline: return .subheadline
    case .body: return .body
    case .callout: return .callout
    case .footnote: return .footnote
    case .caption: return .caption1
    case .caption2: return .caption2
    @unknown default: return .body
    }
  }
}

/**
 How far a fixed-geometry region may grow, applied at the container with
 `.dynamicTypeSize(...)`.

 The limits are the React Native build's `maxFontSizeMultiplier`s, mapped onto
 the nearest Dynamic Type sizes (xLarge is roughly ×1.1, xxLarge ×1.2, xxxLarge
 ×1.35 at body size).
 */
enum TypeCap {
  /// The draft line: a 44pt box, and the digits being typed must not clip.
  /// (RN: ×1.15.)
  static let draft = DynamicTypeSize.xLarge
  /// Keypad labels, inside 48pt keys. (RN: ×1.3.)
  static let keypad = DynamicTypeSize.xxLarge
  /// The entry card's chips and note field, and the total bar. (RN: ×1.4.)
  static let chrome = DynamicTypeSize.xxxLarge
}
