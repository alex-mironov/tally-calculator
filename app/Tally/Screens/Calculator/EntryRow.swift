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
// v2 (tally-app-v2.jsx, SwipeRowV2) draws the row on the canvas: a 32pt circle
// carrying the line's position, the note over its workings, the amount
// trailing. The modes:
//
//   · editing      — the circle takes the deep fill;
//   · link mode    — (the keypad's link key) every line the draft may link
//                    grows a link circle at its end, which turns to a tick
//                    once it is linked; a tap links or unlinks it instead of
//                    editing it. A line the draft may not link — below the
//                    one being edited, or in error — dims and ignores the
//                    tap, and the line being edited says what to do;
//   · select       — the circle is a tick: outlined, then filled when picked.
//                    The tap toggles, and both the context menu and the swipe
//                    action are withheld. Selecting is a read-only lens over
//                    the tab, so nothing that edits or deletes a line should be
//                    one gesture away while it is on.
//
// A row's workings show links as the linked line's number (ExprView), solid
// where it is the line being edited — so editing a line shows which rows read
// it.
//
// Delete stays the system's own swipe action rather than the design's drawn
// red circle (docs/v2-design.md): the native one is the gesture people know.
import SwiftUI
import TallyKit

struct EntryRow: View {
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
  /// Where a linked line stands, for the badges in this row's workings.
  let positionFor: (String) -> Int?
  /// The line being edited, whose badge in these workings is drawn solid.
  let editingID: String?
  /// The draft may link this line (it sits above the edit point).
  let canReference: Bool
  /// The draft links this line.
  let linked: Bool
  let selectMode: Bool
  let picked: Bool
  /// Link mode is on: a tap links this line rather than editing it.
  var referencing = false

  var onEdit: () -> Void
  var onDelete: () -> Void
  var onStartSelect: () -> Void
  var onTogglePick: () -> Void
  var onReference: () -> Void
  /// The menu's "Link in new line".
  var onLinkInNewLine: () -> Void
  var onToggleExcluded: () -> Void

  /// The design's row floor — well over the HIG's 44 for a row you can tap.
  static let minHeight: CGFloat = 64
  /// The rows' side inset, which the hairlines share.
  static let inset: CGFloat = Space.s5

  @Environment(\.theme) private var t
  @State private var glow: Double = 0

  /// What the row draws. Its derived state — the lens, the muting, the
  /// editing highlight — is read from here too, so it is defined once.
  private var content: Content {
    Content(
      entry: entry, position: position, repeatIndex: repeatIndex, selected: selected,
      showExpr: showExpr, positionFor: positionFor, editingID: editingID,
      canReference: canReference, linked: linked, selectMode: selectMode, picked: picked,
      referencing: referencing, onEdit: onEdit, onTogglePick: onTogglePick,
      onReference: onReference)
  }

  /**
   The cell: the row's content, and everything the List reads off the cell
   around it.

   The content is compared (see `Content.==`) so the list can skip the rows a
   change did not touch. The cell around it is not, and must not be: the List
   reads `.listRowInsets`, `.listRowSeparator` and `.listRowBackground` — and
   the swipe actions and context menu — off the *outermost* view of the row,
   and an EquatableView in front of them hides them. With `.equatable()` on the
   whole row the rows took the system's default insets and separators: much
   taller, with the hairlines no longer inset to the rows. The fill also has
   to stay out here because it is driven by `glow`, this cell's own state,
   which a comparison of the row's inputs would never see change.

   What runs per row on every pass is just this: building `Content` and
   comparing it.
   */
  var body: some View {
    let content = content
    content
      .equatable()
      .listRowInsets(EdgeInsets(top: 0, leading: Self.inset, bottom: 0, trailing: Self.inset))
      // The system separator is hidden and the hairline drawn in the row's
      // background instead: a plain List insets its separator to the text, and
      // the design runs it the full width of the rows, circle included.
      .listRowSeparator(.hidden)
      .listRowBackground(rowFill(lit: content.lit))
      .swipeActions(edge: .trailing) {
        if !content.inLens {
          // The design's red delete circle, red by tint rather than by role.
          // A destructive role makes the List take the row out the moment it is
          // tapped, ahead of the data — and a line other lines link now waits
          // on a confirmation first, so the row was still in the data when the
          // collection view had already dropped it: an "invalid number of
          // items" assertion. Without the role the row goes when the line does.
          Button(action: onDelete) { Label("Delete", systemImage: "trash") }
            .tint(t.danger)
        }
      }
      .contextMenu { if !content.inLens { menu(muted: content.muted) } }
      .onChange(of: justAdded, initial: true) { _, added in if added { pulse(hold: 0.52) } }
      .onChange(of: entry.value) { _, _ in
        // A live-reference ripple: this row's value just recomputed because a
        // line it references changed. Shorter than the freshly-added flash.
        if !justAdded { pulse(hold: 0.12) }
      }
      .animation(.easeOut(duration: 0.2), value: selectMode)
      .animation(.easeOut(duration: 0.2), value: picked)
      .animation(.easeOut(duration: 0.15), value: referencing)
      .animation(.easeOut(duration: 0.15), value: linked)
      .animation(.easeOut(duration: 0.15), value: content.lit)
  }

