// Fonts.swift — the app's typefaces.
//
// The whole app runs on Geist:
//   · serif → Geist Medium (display headings — the old serif role)
//   · sans  → Geist         (UI text)
//   · mono  → Geist Mono    (numbers and labels)
//
// Geist rather than the design's System (SF) and Spline Sans Mono is a
// deliberate divergence, carried over from the React Native build. With a
// custom family the weight is carried by the file, not by a `.weight()`
// modifier, so there is one entry per weight actually used.
//
// ── Dynamic Type ────────────────────────────────────────────────────────────
// Every Geist face scales with the user's text size by default. The size a
// call site passes is the size at the default setting, so at that setting
// nothing changes; each size is paired with the system text style nearest it,
// which decides how steeply it grows (a large title grows less than body text).
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

enum TallyFont {
  static let serif = "Geist-Medium"

  static let sans = "Geist-Regular"
  static let sansMedium = "Geist-Medium"
  static let sansSemi = "Geist-SemiBold"
  static let sansBold = "Geist-Bold"

  static let mono = "GeistMono-Regular"
  static let monoMedium = "GeistMono-Medium"
  static let monoSemi = "GeistMono-SemiBold"

  /// Every family name bundled, for the start-up assertion below.
  static let allFamilies = [
    serif, sans, sansMedium, sansSemi, sansBold, mono, monoMedium, monoSemi,
  ]
}

extension Font {
  /// A Geist face that scales with Dynamic Type. `size` is the size at the
  /// default text setting; it grows along the curve of the nearest system style.
  static func tally(_ name: String, _ size: CGFloat) -> Font {
    .custom(name, size: size, relativeTo: TallyFont.style(nearest: size))
  }

  /// A Geist face that scales with Dynamic Type along a named style's curve.
  static func tally(_ name: String, _ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
    .custom(name, size: size, relativeTo: style)
  }
}

extension TallyFont {
  /// The system text style whose default size is nearest `size`, and so whose
  /// growth curve a Geist face of that size should follow.
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

#if DEBUG
  extension TallyFont {
    /**
     Assert at launch that every bundled face actually registered.

     A missing face is not a crash — iOS silently substitutes one, and the app
     renders in something that is nearly right. The React Native build hid this
     class of bug behind a splash screen held until `useFonts` resolved; here
     nothing holds the launch, so the check has to be explicit.
     */
    static func assertAvailable() {
      let registered = Set(
        UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) })
      let missing = allFamilies.filter { !registered.contains($0) }
      assert(
        missing.isEmpty,
        """
        Geist faces missing from the bundle: \(missing.joined(separator: ", ")).
        iOS substitutes silently, so the app would render in a near-miss
        typeface. Check UIAppFonts in Info.plist and Resources/Fonts.
        """)
    }
  }
#endif
