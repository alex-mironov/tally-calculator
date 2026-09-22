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
   Three schemes, from the design's Calculator.html: Lime (dark-only, the
   default), Blue and Violet.
   */
  public static let all: [Accent] = [
    Accent(
      name: "Lime", accent: "#e8ff77", accentDark: "#e8ff77",
      softLight: "#e8ff77", softDark: "#3a4410", inkLight: "#1e2400", inkDark: "#e8ff77",
      onAccent: "#171719", onAccentDark: "#171719", solid: "#566b00", darkOnly: true),
    Accent(
      name: "Blue", accent: "#2f6fe4", accentDark: "#a8cdf8",
      softLight: "#d6e6fb", softDark: "#17283f", inkLight: "#1d4fb0", inkDark: "#bcd9fb",
      onAccent: "#ffffff", onAccentDark: "#0b1d3a", solid: "#1d4fb0", darkOnly: false),
    Accent(
      name: "Violet", accent: "#6b6bf0", accentDark: "#a3a3ff",
      softLight: "#e0e0ff", softDark: "#26264a", inkLight: "#4a4ac9", inkDark: "#c2c2ff",
      onAccent: "#ffffff", onAccentDark: "#15153a", solid: "#4a4ac9", darkOnly: false),
  ]

  public static var `default`: Accent { all[0] }

  /**
   Accents the app used to ship, mapped onto their nearest replacement so a
   device that already stored one doesn't silently drop back to the default.

   Nothing maps onto Lime, even Amber, its nearest hue: Lime forces the dark
   palette, and an update should not switch a light-theme user to dark behind
   their back. Safe to delete once no install can still hold these.
   */
  static let legacy: [String: String] = [
    // The six-accent palette.
    "#0a7aff": "#2f6fe4",  // Blue     → Blue
    "#dd1b80": "#6b6bf0",  // Magenta  → Violet
    "#00c2a0": "#2f6fe4",  // Teal     → Blue
    "#6b00d0": "#6b6bf0",  // Purple   → Violet
    "#e6b800": "#2f6fe4",  // Amber    → Blue
    "#4a5560": "#2f6fe4",  // Graphite → Blue
    // The raspberry family before it.
    "#b3476a": "#6b6bf0",  // Raspberry → Violet
    "#c33a6e": "#6b6bf0",  // Magenta   → Violet
    "#864a7a": "#6b6bf0",  // Plum      → Violet
    "#9c3a48": "#6b6bf0",  // Wine      → Violet
    "#2a2420": "#2f6fe4",  // Ink       → Blue
  ]

  /// A stored accent hex → its token, forgiving a palette the app has retired.
  public static func resolve(_ hex: String) -> Accent {
    let key = legacy[hex] ?? hex
    return all.first { $0.accent == key } ?? .default
  }
}
