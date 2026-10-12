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
//     give the list that space back: drag the dock's grabber, or tap it
//     (see "keypad avoidance" in CalculatorScreen+Dock);
//   · stowing and the system keyboard share one collapse path, so they can
//     never fight over the same height;
//   · select mode is a read-only lens over the tab *in place* — the tab becomes
//     the answer rather than opening a second copy of itself.
//
// This file is the composition root: the screen's state and its body. The rest
// is split by area, as extensions on this type unless it is a view of its own:
//
//   CalculatorScreen+Layout   phone column, iPad portrait, iPad landscape
//   CalculatorList            the lines, or the empty state
//   HeroTotal                 the total at the head, copying it, the toasts
//   CalculatorScreen+Dock     the input dock: entry row, draft, keys, stow
//   CalculatorScreen+Draft    keys, commit, edit, delete and its undo, references
//   CalculatorScreen+Keyboard a hardware keyboard driving the pad
//   CalculatorScreen+Select   select mode, and its footer in the dock's place
//   CalculatorScreen+Toolbar  title, bar buttons, More menu, share link
import Combine
import SwiftUI
import TallyKit

struct CalculatorScreen: View {
  @Environment(TallyStore.self) var store
  @Environment(\.theme) var t

  /**
   Which of the three layouts to draw: the phone's column, the portrait iPad's
   wider column with a centred dock, or the landscape iPad's main column with
   the dock in a pane of its own.

   A plain parameter, decided by `RootView` from the *window's* width. This
   screen deliberately does no measuring of its own: every previous attempt to
   work it out from here — size class, GeometryReader through state,
   GeometryReader off the proxy, ViewThatFits — failed the same way, because
   this used to be the detail column of a NavigationSplitView and the width
   reaching the branch disagreed with the width reaching the container. There is
   no split view any more and no geometry here; see RootView.
   */
  var layout: LayoutMode = .phone

  /// The width this screen is laid out at — the window, less the sidebar where
  /// there is one. Worked out by `RootView` for the same reason as `layout`;
  /// only the portrait iPad's dock reads it.
  var width: CGFloat = 0

  /**
   Opens the archive as an overlay — the portrait iPad's.

   `nil` everywhere else: on a phone the archive is a push, and in landscape it
   is already on screen as the sidebar, so the toolbar has no door to it at all.
   */
  var openSaved: (() -> Void)?

  // ---- the line being typed ----
  @State var draft = ""
  @State var note = ""
  @State var noteOpen = false
  @State var editingID: String?
  /// Bumped when an invalid commit is refused; each bump shakes the draft.
  @State var shakes = 0
  @State var copied = false
  /// The latest delete, while its "Undo" is on offer (CalculatorScreen+Draft).
  @State var undo: TallyStore.DeletedLine?
  /// Freshly committed: drives the row's one-shot highlight and the scroll.
  @State var justAddedID: String?
  /// Reference mode, from the keypad's link key: tapping a line or the total
  /// drops it into the draft. Any other key, or a pick, ends it.
  @State var referencing = false

  // ---- keypad stow ----
  /// 0 = keypad up, 1 = fully stowed. Intermediate values are the live drag.
  @State var stow: CGFloat = 0
  /// -1 while no drag is in progress, so the first onChanged can capture
  /// where the drag started from.
  @State var stowAtDragStart: CGFloat = -1
  @State var padHeight: CGFloat = 0
  @State var keyboardHeight: CGFloat = 0

  // ---- sheets and sharing ----
  /// The menu's "Rename…" / "Name…": the name-only sheet.
  @State var renameOpen = false
  /// The menu's "Tags…": the tag catalog as this tab's picker.
  @State var tagsOpen = false
  /// Settings as a form sheet — iPad only; a phone pushes it.
  @State var settingsOpen = false
  @State var share: SharePayload?
  @State var shareFailed = false

  // ---- hardware keyboard ----
  /**
   Whether the pad has keyboard focus.

   `.onKeyPress` only fires on a view that *has* focus, and nothing gives a
   plain view focus on its own — so without this the handler (in
   CalculatorScreen+Keyboard.swift) was written, compiled, and unreachable:
   typing on an attached keyboard did nothing at all.
   Focus is taken on appear, and taken back whenever the note field lets go of
   it (the field steals it while it is open, which is correct — those keys are
   the note's).
   */
  @FocusState var padFocused: Bool

  // ---- multi-select ----
  @State var selectMode = false
  @State var picked: Set<String> = []

  var body: some View {
    @Bindable var store = store

    ZStack {
      ScreenBackground()

      switch layout {
      case .phone: compactLayout
      case .padPortrait: portraitLayout
      case .padLandscape: wideLayout
      }
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
    // An undo belongs to its tab too: the store would refuse it on another
    // tab anyway, but the toast shouldn't offer what it can't do.
    .onChange(of: store.tabEpoch) {
      clearDraft()
      undo = nil
    }
    // A hardware keyboard drives the pad. Nearly free, and on an iPad — where
    // one is often attached — it is the difference between a calculator you
    // poke at and one you can actually run a list of numbers through.
    .focusable()
    .focused($padFocused)
    .focusEffectDisabled()
    .onKeyPress(action: handleKeyPress)
    .onAppear { padFocused = true }
    .onChange(of: noteOpen) { _, open in if !open { padFocused = true } }
    .sheet(isPresented: $renameOpen) { RenameSheet(name: store.tabName) }
    .sheet(isPresented: $tagsOpen) { TagsSheet(target: .current) }
    .sheet(isPresented: $settingsOpen) { SettingsSheet() }
    .sheet(item: $share) { ActivityView(items: [$0.url]) }
    .alert("Couldn’t create the link", isPresented: $shareFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Check your connection and try again.")
    }
  }
}
