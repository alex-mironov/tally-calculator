// Theme.swift — the runtime palette: a neutral scale composed with the chosen
// accent. Transcribed from mobile/src/constants/tally-theme.ts, keeping every
// name, so `t.ink2` and `t.accentInk` still mean what the design doc says.
//
// ── What got simpler ────────────────────────────────────────────────────────
// The app picks its own palette rather than following the system. In React
// Native that was a JS-only notion, so anything the system presented — a sheet,
// an alert, a menu — arrived in the *system's* appearance and had to be forced
// back with `overrideUserInterfaceStyle` plus an opaque backdrop behind the
// SwiftUI content.
//
// Here the theme is the environment: `preferredColorScheme` on the root
// propagates into every sheet, popover and menu for free. That whole class of
// workaround does not exist in this project, and nothing should reintroduce it.
import SwiftUI
import TallyKit

/// The palette a screen draws with. Read from the environment as `\.theme`.
struct Theme: Equatable {
  // Neutrals
  var screen: Color
  var ink: Color
  var ink2: Color
  var ink3: Color
  var line: Color
  var card: Color
  var key: Color
  var keyLine: Color
  var deep: Color
  var deepInk: Color

  /// The running-total surface.
  var totalBg: Color
  var totalInk: Color
  var totalSub: Color
  /// A wash of the accent behind the row being edited.
  var rowSel: Color
  /// System red — a line whose expression can no longer be evaluated. Matches
  /// the red the native menus draw their destructive items in.
  var danger: Color

  // Accent
  /// The hue as a fill — swatches, solid chips, tinted containers.
  var accent: Color
  /// Soft tinted surface for accent-coloured content to sit on.
  var accent2: Color
  /// The readable shade: accent-coloured text, glyphs and hairlines.
  var accentInk: Color
  /// Foreground for content drawn on top of `accent`.
  var onAccent: Color
  /**
   The accent shade white always reads on, in either theme — for the system
   controls that draw their own white label over a tint (a prominent button, a
   segmented picker) and so cannot be handed a bright fill.
   */
  var accentSolid: Color

  /// Which palette this is, for the few places that need to know rather than
  /// just read a colour (the scroll-edge blooms, `preferredColorScheme`).
  var mode: ThemeMode

  var colorScheme: ColorScheme { mode == .dark ? .dark : .light }
}

extension Theme {
  /// Compose a neutral scale with the chosen accent.
  static func resolve(mode: ThemeMode, accent ac: Accent) -> Theme {
    let base = mode == .dark ? Neutral.dark : Neutral.light
    let dark = mode == .dark

    return Theme(
      screen: base.screen,
      ink: base.ink,
      ink2: base.ink2,
      ink3: base.ink3,
      line: base.line,
      card: base.card,
      key: base.key,
      keyLine: base.keyLine,
      deep: base.deep,
      deepInk: base.deepInk,

      // In dark the total bar takes the accent itself; in light it stays the
      // inverted neutral surface.
      totalBg: dark ? Color(hex: ac.accent) : base.deep,
      totalInk: dark ? Color(hex: ac.onAccent) : base.deepInk,
      totalSub: dark ? Color(hex: ac.onAccent).opacity(0.72) : Color(hex: "#a0a0a8"),

      // The selected row is a wash of the accent, so it has to follow it: the
      // readable shade in dark (where the raw hue disappears into the surface),
      // the hue itself in light.
      rowSel: dark
        ? Color(hex: ac.inkDark).opacity(0.13)
        : Color(hex: ac.accent).opacity(0.07),
      danger: Color(hex: dark ? "#ff453a" : "#ff3b30"),

      accent: Color(hex: ac.accent),
      accent2: Color(hex: ac.soft(mode)),
      accentInk: Color(hex: ac.ink(mode)),
      onAccent: Color(hex: ac.onAccent),
      accentSolid: Color(hex: ac.inkLight),

      mode: mode
    )
  }

  /// The palette a preview or a not-yet-loaded screen draws with.
  static let fallback = Theme.resolve(mode: .light, accent: .default)
}

// MARK: - Environment

extension EnvironmentValues {
  @Entry var theme: Theme = .fallback
}

extension View {
  /// Put a theme in the environment, and make the system draw its own chrome —
  /// sheets, menus, alerts, the keyboard — in the same palette.
  func tallyTheme(_ theme: Theme) -> some View {
    environment(\.theme, theme)
      .preferredColorScheme(theme.colorScheme)
      .tint(theme.accentInk)
  }
}
