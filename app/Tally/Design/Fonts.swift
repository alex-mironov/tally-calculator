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
// The React Native version capped scaling per call site
// (`maxFontSizeMultiplier`) because an unbounded multiplier pushed the draft
// line out of its 44pt box. `.custom(_:size:relativeTo:)` gives the same
// protection more honestly: the size scales with the user's setting against a
// named text style, and a call site that must not grow past its box asks for a
// fixed size instead — which is a decision worth having to write down.
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
  /// A Geist face at a fixed point size — for anything that must stay inside a
  /// box it was measured for (the draft line, a keypad key, a chip).
  static func tally(_ name: String, _ size: CGFloat) -> Font {
    .custom(name, fixedSize: size)
  }

  /// A Geist face that scales with Dynamic Type, relative to a system style.
  static func tally(_ name: String, _ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
    .custom(name, size: size, relativeTo: style)
  }
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
