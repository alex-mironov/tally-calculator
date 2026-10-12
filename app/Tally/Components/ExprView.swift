// ExprView.swift — an expression that may contain reference tokens, drawn as
// literal text runs interleaved with named pills, so "7092.3−{e103}" reads as
// 7092.3 − ⟨Rent⟩ rather than leaking token syntax.
//
// Two variants: the big draft line in the entry card, and the small chip under
// a committed row. Ported from mobile/src/components/tally/expr-view.tsx.
import SwiftUI
import TallyKit

struct ExprView: View {
  let expr: String
  /// Display name for a reference id — a note, "#4", or "Total".
  let nameFor: (String) -> String
  /// The live value of a reference, shown inside its pill so the workings read
  /// as numbers, not just names. Nil leaves the pill a bare name.
  var valueFor: ((String) -> Double?)? = nil
  let variant: Variant
  var tone: Tone = .accent
  /// Draft only, from `Draft.fontSize(forLength:)`, so both draft paths — with
  /// pills and without — step together.
  var fontSize: CGFloat?

  enum Variant { case draft, chip }

  enum Tone {
    /// The workings of a live line.
    case accent
    /// A line that doesn't count toward the total.
    case muted
    /// A line whose expression can't be evaluated.
    case error
  }

  @Environment(\.theme) private var t

  /// The workings' text: second ink, as v2 sets a row's workings, or red when
  /// the line can't be evaluated.
  private var ink: Color { tone == .error ? t.danger : t.ink2 }

  var body: some View {
    // The draft is never wrapped and never squeezed: it is measured at its full
    // width so DraftLine's scroll view carries what doesn't fit, and `fixedSize`
    // is what stops SwiftUI truncating a run to make it fit. A row's workings
    // are the opposite case — a line under a note in a fixed-width row — so
    // there a long run truncates rather than pushing the amount off screen.
    HStack(alignment: variant == .draft ? .center : .firstTextBaseline, spacing: Space.s1) {
      ForEach(Array(Calc.split(expr).enumerated()), id: \.offset) { _, seg in
        switch seg {
        case .text(let text):
          Text(text)
            .tallyFont(
              variant == .draft ? TallyFont.display : TallyFont.mono,
              variant == .draft ? fontSize ?? Draft.fontSize : 14)
            .monospacedDigit()
            .tracking(variant == .draft ? -0.8 : 0)
            .foregroundStyle(variant == .draft ? t.ink : ink)
            .lineLimit(1)

        case .ref(let id):
          if variant == .draft {
            draftPill(id)
          } else {
            chipPill(id)
          }
        }
      }
    }
    .fixedSize(horizontal: variant == .draft, vertical: false)
  }

  /**
   A reference, per the design: a link glyph, the line's name, and what it is
   worth right now, on the operator tone. The value is what makes the pill a
   number in the sum — without it "1,200 + ⟨Rent⟩" can't be checked by eye
   against the preview.
   */
  private func draftPill(_ id: String) -> some View {
    pill(id, glyph: 12, text: 15, maxName: 120)
  }

  /// The same pill, a size down, in a committed row's workings line.
  private func chipPill(_ id: String) -> some View {
    pill(id, glyph: 11, text: 13, maxName: 116)
      // A muted line's pill steps back with the rest of the line.
      .opacity(tone == .muted ? 0.6 : 1)
  }

  private func pill(_ id: String, glyph: CGFloat, text: CGFloat, maxName: CGFloat) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
      Image(systemName: "link")
        .font(.system(size: glyph, weight: .semibold))
      Text(nameFor(id))
        .tallyFont(TallyFont.textSemi, text)
        .lineLimit(1)
        .frame(maxWidth: maxName, alignment: .leading)
        .fixedSize()
      if let value = valueFor?(id) {
        Text(Calc.fmt(value))
          .tallyFont(TallyFont.displayMedium, text)
      }
    }
    .foregroundStyle(tone == .error ? t.danger : t.opInk)
    .padding(.vertical, Space.s1)
    .padding(.horizontal, Space.s2)
    .background(t.op, in: .rect(cornerRadius: Radius.md))
    // `op` is the screen's own white on Paper; the line colour gives the pill
    // an edge there and disappears into it on the other schemes.
    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(t.line, lineWidth: 1))
  }
}
