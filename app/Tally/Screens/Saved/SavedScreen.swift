// SavedScreen.swift — the archive of filed calculations, with the current
// unsaved draft pinned above them so work is never lost.
//
// A tag strip across the top filters to one tag; search matches names and
// tags. Every row gets real swipe actions and a real long-press context menu,
// and "Edit tags" from either opens the tag catalog as a picker sheet for that
// row (TagsSheet). Deleting a calculation asks first: it is the one thing on
// this screen that cannot be taken back.
//
// Drawn to tally-saved-r.jsx: the draft card on the soft accent with a Save
// pill in the call-to-action colours, and an empty state of three ghost cards
// stacked above the copy.
//
// Ported from mobile/src/app/saved.tsx. Two of that file's shapes were
// workarounds and are gone: the whole body was pushed down by `headerHeight`
// because iOS 26 floats the nav bar and `contentInsetAdjustmentBehavior` was
// not available to a hosted SwiftUI List; and the empty state had to *replace*
// the list entirely, because rows there were hosted RN views the list sized
// itself. Here the list handles its own insets and the empty state lives
// inside it.
import SwiftUI
import TallyKit

struct SavedScreen: View {
  /// Where the archive is on screen — which decides what happens after you
  /// act, and where its search field goes.
  enum Placement {
    /// Pushed over the calculator, on a phone: a detour, which gets out of the
    /// way once you have opened something.
    case pushed
    /// The landscape iPad's permanent column: where you live, so it stays put.
    case sidebar
    /// The portrait iPad's panel over the calculator, closed by `close` once
    /// a calculation is opened or started — as a push would be.
    case overlay
  }

  var placement: Placement = .pushed
  /// Closes the overlay. Only the overlay has one.
  var close: (() -> Void)?

  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t
  @Environment(\.dismiss) private var dismiss

  @State private var query = ""
  @State private var filter: String?

  // ---- sheets ----
  /// Naming the unsaved draft — the draft card's Save, and the empty state's.
  @State private var renameOpen = false
  /// The saved calculation whose tags are being edited.
  @State private var tagging: TagTarget?
  /// The calculation waiting on "Delete “X”?".
  @State private var deleting: TallyKit.Tab?

  private var hasDraft: Bool { store.activeID == nil && !store.entries.isEmpty }

