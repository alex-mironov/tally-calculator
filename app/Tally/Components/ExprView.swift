// ExprView.swift — an expression that may contain links to other lines,
// drawn so the token syntax never shows: "{e4}×10%" reads as ④ × 10%.
//
// Two variants, both Calculator v2's (tally-links.jsx):
//
//   · `.workings`, the maths under a committed row (`Formula`): the text with
//     its operators spaced out, and each link as the *number* of the line it
//     points at — a quiet badge, or a solid one when that line is the one
//     being edited, so editing a line shows at a glance which rows read it;
//   · `.draft`, the line being typed (`Pill`): each link as a tonal pill
//     carrying the line's number, its note and what it is worth right now —
//     the value is what lets "1,200 + ⟨Rent⟩" be checked by eye against the
//     result beside it.
//
// Links are numbered by *position*, as the rows' circles are: it is the number
// the eye can find on the screen. A link is to a line's id, not its number, so
// when a line above goes the badges simply renumber with the rows.
//
// Ported from mobile/src/components/tally/expr-view.tsx, whose pills named the
// line instead; v2 replaced the names with numbers in a row's workings.
import SwiftUI
import TallyKit

struct ExprView: View {
  let expr: String
  /// The line a link points at, by position (1-based); nil for a line that is
  /// gone, drawn "?".
  let positionFor: (String) -> Int?
  /// A draft pill's label — the line's note, or "Line n".
  var nameFor: (String) -> String = { _ in "" }
  /// The live value of a link, shown inside a draft pill.
  var valueFor: ((String) -> Double?)? = nil
  let variant: Variant
  var tone: Tone = .live
  /// Workings only: the line being edited, whose badge is drawn solid.
  var highlight: String?
  /// Draft only, from `Draft.fontSize(for:nameFor:)`.
  var fontSize: CGFloat?

  enum Variant { case draft, workings }

  enum Tone {
    /// The workings of a live line.
    case live
    /// A line that doesn't count toward the total.
    case muted
    /// A line whose expression can't be evaluated.
    case error
  }

  @Environment(\.theme) private var t

  private var draftSize: CGFloat { fontSize ?? Draft.fontSize }

  var body: some View {
    // The draft is never wrapped and never squeezed: it is measured at its full
    // width so DraftLine can run it off the leading edge, and `fixedSize` is
    // what stops SwiftUI truncating a run to make it fit. A row's workings are
    // the opposite case — a line under a note in a fixed-width row — so there a
    // long run truncates rather than pushing the amount off screen.
    HStack(spacing: variant == .draft ? 0 : Space.s1) {
      ForEach(Array(Calc.split(expr).enumerated()), id: \.offset) { _, seg in
        switch seg {
        case .text(let text):
          if variant == .draft { draftText(text) } else { workingsText(text) }
        case .ref(let id):
          if variant == .draft { pill(id) } else { badge(id) }
        }
      }
    }
    .fixedSize(horizontal: variant == .draft, vertical: false)
  }

  // MARK: - Workings

  private var ink: Color { tone == .error ? t.danger : t.ink2 }

  /// "4.5×2" as "4.5 × 2", the design's spaced operators.
  private func workingsText(_ text: String) -> some View {
    Text(Self.spaced(text))
      .tallyFont(TallyFont.mono, 14)
      .foregroundStyle(ink)
      .lineLimit(1)
  }

  private func badge(_ id: String) -> some View {
    LineBadge(
      position: positionFor(id), size: Space.s5,
      style: id == highlight ? .solid : .soft
    )
    .opacity(tone == .muted ? 0.6 : 1)
  }

  static func spaced(_ text: String) -> String {
    var out = ""
    for c in text {
      if "+−×÷".contains(c) { out += " \(c) " } else { out.append(c) }
    }
    return out.trimmingCharacters(in: .whitespaces)
  }

  // MARK: - Draft

  /// A text run between pills, with the design's 4pt either side of each
  /// operator so the pills don't crowd them.
  @ViewBuilder
  private func draftText(_ text: String) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(Self.operatorRuns(text).enumerated()), id: \.offset) { _, run in
        Text(run.text)
          .tallyFont(TallyFont.display, draftSize)
          .tracking(-0.03 * draftSize)
          .foregroundStyle(t.dockInk)
          .lineLimit(1)
          .padding(.horizontal, run.isOperator ? Space.s1 : 0)
      }
    }
  }

  /// A link in the draft: the line's number, its note, its value, on the
  /// operator tone. 36 tall, the badge 24 inside it.
  private func pill(_ id: String) -> some View {
    HStack(spacing: Space.s2) {
      LineBadge(position: positionFor(id), size: Space.s6, style: .inverse)
      Text(nameFor(id))
        .tallyFont(TallyFont.textSemi, 16)
        .lineLimit(1)
        .frame(maxWidth: 92, alignment: .leading)
        .fixedSize()
      if let value = valueFor?(id) {
        Text(Calc.fmt(value))
          .tallyFont(TallyFont.displayMedium, 16)
          .opacity(0.7)
      }
    }
    .foregroundStyle(t.opInk)
    // 6 leading, off the grid, so the badge sits concentric in the pill's
    // end: (36 − 24) / 2.
    .padding(.leading, 6)
    .padding(.trailing, Space.s3)
    .frame(height: 36)
    .background(t.op, in: .capsule)
    // `op` is the dock's own white on Paper; the dock's line gives the pill an
    // edge there and disappears into it elsewhere.
    .overlay { Capsule().strokeBorder(t.dockLine, lineWidth: 1) }
    .padding(.horizontal, Space.s1)
  }

  private struct Run {
    let text: String
    let isOperator: Bool
  }

  private static func operatorRuns(_ text: String) -> [Run] {
    var out: [Run] = []
    var buf = ""
    for c in text {
      if "+−×÷".contains(c) {
        if !buf.isEmpty { out.append(Run(text: buf, isOperator: false)) }
        buf = ""
        out.append(Run(text: String(c), isOperator: true))
      } else {
        buf.append(c)
      }
    }
    if !buf.isEmpty { out.append(Run(text: buf, isOperator: false)) }
    return out
  }
}

/**
 A line's number in a circle (tally-links.jsx, `Badge`) — how a link is drawn
 wherever it appears: under a row, in a draft pill, in a toast, in the delete
 confirmation.
 */
struct LineBadge: View {
  /// 1-based; nil for a line that is gone.
  let position: Int?
  var size: CGFloat = Space.s5
  var style: Style = .solid

  enum Style {
    /// The deep fill — the line being edited, a toast, the confirmation.
    case solid
    /// Quiet, for a row's workings.
    case soft
    /// On an operator-toned surface: a draft pill.
    case inverse
  }

  @Environment(\.theme) private var t

  private var colors: (fill: Color, ink: Color) {
    switch style {
    case .solid: (t.deep, t.deepInk)
    case .soft: (t.chip, t.ink2)
    case .inverse: (t.opInk, t.op)
    }
  }

  var body: some View {
    Text(position.map(String.init) ?? "?")
      // The design's 0.62 of the circle: type, not a layout metric.
      .tallyFont(TallyFont.displaySemi, (size * 0.62).rounded())
      .minimumScaleFactor(0.6)
      .lineLimit(1)
      .foregroundStyle(colors.ink)
      .frame(width: size, height: size)
      .background(colors.fill, in: .circle)
      .accessibilityLabel(position.map { "line \($0)" } ?? "a deleted line")
  }
}