  // MARK: - Menu

  /// The design's order (tally-app-v2.jsx, the row's ContextMenu), with the
  /// app's own "Don't count in total" kept in after the link
  /// (docs/v2-design.md, "Decisions"), and Delete set apart below a divider.
  @ViewBuilder
  private func menu(muted: Bool) -> some View {
    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
    // The second way into multi-select, next to the title menu's Select lines
    // — a long press is where iOS trains people to look for it. It starts with
    // this line already ticked.
    Button { onStartSelect() } label: { Label("Select", systemImage: "checkmark.circle") }
    // A new line that starts as a link to this one — "Taxi tip" from "Taxi"
    // is the line, then × 10%. A new line goes at the foot, below every line,
    // so any line may be linked; one in error has nothing to link to.
    if entry.error != true {
      Button { onLinkInNewLine() } label: { Label("Link in new line", systemImage: "link") }
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
  private func rowFill(lit: Bool) -> some View {
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

// MARK: - Content

extension EntryRow {
  /// The row itself — circle, note, workings, amount, link mark — without the
  /// cell's chrome, which EntryRow's body puts around it.
  struct Content: View, Equatable {
    let entry: Entry
    let position: Int
    let repeatIndex: Int?
    let selected: Bool
    let showExpr: Bool
    let positionFor: (String) -> Int?
    let editingID: String?
    let canReference: Bool
    let linked: Bool
    let selectMode: Bool
    let picked: Bool
    let referencing: Bool

    let onEdit: () -> Void
    let onTogglePick: () -> Void
    let onReference: () -> Void

    /**
     What the row draws, so that the list can skip the rows a change did not
     touch.

     Anything that changes the screen — a commit, tapping a row to edit it,
     toggling a line in a selection — re-runs the list, and the list ran every
     row's body, visible or not, because the callbacks below can't be compared:
     fifty bodies for one line's change. With this, only the rows whose inputs
     changed run.

     A row whose workings hold a link is never equal: its badges show where
     another line stands, which reaches it only through `positionFor`, so
     nothing here can tell that it has not changed. The callbacks themselves are
     left out — they act on the screen's state as it is when they run, and what
     they capture of the row (the entry) is compared. (`first` and `justAdded`
     are the cell's — the hairline and the glow — and don't reach the content
     at all.)
     */
    nonisolated static func == (a: Content, b: Content) -> Bool {
      a.entry == b.entry && !a.entry.expr.contains("{")
        && a.position == b.position && a.repeatIndex == b.repeatIndex
        && a.selected == b.selected && a.showExpr == b.showExpr
        && a.canReference == b.canReference && a.linked == b.linked
        && a.selectMode == b.selectMode && a.picked == b.picked
        && a.referencing == b.referencing
    }

    @Environment(\.theme) private var t

    /// Scaled, so the circles keep pace with the row's text.
    @ScaledMetric(relativeTo: .subheadline) private var circleSize: CGFloat = 32
    /// The ⊘ beside a not-counted amount.
    @ScaledMetric(relativeTo: .footnote) private var excludedMark: CGFloat = 12

    /// A lens is on — select or link — so nothing that edits is on offer.
    var inLens: Bool { selectMode || referencing }

    /// A not-counted line reads as present but set aside.
    var muted: Bool { entry.excluded == true }

    /// The editing wash is meaningless while a lens is on — the dock it refers
    /// to is not what the tap is about. (The circle still marks the line.)
    var lit: Bool { selected && !inLens }

    /// Link mode, and this line is one the draft may link.
    private var pickable: Bool { referencing && canReference && !selectMode }

    /// Link mode, and this line may not be linked from here. The line being
    /// edited is exempt: it is what the links are for.
    private var dimmed: Bool { referencing && !canReference && !selected }

    /// Unnamed lines are named for where they stand — the number their circle
    /// carries, and the one a link to them shows.
    private var title: String {
      entry.note.isEmpty ? "Line \(position)" : entry.note
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

          if referencing && selected {
            Text("Link lines above this one")
              .tallyFont(TallyFont.text, 14)
              .foregroundStyle(t.ink2)
          } else if !entry.expr.isEmpty && showExpr {
            ExprView(
              expr: entry.expr, positionFor: positionFor, variant: .workings,
              tone: entry.error == true ? .error : (muted ? .muted : .live),
              highlight: editingID)
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

        if !selectMode && (pickable || linked) { linkMark }
      }
      .opacity(dimmed ? 0.32 : 1)
      .padding(.vertical, Space.s3)
      .frame(minHeight: EntryRow.minHeight)
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
      .accessibilityAddTraits((selectMode && picked) || (referencing && linked) ? .isSelected : [])
      .accessibilityHint(accessibilityHint)
    }

    // MARK: - The circles

    private var circleFill: Color {
      if selectMode { return picked ? t.cta : .clear }
      return selected ? t.deep : t.chip
    }

    private var circleInk: Color {
      if selectMode { return t.ctaInk }
      return selected ? t.deepInk : t.ink2
    }

    private var circle: some View {
      ZStack {
        if selectMode {
          if picked {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
              .transition(.scale.combined(with: .opacity))
          }
        } else {
          Text("\(position)")
            .tallyFont(TallyFont.displaySemi, 14)
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
      }
    }

    /// Link mode's mark at the row's end: a link to tap, or — once the draft
    /// links the line — a tick in the call to action. The design's 30, onto
    /// the grid as the position circle's 32.
    private var linkMark: some View {
      Image(systemName: linked ? "checkmark" : "link")
        .font(.system(size: linked ? 12 : 16, weight: linked ? .heavy : .semibold))
        .foregroundStyle(linked ? t.ctaInk : t.chipInk)
        .frame(width: circleSize, height: circleSize)
        .background(linked ? t.cta : t.chip, in: .circle)
        .contentTransition(.symbolEffect(.replace))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: - Speech

    private var accessibilityHint: String {
      if referencing {
        if !canReference { return selected ? "The line being edited" : "Can’t be linked here" }
        return linked ? "Unlinks it" : "Links it into the entry"
      }
      return selectMode ? "Adds it to the selection" : "Edits the line"
    }

    /**
     The row as one spoken sentence: note, line number, amount, then its state
     and its workings. Links read as "line 4", the number the badge shows.
     */
    private var accessibilityText: String {
      var parts = [title]
      if !entry.note.isEmpty { parts.append("line \(position)") }
      parts.append(entry.error == true ? "can’t be calculated" : Calc.fmt(entry.value))
      if muted { parts.append("not counted in the total") }
      if linked { parts.append("linked") }
      if !entry.expr.isEmpty && showExpr {
        parts.append(
          "from " + Calc.text(entry.expr) { id in positionFor(id).map { "line \($0)" } ?? "a deleted line" })
      }
      return parts.joined(separator: ", ")
    }
  }
}
