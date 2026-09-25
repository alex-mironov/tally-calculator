// CalculatorScreen.swift — Tally's one screen: a nameable tab, a labelled list
// of amounts, a live total, the in-progress entry, and the keypad.
//
// Ported from mobile/src/app/index.tsx (1,022 lines). Much of that file was
// bridge tax — the frame-the-label bar-button workarounds, the responder
// sibling under the entry card, the ListScroll native module, the React
// Compiler's rules about where a function could be declared — and none of it
// appears here. What survives is the choreography, which is the actual design:
//
//   · the keypad is ~360pt, around 40% of the screen, so it can be stowed to
//     give the list that space back: drag the grabber above the total, or tap
//     it (see "keypad avoidance" below);
//   · stowing and the system keyboard share one collapse path, so they can
//     never fight over the same height;
//   · select mode is a read-only lens over the tab *in place* — the tab becomes
//     the answer rather than opening a second copy of itself.
import Combine
import SwiftUI
import TallyKit

struct CalculatorScreen: View {
  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t

  /**
   Whether to draw the list and the entry pane side by side.

   A plain parameter, decided by `RootView` from the *window's* width. This
   screen deliberately does no measuring of its own: every previous attempt to
   work it out from here — size class, GeometryReader through state,
   GeometryReader off the proxy, ViewThatFits — failed the same way, because
   this used to be the detail column of a NavigationSplitView and the width
   reaching the branch disagreed with the width reaching the container. There is
   no split view any more and no geometry here; see RootView.
   */
  var splitEntryPane = false

  /**
   Toggle for the archive sidebar, when there is one.

   `nil` on a phone, where the archive is a push rather than a column — that is
   the difference the toolbar asks about, and it is a separate question from
   `splitEntryPane`: an iPad can have room for the sidebar but not for the
   split, or the other way round.
   */
  var sidebar: Binding<Bool>?

  // ---- the line being typed ----
  @State private var draft = ""
  @State private var note = ""
  @State private var noteOpen = false
  @State private var editingID: String?
  /// An invalid commit was refused — the card's border flashes accent.
  @State private var flash = false
  @State private var copied = false
  /// Freshly committed: drives the row's one-shot highlight and the scroll.
  @State private var justAddedID: String?
  /// Reference mode, from the keypad's link key: tapping a line or the total
  /// drops it into the draft. Any other key, or a pick, ends it.
  @State private var referencing = false

  // ---- keypad stow ----
  /// 0 = keypad up, 1 = fully stowed. Intermediate values are the live drag.
  @State private var stow: CGFloat = 0
  /// -1 while no drag is in progress, so the first onChanged can capture
  /// where the drag started from.
  @State private var stowAtDragStart: CGFloat = -1
  @State private var padHeight: CGFloat = 0
  @State private var keyboardHeight: CGFloat = 0

  // ---- sheets and sharing ----
  @State private var saveOpen = false
  @State private var share: SharePayload?
  @State private var shareFailed = false

  // ---- hardware keyboard ----
  /**
   Whether the pad has keyboard focus.

   `.onKeyPress` only fires on a view that *has* focus, and nothing gives a
   plain view focus on its own — so without this the handler below was written,
   compiled, and unreachable: typing on an attached keyboard did nothing at all.
   Focus is taken on appear, and taken back whenever the note field lets go of
   it (the field steals it while it is open, which is correct — those keys are
   the note's).
   */
  @FocusState private var padFocused: Bool

  // ---- multi-select ----
  @State private var selectMode = false
  @State private var picked: Set<String> = []

  /// Settling is deliberately not a spring: the keypad is a large surface and
  /// overshoot on ~360pt of travel reads as a bounce, not as physics. Past
  /// halfway — or a decisive flick — commits, the usual sheet rule.
  private let settle = Animation.easeOut(duration: 0.26)
  private let flingVelocity: CGFloat = 500

