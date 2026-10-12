// CalculatorList.swift — the tab's lines, or the empty state when there are
// none. Each line is an EntryRow (EntryRow.swift); this wires it to the
// screen's editing, selecting and referencing.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  @ViewBuilder
  var listOrEmpty: some View {
    if store.entries.isEmpty {
      VStack(spacing: Space.s3) {
        Text("Nothing added yet.")
          .tallyFont(TallyFont.textMedium, TextScale.displayMd)
          .foregroundStyle(t.ink2)
          .multilineTextAlignment(.center)
        Text("Tap a number, name it, then hit return")
          .tallyFont(TallyFont.text, TextScale.bodySm)
          .foregroundStyle(t.ink3)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(Space.s5)
    } else {
      ScrollViewReader { proxy in
        List {
          Section {
            ForEach(store.entries) { entry in row(entry) }
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, Space.s2, for: .scrollContent)
        // The scroll edge effect is left ON here, which is a deliberate
        // reversal of what the React Native build did.
        //
        // That build hid it, and needed a native module reaching under SwiftUI
        // to the backing scroll view to do so (modules/list-scroll's
        // `hideTopEdgeEffect`), because the effect drew a flat, lightened band
        // that cut a straight shelf across the accent bloom. Checked side by
        // side here in both palettes, that does not happen: SwiftUI's edge
        // effect on iOS 26 is a progressive blur that follows the content under
        // a *floating* bar, not a band painted across the full width. With it
        // off, rows simply collide with the bar and the screen reads as broken.
        //
        // So the workaround is not merely unnecessary in this project — its
        // reasoning does not survive the move to a native floating bar.
        .onChange(of: justAddedID) { _, id in
          // With the keypad up the list shows only a handful of rows, so a
          // committed entry lands below the fold and is never seen arriving.
          guard let id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
    }
  }

  private func row(_ entry: Entry) -> some View {
    let editIndex = editingID.flatMap { id in store.entries.firstIndex { $0.id == id } }
    let index = store.entries.firstIndex { $0.id == entry.id } ?? 0

    return EntryRow(
      entry: entry,
      selected: entry.id == editingID,
      showExpr: store.showExpr,
      justAdded: entry.id == justAddedID,
      nameFor: nameFor,
      canReference: entry.error != true && (editIndex.map { index < $0 } ?? true),
      selectMode: selectMode,
      picked: picked.contains(entry.id),
      referencing: referencing,
      onEdit: { edit(entry) },
      onDelete: { delete(entry) },
      onStartSelect: { startSelect(seed: entry) },
      onTogglePick: { togglePick(entry) },
      onReference: { insertRef(entry.id, note: entry.note) },
      onToggleExcluded: {
        Haptic.select.play()
        store.toggleExcluded(id: entry.id)
      }
    )
    .id(entry.id)
  }
}
