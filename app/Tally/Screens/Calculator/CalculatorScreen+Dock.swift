// CalculatorScreen+Dock.swift — the input dock, fed from the screen: what its
// entry row says, which notes it suggests, the keys and how far they are shut,
// the stow drag, and the keyboard avoidance that shares one collapse with it.
//
// The views themselves are InputDock, DraftLine and Keypad; this file owns how
// they are fed and where the dock sits.
import Combine
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - The dock

  /**
   The dock, placed: floating `margin` off the screen's sides and bottom,
   ignoring the bottom safe area as the design does (the home indicator sits
   over the dock's own bottom padding), and lifted over the system keyboard
   when the note field raises one.

   `keyHeight` is the keypad's — 48 on a phone and in the iPad's landscape
   pane, 56 in the iPad's portrait dock. `bottomMargin` is for the portrait
   dock, which is centred at a fixed width (no side margin) but stands 24pt off
   the foot; elsewhere the foot matches the sides. In select mode the tab is
   read-only, so there is nothing to type into: the dock gives its place — and
   its shape — to the selection's footer, the subtotal standing where the
   draft did.
   */
  @ViewBuilder
  func inputDock(
    keyHeight: CGFloat = Space.s12, margin: CGFloat = Space.s2, bottomMargin: CGFloat? = nil
  ) -> some View {
    if selectMode {
      SelectFooter(picked: picked.count, of: store.entries.count, subtotal: subtotal)
        .padding(.horizontal, margin)
        .padding(.bottom, bottomMargin ?? margin)
        .ignoresSafeArea(.container, edges: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    } else {
      InputDock(
        line: line,
        noteOpen: $noteOpen,
        focus: $focus,
        editing: editingID != nil,
        shakes: shakes,
        showsGrabber: layout != .padLandscape,
        padStowed: padStowed,
        trailing: dockTrailing,
        suggestions: noteSuggestions,
        nameFor: nameFor,
        positionFor: positionFor,
        resolve: resolveRef,
        stowDrag: AnyGesture(padDrag.map { _ in () }),
        onToggleStow: { setPad(padStowed ? 0 : 1) },
        onCancelEdit: { clearDraft() },
        onTapDraft: { showPad() },
        onSwipeDelete: swipeDelete
      ) { draft in
        keys(height: keyHeight, draft: draft)
      }
      .padding(.horizontal, margin)
      // The keyboard's height is measured from the screen's foot, which is
      // where the dock is measured from too once it ignores the safe area.
      .padding(.bottom, (bottomMargin ?? margin) + keyboardHeight)
      .ignoresSafeArea(.container, edges: .bottom)
      .animation(.easeOut(duration: 0.25), value: keyboardHeight)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  /**
   What the entry row says on the right: the result while the draft is a
   calculation (a bare number does not need telling what it equals), else what
   the tab will total once this line is in — an edit counted as a change to the
   line it replaces *and* to every line linked to it, which the store's own
   pass works out (tally-app-v2.jsx, `projected`).

   A function of the draft, handed to the dock, rather than a property read
   here: it is the dock's body that calls it, so a keystroke re-runs it there
   and nowhere else (see `CalculatorScreen.line`).
   */
  func dockTrailing(_ draft: String) -> String? {
    guard !draft.isEmpty, let preview = Calc.evaluate(draft, resolve: resolveRef) else {
      return nil
    }
    if Calc.hasOperator(draft) || !Calc.refs(in: draft).isEmpty || draft.contains("(") {
      return "= \(Calc.fmt(preview))"
    }
    guard !store.entries.isEmpty else { return nil }
    var next = store.entries
    if let id = editingID, let i = next.firstIndex(where: { $0.id == id }) {
      next[i].expr = ""
      next[i].value = preview
    } else {
      next.append(Entry(id: "draft", value: preview))
    }
    return "Total \(Calc.fmt(totalOf(recalc(next))))"
  }

  /**
   Up to three recent notes that start with what is typed, case-insensitively
   — this tab's lines newest first, then the saved tabs, newest saved first.
   The note already typed in full is not offered back. Called from the dock's
   body, like `dockTrailing`, and only while the note field is open.
   */
  func noteSuggestions(_ note: String) -> [String] {
    let typed = note.trimmingCharacters(in: .whitespaces).lowercased()
    var out: [String] = []
    for candidate in notePool() where candidate.key != typed && candidate.key.hasPrefix(typed) {
      out.append(candidate.name)
      if out.count == 3 { break }
    }
    return out
  }

  /**
   Every distinct note the suggestions can offer, in the order they are
   offered, trimmed and with its lowercased key — worked out once when the
   field opens and kept until it closes, since nothing it reads can change
   while the user is typing a note.

   Rebuilt per letter, as it was, the scan walked every line of every saved
   tab — trimming and lowercasing each note — before the first prefix test:
   about a thousand lines with twenty saved tabs of fifty. Per letter now it
   is a prefix test over the distinct notes, a few dozen.
   */
  private func notePool() -> [EntryDraft.NoteCandidate] {
    if let pool = line.notePool { return pool }
    let saved = store.tabs
      .filter { $0.id != store.activeID }
      .sorted { $0.savedAt > $1.savedAt }
    let lines = store.entries.reversed() + saved.flatMap { $0.entries.reversed() }

    var seen = Set<String>()
    var pool: [EntryDraft.NoteCandidate] = []
    for entry in lines {
      let name = entry.note.trimmingCharacters(in: .whitespaces)
      let key = name.lowercased()
      guard !name.isEmpty, seen.insert(key).inserted else { continue }
      pool.append(.init(name: name, key: key))
    }
    line.notePool = pool
    return pool
  }

  /// The operator the draft ends in, which its key shows inverted.
  private func activeOperator(_ draft: String) -> Key? {
    guard let last = draft.last, let key = Key(rawValue: String(last)) else { return nil }
    return [.plus, .minus, .multiply, .divide].contains(key) ? key : nil
  }

  /// One character per 28pt of swipe across the draft, with a light tick each
  /// — the haptic is the only way to count them without looking.
  private func swipeDelete() {
    guard !draft.isEmpty else { return }
    Haptic.tap.play()
    press(.backspace)
  }

  // MARK: - The keys
  //
  // ---- keypad avoidance (HIG "Virtual keyboards": keyboard layout guide) ----
  // Two things want the keys out of the way, and they share one collapse so
  // they can never fight over the same height:
  //
  //   · the system keyboard. Text entry here — the note chip — raises it, and
  //     the keys are dead weight while it is up, so they collapse in step with
  //     its rise while the dock rides up on top of it (`inputDock`'s padding);
  //   · the user, stowing them by hand to read a long tab.
  //
  // Whichever wants them shut further wins, so stowing the keys while the
  // keyboard is up — or dismissing the keyboard while stowed — never pops them
  // back into view.

  /// How far shut the keys are, 0…1. Link mode's bar ignores the stow: it is
  /// the only way to join links or back out, so it shows with the keys
  /// stowed too (tally-app-v2.jsx, `padOpen || refMode`).
  private var shut: CGFloat {
    guard padHeight > 0 else { return 0 }
    let keyboard = min(1, keyboardHeight / padHeight)
    return referencing ? keyboard : max(keyboard, stow)
  }

  /// The resting state, which drives the VoiceOver labels and whether tapping
  /// the draft doubles as "bring the keys back".
  var padStowed: Bool { stow >= 0.5 }

  private func keys(height: CGFloat, draft: String) -> some View {
    Keypad(
      onPress: press,
      onHoldBackspace: {
        Haptic.impact.play()
        clearDraft()
      },
      canReference: canReference, referencing: referencing, brackets: store.bracketsKey,
      activeOperator: activeOperator(draft), keyHeight: height
    )
    // A keystroke re-runs the dock's body, and with it this; the pad itself
    // only needs redrawing when one of its inputs changes — which, while
    // typing digits, is never. Without it all twenty keys re-ran their bodies
    // on every press (its closures can't be compared, so SwiftUI assumed the
    // worst); `Keypad`'s `==` compares what it draws.
    .equatable()
    .padding(.top, Space.s1)
    .fixedSize(horizontal: false, vertical: true)
    // Measured continuously rather than once: the key height is a parameter,
    // and an iPad turning between portrait and landscape changes it.
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { padHeight = $0 }
    .frame(height: padHeight > 0 ? padHeight * (1 - shut) : nil, alignment: .top)
    .opacity(1 - shut)
    .clipped()
  }

  private var padDrag: some Gesture {
    // Global coordinates, not the default local ones: the gesture is attached
    // to the top of the dock, and the dock moves as the keys collapse. Measured
    // locally, every frame the handle slid under the finger shrank the
    // translation that had just moved it — a feedback loop that read as jitter.
    DragGesture(minimumDistance: 8, coordinateSpace: .global)
      .onChanged { value in
        guard padHeight > 0 else { return }
        if stowAtDragStart == -1 {
          // Decide the axis once, at the start. Re-checking it every frame
          // froze the keys whenever the finger wandered sideways mid-drag.
          guard abs(value.translation.height) > abs(value.translation.width) else { return }
          stowAtDragStart = stow
        }
        // No animation may carry over into the live drag — the finger is the
        // animation. A settle still in flight would otherwise ease towards
        // each new value instead of landing on it.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
          // The dock's top travels exactly the keys' height, so the finger
          // and the handle stay together.
          stow = min(1, max(0, stowAtDragStart + value.translation.height / padHeight))
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
  /// the keys returning is a side effect of their action, not a second event.
  func setPad(_ next: CGFloat, silent: Bool = false) {
    withAnimation(Self.settle) { stow = next }
    if !silent { Haptic.select.play() }
  }

  /// Anything that needs digits brings the keys back, rather than leaving the
  /// user to hunt for the grabber. No-ops while they are already up.
  func showPad(silent: Bool = false) {
    if padStowed { setPad(0, silent: silent) }
  }

  /// Settling is deliberately not a spring: the keys are a large surface and
  /// overshoot on ~280pt of travel reads as a bounce, not as physics. Past
  /// halfway — or a decisive flick — commits, the usual sheet rule.
  private static let settle = Animation.easeOut(duration: 0.26)
  private static let flingVelocity: CGFloat = 500

  // MARK: - Environment odds and ends

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
