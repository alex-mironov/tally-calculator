// TagsScreen.swift — the tag catalog.
//
// Large title, search, and a + that starts a new tag. Edit mode turns each row
// into an inline rename with a red delete, both of which cascade through every
// calculation via the store. The list groups Most Used first, then A–Z.
//
// Pushed with a calculation's id, the screen doubles as the tag *picker* for
// that one calculation: rows carry a checkmark, tapping one files or unfiles
// it, and a tag created here is applied straight away.
//
// Ported from mobile/src/app/tags.tsx. Like Settings, it was hand-drawn cards
// rather than a list, because a hosted SwiftUI List could not drive the large
// title's collapse — and it additionally edited tags through inline RN
// TextInputs that would have ended up inside hosted rows fighting the list for
// focus. Both constraints are gone.
import SwiftUI
import TallyKit

struct TagsScreen: View {
  /// The calculation this screen was pushed to tag, if any.
  var applyingTo: String?

  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t

  @State private var query = ""
  @State private var editMode: EditMode = .inactive
  @State private var renaming: String?
  @State private var renameDraft = ""
  @State private var adding = false
  @State private var newTag = ""
  /// Rejected input used to vanish without a word. HIG "Text fields" asks an
  /// app to validate and say when a value can't be used.
  @State private var notice: String?

  @FocusState private var focused: String?

  /// Looked up on every render, so the checkmarks track the store rather than
  /// a local copy.
  private var applyTab: TallyKit.Tab? {
    applyingTo.flatMap { id in store.tabs.first { $0.id == id } }
  }
  private var applied: [String] { applyTab?.resolvedTags ?? [] }

  /**
   Tag usage, tallied once per visit and then held.

   In picker mode every tap changes a count, and rows re-sorting out from under
   the finger is far worse than a Most Used order that is a few seconds stale.
   */
  @State private var counts: [String: Int] = [:]

  var body: some View {
    List {
      if let notice {
        Section {
          Label(notice, systemImage: "exclamationmark.triangle")
            .font(.tally(TallyFont.sans, TextScale.bodySm))
            .foregroundStyle(t.ink2)
        }
      }

      ForEach(sections, id: \.label) { section in
        Section {
          ForEach(section.items, id: \.self) { row($0) }
        } header: {
          if let label = section.label { Text(label) }
        }
      }

      if adding {
        Section {
          TextField("New tag", text: $newTag)
            .focused($focused, equals: "__new")
            .submitLabel(.done)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .onSubmit(commitNew)
        }
      }

      if store.catalog.isEmpty && !adding {
        ContentUnavailableView {
          Text("No tags yet.").font(.tally(TallyFont.serif, TextScale.displayMd))
        } description: {
          Text("Tags group calculations — a trip, a month of bills, a project.")
            .font(.tally(TallyFont.sans, TextScale.bodySm))
        }
        .listRowBackground(Color.clear)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background { ScreenBackground() }
    .environment(\.editMode, $editMode)
    .navigationTitle(applyTab == nil ? "Tags" : "Tag calculation")
    .navigationBarTitleDisplayMode(.large)
    // `.always`, not the default: the search field is part of the screen's
    // chrome rather than something to hunt for by scrolling up.
    .searchable(
      text: $query, placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search tags")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("New tag", systemImage: "plus") {
          adding = true
          editMode = .inactive
          focused = "__new"
        }
      }
      ToolbarItem(placement: .topBarTrailing) { EditButton() }
    }
    .task {
      var c: [String: Int] = [:]
      for tab in store.tabs {
        for name in tab.resolvedTags { c[name, default: 0] += 1 }
      }
      counts = c
    }
    .onChange(of: notice) { _, value in
      guard value != nil else { return }
      Task {
        try? await Task.sleep(for: .milliseconds(2800))
        notice = nil
      }
    }
  }

  // MARK: - A row

