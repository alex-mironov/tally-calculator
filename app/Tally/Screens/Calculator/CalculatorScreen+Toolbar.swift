// CalculatorScreen+Toolbar.swift — the navigation bar: the archive door and
// New on the leading edge, and the calculation's name as the menu of
// everything you can do to it — including sharing it as a link.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Navigation bar

  var navigationTitle: String {
    // The design's count reads from zero — "0 selected" is the honest answer
    // the moment the mode opens, and the footer's "0 of 6" agrees with it.
    if selectMode { return "\(picked.count) selected" }
    return store.tabName.isEmpty ? "New calculation" : store.tabName
  }

  @ToolbarContentBuilder
  var toolbar: some ToolbarContent {
    if selectMode {
      // Select mode borrows both bar slots, the way Mail and Photos do: Select
      // All on the leading edge, the confirming action on the trailing one.
      // The design's sentence case, which the rest of the app's labels share.
      ToolbarItem(placement: .topBarLeading) {
        Button(allPicked ? "Deselect all" : "Select all") {
          Haptic.select.play()
          withAnimation(.easeOut(duration: 0.2)) {
            picked = allPicked ? [] : Set(store.entries.map(\.id))
          }
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        // `prominent` is the style HIG names for key actions such as Done, and
        // the design fills it in the call to action — the one cta mark in the
        // bar. The bar draws the container, so a bare `checkmark` is all this
        // supplies — no `.circle` variant, which would draw a second ring
        // inside the bar's capsule. The glyph takes ctaInk: on Midnight's lime
        // the system's white checkmark all but disappears.
        Button(action: endSelect) {
          Image(systemName: "checkmark").foregroundStyle(t.ctaInk)
        }
        .buttonStyle(.glassProminent)
        .tint(t.cta)
        .accessibilityLabel("Done selecting")
      }
    } else {
      // The design's header (tally-app-v2.jsx, `header`): the two doors
      // together on the leading edge — the archive, and a fresh calculation
      // filled in the scheme's deep tone — and the calculation's name on the
      // trailing edge as the menu of what can be done to it. In landscape the
      // archive is on screen as the sidebar, with its own "+", so the bar is
      // left to the name alone (and no sidebar toggle: the column is the
      // layout, not a panel to put away).
      if layout != .padLandscape {
        ToolbarItem(placement: .topBarLeading) { savedDoor }
        // Two capsules, not one: the design draws them as separate circles,
        // and the filled one reads as the primary action only on its own.
        ToolbarSpacer(.fixed, placement: .topBarLeading)
        ToolbarItem(placement: .topBarLeading) { newButton }
      }
      ToolbarItem(placement: .topBarTrailing) { titleMenu }
    }
  }

  /**
   The name and a chevron, opening the calculation's menu — v2's title pill.
   It replaces the system's centred title (hidden in CalculatorScreen's body
   outside select mode): the design moves the name to the trailing corner, so
   the two doors can sit together on the other side. A native `Menu` in a bar
   item, so the bar draws its capsule and the system draws the menu.
   */
  private var titleMenu: some View {
    Menu {
      moreMenu
    } label: {
      HStack(spacing: Space.s2) {
        Text(navigationTitle)
          .tallyFont(TallyFont.textMedium, 15)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 12, weight: .semibold))
      }
      // The design's 236pt cap, onto the grid; a long name truncates.
      .frame(maxWidth: 236)
      .fixedSize()
    }
    .accessibilityLabel("\(navigationTitle), calculation menu")
  }

  /// The archive: a push on a phone, the overlay on a portrait iPad.
  @ViewBuilder
  private var savedDoor: some View {
    if layout == .padPortrait {
      Button("Saved calculations", systemImage: "tray.full") { openSaved?() }
    } else {
      NavigationLink(value: Route.saved) {
        Label("Saved calculations", systemImage: "tray.full")
      }
    }
  }

  /**
   The title menu's items.

   "New calculation" is the one action frequent enough to be worth a bar slot
   of its own, so it is promoted out rather than sitting in both.
   */
  @ViewBuilder
  private var moreMenu: some View {
    // What you can do to this calculation, in the design's order
    // (tally-app-v2.jsx, menuItems). An unnamed tab is named rather than
    // renamed; either way the sheet is the name alone, and tags are their own
    // item.
    Button(store.tabName.isEmpty ? "Name…" : "Rename…", systemImage: "pencil") {
      renameOpen = true
    }
    Button("Tags…", systemImage: "tag") { tagsOpen = true }
    Button("Copy total", systemImage: "doc.on.doc") { copyTotal(store.total) }
    // An app extra v2 omits, kept (docs/v2-design.md, "Decisions").
    if !store.entries.isEmpty {
      Button("Share link…", systemImage: "square.and.arrow.up") {
        Task { await shareLink() }
      }
    }
    // Always listed, so the menu keeps its shape; with nothing to pick it is
    // dimmed rather than missing.
    Button("Select lines", systemImage: "checkmark.circle") { startSelect() }
      .disabled(store.entries.isEmpty)
    Divider()
    // …and where else to go. Starting a fresh one is the "+" beside this
    // menu, so it isn't repeated here — and neither is the archive when it is
    // already on screen as the sidebar.
    switch layout {
    case .phone:
      NavigationLink(value: Route.saved) { savedLabel }
    case .padPortrait:
      Button { openSaved?() } label: { savedLabel }
    case .padLandscape:
      EmptyView()
    }
    // A push on a phone; on an iPad a form sheet over the calculator, with
    // the tag catalog pushing inside it (SettingsSheet).
    if layout.isPad {
      Button("Settings", systemImage: "gearshape") { settingsOpen = true }
    } else {
      NavigationLink(value: Route.settings) {
        Label("Settings", systemImage: "gearshape")
      }
    }
  }

  private var savedLabel: some View {
    Label(
      store.tabs.isEmpty ? "Saved calculations" : "Saved calculations (\(store.tabs.count))",
      systemImage: "tray.full")
  }

  /**
   A fresh calculation — the working one is filed, not lost. The design's
   filled circle: `.glassProminent` tinted the deep tone, so the bar fills its
   own capsule rather than a circle being drawn inside it; the glyph takes
   deepInk, as the select-mode Done takes ctaInk, since the system's white
   vanishes on Midnight's pale deep.
   */
  private var newButton: some View {
    Button {
      Haptic.tap.play()
      store.newTab()
      showPad(silent: true)  // a fresh tab is there to be typed into
    } label: {
      Image(systemName: "plus").foregroundStyle(t.deepInk)
    }
    .buttonStyle(.glassProminent)
    .tint(t.deep)
    .accessibilityLabel("New calculation")
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
}
