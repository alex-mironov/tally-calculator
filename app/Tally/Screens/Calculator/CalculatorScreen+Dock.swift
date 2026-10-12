// CalculatorScreen+Dock.swift — everything below the list on a phone: the seam
// (grabber and total), the entry card, and the keypad, with the stow drag and
// the keyboard avoidance that share one collapse.
//
// The views themselves are EntryCard, DraftLine and Keypad; this file owns how
// they are fed and how far the keypad is shut.
import Combine
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - The seam: grabber and total

  /**
   The seam between reviewing (the list) and entering (card + keypad), and the
   handle for the keypad. Drag anywhere on this block, or tap the grabber.
   */
  var seam: some View {
    VStack(spacing: 0) {
      // Nothing to grab while selecting — the keypad isn't the user's to move
      // until Done gives it back.
      if !selectMode {
        Button {
          setPad(padStowed ? 0 : 1)
        } label: {
          // Drawn small (20pt) to keep the seam tight; the hit area is padded
          // out to the 44pt HIG target on its short axis.
          Capsule()
            .fill(padStowed ? t.accentInk : t.ink3)
            .frame(width: 32, height: 4)
            .opacity(0.5)
            .frame(height: 20)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(padStowed ? "Show keypad" : "Hide keypad")
        .accessibilityHint("Hiding the keypad gives the list of amounts the rest of the screen")
      }

      // In select mode this same bar is the answer: it counts what is ticked
      // and reads out their subtotal, in the accent so it is plainly not the
      // tab's total. It shows even when the total is switched off in Settings,
      // because in select mode it is the whole point of the mode.
      // Reference mode needs it too: the total is one of the things to pick.
      if store.showTotal || selectMode || referencing {
        totalBar
      }
    }
    .padding(.top, selectMode ? Space.s3 : 0)
    // Horizontal slop fails the gesture, so a stray sideways drag can't nudge
    // the pad; the drag is disabled entirely in select mode, which owns the
    // keypad's position while it is on.
    .gesture(selectMode ? nil : padDrag)
  }

  // MARK: - The entry card

  var entryCardSection: some View {
    EntryCard(
      draft: $draft,
      note: $note,
      noteOpen: $noteOpen,
      highlighted: flash || editingID != nil,
      padStowed: padStowed,
      nameFor: nameFor,
      resolve: resolveRef,
      onTapCard: { showPad() }
    )
  }

  // MARK: - The keypad
  //
  // ---- keypad avoidance (HIG "Virtual keyboards": keyboard layout guide) ----
  // Two things want the keypad out of the way, and they share one collapse so
  // they can never fight over the same height:
  //
  //   · the system keyboard. Text entry here — the note chip — used to raise it
  //     straight over the keypad, burying the very field being typed into. The
  //     keypad is dead weight while a keyboard is up, so it collapses in step
  //     with the keyboard's rise and a spacer of exactly the keyboard's height
  //     takes its place.
  //   · the user, stowing it by hand to read a long tab.
  //
  // Whichever wants it shut further wins, so stowing the pad while the keyboard
  // is up — or dismissing the keyboard while stowed — never pops the keypad
  // back into view.

  /// How far shut the keypad is, 0…1.
  private var shut: CGFloat {
    guard padHeight > 0 else { return 0 }
    return max(min(1, keyboardHeight / padHeight), stow)
  }

  /// JS mirror of the original: the resting state, which drives the grabber's
  /// tint, the VoiceOver labels, and whether the card doubles as a "bring it
  /// back" target.
  private var padStowed: Bool { stow >= 0.5 }


  var keypadSection: some View {
    VStack(spacing: 0) {
      Keypad(
        onPress: press, canReference: canReference, referencing: referencing,
        seam: !splitEntryPane, bottomInset: safeBottom)
        .background {
          GeometryReader { geo in
            Color.clear.onAppear {
              if padHeight == 0 { padHeight = geo.size.height }
            }
          }
        }
        .frame(height: padHeight > 0 ? padHeight * (1 - shut) : nil, alignment: .top)
        .opacity(1 - shut)
        .clipped()

      // The keypad carried the home-indicator clearance in its own padding, so
      // once it is stowed the spacer takes that over as well as standing in for
      // the keyboard.
      Color.clear
        .frame(height: max(keyboardHeight, stow * (safeBottom + Space.s2)))
    }
    .animation(.easeOut(duration: 0.25), value: keyboardHeight)
  }

  /**
   How far the seam — the thing under the finger — actually moves between
   keypad up and fully stowed.

   Not `padHeight`: as the pad collapses, the spacer beneath it grows to take
   over the home-indicator clearance, so the seam travels that much less.
   Dividing the finger's travel by `padHeight` left the seam trailing behind it.
   */
  private var seamTravel: CGFloat {
    max(1, padHeight - (safeBottom + Space.s2))
  }

  private var padDrag: some Gesture {
    // Global coordinates, not the default local ones: the gesture is attached
    // to the seam, and the seam moves as the pad collapses. Measured locally,
    // every frame the seam slid under the finger shrank the translation that
    // had just moved it — a feedback loop that read as jitter.
    DragGesture(minimumDistance: 8, coordinateSpace: .global)
      .onChanged { value in
        guard padHeight > 0 else { return }
        if stowAtDragStart == -1 {
          // Decide the axis once, at the start. Re-checking it every frame
          // froze the pad whenever the finger wandered sideways mid-drag.
          guard abs(value.translation.height) > abs(value.translation.width) else { return }
          stowAtDragStart = stow
        }
        // No animation may carry over into the live drag — the finger is the
        // animation. A settle still in flight would otherwise ease towards
        // each new value instead of landing on it.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
          stow = min(1, max(0, stowAtDragStart + value.translation.height / seamTravel))
        }
      }
      .onEnded { value in
        guard padHeight > 0, stowAtDragStart != -1 else { return }
        let velocity = value.predictedEndTranslation.height - value.translation.height
        let next: CGFloat =
          abs(velocity) > Self.flingVelocity / 10
          ? (velocity > 0 ? 1 : 0)
          : (stow > 0.5 ? 1 : 0)
        let changed = next != stowAtDragStart
        withAnimation(Self.settle) { stow = next }
        stowAtDragStart = -1
        // Only when it actually landed somewhere else — a drag that snaps back
        // shouldn't fire a haptic.
        if changed { Haptic.select.play() }
      }
  }

  /// Toggling a panel is a toggle, so it takes the selection tick in both
  /// directions. `silent` is for callers that already played their own haptic —
  /// the keypad returning is a side effect of their action, not a second event.
  func setPad(_ next: CGFloat, silent: Bool = false) {
    withAnimation(Self.settle) { stow = next }
    if !silent { Haptic.select.play() }
  }

  /// Anything that needs digits brings the keypad back, rather than leaving the
  /// user to hunt for the grabber. No-ops while it is already up.
  func showPad(silent: Bool = false) {
    if padStowed { setPad(0, silent: silent) }
  }

  /// Settling is deliberately not a spring: the keypad is a large surface and
  /// overshoot on ~360pt of travel reads as a bounce, not as physics. Past
  /// halfway — or a decisive flick — commits, the usual sheet rule.
  private static let settle = Animation.easeOut(duration: 0.26)
  private static let flingVelocity: CGFloat = 500

  // MARK: - Environment odds and ends

  private var safeBottom: CGFloat {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
      .first ?? 0
  }

  /// The keyboard's height, tracked by hand because the screen drives the
  /// collapse itself rather than letting SwiftUI inset the whole stack.
  var keyboardPublisher: AnyPublisher<CGFloat, Never> {
    let willChange = NotificationCenter.default
      .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
      .map { note -> CGFloat in
        let frame =
          note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
        // The keyboard frame is in screen coordinates, so it needs the screen's
        // height to become an overlap. Taken from the active window scene
        // rather than `UIScreen.main`, which is deprecated and, on an iPad
        // running two windows, is the wrong screen to ask.
        let screen = UIApplication.shared.connectedScenes
          .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
          .first ?? frame.maxY
        return max(0, screen - frame.origin.y)
      }
    let willHide = NotificationCenter.default
      .publisher(for: UIResponder.keyboardWillHideNotification)
      .map { _ in CGFloat(0) }
    return willChange.merge(with: willHide).eraseToAnyPublisher()
  }
}
