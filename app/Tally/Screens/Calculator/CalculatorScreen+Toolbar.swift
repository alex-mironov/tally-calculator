// CalculatorScreen+Toolbar.swift — the navigation bar: its title, the leading
// archive door, New, and the More menu with everything you can do to this
// calculation — including sharing it as a link.
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
      // In landscape, nothing: the archive is on screen as the sidebar, and
      // its own "+" is the way to a fresh calculation. The design leaves that
      // bar to the title alone — no sidebar toggle either, since the column is
      // the layout rather than a panel to be put away.
      if layout == .phone {
        ToolbarItem(placement: .topBarLeading) {
          // Saved calculations — the one destination worth a direct door. This
          // is the root screen, so the slot isn't fighting a back button.
          NavigationLink(value: Route.saved) {
            Label("Saved calculations", systemImage: "tray.full")
          }
        }
        ToolbarItem(placement: .topBarTrailing) { newButton }
      } else if layout == .padPortrait {
        // Both doors on the leading edge, as the design's portrait header has
        // them, leaving the trailing side to the title's menu. The tray opens
        // the archive over the calculator rather than pushing it.
        ToolbarItemGroup(placement: .topBarLeading) {
          Button("Saved calculations", systemImage: "tray.full") { openSaved?() }
          newButton
        }
      }
      // The title is the menu: tapping the tab's name opens what can be done
      // to it, with the system's own chevron beside the name. v2 draws this as
      // a pill in the bar's trailing corner; the native title menu is the same
      // idea without a second, hand-drawn control competing with the bar's
      // glass (docs/v2-design.md, "Title/menu"). It replaces the ellipsis
      // button that held these items before.
      ToolbarTitleMenu { moreMenu }
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

  /// A fresh calculation — the working one is filed, not lost.
  private var newButton: some View {
    Button("New calculation", systemImage: "plus") {
      Haptic.tap.play()
      store.newTab()
      showPad(silent: true)  // a fresh tab is there to be typed into
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
}