  /// Newest first, then the search (name + tags) and the single tag filter.
  private var list: [TallyKit.Tab] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return store.tabs
      .sorted { $0.savedAt > $1.savedAt }
      .filter { tab in
        let tags = tab.resolvedTags
        if let filter, !tags.contains(filter) { return false }
        guard !q.isEmpty else { return true }
        return (tab.name + " " + tags.joined(separator: " ")).lowercased().contains(q)
      }
  }

  var body: some View {
    // The sidebar is the screen colour too, flat: the design's column is set
    // apart by the 1px rule RootView draws down its trailing edge, not by a
    // tonal wash of its own.
    VStack(spacing: 0) {
      // The quick filter, pinned above the list so it stays reachable however
      // far down you have scrolled.
      TagFilterBar(tabs: store.tabs, catalog: store.catalog, active: $filter)

      List {
        if hasDraft && filter == nil && query.isEmpty {
          Section { draftCard }
        }

        if list.isEmpty {
          // Edge to edge: the ghost stack's shadow is wider than the cards,
          // and in the 320pt sidebar the section's margins cut it off in two
          // straight vertical lines either side.
          Section { emptyState.listRowSeparator(.hidden) }
            .listSectionMargins(.horizontal, 0)
        } else {
          Section {
            ForEach(list) { tab in
              SavedRow(
                tab: tab,
                isOpen: tab.id == store.activeID,
                onOpen: { open(tab) },
                onDelete: { deleting = tab },
                onEditTags: { tagging = .tab(tab.id) }
              )
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
    }
    .background { ScreenBackground() }
    .navigationTitle("Saved")
    .navigationBarTitleDisplayMode(.inline)
    .modifier(SavedSearch(query: $query, inColumn: placement != .pushed))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("New calculation", systemImage: "plus") {
          Haptic.tap.play()  // the same tick as the "+" on the tab
          store.newTab()
          finish()
        }
      }
    }
    .sheet(isPresented: $renameOpen) { RenameSheet(name: store.tabName) }
    .sheet(item: $tagging) { TagsSheet(target: $0) }
    // HIG "Action sheets": confirm a destructive action the user started, and
    // name what is about to go. The same dialog for the swipe and the menu.
    .confirmationDialog(
      deleting.map { "Delete “\(Self.title(of: $0))”?" } ?? "",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible,
      presenting: deleting
    ) { tab in
      Button("Delete", role: .destructive) { delete(tab) }
    } message: { _ in
      Text("This can’t be undone.")
    }
  }

  private static func title(of tab: TallyKit.Tab) -> String {
    tab.name.isEmpty ? "Untitled" : tab.name
  }

  // MARK: - The pinned draft

  /// Drawn as its own card rather than as a list row's background: the design
  /// gives it a 20pt radius of its own, which a row in an inset section cannot
  /// have — the section decides a row's corners.
  private var draftCard: some View {
    HStack(spacing: Space.s3) {
      VStack(alignment: .leading, spacing: Space.s1) {
        Text("Current · unsaved")
          .tallyFont(TallyFont.textSemi, 16)
          .foregroundStyle(t.accentText)
        Text(draftSubtitle)
          .tallyFont(TallyFont.text, 14)
          .foregroundStyle(t.ink2)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // The card's one action, and the most likely thing to do on this screen,
      // so it is the call to action — in cta with its own ink, never white on
      // a bright fill.
      Button { renameOpen = true } label: {
        Text("Save")
          .tallyFont(TallyFont.textSemi, 15)
          .foregroundStyle(t.ctaInk)
          .padding(.horizontal, Space.s4)
          .frame(minHeight: 36)
          .background(t.cta, in: .capsule)
          .contentShape(.capsule)
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, Space.s4)
    .padding(.horizontal, Space.s4)
    .background(t.chipBg, in: .rect(cornerRadius: 20))
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets())
  }

  /// "Name — 4 items · 1,250.00", as the design writes it.
  private var draftSubtitle: String {
    let n = store.entries.count
    let prefix = store.tabName.isEmpty ? "" : store.tabName + " — "
    return "\(prefix)\(n) item\(n == 1 ? "" : "s") · \(Calc.fmt(store.total))"
  }

  // MARK: - Empty

  @ViewBuilder
  private var emptyState: some View {
    if let filter {
      ContentUnavailableView {
        Text("Nothing tagged “\(filter)”.")
          .tallyFont(TallyFont.text, 28)
          .foregroundStyle(t.ink2)
      } description: {
        Text("Try clearing the filter, or tag more calculations.")
          .tallyFont(TallyFont.text, 17)
          .foregroundStyle(t.ink2)
      }
      .listRowBackground(Color.clear)
    } else if !query.isEmpty {
      ContentUnavailableView.search(text: query)
        .listRowBackground(Color.clear)
    } else {
      // Drawn rather than a ContentUnavailableView: that view's actions slot,
      // inside a list row, stretched its button to the row's full height.
      VStack(spacing: 0) {
        GhostStack()
          .padding(.bottom, Space.s8)
        Text("Nothing filed away yet.")
          .tallyFont(TallyFont.text, 28)
          .tracking(-0.3)
          .foregroundStyle(t.ink2)
          .frame(maxWidth: 280)
        Text("Name the calculation you’re on and it will be filed here.")
          .tallyFont(TallyFont.text, 17)
          .foregroundStyle(t.ink2)
          .frame(maxWidth: 260)
          .padding(.top, Space.s3)
        // The way out of an empty archive: file what is on the tab, or start
        // one worth filing. Tonal, not the call to action — the screen's
        // message is the copy above it.
        Button {
          if hasDraft {
            renameOpen = true
          } else {
            Haptic.tap.play()
            store.newTab()
            finish()
          }
        } label: {
          // An HStack rather than a Label: a Label's icon column is far wider
          // than the design's 6pt gap.
          HStack(spacing: Space.s2) {
            Image(systemName: hasDraft ? "checkmark" : "plus")
              .font(.system(size: 15, weight: .bold))
            Text(hasDraft ? "Save current calculation" : "Start a calculation")
              .tallyFont(TallyFont.textSemi, 15)
          }
          .foregroundStyle(t.accentText)
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 40)
            .background(t.chipBg, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .padding(.top, Space.s6)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Space.s10)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    }
  }

  // MARK: - Actions
  //
  // No haptic on opening or on the way to the tag catalog — those are
  // navigation, and the screen changing is the feedback.

  private func open(_ tab: TallyKit.Tab) {
    store.openTab(id: tab.id)
    finish()
  }

  /// Out of the way once a calculation is open, unless this is the sidebar.
  private func finish() {
    switch placement {
    case .pushed: dismiss()
    case .sidebar: break
    case .overlay: close?()
    }
  }

  private func delete(_ tab: TallyKit.Tab) {
    Haptic.impact.play()
    withAnimation { store.deleteTab(id: tab.id) }
  }
}

/**
 Where Saved's search field sits: floating at the foot of the list, in the
 thumb zone, as the design draws it (tally-saved-r.jsx, `searchWrap`).

 On a phone that is iOS 26's own toolbar search, which a pushed screen already
 puts at the bottom. On an iPad it is not: iPadOS sends `.toolbar` search to
 the top trailing corner of the nav bar as a button, and
 `DefaultToolbarItem(kind: .search, placement: .bottomBar)` does not move it —
 tried in the sidebar, where a bottom bar *does* render inside the 320pt column,
 and the search stayed up top regardless. So the iPad's column and overlay draw
 the design's field themselves (`ColumnSearchField`), as an inset at the foot of
 the list so the last row can still scroll clear of it.
 */
private struct SavedSearch: ViewModifier {
  @Binding var query: String
  let inColumn: Bool

  func body(content: Content) -> some View {
    if inColumn {
      content.safeAreaInset(edge: .bottom, spacing: 0) {
        ColumnSearchField(query: $query)
      }
    } else {
      content.searchable(text: $query, placement: .toolbar, prompt: "Search calculations")
    }
  }
}

/**
 The design's floating search field (tally-ios.jsx, `SearchField floating`): a
 52pt capsule of glass over the bottom of the list, a magnifier, the field, and
 a clear button once there is something to clear. Floating chrome, so system
 glass — like the toasts, and unlike the opaque dock.
 */
private struct ColumnSearchField: View {
  @Binding var query: String

  @Environment(\.theme) private var t
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: Space.s2) {
      // The design's 19pt glyph, on the grid.
      Image(systemName: "magnifyingglass")
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(t.ink)
        .accessibilityHidden(true)
      TextField("Search calculations", text: $query)
        .tallyFont(TallyFont.text, 17)
        .foregroundStyle(t.ink)
        .focused($focused)
        .submitLabel(.search)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onKeyPress(.escape) {
          query = ""
          focused = false
          return .handled
        }
      if !query.isEmpty {
        // The clear button HIG "Search fields" asks for; a plain TextField has
        // none of its own.
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(t.ink3)
        }
        .buttonStyle(.plain)
        .hitTarget()
        .accessibilityLabel("Clear search")
      }
    }
    // The design's 18 either side, on the grid.
    .padding(.horizontal, Space.s4)
    .frame(height: 52)
    .contentShape(.capsule)
    .onTapGesture { focused = true }
    .glassEffect(.regular.interactive(), in: .capsule)
    .dynamicTypeSize(...TypeCap.chrome)
    // The design's 16 either side, and 22 above the bottom edge — 4 over the
    // home indicator's inset here, which puts it 24 from the edge on the grid.
    .padding(.horizontal, Space.s4)
    .padding(.bottom, Space.s1)
  }
}

