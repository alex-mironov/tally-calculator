// EntryRow.swift — a single line in the running tab.
//
// Ported from mobile/src/components/tally/swipe-row.tsx, which was only ever
// the *contents* of a row: the card, separators, row fill, swipe actions and
// context menu all came from a shared `GroupedRow` that existed to work around
// how an RN-hosted view sits inside a SwiftUI cell. None of that is needed
// here — `.listRowBackground`, `.swipeActions` and `.contextMenu` are simply
// available — so the two files collapse into one and grouped-list.tsx (313
// lines) has no counterpart at all.
//
// v2 (tally-app-v2.jsx, SwipeRowV2) draws the row on the canvas: a 40pt circle
// carrying the line's position, the note over its workings, the amount
// trailing. The circle is where every mode shows itself, so the rest of the row
// stays still:
//
//   · editing      — the circle takes the call-to-action fill;
//   · reference    — (the keypad's link key) every circle turns to a link, the
//                    tap drops the line into the draft instead of editing it,
//                    and a line the draft may not see — at or below the one
//                    being edited, or in error — dims and ignores the tap;
//   · select       — the circle is a tick: outlined, then filled when picked.
//                    The tap toggles, and both the context menu and the swipe
//                    action are withheld. Selecting is a read-only lens over
//                    the tab, so nothing that edits or deletes a line should be
//                    one gesture away while it is on.
//
// Delete stays the system's own swipe action rather than the design's drawn
// red circle (docs/v2-design.md): the native one is the gesture people know.
import SwiftUI
import TallyKit

struct EntryRow: View, Equatable {
  let entry: Entry
  /// 1-based position in the tab, shown in the circle. Not the sticky `num`:
  /// the circle counts the rows you can see, and it renumbers when one goes.
  let position: Int
  /// The first row has no hairline above it.
  let first: Bool
  /// "#n" after a note another line also carries; nil when the note is unique.
  let repeatIndex: Int?
  let selected: Bool
  let showExpr: Bool
  /// Freshly committed — flash the selection tint once to draw the eye.
  let justAdded: Bool
  let nameFor: (String) -> String
  /// What a reference in this row's workings is worth, for its pill.
  var valueFor: ((String) -> Double?)?
  /// The draft may reference this line (it sits above the edit point).
  let canReference: Bool
  let selectMode: Bool
  let picked: Bool
  /// Reference mode is on: a tap references this line rather than editing it.
  var referencing = false

  var onEdit: () -> Void
  var onDelete: () -> Void
  var onStartSelect: () -> Void
  var onTogglePick: () -> Void
  var onReference: () -> Void
  var onToggleExcluded: () -> Void

  /**
   What the row draws, so that the list can skip the rows a change did not
   touch.

   Anything that changes the screen — a commit, tapping a row to edit it,
   toggling a line in a selection — re-runs the list, and the list ran every
   row's body, visible or not, because the callbacks below can't be compared:
   fifty bodies for one line's change. With this, only the rows whose inputs
   changed run.

   A row whose workings hold a reference is never equal: its pills show
   another line's note and value, which reach it only through `nameFor` and
   `valueFor`, so nothing here can tell that they have not changed. The
   callbacks themselves are left out — they act on the screen's state as it
   is when they run, and what they capture of the row (the entry) is compared.
   */
  nonisolated static func == (a: EntryRow, b: EntryRow) -> Bool {
    a.entry == b.entry && !a.entry.expr.contains("{")
      && a.position == b.position && a.first == b.first && a.repeatIndex == b.repeatIndex
      && a.selected == b.selected && a.showExpr == b.showExpr && a.justAdded == b.justAdded
      && a.canReference == b.canReference && a.selectMode == b.selectMode
      && a.picked == b.picked && a.referencing == b.referencing
  }

  /// The design's row floor — well over the HIG's 44 for a row you can tap.
  static let minHeight: CGFloat = 64
  /// The rows' side inset, which the hairlines share.
  static let inset: CGFloat = Space.s5

  @Environment(\.theme) private var t
  @State private var glow: Double = 0

  /// Scaled, so the circle keeps pace with the row's text.
  @ScaledMetric(relativeTo: .subheadline) private var circleSize: CGFloat = 40
  /// The ⊘ beside a not-counted amount.
  @ScaledMetric(relativeTo: .footnote) private var excludedMark: CGFloat = 12

