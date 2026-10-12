// Theme.swift — the runtime palette: one colour scheme, as colours.
//
// Calculator v2 draws each screen in one of four whole schemes (Scheme.swift in
// TallyKit), and the scheme decides darkness. There is no longer a neutral
// scale composed with an accent: every tone here comes straight off the scheme.
//
// ── Two vocabularies ────────────────────────────────────────────────────────
// The screens were written against the accent-era names (`t.accent`,
// `t.accent2`, `t.accentInk`…), and the design keeps those alive with its
// `legacy()` map (tally-app-v2.jsx) rather than renaming every call site at
// once. This does the same: the old names are filled from the scheme exactly as
// `legacy()` fills them, so every screen keeps meaning what it meant, and the
// scheme's own names (`dock`, `op`, `cta`, `pill`…) sit beside them for the
// screens that get redrawn in v2's terms.
//
// ── Why the system follows ──────────────────────────────────────────────────
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
  // MARK: The accent-era names, filled per the design's legacy()

  var screen: Color
  var ink: Color
  var ink2: Color
  /// The third ink. The schemes have only two, and `legacy()` sets this to
  /// `ink2`; kept as a name so the screens that use it need not change yet.
  var ink3: Color
  var line: Color
  var card: Color
  /// The entry card's fill.
  var field: Color
  var key: Color
  var keyLine: Color
  var deep: Color
  var deepInk: Color

  /// The running-total surface.
  var totalBg: Color
  var totalInk: Color
  var totalSub: Color
  /// A neutral wash behind the row being edited.
  var rowSel: Color
  /// System red — a line whose expression can no longer be evaluated. Matches
  /// the red the native menus draw their destructive items in.
  var danger: Color

  /// The call-to-action fill (`cta`).
  var accent: Color
  /// Soft tinted surface for accent-coloured content to sit on (`chipBg`).
  var accent2: Color
  /// The readable accent shade: text, glyphs and hairlines (`accentText`).
  var accentInk: Color
  /// Foreground for content drawn on top of `accent` (`ctaInk`).
  var onAccent: Color
  /**
   A fill white always reads on — for the system controls that draw their own
   white label over a tint (a prominent button, a swipe action) and so cannot
   be handed a bright fill. See `resolve` for where it comes from.
   */
  var accentSolid: Color

  // MARK: The scheme's own names, for v2's screens

  /// Tonal fills: a pill button, an outlined chip.
  var pill: Color
  var pillInk: Color
  var chip: Color
  var chipInk: Color

  /// The one opaque input dock, and what is drawn on it.
  var dock: Color
  var dockInk: Color
  var dockInk2: Color
  var dockLine: Color
  /// A plain key's fill while it is held.
  var keyPress: Color
  /// Operator keys.
  var op: Color
  var opInk: Color
  /// The one call to action — ↵, Save, the editing ring.
  var cta: Color
  var ctaInk: Color
  var chipBg: Color
  var accentText: Color

  /// Floating chrome that is drawn rather than system glass.
  var glass: Color
  var glassBrd: Color
  var glassHi: Color

  /// The lift under a floating card. Also what `.elevation(.glass)` draws.
  var shadow: Lift
  /// The dock's lift. Nil where the scheme sets the dock apart by tone alone.
  var dockShadow: Lift?

  // MARK: What the scheme is

  var scheme: Scheme.ID
  /// The scheme decides darkness; nothing else does.
  var isDark: Bool
  var colorScheme: ColorScheme { isDark ? .dark : .light }

  /// The raised set a sheet presents on, where the scheme has one.
  private var raised: Raised?

  struct Raised: Equatable {
    var screen: Color
    var card: Color
    var field: Color
    var line: Color
  }

  /**
   The palette for a surface presented over the screen — the iPad's form
   sheets. On a dark scheme a sheet the same black as the screen behind it has
   no edge, so it steps up a tone (tally-app-v2.jsx, `tSheet`); on a light one
   it is the screen itself.
   */
  var sheet: Theme {
    guard let raised else { return self }
    var out = self
    out.screen = raised.screen
    out.card = raised.card
    out.field = raised.field
    out.key = raised.card
    out.line = raised.line
    out.raised = nil
    return out
  }
}

