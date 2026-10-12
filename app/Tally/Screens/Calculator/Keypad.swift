// Keypad.swift — the 4×5 calculator pad, inside the input dock. The outlined
// link key toggles reference mode, in which tapping a line above (or the total)
// drops it into the line being typed; ↵ commits the current entry to the tab.
//
// The reference key used to open a Menu of the lines above. The design made it
// a mode instead: the rows are already on screen with their notes and amounts,
// so they are the picker — a menu only repeated them as bare strings, capped at
// twelve. The key is a link, not Σ — it picks a line to build on, it doesn't
// add anything up. While the mode is on the key fills with the call to action
// and turns into ✕, the way out.
//
// ── Opaque, not glass ───────────────────────────────────────────────────────
// Calculator v2 draws the keys as opaque pills on an opaque dock, and that was
// taken as a decision (docs/v2-design.md, "Keys & dock"): glass is for floating
// chrome, and twenty glass keys on a solid dock only sampled the dock. So a
// plain key is the dock's own colour with the scheme's `keyPress` fill while it
// is held, the operators are tonal (`op`), and ↵ is the one call-to-action key.
//
// ── Touch-down ──────────────────────────────────────────────────────────────
// A key fires the moment it is touched, as the system keyboard and the design's
// pointer-down handler do — a `Button` waits for the finger to lift, which on a
// calculator reads as lag. That needs a gesture rather than a Button, so the
// key rebuilds what a Button gave for free: the button trait, and an explicit
// accessibility action so VoiceOver's double-tap still presses it.
//
// Ported from mobile/src/components/tally/keypad.tsx.
import SwiftUI
import TallyKit

struct Keypad: View, Equatable {
  let onPress: (Key) -> Void
  /// Holding ⌫ — clear the whole draft.
  var onHoldBackspace: () -> Void = {}
  /// Anything above the edit point to reference. False dims the reference key.
  var canReference = false
  /// Reference mode is on: the reference key is lit and reads as ✕.
  var referencing = false
  /// The operator the draft currently ends in, which inverts — the design's
  /// way of showing that the next digit starts the operand after it.
  var activeOperator: Key?
  /**
   Key height. 48pt on a phone and in the iPad's landscape pane; the iPad's
   portrait dock passes 56–58. The radius is always half of it — the keys are
   pills.
   */
  var keyHeight: CGFloat = Space.s12

  /// What the pad draws. The callbacks are left out: they only reach the
  /// screen's state, which they read when they run, not when they were made.
  nonisolated static func == (a: Keypad, b: Keypad) -> Bool {
    a.canReference == b.canReference && a.referencing == b.referencing
      && a.activeOperator == b.activeOperator && a.keyHeight == b.keyHeight
  }

  var body: some View {
    VStack(spacing: Space.s2) {
      ForEach(Array(Key.rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: Space.s2) {
          ForEach(row, id: \.self) { key in
            KeyButton(
              key: key, height: keyHeight, canReference: canReference, referencing: referencing,
              active: key == activeOperator, onPress: onPress, onHoldBackspace: onHoldBackspace
            )
            // So that when the pad does redraw — the draft coming to end in an
            // operator, or leaving it — only the key whose look changed runs
            // its body, not all twenty.
            .equatable()
          }
        }
      }
    }
    // The keys are fixed-height; the labels grow with the user's text size only
    // as far as still fits them.
    .dynamicTypeSize(...TypeCap.keypad)
  }
}

private struct KeyButton: View, Equatable {
  let key: Key
  let height: CGFloat
  let canReference: Bool
  let referencing: Bool
  /// This is the draft's trailing operator.
  let active: Bool
  let onPress: (Key) -> Void
  let onHoldBackspace: () -> Void

  /// What the key draws, as `Keypad`'s `==`.
  nonisolated static func == (a: KeyButton, b: KeyButton) -> Bool {
    a.key == b.key && a.height == b.height && a.canReference == b.canReference
      && a.referencing == b.referencing && a.active == b.active
  }

  @Environment(\.theme) private var t
  @State private var pressed = false
  @State private var hold: Task<Void, Never>?

  /// Dimmed rather than hidden, so the pad never re-flows under a finger. Lit,
  /// the key stays live whatever is above: it is the only way back out.
  private var enabled: Bool { !isRef || canReference || referencing }
  /// The reference key while its mode is on.
  private var lit: Bool { isRef && referencing }

  private var isOperator: Bool {
    key == .plus || key == .minus || key == .multiply || key == .divide
  }
  /// AC and % — words, quiet, on no fill.
  private var isWord: Bool { key == .clear || key == .percent }
  private var isRef: Bool { key == .ref }
  private var isEnter: Bool { key == .enter }

  private enum Surface { case plain, op, opActive, cta }

