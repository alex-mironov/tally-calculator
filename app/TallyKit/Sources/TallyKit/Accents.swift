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
 One interchangeable accent.

 The soft and ink shades are derived from the hue rather than hand-picked: same
 hue, lightness walked until it clears 4.5:1 on the surfaces it lands on. That
 is why `ink` exists at all — once the palette includes a teal and an amber, the
 hue itself cannot promise contrast as a foreground. Bright hues are fills.
 */
public struct Accent: Equatable, Hashable, Sendable, Identifiable {
  public let name: String
  /// The hue itself. A *fill*: swatches, solid chips, tinted containers.
  public let accent: String
  /// Tinted surface behind accent-coloured content (chips, pills, the bloom).
  public let softLight: String
  public let softDark: String
  /// The readable shade — every accent-coloured word, glyph and hairline.
  public let inkLight: String
  public let inkDark: String
  /// Foreground for content sitting *on* the solid accent fill.
  public let onAccent: String

  public var id: String { accent }

  public func soft(_ mode: ThemeMode) -> String { mode == .dark ? softDark : softLight }
  public func ink(_ mode: ThemeMode) -> String { mode == .dark ? inkDark : inkLight }
}

extension Accent {
  /**
   Six interchangeable accents (blue → magenta → teal → purple → amber →
   graphite). Blue is the default.
   */
  public static let all: [Accent] = [
    Accent(name: "Blue", accent: "#0a7aff", softLight: "#d0e4fb", softDark: "#0c2645", inkLight: "#005fd1", inkDark: "#338efa", onAccent: "#ffffff"),
    Accent(name: "Magenta", accent: "#dd1b80", softLight: "#f6d5e6", softDark: "#3f122a", inkLight: "#b81268", inkDark: "#e654a0", onAccent: "#ffffff"),
    Accent(name: "Teal", accent: "#00c2a0", softLight: "#d0fbf4", softDark: "#0c453b", inkLight: "#007b65", inkDark: "#05bd9d", onAccent: "#0c312b"),
    Accent(name: "Purple", accent: "#6b00d0", softLight: "#e6d0fb", softDark: "#2a0c45", inkLight: "#6b00d0", inkDark: "#ad5afb", onAccent: "#ffffff"),
    Accent(name: "Amber", accent: "#e6b800", softLight: "#fbf3d0", softDark: "#453a0c", inkLight: "#856a00", inkDark: "#e0b506", onAccent: "#312a0c"),
    Accent(name: "Graphite", accent: "#4a5560", softLight: "#e3e6e8", softDark: "#25292c", inkLight: "#495561", inkDark: "#8592a0", onAccent: "#ffffff"),
  ]

  public static var `default`: Accent { all[0] }

  /**
   Accents the app used to ship (the raspberry family), mapped onto their
   nearest replacement so a device that already stored one doesn't silently drop
   back to the default. Safe to delete once no install can still hold these.
   */
  static let legacy: [String: String] = [
    "#b3476a": "#dd1b80",  // Raspberry → Magenta
    "#c33a6e": "#dd1b80",  // Magenta   → Magenta
    "#864a7a": "#6b00d0",  // Plum      → Purple
    "#9c3a48": "#dd1b80",  // Wine      → Magenta
    "#2a2420": "#4a5560",  // Ink       → Graphite
  ]

  /// A stored accent hex → its token, forgiving a palette the app has retired.
  public static func resolve(_ hex: String) -> Accent {
    let key = legacy[hex] ?? hex
    return all.first { $0.accent == key } ?? .default
  }
}
