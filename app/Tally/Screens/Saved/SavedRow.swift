// SavedRow.swift — one saved calculation.
//
// Swipe left for Delete, swipe right for Tags, long-press for the context menu:
// Open · Tags ▸ · Delete. The Tags submenu is the quick path — a checkmark per
// catalog tag, toggled in place — and "Manage tags…" at its foot opens the tag
// catalog, where tags can be created, renamed, deleted and applied.
//
// Ported from mobile/src/components/tally/saved-row.tsx. One note from that
// file no longer applies and is worth retiring explicitly: it used a
// checkmark-imaged `Button` rather than a `Toggle` in the Tags submenu, because
// a hosted SwiftUI `Toggle` reached UIKit as a plain menu row and its on-state
// never drew. A real `Toggle` works here — but the checkmark-Button reads the
// same and keeps the submenu's rows identical to the save sheet's, so it stays.
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
  var onDelete: () -> Void
  var onToggleTag: (String) -> Void

  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t

  /// A context menu is a menu, not an archive: past a dozen entries the tag
  /// list stops being scannable and "Manage tags…" is the better door.
  private let submenuTagLimit = 12

  var body: some View {
    HStack(alignment: .top, spacing: Space.s3) {
      VStack(alignment: .leading, spacing: Space.s1) {
        Text(tab.name.isEmpty ? "Untitled tab" : tab.name)
          .font(.tally(TallyFont.serif, 16.5))
          .tracking(-0.2)
          .foregroundStyle(t.ink)
          .lineLimit(1)

        HStack(spacing: Space.s2) {
          if isOpen {
            Text("Open")
              .font(.tally(TallyFont.sansSemi, 11))
              .foregroundStyle(t.accentInk)
              .padding(.vertical, Space.s1)
              .padding(.horizontal, Space.s2)
              .background(t.screen, in: .rect(cornerRadius: Radius.sm))
          }
          Text("\(tab.entries.count) item\(tab.entries.count == 1 ? "" : "s")")
            .foregroundStyle(t.ink2)
          Text("·").foregroundStyle(t.ink3)
          Text(Self.relativeDate(tab.savedAt))
            .foregroundStyle(t.ink2)
        }
        .font(.tally(TallyFont.sans, 12.5))

        // Tags are shown, never edited here: the row is one tap target, so the
        // gestures above own everything else.
        if !tab.resolvedTags.isEmpty {
          HStack(spacing: Space.s2) {
            ForEach(tab.resolvedTags, id: \.self) { TagChip(name: $0, size: .small) }
          }
          .padding(.top, Space.s1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(Calc.fmt(tab.total))
        .font(.tally(TallyFont.monoSemi, 17))
        .monospacedDigit()
        .tracking(-0.2)
        .foregroundStyle(t.ink)
    }
    .padding(.vertical, Space.s2)
    .contentShape(.rect)
    .onTapGesture(perform: onOpen)
    // The open calculation is tinted through the *cell*, so the fill covers the
    // row edge to edge and clips to the card's rounded ends.
    .listRowBackground(isOpen ? t.accent2 : t.card)
    .listRowSeparatorTint(t.line)
    .swipeActions(edge: .trailing) {
      Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
    }
    // A visible affordance for tagging, so it isn't hidden behind the
    // long-press alone.
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      NavigationLink(value: Route.tags(applyingTo: tab.id)) {
        Label("Tags", systemImage: "tag")
      }
      .tint(t.accentSolid)
    }
    .contextMenu {
      Button { onOpen() } label: { Label("Open", systemImage: "arrow.up.forward.app") }
      Menu {
        ForEach(store.catalog.prefix(submenuTagLimit), id: \.self) { name in
          Button {
            onToggleTag(name)
          } label: {
            Label(name, systemImage: tab.resolvedTags.contains(name) ? "checkmark" : "")
          }
        }
        if !store.catalog.isEmpty { Divider() }
        NavigationLink(value: Route.tags(applyingTo: tab.id)) {
          Label("Manage tags…", systemImage: "tag.circle")
        }
      } label: {
        Label("Tags", systemImage: "tag")
      }
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