  private var surface: Surface {
    if isEnter || lit { return .cta }
    if isOperator { return active ? .opActive : .op }
    return .plain
  }

  private var fill: Color {
    switch surface {
    case .plain: pressed && enabled ? t.keyPress : t.dock
    case .op: t.op
    case .opActive: t.dockInk
    case .cta: t.cta
    }
  }

  private var ink: Color {
    switch surface {
    case .cta: return t.ctaInk
    case .opActive: return t.dock
    case .op: return t.opInk
    case .plain: return isWord || key == .backspace ? t.dockInk2 : t.dockInk
    }
  }

  /// SF Symbols for the keys that are not characters, with their VoiceOver
  /// labels — "⌫" reads as nothing useful. Operators are symbols too, so the
  /// four of them share one size and one optical centre.
  private var symbol: (name: String, size: CGFloat, label: String)? {
    switch key {
    case .backspace: return ("delete.left", 24, "Delete")
    case .divide: return ("divide", 24, "Divide")
    case .multiply: return ("multiply", 24, "Multiply")
    case .minus: return ("minus", 24, "Minus")
    case .plus: return ("plus", 24, "Plus")
    case .ref:
      return referencing ? ("xmark", 20, "Stop referencing") : ("link", 20, "Reference an earlier line")
    case .enter: return ("return", 24, "Add to tab")
    default: return nil
    }
  }

  private var accessibilityText: String {
    if key == .clear { return "All clear" }
    if key == .percent { return "Percent" }
    return symbol?.label ?? key.rawValue
  }

  var body: some View {
    label
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background {
        Capsule()
          .fill(fill)
          // A filled key darkens under the finger (lightens on the dark
          // scheme) rather than taking `keyPress`, which is a plain key's tone.
          .brightness(pressed && surface != .plain ? (t.isDark ? 0.08 : -0.06) : 0)
          .overlay {
            if isRef && !lit {
              Capsule().strokeBorder(t.dockLine, lineWidth: 1.5)
            }
          }
      }
      .contentShape(.capsule)
      // Press-in is instant, as the design's `transition: none` on
      // [data-pressed] has it. The release is a 0.1s fade rather than the
      // design's .25s: typing is unanimated (docs/v2-design.md, Decisions), and
      // at a typing pace a quarter-second tail left two or three keys still
      // fading behind the one being pressed.
      .animation(pressed ? nil : .easeOut(duration: 0.1), value: pressed)
      // The operator inverting as the draft comes to end in it is a keystroke's
      // doing too, so it lands outright. The link key's mode is not typing.
      .animation(.easeOut(duration: 0.15), value: lit)
      .opacity(enabled ? 1 : 0.36)
      .gesture(touch, isEnabled: enabled)
      // A pointer is an iPad reality (trackpad, Magic Keyboard), and a key that
      // doesn't answer one reads as a picture of a key.
      .hoverEffect(.highlight)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityText)
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(lit || active ? .isSelected : [])
      .accessibilityHint(key == .backspace ? "Hold to clear the entry" : "")
      .accessibilityAction { if enabled { fire() } }
  }

  @ViewBuilder
  private var label: some View {
    if let symbol {
      Image(systemName: symbol.name)
        .font(.system(size: symbol.size, weight: isOperator ? .medium : .regular))
        .foregroundStyle(ink)
    } else {
      Text(key.rawValue)
        .tallyFont(
          isWord ? TallyFont.textMedium : TallyFont.display, isWord ? 18 : 28)
        .foregroundStyle(ink)
    }
  }

  /// Down fires; the rest of the drag only keeps the key lit until it lifts.
  private var touch: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { _ in
        guard !pressed else { return }
        pressed = true
        fire()
        if key == .backspace { startHold() }
      }
      .onEnded { _ in
        pressed = false
        hold?.cancel()
        hold = nil
      }
  }

  private func fire() {
    // HIG asks a custom input view to sound like the system keyboard, so every
    // key gets the standard click (silent if the user has keyboard sounds off)
    // — and, like the system keyboard, nothing tactile. The haptics belong to
    // the outcomes: an entry landing or being refused, a hold clearing it.
    KeyClick.play()
    Haptic.prepareForCommit()
    onPress(key)
  }

  /// Hold ⌫ for the design's 480ms and the whole draft goes.
  private func startHold() {
    hold?.cancel()
    hold = Task {
      try? await Task.sleep(for: .milliseconds(480))
      guard !Task.isCancelled, pressed else { return }
      onHoldBackspace()
    }
  }
}

#Preview {
  VStack {
    Spacer()
    Keypad(onPress: { _ in }, canReference: true, activeOperator: .plus)
      .padding(Space.s3)
      .background(Theme.fallback.dock, in: .rect(cornerRadius: Space.s10))
      .padding(Space.s2)
  }
  .background { ScreenBackground() }
  .tallyTheme(.fallback)
}
