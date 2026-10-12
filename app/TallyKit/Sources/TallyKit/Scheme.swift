// Scheme.swift — the four colour schemes, as data.
//
// Calculator v2 ("tonal monochrome") replaces the accent × light/dark grid with
// four whole schemes. Each one is a mood colour that fills the screen plus the
// handful of tones the rest of the app is drawn in; colour is never sprinkled
// on top. The scheme also decides darkness — only Midnight is dark — so there
// is no separate theme setting any more.
//
// Hex strings rather than `Color`, for the same reason as Accents.swift: the
// store resolves a persisted scheme, and migrates an older build's accent and
// theme onto one, below the UI. Turning these into colours is Theme.swift's job.
//
// Transcribed from the design's tally-app-v2.jsx (`SCHEMES`), keeping its
// token names so the handoff and the code share one vocabulary. Translucent
// tokens are spelled with `rgba(…)` exactly as the design writes them and
// packed into `#rrggbbaa` here, so the source values stay checkable by eye.
import Foundation

public struct Scheme: Equatable, Hashable, Sendable, Identifiable {

  /// The scheme's persisted identity. The raw value is what `tally:scheme`
  /// holds, so it is a compatibility surface: never rename a case.
  public enum ID: String, Codable, CaseIterable, Sendable {
    case midnight, lilac, sand, paper
  }

  /// A CSS `box-shadow`, kept in the design's own terms. SwiftUI has no
  /// spread, so the app layer decides how to approximate one.
  public struct Shadow: Equatable, Hashable, Sendable {
    public let color: String
    public let y: Double
    public let blur: Double
    public let spread: Double
  }

  /// The raised surface a sheet presents on. Only a dark scheme needs one:
  /// a sheet the same black as the screen behind it has no edge.
  public struct Elevated: Equatable, Hashable, Sendable {
    public let screen: String
    public let card: String
    public let field: String
    public let line: String
  }

  public let id: ID
  public let name: String
  public let isDark: Bool
  /// What the scheme looks like as one dot in Settings. Not always `screen`:
  /// Paper's screen is white, which would vanish on a white row.
  public let swatch: String

  // The canvas
  public let screen: String
  public let ink: String
  public let ink2: String
  public let line: String
  /// The inverted surface — a position circle, a solid badge.
  public let deep: String
  public let deepInk: String

  // Tonal fills
  public let pill: String
  public let pillInk: String
  public let chip: String
  public let chipInk: String

  // The dock and its keys
  public let dock: String
  public let dockInk: String
  public let dockInk2: String
  public let dockLine: String
  /// A plain key's fill while the finger is on it.
  public let keyPress: String
  /// Operator keys — tonal, a step off the dock.
  public let op: String
  public let opInk: String
  /// The one call to action: ↵, Save, the editing ring.
  public let cta: String
  public let ctaInk: String

  // Grouped surfaces
  public let card: String
  public let field: String
  public let rowSel: String
  /// The soft tint behind accent-coloured content (a tag chip, the draft card).
  public let chipBg: String
  /// Text and glyphs in the scheme's accent role.
  public let accentText: String

  // Floating chrome
  public let glass: String
  public let glassBrd: String
  public let glassHi: String
  public let shadow: Shadow
  /// The dock's own lift. Nil where the design gives it none — on Midnight
  /// and Paper the dock is set apart by tone alone.
  public let dockShadow: Shadow?

  /// The sheet surface, where it differs from the screen's own.
  public let elevated: Elevated?
}

// MARK: - The four

extension Scheme {

  public static let midnight = Scheme(
    id: .midnight, name: "Midnight", isDark: true, swatch: "#111111",
    screen: "#000000", ink: "#ffffff", ink2: "#9d9da3", line: "#1f1f22",
    deep: "#cbd5e3", deepInk: "#0a0a0a",
    pill: "#ffffff", pillInk: "#0a0a0a", chip: "#1c1c1e", chipInk: "#ffffff",
    dock: "#1c1c1e", dockInk: "#ffffff", dockInk2: "#9d9da3", dockLine: "#3a3a3d",
    keyPress: "#2f2f33",
    op: "#cbd5e3", opInk: "#0a0a0a", cta: "#e6fc7c", ctaInk: "#0a0a0a",
    card: "#1c1c1e", field: "#26262a", rowSel: rgba(255, 255, 255, 0.06),
    chipBg: "#2a3140", accentText: "#cbd5e3",
    glass: rgba(38, 38, 41, 0.74), glassBrd: rgba(255, 255, 255, 0.08),
    glassHi: rgba(255, 255, 255, 0.08),
    shadow: Shadow(color: rgba(0, 0, 0, 0.8), y: 12, blur: 32, spread: -14),
    dockShadow: nil,
    // The iPad form sheet's raised set (tally-app-v2.jsx, `tSheet`).
    elevated: Elevated(screen: "#1c1c1e", card: "#2c2c2e", field: "#3a3a3c", line: "#38383a"))

