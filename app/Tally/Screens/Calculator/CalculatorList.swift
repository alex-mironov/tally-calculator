// CalculatorList.swift — the tab's lines, or the empty state when there are
// none. Each line is an EntryRow (EntryRow.swift); this wires it to the
// screen's editing, selecting and linking.
//
// v2 puts the rows straight on the screen colour — no card — with a hairline
// between each pair (tally-app-v2.jsx, SwipeRowV2). It is still a `List`, for
// what a List gives a row for free: native swipe actions, the context menu's
// lift, and programmatic scrolling. Only its chrome is turned off.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  @ViewBuilder
  var listOrEmpty: some View {
    if store.entries.isEmpty {
      // Bottom-left, just above the dock: where the first line will land, and
      // where the eye already is when it is typed.
      VStack(alignment: .leading, spacing: Space.s2) {
        Text("Start a tally.")
          .tallyFont(TallyFont.displayMedium, 36, relativeTo: .largeTitle)
          .tracking(-0.035 * 36)
          .foregroundStyle(t.ink)
        Text("Type an amount, add a note, then tap return. Lines stack up here.")
          .tallyFont(TallyFont.text, 16)
          .foregroundStyle(t.ink2)
          .frame(maxWidth: 288, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      .padding(.horizontal, Space.s6)
      .padding(.bottom, Space.s5)
    } else {
      // Worked out once per pass, not once per row: as properties read inside
      // `row`, each was a scan of the whole tab for every row — the repeats
      // lowercasing every note fifty times over on a fifty-line tab.
      let repeats = noteRepeats
      let editIndex = editingID.flatMap { id in store.entries.firstIndex { $0.id == id } }
      // The draft's links — tracked apart from its text, so a digit typed
      // doesn't re-run this list (see `EntryDraft.linked`).
      let linked = line.linked
      ScrollViewReader { proxy in
        List {
          ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
            row(
              entry, at: index, repeatIndex: repeats[entry.id], editIndex: editIndex,
              linked: linked.contains(entry.id))
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, EntryRow.minHeight)
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
        //
        // With the hero on screen, though, the list's top edge is the hero's
        // foot rather than the bar, and the edge effect has nothing to follow:
        // rows scrolled up were cut off flat under the number. A short fade
        // there lets them go the way they go under the bar. 12pt, so a row at
        // rest — whose text sits 12pt into it — is untouched.
        //
        // Painted over the rows in the screen's colour rather than masking
        // them out: a mask over a scroll view renders the whole list offscreen
        // on every scroll frame. With the hero up the pixels are the same,
        // because the screen behind the rows is flat `t.screen`
        // (ScreenBackground); if that ever stops being true, this has to
        // become a mask again.
        //
        // With the hero hidden there is nothing here at all, which is a
        // change: the mask stayed on with a 0pt fade, and being sized to the
        // List's frame it hid every row scrolled up under the bar, cutting
        // them off flat at its foot. Without it they pass under the bar
        // through the edge effect, as the paragraph above means them to.
        .overlay(alignment: .top) {
          if showsHero {
            LinearGradient(
              colors: [t.screen, t.screen.opacity(0)], startPoint: .top, endPoint: .bottom
            )
            .frame(height: Space.s3)
            .allowsHitTesting(false)
          }
        }
        .onChange(of: justAddedID) { _, id in
          // With the keypad up the list shows only a handful of rows, so a
          // committed entry lands below the fold and is never seen arriving.
          guard let id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
    }
  }

  private func row(
    _ entry: Entry, at index: Int, repeatIndex: Int?, editIndex: Int?, linked: Bool
  ) -> some View {
    EntryRow(
      entry: entry,
      position: index + 1,
      first: index == 0,
      repeatIndex: repeatIndex,
      selected: entry.id == editingID,
      showExpr: store.showExpr,
      justAdded: entry.id == justAddedID,
      positionFor: positionFor,
      editingID: editingID,
      canReference: entry.error != true && (editIndex.map { index < $0 } ?? true),
      linked: linked,
      selectMode: selectMode,
      picked: picked.contains(entry.id),
      referencing: referencing,
      onEdit: { edit(entry) },
      onDelete: { delete(entry) },
      onStartSelect: { startSelect(seed: entry) },
      onTogglePick: { togglePick(entry) },
      onReference: { toggleLink(entry.id) },
      onLinkInNewLine: { linkInNewLine(entry) },
      onToggleExcluded: {
        Haptic.select.play()
        store.toggleExcluded(id: entry.id)
      }
    )
    .id(entry.id)
  }

  /**
   "#n" for a note that more than one line carries — the second "Coffee" reads
   "Coffee #2" — so two rows that would otherwise look the same can be told
   apart. Counted per note, case-insensitively, in tab order; lines whose note
   is unique (or empty) get nothing.
   */
  private var noteRepeats: [String: Int] {
    let keys = store.entries.map { $0.note.lowercased() }
    let counts = Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
    var seen: [String: Int] = [:]
    var out: [String: Int] = [:]
    for (entry, key) in zip(store.entries, keys) where !key.isEmpty && counts[key, default: 0] > 1 {
      seen[key, default: 0] += 1
      out[entry.id] = seen[key]
    }
    return out
  }
}
