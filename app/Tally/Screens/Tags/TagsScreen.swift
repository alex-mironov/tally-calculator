// TagsScreen.swift — the tag catalog.
//
// Large title, a + that starts a new tag, and search on demand. Edit mode turns
// each row into an inline rename with a red delete, both of which cascade
// through every calculation via the store. The list groups Most Used first,
// then A–Z, with the system's section index down the trailing edge (★ for Most
// Used), as tally-tags.jsx's TagSheet draws it.
//
// Given a target, the screen doubles as the tag *picker* for that one
// calculation — the calculator's "Tags…", or a saved row's "Edit tags", both
// presented as a sheet (TagsSheet): rows carry a checkmark, tapping one files
// or unfiles it, and a tag created here is applied straight away. Pushed from
// Settings without one, it is the catalog alone.
//
// Ported from mobile/src/app/tags.tsx. Like Settings, it was hand-drawn cards
// rather than a list, because a hosted SwiftUI List could not drive the large
// title's collapse — and it additionally edited tags through inline RN
// TextInputs that would have ended up inside hosted rows fighting the list for
// focus. Both constraints are gone.
import SwiftUI
import TallyKit

/// The calculation a tag picker files: the one on the calculator, or a saved
/// one by id.
enum TagTarget: Hashable, Identifiable {
  /// The live tab, saved or not. An unsaved tab can carry tags before it has
  /// an id to file them under.
  case current
  case tab(String)

  var id: Self { self }
}

struct TagsScreen: View {
  /// The calculation this screen tags, if any. Nil is the catalog alone.
  var applyingTo: TagTarget?

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

  /// Whether this is a picker at all — and, for a saved tab, whether that tab
  /// still exists (it can be deleted from under an open sheet on iPad).
  private var isPicker: Bool {
    switch applyingTo {
    case nil: false
    case .current: true
    case .tab(let id): store.tabs.contains { $0.id == id }
    }
  }

  /// Looked up on every render, so the checkmarks track the store rather than
  /// a local copy.
  private var applied: [String] {
    switch applyingTo {
    case nil: []
    case .current: store.tags
    case .tab(let id): store.tabs.first { $0.id == id }?.resolvedTags ?? []
    }
  }

  private func apply(_ next: [String]) {
    switch applyingTo {
    case nil: break
    case .current: store.setTags(next)
    case .tab(let id): store.setTags(next, forTab: id)
    }
  }

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
            .tallyFont(TallyFont.text, TextScale.bodySm)
            .foregroundStyle(t.ink2)
        }
        .listRowBackground(t.card)
      }

      if adding {
        // At the top, where the + that opened it is, as the design puts it.
        Section {
          TextField("New tag", text: $newTag)
            .focused($focused, equals: "__new")
            .submitLabel(.done)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .onSubmit(commitNew)
        }
        .listRowBackground(t.card)
      }

      ForEach(sections, id: \.label) { section in
        Section {
          ForEach(section.items, id: \.self) { row($0) }
        } header: {
          if let label = section.label {
            // The design's section labels are headings, not the system's small
            // grey caption: 19pt semibold in ink, in the label's own case.
            Text(label)
              .tallyFont(TallyFont.textSemi, 19)
              .tracking(-0.2)
              .foregroundStyle(t.ink)
              .textCase(nil)
          }
        }
        .sectionIndexLabel(section.index)
      }

      if store.catalog.isEmpty && !adding {
        ContentUnavailableView {
          Text("No tags yet.").tallyFont(TallyFont.textMedium, TextScale.displayMd)
        } description: {
          Text("Tags group calculations — a trip, a month of bills, a project.")
            .tallyFont(TallyFont.text, TextScale.bodySm)
        }
        .listRowBackground(Color.clear)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    // The A–Z rail: iOS 26's own section index, so it scrubs, ticks and reads
    // to VoiceOver the way Contacts' does. Hidden while a search flattens the
    // list into one unlabelled section, and when there is only one letter.
    .listSectionIndexVisibility(showsIndex ? .visible : .hidden)
    .background { ScreenBackground() }
    .environment(\.editMode, $editMode)
    .navigationTitle("Tags")
    .navigationBarTitleDisplayMode(.large)
    // Search on demand, as the design has it: a button until it is wanted,
    // rather than a field parked on screen. A tag list is short enough to scan,
    // so the field is a tool rather than part of the screen.
    //
    // iOS 26's minimised toolbar search: a glass button at the foot of the
    // screen that opens into the field. It only minimises when the bottom bar
    // is explicitly laid out — `DefaultToolbarItem(kind: .search)` plus a
    // spacer, below — without them it is drawn full width whatever the
    // behaviour says. (Attaching `.searchable` only while searching was tried
    // too, and made UIKit throw "View has already been loaned out" as the
    // search controller was swapped under a live bar.)
    .searchable(text: $query, placement: .toolbar, prompt: "Search tags")
    .searchToolbarBehavior(.minimize)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("New tag", systemImage: "plus") {
          adding = true
          editMode = .inactive
          focused = "__new"
        }
      }
      ToolbarItem(placement: .topBarTrailing) { EditButton() }
      // The search button, bottom-leading, with the rest of the bar left
      // empty — see `.searchToolbarBehavior` above.
      DefaultToolbarItem(kind: .search, placement: .bottomBar)
      ToolbarSpacer(.flexible, placement: .bottomBar)
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
        .listRowBackground(t.card)
    } else {
      Button {
        if editMode == .active {
          renameDraft = name
          renaming = name
          focused = name
        } else if isPicker {
          toggleOnTab(name)
        }
      } label: {
        HStack {
          Text(name)
            .tallyFont(TallyFont.text, TextScale.bodyLg)
            .foregroundStyle(t.ink)
          Spacer(minLength: Space.s3)
          if let count = counts[name], count > 0, !isPicker {
            Text("\(count)")
              .tallyFont(TallyFont.mono, TextScale.bodySm)
              .foregroundStyle(t.ink3)
          }
          if isPicker && applied.contains(name) {
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
    /// What the section shows in the index rail.
    var index: String? = nil
  }

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func letter(_ name: String) -> String {
    name.first.map { String($0).uppercased() } ?? "#"
  }

  private var showsIndex: Bool {
    trimmedQuery.isEmpty && Set(store.catalog.map(Self.letter)).count > 1
  }

  private var sections: [TagSection] {
    let q = trimmedQuery
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

    let byLetter = Dictionary(grouping: store.catalog, by: Self.letter)

    return [TagSection(label: "Most Used", items: mostUsed, index: "★")]
      + byLetter.keys.sorted().map { letter in
        TagSection(label: letter, items: byLetter[letter]!.sorted(), index: letter)
      }
  }

  // MARK: - Editing

  private func toggleOnTab(_ name: String) {
    guard isPicker else { return }
    Haptic.select.play()
    apply(applied.contains(name) ? applied.filter { $0 != name } : applied + [name])
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
      if isPicker && !applied.contains(existing) {
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
    if isPicker { apply(applied + [name]) }
  }
}
