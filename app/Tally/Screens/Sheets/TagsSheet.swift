// TagsSheet.swift — the tag catalog, presented as one calculation's picker.
//
// The calculator's "Tags…" and a saved row's "Edit tags" both open this. It is
// TagsScreen in a NavigationStack of its own, so the catalog keeps its large
// title, its + and Edit, and its on-demand search inside the sheet, rather than
// a second, smaller tag form that would have to be kept in step with it.
//
// Tags apply as they are tapped, so there is nothing to confirm: the bar has a
// ✕ to close and no ✓.
import SwiftUI
import TallyKit

struct TagsSheet: View {
  let target: TagTarget

  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t
  @Environment(\.dismiss) private var dismiss

  /// The live tab's tags when the sheet opened — to tell, on the way out,
  /// whether an unsaved tab was actually tagged.
  @State private var openedWith: [String]?

  var body: some View {
    let s = t.sheet

    NavigationStack {
      TagsScreen(applyingTo: target)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) { dismiss() }
          }
        }
    }
    .environment(\.theme, s)
    .presentationDetents([.large])
    .presentationBackground(s.screen)
    .onAppear { openedWith = store.tags }
    .onDisappear {
      // Tagging the unsaved tab files it, as the design's sheet does on close
      // — a tag is a way of finding a calculation later, and an unsaved one
      // cannot be found at all. Only if the tags actually changed: opening the
      // sheet to look should not file anything.
      guard target == .current, store.activeID == nil, store.tags != openedWith else { return }
      store.saveDraft()
    }
  }
}
