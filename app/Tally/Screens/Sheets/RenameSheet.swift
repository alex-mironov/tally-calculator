// RenameSheet.swift — naming the calculation, and nothing else.
//
// Calculator v2 splits what used to be one "name + tags" form in two: this
// sheet is the name alone, and "Tags…" opens the tag catalog as a picker (see
// TagsSheet). A sheet that did both had two primary jobs and so neither — and
// the catalog is a far better tag picker than a list of rows in a form.
//
// The form it replaces (SaveSheet) was itself lifted from the SwiftUI inside
// modules/tally-sheet, an Expo module that presented a `UIHostingController`
// by hand with `overrideUserInterfaceStyle` and an opaque backdrop forced
// behind it. All of that is `.sheet` and the environment here.
//
// The shape is the design's (tally-app-v2.jsx, the save sheet): ✕ / title / ✓
// across the top, one field with today's date as its placeholder, and a line
// saying what leaving it blank does.
import SwiftUI
import TallyKit

struct RenameSheet: View {
  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t
  @Environment(\.dismiss) private var dismiss

  /// Prefilled from the tab, then owned by the sheet until it is committed.
  @State private var name: String
  @FocusState private var focused: Bool

  private let initialName: String

  init(name: String) {
    _name = State(initialValue: name)
    initialName = name
  }

  /// A saved tab is renamed; an unsaved one is named, which also files it.
  private var isSaved: Bool { store.activeID != nil }

  /// Naming an unsaved tab files it, and an empty one has nothing to file —
  /// the store refuses to save a tab with no lines.
  private var canCommit: Bool { isSaved || !store.entries.isEmpty }

  var body: some View {
    // The sheet surface: on Midnight a step up from the black screen behind
    // it, so the sheet has an edge (Theme.sheet); the light schemes' sheet is
    // their screen.
    let s = t.sheet

    NavigationStack {
      VStack(alignment: .leading, spacing: Space.s2) {
        field(s)
        Text("Leave blank to use today’s date.")
          .tallyFont(TallyFont.text, 13)
          .foregroundStyle(s.ink2)
          .padding(.horizontal, Space.s1)
      }
      .padding(.horizontal, Space.s4)
      .padding(.top, Space.s2)
      .frame(maxHeight: .infinity, alignment: .top)
      .navigationTitle(isSaved ? "Rename" : "Name calculation")
      .navigationBarTitleDisplayMode(.inline)
      // HIG "Sheets": dismiss on the leading edge, confirm on the trailing one.
      // The iOS 26 roles draw the ✕ and ✓ the design asks for, in the bar's
      // own glass — no hand-drawn circles.
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(role: .confirm, action: commit)
            .disabled(!canCommit)
            .accessibilityLabel(isSaved ? "Done" : "Save")
        }
      }
    }
    .environment(\.theme, s)
    // Just tall enough for the bar, the field and its footnote: this sheet is
    // a quick edit over the calculator, not a screen of its own.
    .presentationDetents([.height(200)])
    .presentationBackground(s.screen)
    // A typed name should not vanish to a stray swipe; ✕ is the way out.
    .interactiveDismissDisabled(name != initialName)
    .task {
      // The field is the point of the sheet, so it takes the keyboard — after
      // the presentation animation, which otherwise swallows the focus.
      try? await Task.sleep(for: .milliseconds(400))
      focused = true
    }
  }

  private func field(_ s: Theme) -> some View {
    HStack(spacing: Space.s2) {
      TextField(Self.today(), text: $name)
        .tallyFont(TallyFont.text, 17)
        .foregroundStyle(s.ink)
        .focused($focused)
        .submitLabel(.done)
        .onSubmit(commit)
      if !name.isEmpty {
        // The clear button HIG "Text fields" asks for; SwiftUI's TextField
        // has no built-in one.
        Button {
          name = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(s.ink2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear name")
      }
    }
    .padding(.leading, Space.s4)
    .padding(.trailing, Space.s3)
    .frame(height: 52)
    .background(s.card, in: .rect(cornerRadius: Radius.lg))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(s.line, lineWidth: 1)
    }
  }

  private func commit() {
    guard canCommit else { return }
    Haptic.success.play()
    if store.entries.isEmpty {
      // A saved tab whose lines have all been deleted: the store will not
      // re-save it, but it can still be renamed.
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      store.setTabName(trimmed.isEmpty ? Self.today() : trimmed)
    } else {
      // The store owns the blank-means-today rule; the placeholder only shows
      // it.
      store.saveDraft(name: name)
    }
    dismiss()
  }

  /**
   Today's date, the way the store names an unnamed tab.

   A copy of `TallyStore.defaultTabName`, which is internal to TallyKit. It is
   only the placeholder — what a blank name actually becomes is still decided
   by the store — so the two can only disagree about a hint, never about data.
   */
  static func today(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.setLocalizedDateFormatFromTemplate("EEEdMMM")
    return f.string(from: date)
  }
}
