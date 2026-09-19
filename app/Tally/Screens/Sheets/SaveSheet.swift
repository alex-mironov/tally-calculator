// SaveSheet.swift — the "name + tags" form.
//
// Lifted almost verbatim from the SwiftUI inside modules/tally-sheet
// (TallySheetView, 598 lines of Swift in total). What came off it was all
// plumbing, and it is worth listing because it is the clearest example of what
// the rewrite is actually for:
//
//   · an Expo `Module` with `Record` types to decode the options from JS, a
//     `Promise` to resolve the outcome back, and a registry of live resolvers
//     so a sheet could be dismissed from either side;
//   · a `UIHostingController` presented by hand, with `modalPresentationStyle`,
//     detents, grabber and a `UIAdaptivePresentationControllerDelegate` to veto
//     swipe-dismiss;
//   · `overrideUserInterfaceStyle` on the controller *and* an opaque backdrop
//     painted behind the form, because the app's theme was a JS-only notion and
//     never reached UIKit's trait collection — so with the app in dark on a
//     light phone, white form text sat over a light backdrop.
//
// All of that is `.sheet` and `.presentationDetents` here, and the theme is
// simply the environment. What is left below is the form the user actually saw.
import SwiftUI
import TallyKit

struct SaveSheet: View {
  /// Prefilled from the tab, then owned by the sheet until it is committed.
  @State private var name: String
  @State private var selected: Set<String>
  @State private var adding = false
  @State private var newTag = ""
  @State private var confirmingDiscard = false

  private let initialName: String
  private let initialSelection: Set<String>

  let title: String
  let subtitle: String
  /// Show the name field (Save) or tags only (Edit tags).
  let showsName: Bool
  let namePlaceholder: String
  let primaryLabel: String
  /// Gate the primary button — e.g. nothing to save yet.
  let canSave: Bool

  var onSave: (_ name: String, _ tags: [String]) -> Void

  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t
  @Environment(\.dismiss) private var dismiss

  private enum Field: Hashable { case name, newTag }
  @FocusState private var focus: Field?

  init(
    title: String, subtitle: String, showsName: Bool = true, name: String = "",
    namePlaceholder: String = "", selected: [String] = [], primaryLabel: String = "Save",
    canSave: Bool = true, onSave: @escaping (String, [String]) -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.showsName = showsName
    self.namePlaceholder = namePlaceholder
    self.primaryLabel = primaryLabel
    self.canSave = canSave
    self.onSave = onSave
    _name = State(initialValue: name)
    _selected = State(initialValue: Set(selected))
    initialName = name
    initialSelection = Set(selected)
  }

  /// Anything the user would lose by backing out.
  private var isDirty: Bool { name != initialName || selected != initialSelection }

  /// Selected tags in catalog order, so the result is stable across edits.
  private var orderedSelection: [String] { store.catalog.filter { selected.contains($0) } }

  var body: some View {
    NavigationStack {
      Form {
        if showsName {
          Section {
            TextField(namePlaceholder, text: $name)
              .focused($focus, equals: .name)
              .submitLabel(.done)
              .onSubmit(commit)
          } footer: {
            Text(subtitle)
          }
          Section("Tags") { tagRows }
        } else {
          Section {
            tagRows
          } header: {
            Text("Tags")
          } footer: {
            Text(subtitle)
          }
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      // HIG "Sheets" (iOS): Cancel on the leading edge, the confirming action on
      // the trailing edge — and never a Done without a Cancel beside it.
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { attemptDiscard() }
        }
        ToolbarItem(placement: .confirmationAction) {
          // The sheet's one key action, so it takes the prominent style HIG
          // "Toolbars" reserves for a Done/Submit on the trailing edge.
          Button(primaryLabel, action: commit)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
      }
      .confirmationDialog(
        "Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible
      ) {
        Button("Discard Changes", role: .destructive) { dismiss() }
        Button("Keep Editing", role: .cancel) {}
      }
    }
    // HIG "Sheets": support the medium detent for progressive disclosure, and
    // show a grabber so the sheet advertises that it resizes — the grabber is
    // also how VoiceOver users move between detents.
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    // Confirm before unsaved edits are thrown away. This is the one thing HIG
    // asks an app to add on top of the system's swipe-to-dismiss.
    .interactiveDismissDisabled(isDirty)
    .task {
      // The name field is the point of the sheet, so it takes the keyboard —
      // after the presentation animation, which otherwise swallows the focus.
      guard showsName else { return }
      try? await Task.sleep(for: .milliseconds(400))
      focus = .name
    }
  }

  /// One row per tag: tap anywhere on it to file or unfile the calculation,
  /// with a checkmark on the ones that are on. Standard list rows, so they are
  /// a full 44pt tall and VoiceOver reads them as selected.
  @ViewBuilder private var tagRows: some View {
    ForEach(store.catalog, id: \.self) { tag in
      let on = selected.contains(tag)
      Button {
        if on { selected.remove(tag) } else { selected.insert(tag) }
      } label: {
        HStack {
          Text(tag)
          Spacer(minLength: Space.s3)
          if on {
            Image(systemName: "checkmark")
              .fontWeight(.semibold)
              .foregroundStyle(t.accentInk)
          }
        }
        .contentShape(.rect)
      }
      // .plain so the row reads as a list row with a checkmark, not as a row of
      // tinted button text — the tint belongs to the checkmark alone.
      .buttonStyle(.plain)
      .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    if adding {
      TextField("New tag", text: $newTag)
        .focused($focus, equals: .newTag)
        .submitLabel(.done)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.words)
        .onSubmit(commitNewTag)
    } else {
      Button {
        adding = true
        focus = .newTag
      } label: {
        Label("Add Tag", systemImage: "plus")
      }
    }
  }

  /// Commit the inline "new tag" field. A name that already exists just selects
  /// the tag it matches rather than making a near-duplicate.
  private func commitNewTag() {
    let typed = newTag
    adding = false
    newTag = ""
    guard let name = store.addCatalogTag(typed) else { return }
    selected.insert(name)
  }

  private func commit() {
    guard canSave else { return }
    onSave(name, orderedSelection)
    dismiss()
  }

  private func attemptDiscard() {
    if isDirty {
      confirmingDiscard = true
    } else {
      dismiss()
    }
  }
}