  /// A lens is on — select or reference — so nothing that edits is on offer.
  private var inLens: Bool { selectMode || referencing }

  /// A not-counted line reads as present but set aside.
  private var muted: Bool { entry.excluded == true }

  /// The editing highlight is meaningless while a lens is on — the entry card
  /// it refers to is not what the tap is about, and a second kind of lit row
  /// would only compete with the circles.
  private var lit: Bool { selected && !inLens }

  /// Unnamed lines are named for their sticky number, which is the name a
  /// reference to them already carries — not their position, which moves.
  private var title: String {
    entry.note.isEmpty ? "Line \(entry.num.map(String.init) ?? "\(position)")" : entry.note
  }

  var body: some View {
    HStack(spacing: Space.s3) {
      circle

      VStack(alignment: .leading, spacing: Space.s1) {
        HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
          Text(title)
            .tallyFont(TallyFont.textMedium, 16)
            .foregroundStyle(entry.note.isEmpty || muted ? t.ink2 : t.ink)
            .lineLimit(1)
          if let repeatIndex {
            Text("#\(repeatIndex)")
              .tallyFont(TallyFont.mono, 13)
              .foregroundStyle(t.ink2)
          }
        }

        if !entry.expr.isEmpty && showExpr {
          ExprView(
            expr: entry.expr, nameFor: nameFor, valueFor: valueFor, variant: .chip,
            tone: entry.error == true ? .error : (muted ? .muted : .accent))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: Space.s1) {
        if muted {
          Image(systemName: "circle.slash")
            .font(.system(size: excludedMark, weight: .regular))
            .foregroundStyle(t.ink2)
        }
        // A line in error keeps its note but shows a dash for the amount — there
        // is no number to show, and a stale one would be worse.
        Text(entry.error == true ? "—" : Calc.fmt(entry.value))
          .tallyFont(TallyFont.displayMedium, 17)
          .tracking(-0.17)
          .foregroundStyle(entry.error == true ? t.danger : (muted ? t.ink2 : t.ink))
      }
    }
    .opacity(referencing && !canReference ? 0.4 : 1)
    .padding(.vertical, Space.s3)
    .frame(minHeight: Self.minHeight)
    .contentShape(.rect)
    .onTapGesture {
      if referencing {
        if canReference { onReference() }
      } else if selectMode {
        onTogglePick()
      } else {
        onEdit()
      }
    }
    // One VoiceOver stop per line, not four. Left to itself VoiceOver read the
    // note, the "#5", the amount and the workings as separate elements — and
    // never said the row did anything, though tapping it edits the line.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(selectMode && picked ? .isSelected : [])
    .accessibilityHint(accessibilityHint)
    .listRowInsets(EdgeInsets(top: 0, leading: Self.inset, bottom: 0, trailing: Self.inset))
    // The system separator is hidden and the hairline drawn in the row's
    // background instead: a plain List insets its separator to the text, and
    // the design runs it the full width of the rows, circle included.
    .listRowSeparator(.hidden)
    .listRowBackground(rowFill)
    .swipeActions(edge: .trailing) {
      if !inLens {
        // The design's red delete circle. The role alone does not make it red:
        // the app-wide tint (Theme's accentInk) wins over it, and drew a pale
        // grey-blue trash on Midnight that read as "edit", not "delete".
        Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
          .tint(t.danger)
      }
    }
    .contextMenu { if !inLens { menu } }
    .onChange(of: justAdded, initial: true) { _, added in if added { pulse(hold: 0.52) } }
    .onChange(of: entry.value) { _, _ in
      // A live-reference ripple: this row's value just recomputed because a
      // line it references changed. Shorter than the freshly-added flash.
      if !justAdded { pulse(hold: 0.12) }
    }
    .animation(.easeOut(duration: 0.2), value: selectMode)
    .animation(.easeOut(duration: 0.2), value: picked)
    .animation(.easeOut(duration: 0.15), value: referencing)
    .animation(.easeOut(duration: 0.15), value: lit)
  }

  // MARK: - The circle

  private var circleFill: Color {
    if selectMode { return picked ? t.cta : .clear }
    if referencing { return t.op }
    if lit { return t.cta }
    return muted ? t.chip : t.deep
  }