/**
 A drop shadow, in SwiftUI's terms.

 The schemes spell theirs as CSS `box-shadow`s, which SwiftUI cannot draw
 exactly: it has no spread. The design's spreads are all negative — a shadow
 pulled in under its card so only the soft bottom edge shows — so the
 conversion folds the spread into the blur instead of dropping it, which keeps
 the shadow as tight as the design meant rather than haloing the sides. A CSS
 blur is roughly twice the radius SwiftUI's `shadow` takes.
 */
struct Lift: Equatable {
  var color: Color
  var radius: CGFloat
  var y: CGFloat

  init(color: Color, radius: CGFloat, y: CGFloat) {
    self.color = color
    self.radius = radius
    self.y = y
  }

  init(_ s: Scheme.Shadow) {
    self.init(color: Color(hex: s.color), radius: max(0, s.blur + s.spread) / 2, y: s.y)
  }
}

extension Theme {
  /// Turn a scheme into colours, filling the accent-era names the way the
  /// design's `legacy()` does.
  static func resolve(scheme s: Scheme) -> Theme {
    let c = { (hex: String) in Color(hex: hex) }

    return Theme(
      screen: c(s.screen),
      ink: c(s.ink),
      ink2: c(s.ink2),
      ink3: c(s.ink2),
      line: c(s.line),
      card: c(s.card),
      field: c(s.field),
      key: c(s.card),
      keyLine: .clear,
      deep: c(s.deep),
      deepInk: c(s.deepInk),

      // The total bar is the call to action's colour. That is what it already
      // was in every case — lime on the dark palette, the inverted ink on the
      // light ones — and v2's light schemes all set `cta` to that ink.
      totalBg: c(s.cta),
      totalInk: c(s.ctaInk),
      totalSub: c(s.ctaInk).opacity(0.72),

      rowSel: c(s.rowSel),
      danger: c(s.isDark ? "#ff453a" : "#ff3b30"),

      accent: c(s.cta),
      accent2: c(s.chipBg),
      accentInk: c(s.accentText),
      onAccent: c(s.ctaInk),
      // On the light schemes `cta` is a deep ink white reads on. Midnight's is
      // a bright lime, which it cannot, so Midnight keeps the shade it had as
      // Lime until v2's screens give those controls ctaInk labels of their own.
      accentSolid: c(s.isDark ? s.legacyAccent.solid : s.cta),

      pill: c(s.pill),
      pillInk: c(s.pillInk),
      chip: c(s.chip),
      chipInk: c(s.chipInk),
      dock: c(s.dock),
      dockInk: c(s.dockInk),
      dockInk2: c(s.dockInk2),
      dockLine: c(s.dockLine),
      keyPress: c(s.keyPress),
      op: c(s.op),
      opInk: c(s.opInk),
      cta: c(s.cta),
      ctaInk: c(s.ctaInk),
      chipBg: c(s.chipBg),
      accentText: c(s.accentText),
      glass: c(s.glass),
      glassBrd: c(s.glassBrd),
      glassHi: c(s.glassHi),
      shadow: Lift(s.shadow),
      dockShadow: s.dockShadow.map(Lift.init),

      scheme: s.id,
      isDark: s.isDark,
      raised: s.elevated.map {
        Raised(screen: c($0.screen), card: c($0.card), field: c($0.field), line: c($0.line))
      }
    )
  }

  /// The palette a preview or a not-yet-loaded screen draws with.
  static let fallback = Theme.resolve(scheme: .default)
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

  /// Draw a `Lift`. Nil draws nothing, which is what a scheme without a dock
  /// shadow asks for.
  func shadow(_ lift: Lift?) -> some View {
    shadow(
      color: lift?.color ?? .clear, radius: lift?.radius ?? 0, x: 0, y: lift?.y ?? 0)
  }
}
