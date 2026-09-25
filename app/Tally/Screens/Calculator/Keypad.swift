// Keypad.swift — the 4×5 calculator pad. The tinted reference key toggles
// reference mode, in which tapping a line above (or the total) drops it into
// the line being typed; ↵ commits the current entry to the tab.
//
// The reference key used to open a Menu of the lines above. The design made it
// a mode instead: the rows are already on screen with their notes and amounts,
// so they are the picker — a menu only repeated them as bare strings, capped at
// twelve. The key is a link, not Σ — it picks a line to build on, it doesn't
// add anything up. While the mode is on the key fills with the accent and turns
// into ✕, the way out.
//
// The keys are Liquid Glass, unconditionally: the iOS 26 floor is what lets
// this be one design instead of two, so the opaque "refresh" fallback the React
// Native build carried alongside it is gone. ↵ stays solid, the accent-filled
// CTA, and the lit reference key borrows its fill — glass is for the neutral
// surface keys.
//
// Ported from mobile/src/components/tally/keypad.tsx. The whole `latest`-ref
// dance in that file — one stable callback reaching the current handler so a
// keystroke didn't re-render twenty glass surfaces — has no equivalent here;
// SwiftUI re-renders the keys only if what they display changes, and it doesn't.
import SwiftUI
import TallyKit

struct Keypad: View {
  let onPress: (Key) -> Void
  /// Anything above the edit point to reference. False dims the reference key.
  var canReference = false
  /// Reference mode is on: the reference key is lit and reads as ✕.
  var referencing = false
  /// Extra padding so the bottom row clears the home indicator.
  var bottomInset: CGFloat = 0

  @Environment(\.theme) private var t

  var body: some View {
    // One GlassEffectContainer around the pad: the keys are one surface
    // together rather than twenty separately-sampled ones, which is both
    // cheaper and what makes them read as a single control.
    GlassEffectContainer(spacing: Space.s2) {
      VStack(spacing: Space.s2) {
        ForEach(Array(Key.rows.enumerated()), id: \.offset) { _, row in
          HStack(spacing: Space.s2) {
            ForEach(row, id: \.self) { key in
              KeyButton(
                key: key, canReference: canReference, referencing: referencing,
                onPress: onPress)
            }
          }
        }
      }
    }
    .padding(.horizontal, Space.s4)
    .padding(.top, Space.s3)
    .padding(.bottom, bottomInset + Space.s2)
    // The keys are a fixed 48pt; the labels grow with the user's text size only
    // as far as still fits them.
    .dynamicTypeSize(...TypeCap.keypad)
    .background(alignment: .top) {
      // The seam between the pad and everything above it.
      Rectangle().fill(t.line).frame(height: 1 / 3)
    }
  }
}

private struct KeyButton: View {
  let key: Key
  let canReference: Bool
  let referencing: Bool
  let onPress: (Key) -> Void

  /// Dimmed rather than hidden, so the pad never re-flows under a finger. Lit,
  /// the key stays live whatever is above: it is the only way back out.
  private var enabled: Bool { !isRef || canReference || referencing }
  /// The reference key while its mode is on — the one other solid key.
  private var lit: Bool { isRef && referencing }

  @Environment(\.theme) private var t
  @State private var pressed = false

  /// 48pt keys: above the 44pt HIG minimum, and the shave (plus tighter gaps)
  /// hands the list back roughly a full row of height.
  private let height: CGFloat = 48

  private var isOperator: Bool {
    key == .plus || key == .minus || key == .multiply || key == .divide
  }
  /// AC, %, ⌫ — present but quiet.
  private var isDim: Bool { key == .clear || key == .percent || key == .backspace }
  private var isRef: Bool { key == .ref }
  private var isEnter: Bool { key == .enter }

  /// One ink per role, shared by the text keys and the symbol keys. Emphasis is
  /// carried by colour alone — every symbol keeps the same size and weight.
  private var ink: Color {
    if lit || isEnter { return t.onAccent }
    if isOperator || isRef { return t.accentInk }
    if isDim { return t.ink3 }
    return t.ink
  }

