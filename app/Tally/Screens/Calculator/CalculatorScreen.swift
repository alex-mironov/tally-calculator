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
   The archive is already on screen as a split-view sidebar.

   A *separate* question from `isWide` below, and conflating the two was a bug:
   the sidebar exists whenever the app is in regular width, but this screen —
   the detail column — may still be too narrow to split. So the toolbar asks
   this, and the layout asks that.
   */
  @Environment(\.horizontalSizeClass) private var sizeClass
  private var hasSidebar: Bool { sizeClass == .regular }

  /**
   The width at which the list and the entry pane can sit side by side.

   Measured from this screen's own geometry, *not* taken from the horizontal
   size class, and the difference is not academic. The size class says
   "regular" for the whole of an iPad, but this screen is the detail column of
   a split view: with the sidebar showing on an 834pt portrait iPad it actually
   gets ~514pt, and a fixed 380pt entry pane would leave the list 134pt —
   narrow enough that every amount wrapped to one digit per line. Stage Manager
   and Split View make the same point more sharply, since there the window can
   be any width at all.

   The threshold is the entry pane plus the narrowest list still worth reading:
   a note and an amount need roughly 320.
   */
  static let splitThreshold: CGFloat = entryPaneWidth + 320

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

    // The layout reads the proxy directly rather than mirroring it into
    // `@State` first. Routing it through state cost an afternoon: the width
    // updated and the branch did not, because the two were evaluated a beat
    // apart. A width taken straight from the proxy cannot be stale.
    GeometryReader { geo in
      let wide = geo.size.width >= Self.splitThreshold

      ZStack {
        ScreenBackground()

        if wide { wideLayout } else { compactLayout }
      }
      .frame(width: geo.size.width, height: geo.size.height)
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
    .focusEffectDisabled()
    .onKeyPress(action: handleKeyPress)
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

   ⚠️ NOT CURRENTLY REACHED — the iPad falls back to `compactLayout`, which
   works. The layout itself is sound: forcing the condition to `true` renders it
   correctly. What fails is deciding *when* to use it, inside a
   NavigationSplitView's detail column.

   Four approaches tried on an iPad Pro 11 (26.5), all on the same symptom —
   when the sidebar collapses the column goes 504 → 834 and the screen does not
   follow:

   1. `@Environment(\.horizontalSizeClass)`. Wrong signal: "regular" for a whole
      iPad, including when this column is 504pt. Left the list 134pt wide, one
      digit per line.
   2. `GeometryReader` → `@State` → branch. `onChange` received 834; the branch
      kept rendering the 504 arm.
   3. `GeometryReader` → branch directly off the proxy, no state. Identical.
      Proved by giving `wideLayout` a red background that never appeared while
      a debug title in the same `body` read `w=834 WIDE`.
   4. `ViewThatFits(in: .horizontal)`. Always picks the wide arm and overflows
      off-screen, because a `List`'s ideal width is unbounded so it always
      "fits". A `minWidth` on the list column does not bound it.

   Adding `.id(wide)` to the container does force the rebuild — so (2)/(3) are
   view-identity reuse — but the proxy then supplies 504 to the `.frame()` while
   the container is 834, so the content lays out at the old width in the new
   space. The proxy is genuinely inconsistent between content build and change
   notification here.

   **Strongest remaining lead:** stop making this screen a
   `NavigationSplitView` detail column. Build the iPad arrangement one level up
   in `RootView` as a plain `HStack { SavedScreen; calculator }`, where nothing
   is re-proposing a column width behind SwiftUI's back. That is a restructure
   of `RootView`, not of this file.

   The total stays with the list rather than moving to the entry pane, because
   it is the list's answer — the sum of what is in that column. In select mode
   it becomes the subtotal in the same place, so the lines being picked and the
   number they come to stay in one column.
   */
  private var wideLayout: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        listOrEmpty
        if store.showTotal || selectMode { totalBar }
      }

      Rectangle()
        .fill(t.line)
        .frame(width: 1 / 3)
        .ignoresSafeArea(edges: .bottom)

      VStack(spacing: 0) {
        Spacer(minLength: 0)
        if !selectMode { EntryCardSection }
        keypadSection
      }
      .frame(width: Self.entryPaneWidth)
    }
  }

  /**
   The trailing pane's width.

   380 is not arbitrary: with the keypad's own 16pt side padding and 8pt gaps it
   puts each key at ~81pt, which is within a point of what the same keypad
   measures on a 393pt iPhone. The pad keeps the proportions it was designed
   with instead of being stretched to whatever is left over — which is exactly
   what made the iPad build before this look like a blown-up phone.
   */
  static let entryPaneWidth: CGFloat = 380

  // MARK: - The list

  @ViewBuilder
  private var listOrEmpty: some View {
    if store.entries.isEmpty {
      VStack(spacing: Space.s3) {
        Text("Nothing tallied yet.")
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
      canReference: editIndex.map { index < $0 } ?? true,
      selectMode: selectMode,
      picked: picked.contains(entry.id),
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
      if store.showTotal || selectMode {
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
    let value = selectMode ? subtotal : store.total
    return HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
      Text(totalLabel)
        .font(.tally(TallyFont.sansMedium, TextScale.bodySm))
        .foregroundStyle(copied ? t.accentInk : t.ink2)
        .lineLimit(1)
        .contentTransition(.opacity)
      Spacer()
      // The total lands on its new value outright — no count-up tween, no scale
      // pulse: it is a number you read, not an event.
      Text(Calc.fmt(value))
        .font(.tally(TallyFont.monoSemi, TextScale.numLg))
        .monospacedDigit()
        .tracking(-0.2)
        .foregroundStyle(
          selectMode ? (picked.isEmpty ? t.ink3 : t.accentInk) : t.ink)
    }
    .padding(.top, Space.s2)
    .padding(.horizontal, Space.s5)
    .padding(.bottom, Space.s2)
    .overlay(alignment: .top) {
      Rectangle().fill(t.line).frame(height: 1 / 3).padding(.horizontal, Space.s5)
    }
    .contentShape(.rect)
    // Long-press the running total — or a selection's subtotal — to copy the
    // plain number, so it pastes cleanly into spreadsheets and other apps.
    .onLongPressGesture(minimumDuration: 0.35) { copyTotal(value) }
    .animation(.easeOut(duration: 0.2), value: copied)
  }

  private var totalLabel: String {
    if copied { return "Copied" }
    guard selectMode else { return "Total" }
    return picked.isEmpty
      ? "Tap lines to add them up"
      : "\(picked.count) of \(store.entries.count) selected"
  }

  // MARK: - The entry card

  @ViewBuilder
  private var EntryCardSection: some View {
    let editIndex = editingID.flatMap { id in store.entries.firstIndex { $0.id == id } }
    // A line in error resolves to nothing, so it is not offered.
    let visible = (editIndex.map { Array(store.entries.prefix($0)) } ?? store.entries)
      .filter { $0.error != true }

    EntryCard(
      draft: $draft,
      note: $note,
      noteOpen: $noteOpen,
      highlighted: flash || editingID != nil,
      padStowed: padStowed,
      nameFor: nameFor,
      referenceable: Array(visible.suffix(12).reversed()),
      referenceSum: totalOf(visible),
      resolve: resolveRef,
      onTapCard: { showPad() },
      onInsertRef: { id, sourceNote in insertRef(id, note: sourceNote) }
    )
  }

  // MARK: - The keypad
  //
  // ---- keypad avoidance (HIG "Virtual keyboards": keyboard layout guide) ----
  // Two things want the keypad out of the way, and they share one collapse so
  // they can never fight over the same height:
  //
  //   · the system keyboard. Text entry here — the ✎ note — used to raise it
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

  private var keypadSection: some View {
    VStack(spacing: 0) {
      Keypad(onPress: press, bottomInset: safeBottom)
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

  private var padDrag: some Gesture {
    DragGesture(minimumDistance: 8)
      .onChanged { value in
        guard padHeight > 0, abs(value.translation.height) > abs(value.translation.width) else {
          return
        }
        if stowAtDragStart == -1 { stowAtDragStart = stow }
        stow = min(1, max(0, stowAtDragStart + value.translation.height / padHeight))
      }
      .onEnded { value in
        guard padHeight > 0 else { return }
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

    let key: Key? =
      switch event.key {
      case .return: .enter
      case .delete: .backspace
      case .escape: .clear
      default:
        switch event.characters {
        // '=' commits too — every physical calculator says so, and the keypad's
        // own ↵ is in the same place on the numeric pad.
        case "=", "\r", "\n": .enter
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
    switch key {
    case .clear: clearDraft()
    case .note: noteOpen.toggle()
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

  /// No haptic: a menu pick, and the pill landing in the draft is the feedback.
  private func insertRef(_ id: String, note sourceNote: String?) {
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
    if id == "sum" { return "Σ total" }
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
      // Saved calculations — the one destination worth a direct door. This is
      // the root screen, so the slot isn't fighting a back button.
      //
      // Withheld when the archive is already a column away: a button that
      // pushed a second copy of the sidebar over the detail would be worse
      // than no button.
      if !hasSidebar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink(value: Route.saved) {
            Label("Saved calculations", systemImage: "tray.full")
          }
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("New calculation", systemImage: "plus") {
          Haptic.tap.play()  // a fresh tab started — the working one is filed, not lost
          store.newTab()
          showPad(silent: true)  // a fresh tab is there to be typed into
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
      if !hasSidebar {
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