  private var circleInk: Color {
    if selectMode { return t.ctaInk }
    if referencing { return t.opInk }
    if lit { return t.ctaInk }
    return muted ? t.ink2 : t.deepInk
  }

  private var circle: some View {
    ZStack {
      if selectMode {
        if picked {
          Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
            .transition(.scale.combined(with: .opacity))
        }
      } else if referencing {
        Image(systemName: "link").font(.system(size: 16, weight: .semibold))
          .transition(.opacity)
      } else {
        Text("\(position)")
          .tallyFont(TallyFont.displaySemi, 15)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
          .padding(.horizontal, Space.s1)
      }
    }
    .foregroundStyle(circleInk)
    .frame(width: circleSize, height: circleSize)
    .background(circleFill, in: .circle)
    .overlay {
      // Unpicked, the tick is an outline. 1.5pt is the design's ring; the
      // stroke is a line weight, not a layout metric, so it sits off the grid.
      if selectMode && !picked { Circle().strokeBorder(t.ink2, lineWidth: 1.5) }
      // A link circle is `op`, which on Paper is the screen's own white; the
      // line colour gives it an edge there and vanishes into it elsewhere.
      if referencing && !selectMode { Circle().strokeBorder(t.line, lineWidth: 1) }
    }
  }

  // MARK: - Speech

  private var accessibilityHint: String {
    if referencing { return canReference ? "Adds it to the entry" : "Can’t be referenced here" }
    return selectMode ? "Adds it to the selection" : "Edits the line"
  }

  /**
   The row as one spoken sentence: note, line number, amount, then its state
   and its workings. The workings go through `Calc.text` so a reference reads as
   the name of the line it points at, not as `{e103}`.
   */
  private var accessibilityText: String {
    var parts = [title]
    if !entry.note.isEmpty, let num = entry.num { parts.append("line \(num)") }
    parts.append(entry.error == true ? "can’t be calculated" : Calc.fmt(entry.value))
    if muted { parts.append("not counted in the total") }
    if !entry.expr.isEmpty && showExpr {
      parts.append("from " + Calc.text(entry.expr, nameFor: nameFor))
    }
    return parts.joined(separator: ", ")
  }

  // MARK: - Menu

  /// The design's order (tally-app-v2.jsx, the row's ContextMenu), with the
  /// app's own "Don't count in total" kept in after the reference
  /// (docs/v2-design.md, "Decisions"), and Delete set apart below a divider.
  @ViewBuilder
  private var menu: some View {
    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
    // The second way into multi-select, next to the title menu's Select lines
    // — a long press is where iOS trains people to look for it. It starts with
    // this line already ticked.
    Button { onStartSelect() } label: { Label("Select", systemImage: "checkmark.circle") }
    // The second way to reference a line, next to the keypad's reference
    // key. Absent for a line the draft may not see — a line only references lines above it,
    // which is what keeps reference cycles impossible.
    if canReference {
      Button { onReference() } label: { Label("Use as reference", systemImage: "link") }
    }
    // Out of the total but still on the tab — an input, a subtotal mirror, a
    // number that is really a note.
    Button { onToggleExcluded() } label: {
      Label(
        muted ? "Count in total" : "Don’t count in total",
        systemImage: muted ? "circle" : "circle.slash")
    }
    Divider()
    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
  }

  // MARK: - Fill

  /// The cell's fill: the canvas itself, the editing wash, the hairline above.
  /// Drawn as the cell's background rather than inside the row so it runs edge
  /// to edge and stays out of the context menu's lifted preview.
  private var rowFill: some View {
    (lit ? t.rowSel : Color.clear)
      .overlay(t.rowSel.opacity(glow))
      .overlay(alignment: .top) {
        if !first {
          // 1pt, the design's 1px rule: a CSS pixel is a point.
          Rectangle().fill(t.line).frame(height: 1).padding(.horizontal, Self.inset)
        }
      }
  }

  /// Swell the highlight in, hold it, then fade it out.
  private func pulse(hold: Double) {
    withAnimation(.easeOut(duration: 0.18)) { glow = 1 }
    withAnimation(.easeIn(duration: 0.48).delay(0.18 + hold)) { glow = 0 }
  }
}