  public static let lilac = Scheme(
    id: .lilac, name: "Lilac", isDark: false, swatch: "#e3abe2",
    screen: "#e3abe2", ink: "#1f0d1d", ink2: "#5e2e5a", line: rgba(94, 46, 90, 0.16),
    deep: "#5e2a59", deepInk: "#fbe8fa",
    pill: "#ffffff", pillInk: "#1f0d1d", chip: rgba(255, 255, 255, 0.55), chipInk: "#1f0d1d",
    dock: "#ffffff", dockInk: "#1f0d1d", dockInk2: "#8b6688", dockLine: "#ecd9eb",
    keyPress: "#f6e6f5",
    op: "#f4dff3", opInk: "#5e2a59", cta: "#5e2a59", ctaInk: "#ffffff",
    card: "#ffffff", field: "#f6e9f5", rowSel: rgba(94, 46, 90, 0.08),
    chipBg: "#f4dff3", accentText: "#5e2a59",
    glass: rgba(255, 255, 255, 0.72), glassBrd: rgba(255, 255, 255, 0.85),
    glassHi: rgba(255, 255, 255, 0.7),
    shadow: Shadow(color: rgba(60, 20, 55, 0.35), y: 12, blur: 30, spread: -16),
    dockShadow: Shadow(color: rgba(60, 20, 55, 0.45), y: 18, blur: 40, spread: -24),
    elevated: nil)

  public static let sand = Scheme(
    id: .sand, name: "Sand", isDark: false, swatch: "#f3e5cf",
    screen: "#f3e5cf", ink: "#1d160e", ink2: "#6b5a44", line: rgba(74, 55, 30, 0.13),
    deep: "#1d160e", deepInk: "#f3e5cf",
    pill: "#ffffff", pillInk: "#1d160e", chip: "#e6d3b5", chipInk: "#1d160e",
    dock: "#ffffff", dockInk: "#1d160e", dockInk2: "#857259", dockLine: "#efe4d3",
    keyPress: "#f7efe3",
    op: "#f1e5d2", opInk: "#1d160e", cta: "#1d160e", ctaInk: "#ffffff",
    card: "#ffffff", field: "#f8f0e4", rowSel: rgba(74, 55, 30, 0.07),
    chipBg: "#e6d3b5", accentText: "#4a3a24",
    glass: rgba(255, 255, 255, 0.72), glassBrd: rgba(255, 255, 255, 0.85),
    glassHi: rgba(255, 255, 255, 0.7),
    shadow: Shadow(color: rgba(60, 40, 15, 0.3), y: 12, blur: 30, spread: -16),
    dockShadow: Shadow(color: rgba(60, 40, 15, 0.4), y: 18, blur: 40, spread: -24),
    elevated: nil)

  public static let paper = Scheme(
    id: .paper, name: "Paper", isDark: false, swatch: "#dcdce0",
    screen: "#ffffff", ink: "#0b0b0c", ink2: "#6b6b70", line: "#efeff1",
    deep: "#0b0b0c", deepInk: "#ffffff",
    pill: "#f2f2f3", pillInk: "#0b0b0c", chip: "#f2f2f3", chipInk: "#0b0b0c",
    dock: "#f4f4f5", dockInk: "#0b0b0c", dockInk2: "#6b6b70", dockLine: "#e2e2e5",
    keyPress: "#e6e6e9",
    op: "#ffffff", opInk: "#0b0b0c", cta: "#0b0b0c", ctaInk: "#ffffff",
    card: "#f4f4f5", field: "#f4f4f5", rowSel: rgba(0, 0, 0, 0.04),
    chipBg: "#ececee", accentText: "#0b0b0c",
    glass: rgba(244, 244, 245, 0.82), glassBrd: rgba(255, 255, 255, 0.9),
    glassHi: rgba(255, 255, 255, 0.8),
    shadow: Shadow(color: rgba(0, 0, 0, 0.22), y: 12, blur: 30, spread: -16),
    dockShadow: nil,
    elevated: nil)

  /// In the order Settings lays them out.
  public static let all: [Scheme] = [.midnight, .lilac, .sand, .paper]

  /// What a fresh install draws in.
  public static var `default`: Scheme { .midnight }

  public static func named(_ id: ID) -> Scheme {
    all.first { $0.id == id } ?? .default
  }

  /// The design's `rgba(r, g, b, a)`, as the `#rrggbbaa` the app's hex parser
  /// reads.
  static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> String {
    let alpha = Int((a * 255).rounded())
    return String(format: "#%02x%02x%02x%02x", r, g, b, alpha)
  }
}

// MARK: - The bridge to the accent era

extension Scheme {
  /**
   The scheme an older build's stored accent and theme land on, when no scheme
   has been stored yet.

   Lime, or anything drawn dark, becomes Midnight — the one dark scheme. In
   light, the Violet family (retired hexes included, via `Accent.resolve`)
   becomes Lilac, its nearest mood, and Blue becomes Paper: Blue was the
   neutral pick, and Paper is the neutral scheme. Nothing stored at all
   resolves through the old default, Lime, and so also lands on Midnight.
   */
  public static func migrating(accent hex: String?, mode: ThemeMode?) -> Scheme {
    let accent = hex.map(Accent.resolve) ?? .default
    // The old store's default theme was light; `Accent.mode` then applies
    // Lime's dark-only rule, exactly as the old Theme did.
    guard accent.mode(mode ?? .light) == .light else { return .midnight }
    return accent.name == "Violet" ? .lilac : .paper
  }

  /**
   The accent this scheme is written back as, for the two places that still
   speak accents: `tally:config`, which an older build on the user's other
   device reads, and the frozen share API, which takes an accent hex.

   Sand has no counterpart of its own, so it shares Paper's Blue.
   */
  public var legacyAccent: Accent {
    switch id {
    case .midnight: return Accent.all.first { $0.name == "Lime" } ?? .default
    case .lilac: return Accent.all.first { $0.name == "Violet" } ?? .default
    case .sand, .paper: return Accent.all.first { $0.name == "Blue" } ?? .default
    }
  }

  /// The theme written back beside `legacyAccent`.
  public var legacyMode: ThemeMode { isDark ? .dark : .light }
}
