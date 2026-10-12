// CalculatorScreen+Toolbar.swift — the navigation bar: its title, the leading
// archive door, New, and the More menu with everything you can do to this
// calculation — including sharing it as a link.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Navigation bar

  var navigationTitle: String {
    if selectMode {
      return picked.isEmpty ? "Select lines" : "\(picked.count) selected"
    }
    return store.tabName.isEmpty ? "New calculation" : store.tabName
  }

  @ToolbarContentBuilder
  var toolbar: some ToolbarContent {
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
