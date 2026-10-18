// Keypad.swift — the 4×5 calculator pad, inside the input dock. The outlined
// link key starts link mode, in which tapping lines above links them into the
// line being typed; ↵ commits the current entry to the tab. With the brackets
// key on in Settings, "( )" takes AC's place (clearing is a hold of ⌫).
//
// The link key used to open a Menu of the lines above. The design made it a
// mode instead: the rows are already on screen with their notes and amounts,
// so they are the picker — a menu only repeated them as bare strings, capped at
// twelve. While the mode is on there is nothing to type but the operators that
// join links, so the pad folds to one row (tally-app-v2.jsx, `PICK`): "123"
// back to the numbers, + − × ÷, and ↵.
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
  /// Anything above the edit point to link. False dims the link key.
  var canReference = false
  /// Link mode is on: the pad is folded to the link bar.
  var referencing = false
  /// The brackets key in AC's place (Settings).
  var brackets = false
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
      && a.brackets == b.brackets && a.activeOperator == b.activeOperator
      && a.keyHeight == b.keyHeight
  }

  /// The pad's height for so many rows of keys — fixed, because every key is.
  /// The dock sizes its keys area from this rather than measuring it
  /// (`CalculatorScreen.padHeight`).
  static func height(referencing: Bool, brackets: Bool, keyHeight: CGFloat) -> CGFloat {
    let rows = CGFloat(referencing ? 1 : Key.rows(brackets: brackets).count)
    return rows * keyHeight + (rows - 1) * Space.s2
  }

  var body: some View {
    // One container standing on its foot, so the fold reads as the pad
    // closing down onto its ↵ row: the link bar fades in where that row is,
    // and the rows going out overhang the top, where the dock clips them.
    //
    // No animation of its own. Folding in rides `setReferencing`'s
    // `Motion.surface`, the one clock the dock's edge glides on too (none
    // under Reduce Motion); folding back out is a way back to typing, and
    // lands in the frame.
    ZStack(alignment: .bottom) {
      if referencing {
        row(Key.linkBar)
          .transition(.opacity.combined(with: .offset(y: Space.s1)))
      } else {
        VStack(spacing: Space.s2) {
          ForEach(Array(Key.rows(brackets: brackets).enumerated()), id: \.offset) { _, keys in
            row(keys)
          }
        }
        .transition(.opacity.combined(with: .offset(y: Space.s1)))
      }
    }
    // The keys are fixed-height; the labels grow with the user's text size only
    // as far as still fits them.
    .dynamicTypeSize(...TypeCap.keypad)
  }

  private func row(_ keys: [Key]) -> some View {
    HStack(spacing: Space.s2) {
      ForEach(keys, id: \.self) { key in
        KeyButton(
          key: key, height: keyHeight, canReference: canReference, inLinkBar: referencing,
          active: key == activeOperator, onPress: onPress, onHoldBackspace: onHoldBackspace
        )
        // So that when the pad does redraw — the draft coming to end in an
        // operator, or leaving it — only the key whose look changed runs its
        // body, not all twenty.
        .equatable()
      }
    }
  }
}

private struct KeyButton: View, Equatable {
  let key: Key
  let height: CGFloat
  let canReference: Bool
  /// On the folded link bar, where the link key's place is "123".
  let inLinkBar: Bool
  /// This is the draft's trailing operator.
  let active: Bool
  let onPress: (Key) -> Void
  let onHoldBackspace: () -> Void

  /// What the key draws, as `Keypad`'s `==`.
  nonisolated static func == (a: KeyButton, b: KeyButton) -> Bool {
    a.key == b.key && a.height == b.height && a.canReference == b.canReference
      && a.inLinkBar == b.inLinkBar && a.active == b.active
  }

  @Environment(\.theme) private var t
  @State private var pressed = false
  @State private var hold: Task<Void, Never>?

  /// Dimmed rather than hidden, so the pad never re-flows under a finger. On
  /// the link bar it is "123", always live: it is the way back out.
  private var enabled: Bool { !isRef || canReference || inLinkBar }

  private var isOperator: Bool {
    key == .plus || key == .minus || key == .multiply || key == .divide
  }
  /// AC, % and the link bar's "123" — words, on no fill.
  private var isWord: Bool { key == .clear || key == .percent || (isRef && inLinkBar) }
  private var isRef: Bool { key == .ref }
  private var isEnter: Bool { key == .enter }

  private enum Surface { case plain, op, opActive, cta }

  private var surface: Surface {
    if isEnter { return .cta }
    if isOperator { return active ? .opActive : .op }
    return .plain
  }

  /// The key's own colour, which changes outright — the operator inverting
  /// is a keystroke's doing.
  private var fill: Color {
    switch surface {
    case .plain: t.dock
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
    case .plain:
      // "123" is a way out, not a quiet word: full ink, like the digits.
      if isRef && inLinkBar { return t.dockInk }
      return isWord || key == .backspace ? t.dockInk2 : t.dockInk
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
      return inLinkBar ? nil : ("link", 20, "Link lines")
    case .enter: return ("return", 24, "Add to tab")
    default: return nil
    }
  }

  private var accessibilityText: String {
    if key == .clear { return "All clear" }
    if key == .percent { return "Percent" }
    if key == .brackets { return "Bracket" }
    if isRef && inLinkBar { return "Back to numbers" }
    return symbol?.label ?? key.rawValue
  }

  var body: some View {
    label
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background {
        Capsule()
          .fill(fill)
          .overlay { pressTint }
          .overlay {
            if isRef {
              Capsule().strokeBorder(t.dockLine, lineWidth: 1.5)
            }
          }
      }
      .contentShape(.capsule)
      .opacity(enabled ? 1 : 0.36)
      .gesture(touch, isEnabled: enabled)
      // A pointer is an iPad reality (trackpad, Magic Keyboard), and a key that
      // doesn't answer one reads as a picture of a key.
      .hoverEffect(.highlight)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityText)
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(active ? .isSelected : [])
      .accessibilityHint(key == .backspace ? "Hold to clear the entry" : "")
      .accessibilityAction { if enabled { fire() } }
  }

  /**
   The press, on a layer of its own over the key's colour: a plain key takes
   `keyPress`, and a filled key darkens (lightens on the dark scheme) rather
   than taking a plain key's tone.

   Press-in is instant, as the design's `transition: none` on [data-pressed]
   has it. The release is a 0.1s fade rather than the design's .25s: at a
   typing pace a quarter-second tail left two or three keys still fading behind
   the one being pressed. And it is only this layer that fades. Scoped to the
   whole key, as it was, the fade swept up whatever else changed in the same
   update — with fingers rolling from "+" to the next digit, the operator's
   un-inverting arrived with "+" lifting, and faded instead of landing.
   */
  private var pressTint: some View {
    Group {
      if surface == .plain {
        Capsule().fill(t.keyPress)
      } else {
        Capsule().fill(fill).brightness(t.isDark ? 0.08 : -0.06)
      }
    }
    .opacity(pressed && enabled ? 1 : 0)
    .animation(pressed ? nil : Motion.release, value: pressed)
  }

  @ViewBuilder
  private var label: some View {
    if let symbol {
      Image(systemName: symbol.name)
        .font(.system(size: symbol.size, weight: isOperator ? .medium : .regular))
        .foregroundStyle(ink)
    } else if isRef {
      Text("123")
        .tallyFont(TallyFont.textSemi, 16)
        .foregroundStyle(ink)
    } else if key == .brackets {
      // The design's "( )" at 24, tracked 0.08em.
      Text("( )")
        .tallyFont(TallyFont.display, 24)
        .tracking(0.08 * 24)
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
