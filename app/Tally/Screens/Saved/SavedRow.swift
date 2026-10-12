// SavedRow.swift — one saved calculation.
//
// Swipe left for Delete, swipe right for Tags, long-press for the context menu:
// Open · Edit tags · Delete, as tally-saved-r.jsx has it. "Edit tags" opens the
// tag catalog as a picker sheet for this calculation — the same sheet the
// calculator's "Tags…" opens. Delete asks first, whichever way it is reached.
//
// The menu used to carry a Tags ▸ submenu as a quick path, a checkmark per
// catalog tag. v2 drops it: the sheet is one tap further and is the whole
// catalog, with search, rather than the first dozen tags in a menu.
//
// Ported from mobile/src/components/tally/saved-row.tsx.
import SwiftUI
import TallyKit

// NOTE: `Tab` is spelled `TallyKit.Tab` throughout the app target. SwiftUI has
// its own `Tab` (the TabView element), and an unqualified mention is ambiguous
// wherever both are in scope. The model keeps the name because that is what the
// domain and the persisted `tally:tabs` key call it.

struct SavedRow: View {
  let tab: TallyKit.Tab
  /// This calculation is the one currently open on the calculator.
  let isOpen: Bool
  var onOpen: () -> Void
  /// Ask to delete. The screen confirms before anything is removed.
  var onDelete: () -> Void
  var onEditTags: () -> Void

  @Environment(\.theme) private var t

  var body: some View {
    HStack(alignment: .top, spacing: Space.s3) {
      VStack(alignment: .leading, spacing: Space.s1) {
        Text(tab.name.isEmpty ? "Untitled" : tab.name)
          .tallyFont(TallyFont.textMedium, 17)
          .tracking(-0.2)
          .foregroundStyle(t.ink)
          .lineLimit(1)

        HStack(spacing: Space.s2) {
          if isOpen {
            Text("Open")
              .tallyFont(TallyFont.textSemi, TextScale.caption)
              .foregroundStyle(t.accentInk)
              .padding(.horizontal, Space.s2)
              .background(t.accent2, in: .rect(cornerRadius: Radius.xs))
          }
          Text("\(tab.entries.count) item\(tab.entries.count == 1 ? "" : "s")")
          Text("·").opacity(0.5)
          Text(Self.relativeDate(tab.savedAt))
        }
        .tallyFont(TallyFont.text, 14)
        .foregroundStyle(t.ink2)

        // Tags are shown, never edited here: the row is one tap target, so the
        // gestures above own everything else. 8pt below the meta line — the
        // stack's 4 plus 4 more.
        if !tab.resolvedTags.isEmpty {
          HStack(spacing: Space.s2) {
            ForEach(tab.resolvedTags, id: \.self) { TagChip(name: $0, size: .small) }
          }
          .padding(.top, Space.s1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(Calc.fmt(tab.total))
        .tallyFont(TallyFont.displayMedium, 17)
        .tracking(-0.2)
        .foregroundStyle(t.ink)
    }
    .padding(.vertical, Space.s1)
    .contentShape(.rect)
    .onTapGesture(perform: onOpen)
    // The open calculation is marked through the *cell*, so the fill covers the
    // row edge to edge and clips to the card's rounded ends. A neutral wash, as
    // the design has it: the "Open" badge carries the accent.
    .listRowBackground(isOpen ? t.rowSel : t.card)
    .listRowSeparatorTint(t.line)
    // Not `role: .destructive`: that role tells the list the row is already
    // gone, and it animates out before the confirmation has been answered. A
    // plain button in the system red keeps the row until it really is deleted.
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(action: onDelete) { Label("Delete", systemImage: "trash") }
        .tint(t.danger)
    }
    // A visible affordance for tagging, so it isn't hidden behind the
    // long-press alone.
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      Button(action: onEditTags) { Label("Tags", systemImage: "tag") }
        .tint(t.accentSolid)
    }
    .contextMenu {
      Button { onOpen() } label: { Label("Open", systemImage: "arrow.up.forward.app") }
      Button { onEditTags() } label: { Label("Edit tags", systemImage: "tag") }
      Divider()
      Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
    }
  }

  /// How recently a calculation was filed, in the terms people actually use.
  static func relativeDate(_ ms: Int) -> String {
    guard ms > 0 else { return "" }
    let date = Date(timeIntervalSince1970: Double(ms) / 1000)
    let seconds = Date().timeIntervalSince(date)

    if seconds < 60 { return "Just now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m ago" }

    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "\(Int(seconds / 3600))h ago" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }

    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.setLocalizedDateFormatFromTemplate("dMMM")
    return f.string(from: date)
  }
}
