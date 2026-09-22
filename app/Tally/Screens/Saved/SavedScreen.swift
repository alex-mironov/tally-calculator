// SavedScreen.swift — the archive of filed calculations, with the current
// unsaved draft pinned above them so work is never lost.
//
// A tag strip across the top filters to one tag; the nav bar's search matches
// names and tags. Every row gets real swipe actions and a real long-press
// context menu, with Tags ▸ as a submenu for quick tagging and "Manage tags…"
// opening the catalog for anything heavier.
//
// Ported from mobile/src/app/saved.tsx. Two of that file's shapes were
// workarounds and are gone: the whole body was pushed down by `headerHeight`
// because iOS 26 floats the nav bar and `contentInsetAdjustmentBehavior` was
// not available to a hosted SwiftUI List; and the empty state had to *replace*
// the list entirely, because rows there were hosted RN views the list sized
// itself. Here the list handles its own insets and `ContentUnavailableView`
// lives inside it.
import SwiftUI
import TallyKit

struct SavedScreen: View {
  /**
   Presented as the iPad's permanent sidebar rather than pushed.

   The only difference is what happens after you act: a pushed archive is a
   detour and gets out of the way once you have opened something, while a
   sidebar is where you live and stays put.
   */
  var inSidebar = false

  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t
  @Environment(\.dismiss) private var dismiss

  @State private var query = ""
  @State private var filter: String?
  @State private var saveOpen = false

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
    ZStack {
      ScreenBackground()

      VStack(spacing: 0) {
        // The quick filter, pinned above the list so it stays reachable however
        // far down you have scrolled.
        TagFilterBar(tabs: store.tabs, catalog: store.catalog, active: $filter)

        List {
          if hasDraft && filter == nil && query.isEmpty {
            Section { draftCard }
          }

          if list.isEmpty {
            emptyState
          } else {
            Section {
              ForEach(list) { tab in
                SavedRow(
                  tab: tab,
                  isOpen: tab.id == store.activeID,
                  onOpen: { open(tab) },
                  onDelete: { delete(tab) },
                  onToggleTag: { toggleTag(tab, $0) }
                )
              }
            }
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
      }
    }
    .navigationTitle("Saved")
    .navigationBarTitleDisplayMode(.inline)
    // A real search field in the nav bar, which brings the system clear button,
    // the cancel button, the "search" return key and no-autocapitalise /
    // no-autocorrect behaviour with it.
    // `.always`, not the default: the search field is part of the screen's
    // chrome rather than something to hunt for by scrolling up.
    .searchable(
      text: $query, placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search calculations")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("New calculation", systemImage: "plus") {
          Haptic.tap.play()  // the same tick as the "+" on the tab
          store.newTab()
          if !inSidebar { dismiss() }
        }
      }
    }
    .sheet(isPresented: $saveOpen) {
      SaveSheet(
        title: "Save Calculation",
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
  }

  // MARK: - The pinned draft

  private var draftCard: some View {
    HStack(spacing: Space.s3) {
      VStack(alignment: .leading, spacing: Space.s1) {
        Text("Current · unsaved")
          .font(.tally(TallyFont.sansSemi, TextScale.bodySm))
          .foregroundStyle(t.accentInk)
        Text(draftSubtitle)
          .font(.tally(TallyFont.sans, TextScale.bodySm))
          .foregroundStyle(t.ink2)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // The card's one action, and the most likely thing to do on this screen —
      // so it takes the prominent style HIG reserves for exactly that.
      Button("Save") { saveOpen = true }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(t.accentSolid)
    }
    .padding(.vertical, Space.s1)
    .listRowBackground(t.accent2)
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
          .font(.tally(TallyFont.serif, TextScale.displayMd))
      } description: {
        Text("Try clearing the filter, or tag more calculations.")
          .font(.tally(TallyFont.sans, TextScale.bodySm))
      }
      .listRowBackground(Color.clear)
    } else if !query.isEmpty {
      ContentUnavailableView.search(text: query)
        .listRowBackground(Color.clear)
    } else {
      // Drawn rather than a ContentUnavailableView: that view's actions slot,
      // inside a list row, stretched its button to the row's full height.
      VStack(spacing: Space.s3) {
        Text("Nothing filed away yet.")
          .font(.tally(TallyFont.serif, TextScale.displayMd))
          .foregroundStyle(t.ink)
        Text("Name the calculation you’re on and it will be filed here.")
          .font(.tally(TallyFont.sans, TextScale.bodySm))
          .foregroundStyle(t.ink2)
        // The way out of an empty archive: file what is on the tab, or start
        // one worth filing.
        Button {
          if hasDraft {
            saveOpen = true
          } else {
            Haptic.tap.play()
            store.newTab()
            if !inSidebar { dismiss() }
          }
        } label: {
          Label(
            hasDraft ? "Save current calculation" : "Start a calculation",
            systemImage: hasDraft ? "checkmark" : "plus")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(t.accentInk)
        .padding(.top, Space.s2)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Space.s12)
      .listRowBackground(Color.clear)
    }
  }

  // MARK: - Actions
  //
  // No haptic on opening or on the way to the tag catalog — those are
  // navigation, and the screen changing is the feedback.

  private func open(_ tab: TallyKit.Tab) {
    store.openTab(id: tab.id)
    if !inSidebar { dismiss() }
  }

  private func delete(_ tab: TallyKit.Tab) {
    Haptic.impact.play()
    store.deleteTab(id: tab.id)
  }

  /// Quick path from the row's Tags submenu — flip one tag on or off in place.
  private func toggleTag(_ tab: TallyKit.Tab, _ name: String) {
    Haptic.select.play()
    let current = tab.resolvedTags
    store.setTags(
      current.contains(name) ? current.filter { $0 != name } : current + [name],
      forTab: tab.id)
  }
}