  var body: some View {
    @Bindable var store = store

    ZStack {
      ScreenBackground()

      if splitEntryPane { wideLayout } else { compactLayout }
    }
    // SwiftUI's automatic keyboard avoidance would push the whole stack up
    // *and* the keypad would collapse, double-counting the same height. The
    // screen drives it by hand instead — see `shut` below.
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .navigationTitle(navigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .onReceive(keyboardPublisher) { keyboardHeight = $0 }
    // The draft belongs to the tab it was typed on. Opening a saved
    // calculation — or starting a fresh one — swaps `entries` out from under
    // the editor, and the draft, its note and the row being edited are local to
    // this screen. Keyed on tabEpoch rather than activeID, because a new tab
    // started from an already-unsaved one leaves activeID nil on both sides.
    .onChange(of: store.tabEpoch) { clearDraft() }
    // A hardware keyboard drives the pad. Nearly free, and on an iPad — where
    // one is often attached — it is the difference between a calculator you
    // poke at and one you can actually run a list of numbers through.
    .focusable()
    .focused($padFocused)
    .focusEffectDisabled()
    .onKeyPress(action: handleKeyPress)
    .onAppear { padFocused = true }
    .onChange(of: noteOpen) { _, open in if !open { padFocused = true } }
    .sheet(isPresented: $saveOpen) {
      SaveSheet(
        title: store.activeID == nil ? "Save Calculation" : "Edit Calculation",
        subtitle: "Name it and add tags to find it later.",
        name: store.tabName,
        namePlaceholder: "Name this calculation…",
        selected: store.tags,
        canSave: !store.entries.isEmpty
      ) { name, tags in
        Haptic.success.play()
        store.saveDraft(name: name, tags: tags)
      }
    }
    .sheet(item: $share) { ActivityView(items: [$0.url]) }
    .alert("Couldn’t create the link", isPresented: $shareFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Check your connection and try again.")
    }
  }

  // MARK: - Sharing
  //
  // Snapshot the tab to the tally-share Worker (web/ in this repo) and hand the
  // returned link to the system share sheet. The snapshot is frozen at this
  // moment — later edits here don't travel.

  private func shareLink() async {
    do {
      let url = try await ShareClient.createLink(
        name: store.tabName, tags: store.tags, entries: store.entries,
        accent: store.accentHex)
      share = SharePayload(url: url)
    } catch {
      shareFailed = true
    }
  }

  // MARK: - Layout

  /// Phone, and any compact window: one column, keypad at the foot, stowable.
  private var compactLayout: some View {
    VStack(spacing: 0) {
      listOrEmpty
      seam
      if !selectMode { EntryCardSection }
      keypadSection
    }
  }

  /**
   iPad: the tab on the leading side, the thing you type into on the trailing
   side.

   Used when `splitEntryPane` says so — which `RootView` decides from the
   window's width, not this screen's. That distinction is the whole fix, and is
   worth keeping because the failure was so misleading.

   While this screen was the detail column of a `NavigationSplitView`, four
   ways of working the width out from *here* all failed the same way: the size
   class (which reads "regular" for a 504pt column, leaving the list 134pt wide
   and one digit per line), a GeometryReader through `@State`, a GeometryReader
   read straight off the proxy, and `ViewThatFits` (a `List`'s ideal width is
   unbounded, so the wide arm always "fits" and overflowed). The third was
   disproved outright: a red background on this layout never appeared while a
   debug title in the same `body` read `w=834 WIDE`. A detail column's width is
   re-proposed by the split view as the sidebar comes and goes, and the width
   that reached the branch disagreed with the width its container was laid out
   at.

   The split view is gone. `RootView` measures the window — which nothing
   re-proposes — subtracts a fixed sidebar, and passes the answer down.
   */
  private var wideLayout: some View {
    // No rule between the columns, per the design: the pane is the phone's
    // bottom band standing on the screen's own background, and a hairline
    // down the middle only fenced the keypad off from the lines it adds to.
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        listOrEmpty
      }

      VStack(spacing: 0) {
        Spacer(minLength: 0)
        // The total sits directly above the card, as it does on the phone, so
        // the trailing pane is the phone's bottom band — total, card, keypad —
        // unchanged. It used to stay under the list on the theory that it is
        // the list's answer, and ended up stranded in the bottom-left corner,
        // level with the keypad's last row and nowhere near the lines it adds.
        if store.showTotal || selectMode || referencing { totalBar }
        if !selectMode { EntryCardSection }
        keypadSection
      }
      .frame(width: Self.entryPaneWidth)
      // The design's 8pt trailing inset, so the pad doesn't run into the
      // window edge harder than the list does on the other side.
      .padding(.trailing, Space.s2)
    }
  }

  /**
   The trailing pane's width — the design's 400pt cap on the iPad keypad.

   With the keypad's own 16pt side padding and 8pt gaps that puts each key at
   86pt, a few points wider than the same keypad on a 393pt iPhone. The pad
   keeps the proportions it was designed with instead of being stretched to
   whatever is left over — which is exactly what made the iPad build before
   this look like a blown-up phone.
   */
  static let entryPaneWidth: CGFloat = 400

  /// The width this screen needs before the list and the entry pane can sit
  /// side by side: the entry pane, plus the narrowest list still worth reading
  /// (a note and an amount need roughly 320). `RootView` applies it.
  static let splitWidth: CGFloat = entryPaneWidth + Space.s2 + 320

  // MARK: - The list

  @ViewBuilder
  private var listOrEmpty: some View {
    if store.entries.isEmpty {
      VStack(spacing: Space.s3) {
        Text("Nothing added yet.")
          .font(.tally(TallyFont.serif, TextScale.displayMd))
          .foregroundStyle(t.ink2)
          .multilineTextAlignment(.center)
        Text("Tap a number, name it, then hit return")
          .font(.tally(TallyFont.sans, TextScale.bodySm))
          .foregroundStyle(t.ink3)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(Space.s5)
    } else {
      ScrollViewReader { proxy in
        List {
          Section {
            ForEach(store.entries) { entry in row(entry) }
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, Space.s2, for: .scrollContent)
        // The scroll edge effect is left ON here, which is a deliberate
        // reversal of what the React Native build did.
        //
        // That build hid it, and needed a native module reaching under SwiftUI
        // to the backing scroll view to do so (modules/list-scroll's
        // `hideTopEdgeEffect`), because the effect drew a flat, lightened band
        // that cut a straight shelf across the accent bloom. Checked side by
        // side here in both palettes, that does not happen: SwiftUI's edge
        // effect on iOS 26 is a progressive blur that follows the content under
        // a *floating* bar, not a band painted across the full width. With it
        // off, rows simply collide with the bar and the screen reads as broken.
        //
        // So the workaround is not merely unnecessary in this project — its
        // reasoning does not survive the move to a native floating bar.
        .onChange(of: justAddedID) { _, id in
          // With the keypad up the list shows only a handful of rows, so a
          // committed entry lands below the fold and is never seen arriving.
          guard let id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
    }
  }

  private func row(_ entry: Entry) -> some View {
    let editIndex = editingID.flatMap { id in store.entries.firstIndex { $0.id == id } }
    let index = store.entries.firstIndex { $0.id == entry.id } ?? 0

    return EntryRow(
      entry: entry,
      selected: entry.id == editingID,
      showExpr: store.showExpr,
      justAdded: entry.id == justAddedID,
      nameFor: nameFor,
      canReference: entry.error != true && (editIndex.map { index < $0 } ?? true),
      selectMode: selectMode,
      picked: picked.contains(entry.id),
      referencing: referencing,
      onEdit: { edit(entry) },
      onDelete: { delete(entry) },
      onStartSelect: { startSelect(seed: entry) },
      onTogglePick: { togglePick(entry) },
      onReference: { insertRef(entry.id, note: entry.note) },
      onToggleExcluded: {
        Haptic.select.play()
        store.toggleExcluded(id: entry.id)
      }
    )
    .id(entry.id)
  }

  // MARK: - The seam: grabber and total

  /**
   The seam between reviewing (the list) and entering (card + keypad), and the
   handle for the keypad. Drag anywhere on this block, or tap the grabber.
   */
  private var seam: some View {
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

  private var totalBar: some View {
    // While referencing, the figure is what a `sum` pill would be worth —
    // only the lines above the edit point when editing.
    let value = selectMode ? subtotal : referencing ? (resolveRef("sum") ?? 0) : store.total
    return HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
      Text(totalLabel)
        .font(.tally(referencing ? TallyFont.sansSemi : TallyFont.sansMedium, TextScale.bodySm))
        .foregroundStyle(copied || referencing ? t.accentInk : t.ink2)
        .lineLimit(1)
        .contentTransition(.opacity)
      Spacer()
      HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
        if referencing {
          Image(systemName: "link")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(t.accentInk)
            .transition(.opacity)
        }
        // The total lands on its new value outright — no count-up tween, no
        // scale pulse: it is a number you read, not an event.
        Text(Calc.fmt(value))
          .font(.tally(TallyFont.monoSemi, TextScale.numLg))
          .monospacedDigit()
          .tracking(-0.2)
          .foregroundStyle(
            selectMode ? (picked.isEmpty ? t.ink3 : t.accentInk) : referencing ? t.accentInk : t.ink)
      }
    }
    .padding(.top, Space.s2)
    .padding(.horizontal, Space.s5)
    .padding(.bottom, Space.s2)
    .overlay(alignment: .top) {
      Rectangle().fill(t.line).frame(height: 1 / 3).padding(.horizontal, Space.s5)
    }
    .contentShape(.rect)
    // Tap the running total — or a selection's subtotal — to copy the plain
    // number, so it pastes cleanly into spreadsheets and other apps. The label
    // turning to "Copied" is the confirmation.
    // In reference mode the same tap references the total instead.
    .onTapGesture { referencing ? insertRef("sum", note: nil) : copyTotal(value) }
    .animation(.easeOut(duration: 0.2), value: copied)
    .animation(.easeOut(duration: 0.15), value: referencing)
    // The total is one line that has to stay one line between the list and the
    // entry card; it grows with the user's text size to the same cap as the card.
    .dynamicTypeSize(...TypeCap.chrome)
    // "Total, 199.20" as one stop, with the copy gesture offered as an action
    // rather than left to a long press VoiceOver users would never find.
    .accessibilityElement(children: .combine)
    .accessibilityAction(named: referencing ? "Add to entry" : "Copy") {
      referencing ? insertRef("sum", note: nil) : copyTotal(value)
    }
  }

  private var totalLabel: String {
    if copied { return "Copied" }
    if referencing { return "Tap a line to insert" }
    guard selectMode else { return "Total" }
    return picked.isEmpty
      ? "Tap lines to add them up"
      : "\(picked.count) of \(store.entries.count) selected"
  }

  // MARK: - The entry card

  private var EntryCardSection: some View {
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

  /**
   Whether the reference key has anything to offer: a line the draft may see.
   A line may only reference lines above it (all of them for a new line, the
   ones above the edit point when editing), which is also what makes reference
   cycles impossible; a line in error resolves to nothing, so it doesn't count.
   Picking one drops a *reference token* into the draft — a live link drawn as
   a pill, so the row recomputes whenever the referenced line changes.
   */
  private var canReference: Bool {
    let editIndex = editingID.flatMap { id in store.entries.firstIndex { $0.id == id } }
    let visible = editIndex.map { Array(store.entries.prefix($0)) } ?? store.entries
    return visible.contains { $0.error != true }
  }

  private var keypadSection: some View {
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
          abs(velocity) > flingVelocity / 10
          ? (velocity > 0 ? 1 : 0)
          : (stow > 0.5 ? 1 : 0)
        let changed = next != stowAtDragStart
        withAnimation(settle) { stow = next }
        stowAtDragStart = -1
        // Only when it actually landed somewhere else — a drag that snaps back
        // shouldn't fire a haptic.
        if changed { Haptic.select.play() }
      }
  }

  /// Toggling a panel is a toggle, so it takes the selection tick in both
  /// directions. `silent` is for callers that already played their own haptic —
  /// the keypad returning is a side effect of their action, not a second event.
  private func setPad(_ next: CGFloat, silent: Bool = false) {
    withAnimation(settle) { stow = next }
    if !silent { Haptic.select.play() }
  }

  /// Anything that needs digits brings the keypad back, rather than leaving the
  /// user to hunt for the grabber. No-ops while it is already up.
  private func showPad(silent: Bool = false) {
    if padStowed { setPad(0, silent: silent) }
  }

  // MARK: - Keys

  /**
   Map a physical key onto a pad key.

   Ignored entirely while the note field is up: those keystrokes belong to the
   field being typed into, not to the pad behind it.
   */
  private func handleKeyPress(_ event: KeyPress) -> KeyPress.Result {
    guard !noteOpen else { return .ignored }
    // Escape backs out of reference mode before it clears anything.
    if referencing && event.key == .escape {
      setReferencing(false)
      return .handled
    }

    let key: Key? =
      switch event.key {
      case .return: .enter
      case .delete: .backspace
      case .escape: .clear
      default:
        switch event.characters {
        // Deliberately *not* '='. It commits on a desk calculator, but on most
        // keyboards '+' is Shift-'=', so '=' meant a mistimed Shift filed the
        // line you were in the middle of — found by typing "12+3" and watching
        // "12" commit. Return (and the numeric pad's Enter) commits instead.
        case "\r", "\n": .enter
        case "+": .plus
        case "-", "−": .minus
        case "*", "x", "×": .multiply
        case "/", "÷": .divide
        // A comma is the decimal separator on a great many keyboards, and
        // nothing else on this pad wants it.
        case ".", ",": .dot
        case "%": .percent
        case "c", "C": .clear
        default: Key(rawValue: event.characters)  // the digits
        }
      }

    guard let key else { return .ignored }
    press(key)
    return .handled
  }

  private func press(_ key: Key) {
    // Only the reference key keeps the mode; typing anything else means the
    // user has moved on without picking.
    if key != .ref { setReferencing(false) }
    switch key {
    case .clear: clearDraft()
    case .ref: if canReference || referencing { setReferencing(!referencing) }
    case .enter: commit()
    default:
      if let next = Draft.apply(key, to: draft) { draft = next }
    }
  }

  private func commit() {
    guard !draft.isEmpty, let value = Calc.evaluate(draft, resolve: resolveRef) else {
      Haptic.error.play()
      flash = true
      Task {
        try? await Task.sleep(for: .milliseconds(320))
        flash = false
      }
      return
    }

    // An edit keeps the line's sticky number and its counted state — only new
    // lines get a fresh number, and every new line counts.
    let existing = editingID.flatMap { id in store.entries.first { $0.id == id } }
    let entry = Entry(
      id: editingID ?? store.mintID(),
      note: note.trimmingCharacters(in: .whitespacesAndNewlines),
      // References must survive in `expr` even without an operator — a bare
      // ⟨Rent⟩ line is a live mirror, not a copy.
      expr: (Calc.hasOperator(draft) || !Calc.refs(in: draft).isEmpty) ? draft : "",
      value: value,
      num: existing?.num,
      excluded: existing?.excluded
    )

    if editingID != nil {
      store.replace(entry)
    } else {
      store.append(entry)
      // Edits happen on a row already on screen (the user just tapped it) —
      // only a brand-new entry needs the scroll and the flash.
      justAddedID = entry.id
      Task {
        try? await Task.sleep(for: .milliseconds(1400))
        if justAddedID == entry.id { justAddedID = nil }
      }
    }
    Haptic.success.play()
    clearDraft()
  }

  private func clearDraft() {
    draft = ""
    note = ""
    noteOpen = false
    editingID = nil
    setReferencing(false)
  }

  private func setReferencing(_ on: Bool) {
    guard on != referencing else { return }
    withAnimation(.easeOut(duration: 0.15)) { referencing = on }
  }

  /// No haptic from either entry point (the row's tap, the context menu's
  /// Edit): the row lighting up and the draft filling in are the feedback.
  private func edit(_ entry: Entry) {
    draft = entry.expr.isEmpty ? Calc.plain(entry.value) : entry.expr
    note = entry.note
    editingID = entry.id
    noteOpen = false
    showPad(silent: true)  // the keypad returning is part of the same tap
  }

  private func delete(_ entry: Entry) {
    Haptic.impact.play()
    store.delete(id: entry.id)
    if editingID == entry.id { clearDraft() }
  }

  /// No haptic: the pill landing in the draft is the feedback. Ends reference
  /// mode — one pick per press of the key, as the design has it.
  private func insertRef(_ id: String, note sourceNote: String?) {
    setReferencing(false)
    draft = Draft.insertRef(id, into: draft)
    // An unnamed draft borrows the source's note.
    if let sourceNote, !sourceNote.isEmpty, note.isEmpty { note = sourceNote }
    showPad(silent: true)
  }

  private func copyTotal(_ value: Double) {
    UIPasteboard.general.string = String(format: "%.2f", value)
    Haptic.select.play()
    copied = true
    Task {
      try? await Task.sleep(for: .milliseconds(1200))
      copied = false
    }
  }

  // MARK: - References

  /**
   Resolver for the draft's reference tokens.

   Entry ids look up the current value; `sum` is the running total of the
   counted lines the draft can see — all of them for a new line, only the ones
   above when editing, which matches the forward-pass evaluation order in the
   store. A line in error resolves to nothing, so the draft cannot be committed
   on top of it.
   */
  private func resolveRef(_ id: String) -> Double? {
    if id == "sum" {
      let upto = editingID.flatMap { eid in store.entries.firstIndex { $0.id == eid } }
      return totalOf(upto.map { Array(store.entries.prefix($0)) } ?? store.entries)
    }
    guard let src = store.entries.first(where: { $0.id == id }), src.error != true else {
      return nil
    }
    return src.value
  }

  /// Display name for a reference id — a note, "#4", or the subtotal.
  private func nameFor(_ id: String) -> String {
    if id == "sum" { return "Total" }
    guard let src = store.entries.first(where: { $0.id == id }) else { return "#?" }
    if src.note.isEmpty { return "#\(src.num.map(String.init) ?? "?")" }
    return src.note.count > 16 ? String(src.note.prefix(15)) + "…" : src.note
  }

  // MARK: - Multi-select
  //
  // "What do these three come to?" — a question the running total can't answer.
  // It used to open a sheet over the tab, which meant re-reading the same list
  // in a second copy of itself. Now the tab *becomes* the answer: the keypad
  // stows, the entry card steps out of the way, every row grows a selection
  // circle and the total bar turns into a subtotal. Nothing is re-laid-out, so
  // the lines being picked stay exactly where they already were.

  private var subtotal: Double {
    store.entries.reduce(0) { $0 + (picked.contains($1.id) ? $1.value : 0) }
  }

  private var allPicked: Bool {
    !store.entries.isEmpty && picked.count == store.entries.count
  }

  private func startSelect(seed: Entry? = nil) {
    Haptic.select.play()
    // The draft itself is left alone — it is still there when Done gives the
    // card back — but a live note field would keep the keyboard up over a
    // screen that no longer has anywhere to type.
    noteOpen = false
    setReferencing(false)
    picked = seed.map { [$0.id] } ?? []
    withAnimation(.easeOut(duration: 0.22)) { selectMode = true }
    setPad(1, silent: true)  // the tick above already covered this
  }

  private func endSelect() {
    // No haptic: Done is a button, and the keypad coming back is the feedback.
    withAnimation(.easeOut(duration: 0.22)) { selectMode = false }
    picked = []
    setPad(0, silent: true)
  }

  private func togglePick(_ entry: Entry) {
    Haptic.select.play()
    if picked.contains(entry.id) { picked.remove(entry.id) } else { picked.insert(entry.id) }
  }

  // MARK: - Navigation bar

  private var navigationTitle: String {
    if selectMode {
      return picked.isEmpty ? "Select lines" : "\(picked.count) selected"
    }
    return store.tabName.isEmpty ? "New calculation" : store.tabName
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if selectMode {
      // Select mode borrows both bar slots, the way Mail and Photos do: Select
      // All on the leading edge, the confirming action on the trailing one.
      ToolbarItem(placement: .topBarLeading) {
        Button(allPicked ? "Deselect All" : "Select All") {
          Haptic.select.play()
          picked = allPicked ? [] : Set(store.entries.map(\.id))
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        // `prominent` is the style HIG names for key actions such as Done. The
        // bar tints its own container, so a bare `checkmark` is all this
        // supplies — no `.circle` variant, which would draw a second ring
        // inside the bar's capsule.
        Button("Done", systemImage: "checkmark", action: endSelect)
          .buttonStyle(.borderedProminent)
          .accessibilityLabel("Done selecting")
      }
    } else {
      ToolbarItem(placement: .topBarLeading) {
        if let sidebar {
          // The archive is a column, so the leading slot shows it rather than
          // pushing a second copy of it. NavigationSplitView used to supply
          // this button; the arrangement is RootView's HStack now, so the
          // toggle is ours to draw.
          Button {
            withAnimation(.snappy(duration: 0.28)) { sidebar.wrappedValue.toggle() }
          } label: {
            Label(
              sidebar.wrappedValue ? "Hide saved calculations" : "Show saved calculations",
              systemImage: "sidebar.leading")
          }
        } else {
          // Saved calculations — the one destination worth a direct door. This
          // is the root screen, so the slot isn't fighting a back button.
          NavigationLink(value: Route.saved) {
            Label("Saved calculations", systemImage: "tray.full")
          }
        }
      }
      // With the archive on screen as a sidebar, its own "+" is the way to a
      // fresh calculation — the design has Saved and New leave this bar then.
      if sidebar?.wrappedValue != true {
        ToolbarItem(placement: .topBarTrailing) {
          Button("New calculation", systemImage: "plus") {
            Haptic.tap.play()  // a fresh tab started — the working one is filed, not lost
            store.newTab()
            showPad(silent: true)  // a fresh tab is there to be typed into
          }
        }
      }
      ToolbarItem(placement: .topBarTrailing) { moreMenu }
    }
  }

  /**
   The More menu.

   HIG "Toolbars": when a screen has more actions than the bar should show,
   collapse them into a single `ellipsis` menu rather than lining symbols up
   across the bar. "New calculation" is the one action frequent enough to be
   worth a slot of its own, so it is promoted out rather than sitting in both.

   The symbol is bare `ellipsis`, not `ellipsis.circle`: a bar button already
   sits in its own container, and a circle-variant symbol draws a second ring
   inside the first.
   */
  private var moreMenu: some View {
    Menu {
      // What you can do to this calculation…
      Button("Rename & tags…", systemImage: "pencil") { saveOpen = true }
      Button("Copy total", systemImage: "doc.on.doc") { copyTotal(store.total) }
      if !store.entries.isEmpty {
        Button("Share link…", systemImage: "square.and.arrow.up") {
          Task { await shareLink() }
        }
      }
      if store.entries.count > 1 {
        Button("Select lines…", systemImage: "checkmark.circle") { startSelect() }
      }
      Divider()
      // …and where else to go. Starting a fresh one is the "+" beside this
      // menu, so it isn't repeated here — and neither is the archive when it is
      // already on screen as the sidebar.
      if sidebar == nil {
        NavigationLink(value: Route.saved) {
          Label(
            store.tabs.isEmpty ? "Saved calculations" : "Saved calculations (\(store.tabs.count))",
            systemImage: "tray.full")
        }
      }
      NavigationLink(value: Route.settings) {
        Label("Settings", systemImage: "gearshape")
      }
    } label: {
      Label("Calculation options", systemImage: "ellipsis")
    }
  }

  // MARK: - Environment odds and ends

  private var safeBottom: CGFloat {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
      .first ?? 0
  }

  /// The keyboard's height, tracked by hand because the screen drives the
  /// collapse itself rather than letting SwiftUI inset the whole stack.
  private var keyboardPublisher: AnyPublisher<CGFloat, Never> {
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