/**
 The empty archive's illustration: three blank cards stacked back to front,
 each narrower, higher and fainter than the one before it (tally-saved-r.jsx,
 `ghost`). Decorative, so hidden from VoiceOver.
 */
private struct GhostStack: View {
  @Environment(\.theme) private var t

  /// Back to front: width as a share of the front card, rise above it, opacity.
  /// The design's rises are 34 and 17; on the grid they are 32 and 16.
  private let layers: [(width: CGFloat, rise: CGFloat, opacity: Double)] = [
    (0.72, 32, 0.45), (0.86, 16, 0.7), (1, 0, 1),
  ]

  var body: some View {
    ZStack(alignment: .bottom) {
      ForEach(layers.indices, id: \.self) { i in
        let layer = layers[i]
        card(front: i == layers.count - 1)
          .frame(width: 268 * layer.width)
          .offset(y: -layer.rise)
          .opacity(layer.opacity)
      }
    }
    .padding(.top, 32)  // room for the two cards rising behind the front one
    .shadow(color: .black.opacity(0.06), radius: 16, y: 16)
    .accessibilityHidden(true)
  }

  private func card(front: Bool) -> some View {
    HStack(spacing: Space.s3) {
      VStack(alignment: .leading, spacing: Space.s2) {
        bar(width: front ? 96 : 72)
        bar(width: front ? 56 : 44).opacity(0.7)
      }
      Spacer(minLength: 0)
      if front {
        Text("—")
          .tallyFont(TallyFont.monoSemi, 15)
          .foregroundStyle(t.ink3)
      }
    }
    .padding(Space.s4)
    .background(t.card, in: .rect(cornerRadius: 20))
    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(edge, lineWidth: 1) }
  }

  // The design draws the edge and the bars in `t.line`. That token is tuned to
  // read against the *screen* — it is the rows' hairline — and on two surfaces
  // it vanishes against the card instead: Midnight's sidebar (#1f1f22 on a
  // #1c1c1e card) and Paper (#efeff1 on #f4f4f5). The secondary ink at a low
  // opacity reads on whatever card it is laid over, light or dark, raised or
  // not, and keeps each scheme's tint: Lilac's line *is* its ink2 at 0.16.

  /// The card's 1pt edge.
  private var edge: Color { t.ink2.opacity(0.16) }

  /// A line of text that isn't there. The design's bars are 9 and 7 tall;
  /// both are 8 here, the second told apart by its opacity and length.
  private func bar(width: CGFloat) -> some View {
    Capsule().fill(t.ink2.opacity(0.24)).frame(width: width, height: 8)
  }
}
