// Accents.swift — the accent palette, as data.
//
// Colours live here rather than in the app target because the *store* needs
// them: a persisted accent hex has to be resolved on hydration, including hexes
// from palettes the app has since retired. TallyKit stays UI-free, so these are
// hex strings; turning them into `Color` is the app layer's job.
//
// Ported from mobile/src/constants/tokens.ts.
import Foundation

/// Which of the two palettes the app is drawing in. The app picks its own
/// rather than following the system, so this is stored, not sensed.
public enum ThemeMode: String, Codable, CaseIterable, Sendable {
  case light, dark
}

/**
 One interchangeable colour scheme.

 The soft and ink shades are derived from the hue rather than hand-picked: same
 hue, lightness walked until it clears 4.5:1 on the surfaces it lands on. That
 is why `ink` exists at all — the hue itself cannot promise contrast as a
 foreground. Bright hues are fills.

 A scheme can carry a second hue for the dark palette (`accentDark`), because a
 hue tuned for a light screen goes muddy on a dark one, and can be dark-only:
 Lime is a highlighter, and there is no light screen it reads on.
 */
public struct Accent: Equatable, Hashable, Sendable, Identifiable {
  public let name: String
  /// The hue itself, on the light palette — and the scheme's stored identity.
  /// A *fill*: swatches, solid chips, tinted containers.
  public let accent: String
  /// The hue on the dark palette.
  public let accentDark: String
  /// Tinted surface behind accent-coloured content (chips, pills, the bloom).
  public let softLight: String
  public let softDark: String
  /// The readable shade — every accent-coloured word, glyph and hairline.
  public let inkLight: String
  public let inkDark: String
  /// Foreground for content sitting *on* the solid accent fill.
  public let onAccent: String
  public let onAccentDark: String
  /// The shade a system control's own white label always reads on, in either
  /// palette — a prominent button, a segmented picker's selected segment.
  public let solid: String
  /// The scheme forces the dark palette, whatever the theme setting says.
  public let darkOnly: Bool

  public var id: String { accent }

  /// The palette this scheme actually draws in, given the user's theme choice.
  public func mode(_ chosen: ThemeMode) -> ThemeMode { darkOnly ? .dark : chosen }

  public func hue(_ mode: ThemeMode) -> String { mode == .dark ? accentDark : accent }
  public func soft(_ mode: ThemeMode) -> String { mode == .dark ? softDark : softLight }
  public func ink(_ mode: ThemeMode) -> String { mode == .dark ? inkDark : inkLight }
  public func on(_ mode: ThemeMode) -> String { mode == .dark ? onAccentDark : onAccent }
}

extension Accent {
  /**
   Three schemes, from the design's Calculator.html ("Refined" set): Lime
   (dark-only, the default), Blue and Violet. One OKLCH recipe per role, only
   the hue varies — fill L.55 C.19 (white text ≥4.9:1), dark fill L.80 C.12,
   soft L.94 / .29, ink L.45 / .88.
   */
  public static let all: [Accent] = [
    Accent(
      name: "Lime", accent: "#d2fc4a", accentDark: "#d2fc4a",
      softLight: "#d2fc4a", softDark: "#2a3505", inkLight: "#283300", inkDark: "#d2fc4a",
      onAccent: "#1a1a19", onAccentDark: "#1a1a19", solid: "#5d7300", darkOnly: true),
    Accent(
      name: "Blue", accent: "#156cdd", accentDark: "#96c0fe",
      softLight: "#e0ecfe", softDark: "#172b49", inkLight: "#0150af", inkDark: "#c0d9fe",
      onAccent: "#ffffff", onAccentDark: "#0b1f3b", solid: "#0150af", darkOnly: false),
    Accent(
      name: "Violet", accent: "#6b58d9", accentDark: "#b6b4fe",
      softLight: "#e9e9ff", softDark: "#292648", inkLight: "#503ead", inkDark: "#d3d3fe",
      onAccent: "#ffffff", onAccentDark: "#1d1a3a", solid: "#503ead", darkOnly: false),
  ]

  public static var `default`: Accent { all[0] }

  /**
   Accents the app used to ship, mapped onto their nearest replacement so a
   device that already stored one doesn't silently drop back to the default.

   Nothing else maps onto Lime, even Amber, its nearest hue: Lime forces the dark
   palette, and an update should not switch a light-theme user to dark behind
   their back. Safe to delete once no install can still hold these.
   */
  static let legacy: [String: String] = [
    // The same three schemes before the "Refined" retune.
    "#e8ff77": "#d2fc4a",  // Lime   → Lime
    "#2f6fe4": "#156cdd",  // Blue   → Blue
    "#6b6bf0": "#6b58d9",  // Violet → Violet
    // The six-accent palette.
    "#0a7aff": "#156cdd",  // Blue     → Blue
    "#dd1b80": "#6b58d9",  // Magenta  → Violet
    "#00c2a0": "#156cdd",  // Teal     → Blue
    "#6b00d0": "#6b58d9",  // Purple   → Violet
    "#e6b800": "#156cdd",  // Amber    → Blue
    "#4a5560": "#156cdd",  // Graphite → Blue
    // The raspberry family before it.
    "#b3476a": "#6b58d9",  // Raspberry → Violet
    "#c33a6e": "#6b58d9",  // Magenta   → Violet
    "#864a7a": "#6b58d9",  // Plum      → Violet
    "#9c3a48": "#6b58d9",  // Wine      → Violet
    "#2a2420": "#156cdd",  // Ink       → Blue
  ]

  /// A stored accent hex → its token, forgiving a palette the app has retired.
  public static func resolve(_ hex: String) -> Accent {
    let key = legacy[hex] ?? hex
    return all.first { $0.accent == key } ?? .default
  }
}