  @ViewBuilder
  private func row(_ name: String) -> some View {
    if renaming == name {
      TextField("Tag name", text: $renameDraft)
        .focused($focused, equals: name)
        .submitLabel(.done)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.words)
        .onSubmit { commitRename(from: name) }
    } else {
      Button {
        if editMode == .active {
          renameDraft = name
          renaming = name
          focused = name
        } else if applyTab != nil {
          toggleOnTab(name)
        }
      } label: {
        HStack {
          Text(name)
            .font(.tally(TallyFont.sans, TextScale.bodyLg))
            .foregroundStyle(t.ink)
          Spacer(minLength: Space.s3)
          if let count = counts[name], count > 0, applyTab == nil {
            Text("\(count)")
              .font(.tally(TallyFont.mono, TextScale.bodySm))
              .foregroundStyle(t.ink3)
          }
          if applyTab != nil && applied.contains(name) {
            Image(systemName: "checkmark")
              .fontWeight(.semibold)
              .foregroundStyle(t.accentInk)
          }
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(applied.contains(name) ? [.isSelected] : [])
      .listRowBackground(t.card)
      .listRowSeparatorTint(t.line)
      .swipeActions(edge: .trailing) {
        // Deleting cascades through every calculation that used the tag, which
        // is why it is destructive rather than a simple list removal.
        Button(role: .destructive) {
          Haptic.impact.play()
          store.removeCatalogTag(name)
        } label: {
          Label("Delete", systemImage: "trash")
        }
        Button {
          renameDraft = name
          renaming = name
          focused = name
        } label: {
          Label("Rename", systemImage: "pencil")
        }
        .tint(t.accentSolid)
      }
    }
  }

  // MARK: - Sections
  //
  // A flat list while searching; otherwise Most Used (by how many calculations
  // carry each tag) then alphabetical letter groups.

  private struct TagSection {
    let label: String?
    let items: [String]
  }

  private var sections: [TagSection] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !q.isEmpty {
      return [TagSection(label: nil, items: store.catalog.filter { $0.lowercased().contains(q) })]
    }
    guard !store.catalog.isEmpty else { return [] }

    let mostUsed = store.catalog
      .enumerated()
      .sorted {
        let a = counts[$0.element] ?? 0
        let b = counts[$1.element] ?? 0
        return a == b ? $0.offset < $1.offset : a > b
      }
      .prefix(5)
      .map(\.element)

    let byLetter = Dictionary(grouping: store.catalog) { name in
      String(name.first.map { String($0).uppercased() } ?? "#")
    }

    return [TagSection(label: "Most Used", items: mostUsed)]
      + byLetter.keys.sorted().map { letter in
        TagSection(label: letter, items: byLetter[letter]!.sorted())
      }
  }

  // MARK: - Editing

  private func toggleOnTab(_ name: String) {
    guard let tab = applyTab else { return }
    Haptic.select.play()
    store.setTags(
      applied.contains(name) ? applied.filter { $0 != name } : applied + [name],
      forTab: tab.id)
  }

  private func commitRename(from old: String) {
    let next = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    renaming = nil
    renameDraft = ""
    guard !next.isEmpty, next != old else { return }
    if let clash = store.catalog.first(where: { $0 != old && $0.lowercased() == next.lowercased() })
    {
      Haptic.error.play()
      notice = "“\(clash)” already exists — \(old) was left as it is."
      return
    }
    store.renameCatalogTag(old, to: next)
  }

  private func commitNew() {
    let typed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    adding = false
    newTag = ""
    guard !typed.isEmpty else { return }

    if let existing = store.catalog.first(where: { $0.lowercased() == typed.lowercased() }) {
      // In picker mode a name that already exists isn't really an error — the
      // user asked for that tag, so file the calculation under it and say so.
      if applyTab != nil && !applied.contains(existing) {
        toggleOnTab(existing)
        notice = "“\(existing)” already existed — added to this calculation."
        return
      }
      Haptic.error.play()
      notice = "“\(existing)” is already in your tags."
      return
    }

    // A tag created from a calculation is created *for* it.
    guard let name = store.addCatalogTag(typed) else { return }
    if let tab = applyTab { store.setTags(applied + [name], forTab: tab.id) }
  }
}
