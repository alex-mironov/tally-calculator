// Keypad.swift — the 4×5 calculator pad. The tinted ✎ opens the note field and
// ↵ commits the current entry to the running tab.
//
// The keys are Liquid Glass, unconditionally: the iOS 26 floor is what lets
// this be one design instead of two, so the opaque "refresh" fallback the React
// Native build carried alongside it is gone. ↵ stays the solid deep-ink CTA —
// glass is for the neutral surface keys.
//
// Ported from mobile/src/components/tally/keypad.tsx. The whole `latest`-ref
// dance in that file — one stable callback reaching the current handler so a
// keystroke didn't re-render twenty glass surfaces — has no equivalent here;
// SwiftUI re-renders the keys only if what they display changes, and it doesn't.
import SwiftUI
import TallyKit

struct Keypad: View {
  let onPress: (Key) -> Void
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
              KeyButton(key: key, onPress: onPress)
            }
          }
        }
      }
    }
    .padding(.horizontal, Space.s4)
    .padding(.top, Space.s3)
    .padding(.bottom, bottomInset + Space.s2)
    .background(alignment: .top) {
      // The seam between the pad and everything above it.
      Rectangle().fill(t.line).frame(height: 1 / 3)
    }
  }
}

private struct KeyButton: View {
  let key: Key
  let onPress: (Key) -> Void

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
  private var isNote: Bool { key == .note }
  private var isEnter: Bool { key == .enter }

  /// One ink per role, shared by the text keys and the symbol keys. Emphasis is
  /// carried by colour alone — every symbol keeps the same size and weight.
  private var ink: Color {
    if isOperator || isNote { return t.accentInk }
    if isDim { return t.ink3 }
    if isEnter { return t.deepInk }
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
    case .note: return ("square.and.pencil", "Add a note")
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
    .buttonStyle(KeyPressStyle())
    .background {
      if isEnter {
        // The one solid key: the confirming action, in the inverted surface,
        // with the tinted CTA lift under it.
        RoundedRectangle(cornerRadius: Radius.lg)
          .fill(t.deep)
          .elevation(.cta(t.deep))
      }
    }
    .glassEffect(
      isEnter ? .identity : .regular.tint(isNote ? t.accent2 : nil),
      in: .rect(cornerRadius: Radius.lg)
    )
    .accessibilityLabel(symbol?.label ?? key.rawValue)
  }

  @ViewBuilder
  private var label: some View {
    if let symbol {
      Image(systemName: symbol.name)
        .font(.system(size: 20, weight: .regular))
        .foregroundStyle(ink)
    } else {
      Text(key.rawValue)
        // "AC" is a word, not an icon; a point down and a weight up so its cap
        // height sits level with the 20pt symbols sharing its row.
        .font(.tally(isDim ? TallyFont.sansSemi : TallyFont.sansMedium, isDim ? 17 : 21))
        .foregroundStyle(ink)
    }
  }
}

/// The design's `.tally-key:active` — keys squish down rather than fading.
private struct KeyPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .opacity(configuration.isPressed ? 0.9 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