  /**
   Every non-numeric key is an SF Symbol at one size and weight.

   HIG "Icons" asks for a consistent size, detail and stroke weight across
   interface icons, which matters most here because the original labels were
   raw glyphs (⌫ ✎ ↵) that Geist has no coverage for — iOS substituted a
   *different* fallback font per character, so they rendered at visibly
   different weights. SF Symbols solve that by construction.

   The tuple is the symbol and its VoiceOver label, because "⌫" reads as
   nothing useful.
   */
  private var symbol: (name: String, label: String)? {
    switch key {
    case .percent: return ("percent", "Percent")
    case .backspace: return ("delete.left", "Delete")
    case .divide: return ("divide", "Divide")
    case .multiply: return ("multiply", "Multiply")
    case .minus: return ("minus", "Minus")
    case .plus: return ("plus", "Plus")
    case .ref: return referencing ? ("xmark", "Stop referencing") : ("link", "Reference an earlier line")
    case .enter: return ("return", "Add to tab")
    default: return nil
    }
  }

  var body: some View {
    Button {
      // HIG asks a custom input view to sound like the system keyboard, so
      // every key gets the standard click (silent if the user has keyboard
      // sounds off) — and, like the system keyboard, nothing tactile. The
      // haptics belong to the commit, for the entry landing or being refused,
      // and they only register because the keys around them stay quiet.
      KeyClick.play()
      onPress(key)
    } label: {
      label
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(.rect)
    }
    .modifier(
      KeyChrome(
        key: key, lit: lit, enabled: enabled, accessibilityText: symbol?.label ?? key.rawValue)
    )
    .accessibilityAddTraits(lit ? .isSelected : [])
  }

  @ViewBuilder
  private var label: some View {
    if let symbol {
      // `.title3` is 20pt at the default size, and scales with the digits on
      // the neighbouring keys — a fixed 20 would leave the operators behind as
      // the numbers grow.
      Image(systemName: symbol.name)
        .font(.title3.weight(.regular))
        .foregroundStyle(ink)
        // The glass is drawn by the container, which ignores an opacity set on
        // the key, so a disabled key dims its glyph (and drops its tint).
        .opacity(enabled ? 1 : 0.4)
    } else {
      Text(key.rawValue)
        // "AC" is a word, not an icon; a point down and a weight up so its cap
        // height sits level with the 20pt symbols sharing its row.
        .font(.tally(isDim ? TallyFont.sansSemi : TallyFont.sansMedium, isDim ? 17 : 21))
        .foregroundStyle(ink)
    }
  }
}

/// What every key wears.
private struct KeyChrome: ViewModifier {
  let key: Key
  /// The reference key with its mode on, filled like ↵.
  let lit: Bool
  let enabled: Bool
  let accessibilityText: String

  @Environment(\.theme) private var t

  private var isEnter: Bool { key == .enter }
  private var solid: Bool { isEnter || lit }

  func body(content: Content) -> some View {
    content
      .buttonStyle(KeyPressStyle())
      // A pointer is an iPad reality (trackpad, Magic Keyboard), and a key that
      // doesn't answer one reads as a picture of a key.
      .hoverEffect(.highlight)
      .background {
        if solid {
          // The one solid key: the confirming action, in the accent, with the
          // tinted CTA lift under it.
          RoundedRectangle(cornerRadius: Radius.lg)
            .fill(t.accent)
            .elevation(.cta(t.accent))
        }
      }
      // `.interactive()` is the press response: the system's own Liquid Glass
      // compress-and-glow under the finger, the same one every other glass
      // control has, instead of a hand-rolled scale. ↵ is glass too — tinted
      // the accent over its solid fill — so it answers the finger the same way.
      .glassEffect(
        .regular.tint(solid ? t.accent : (key == .ref && enabled ? t.accent2 : nil))
          .interactive(enabled),
        in: .rect(cornerRadius: Radius.lg)
      )
      .disabled(!enabled)
      .accessibilityLabel(accessibilityText)
  }
}

/// No press styling of its own: the interactive glass is the press response,
/// and a scale or dim here would stack a second one on top of it.
private struct KeyPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

#Preview {
  VStack {
    Spacer()
    Keypad(onPress: { _ in })
  }
  .background { ScreenBackground() }
  .tallyTheme(.fallback)
}
