// EntryRow.swift — a single line in the running tab.
//
// Ported from mobile/src/components/tally/swipe-row.tsx, which was only ever
// the *contents* of a row: the card, separators, row fill, swipe actions and
// context menu all came from a shared `GroupedRow` that existed to work around
// how an RN-hosted view sits inside a SwiftUI cell. None of that is needed
// here — `.listRowBackground`, `.listRowSeparatorTint`, `.swipeActions` and
// `.contextMenu` are simply available — so the two files collapse into one and
// grouped-list.tsx (313 lines) has no counterpart at all.
//
// In select mode the row is a different animal: a leading selection circle
// appears, the tap toggles instead of editing, and both the context menu and
// the swipe action are withheld. Selecting is a read-only lens over the tab, so
// nothing that edits or deletes a line should be one gesture away while it is on.
import SwiftUI
import TallyKit

struct EntryRow: View {
  let entry: Entry
  let selected: Bool
  let showExpr: Bool
  /// Freshly committed — flash the selection tint once to draw the eye.
  let justAdded: Bool
  let nameFor: (String) -> String
  /// The draft may reference this line (it sits above the edit point).
  let canReference: Bool
  let selectMode: Bool
  let picked: Bool

  var onEdit: () -> Void
  var onDelete: () -> Void
  var onStartSelect: () -> Void
  var onTogglePick: () -> Void
  var onReference: () -> Void
  var onToggleExcluded: () -> Void

  @Environment(\.theme) private var t
  @State private var glow: Double = 0

  /// The selection circle is a touch target as much as a symbol, so it is drawn
  /// a good bit larger than a row affordance — this is the control the whole
  /// mode is about. Scaled, so it keeps pace with the row's text.
  @ScaledMetric(relativeTo: .body) private var tickSize: CGFloat = 24
  /// The ⊘ beside a not-counted amount, a step under the 13.5pt amount.
  @ScaledMetric(relativeTo: .footnote) private var excludedMark: CGFloat = 12

  /// A not-counted line reads as present but set aside.
  private var muted: Bool { entry.excluded == true }

  /// The editing highlight is meaningless while selecting — the entry card it
  /// refers to is off screen, and a second kind of lit row would only compete
  /// with the ticks.
  private var lit: Bool { selected && !selectMode }

  var body: some View {
    HStack(alignment: .top, spacing: Space.s3) {
      if selectMode {
        // Apple's own edit modes (Mail, Photos) let the leading circle carry
        // the state on its own rather than filling the row. Ticked is the
        // *filled* symbol — the accent becomes the circle's fill and the
        // checkmark is knocked out of it, which reads across the room in a way
        // an outlined tick of the same size doesn't.
        //
        // Drawn by hand rather than with List(selection:) in edit mode, whose
        // grey full-width highlight escapes an inset-grouped card's rounded
        // ends.
        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
          .font(.system(size: tickSize, weight: .regular))
          .foregroundStyle(picked ? t.accentInk : t.ink3)
          .transition(.scale.combined(with: .opacity))
      }

      VStack(alignment: .leading, spacing: Space.s1) {
        HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
          Text(entry.note.isEmpty ? "No note" : entry.note)
            .font(.tally(TallyFont.sansMedium, 13.5))
            .italic(entry.note.isEmpty)
            .foregroundStyle(entry.note.isEmpty ? t.ink3 : (muted ? t.ink3 : t.ink2))
            .lineLimit(1)
          // Sticky line number — how unnamed lines are referenced.
          if let num = entry.num {
            Text("#\(num)")
              .font(.tally(TallyFont.mono, 10.5))
              .foregroundStyle(t.ink3)
          }
        }

        if !entry.expr.isEmpty && showExpr { expression }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: Space.s1) {
        if muted {
          Image(systemName: "circle.slash")
            .font(.system(size: excludedMark, weight: .regular))
            .foregroundStyle(t.ink3)
        }
        // A line in error keeps its note but shows a dash for the amount — there
        // is no number to show, and a stale one would be worse.
        Text(entry.error == true ? "—" : Calc.fmt(entry.value))
          .font(.tally(TallyFont.monoMedium, 13.5))
          .monospacedDigit()
          .foregroundStyle(entry.error == true ? t.danger : (muted ? t.ink3 : t.ink))
      }
    }
    .padding(.vertical, Space.s3)
    .frame(minHeight: 44)  // the HIG floor for a row you can tap
    .contentShape(.rect)
    .onTapGesture { selectMode ? onTogglePick() : onEdit() }
    .listRowBackground(rowFill)
    .listRowSeparatorTint(t.line)
    .swipeActions(edge: .trailing) {
      if !selectMode {
        Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
      }
    }
    .contextMenu { if !selectMode { menu } }
    .onChange(of: justAdded, initial: true) { _, added in if added { pulse(hold: 0.52) } }
    .onChange(of: entry.value) { _, _ in
      // A live-reference ripple: this row's value just recomputed because a
      // line it references changed. Shorter than the freshly-added flash.
      if !justAdded { pulse(hold: 0.12) }
    }
    .animation(.easeOut(duration: 0.2), value: selectMode)
    .animation(.easeOut(duration: 0.2), value: picked)
  }

  @ViewBuilder
  private var expression: some View {
    if !Calc.refs(in: entry.expr).isEmpty {
      ExprView(
        expr: entry.expr, nameFor: nameFor, variant: .chip,
        tone: entry.error == true ? .error : (muted ? .muted : .accent))
    } else {
      // 12pt floor — below that the calculation reads as decoration.
      Text(entry.expr)
        .font(.tally(TallyFont.mono, 12))
        .foregroundStyle(muted ? t.ink2 : t.accentInk)
        .padding(.vertical, Space.s1)
        .padding(.horizontal, Space.s2)
        .background(muted ? t.line : t.accent2, in: .rect(cornerRadius: Radius.sm))
    }
  }

  @ViewBuilder
  private var menu: some View {
    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
    // The second way to reference a line, next to the card's Σ menu. Absent for
    // a line the draft may not see — a line only references lines above it,
    // which is what keeps reference cycles impossible.
    if canReference {
      Button { onReference() } label: { Label("Use as reference", systemImage: "sum") }
    }
    // Out of the total but still on the tab — an input, a subtotal mirror, a
    // number that is really a note.
    Button { onToggleExcluded() } label: {
      Label(
        muted ? "Count in total" : "Don’t count in total",
        systemImage: muted ? "circle" : "circle.slash")
    }
    // The second way into multi-select, next to the More menu's Select — a
    // long press is where iOS trains people to look for it.
    Button { onStartSelect() } label: { Label("Select lines", systemImage: "checkmark.circle") }
    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
  }

  /// The cell's fill, so it covers the row edge to edge and clips to the card's
  /// rounded ends — something a background inside the row cannot do.
  private var rowFill: some View {
    (lit ? t.rowSel : t.card)
      .overlay(t.rowSel.opacity(glow))
  }

  /// Swell the highlight in, hold it, then fade it out.
  private func pulse(hold: Double) {
    withAnimation(.easeOut(duration: 0.18)) { glow = 1 }
    withAnimation(.easeIn(duration: 0.48).delay(0.18 + hold)) { glow = 0 }
  }
}
