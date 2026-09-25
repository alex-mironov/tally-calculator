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
  /// Draft only: the live value of a reference, shown inside its pill so the
  /// line being built reads as numbers, not just names.
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

  private var ink: Color {
    switch tone {
    case .error: return t.danger
    case .muted: return t.ink2
    case .accent: return t.accentInk
    }
  }

  private var pillBackground: Color { tone == .muted ? t.line : t.accent2 }

  var body: some View {
    // Never wrapped and never squeezed: the draft is measured at its full width
    // so DraftLine's scroll view carries what doesn't fit. `fixedSize` is what
    // stops SwiftUI truncating a run to make the row fit.
    HStack(alignment: variant == .draft ? .center : .firstTextBaseline, spacing: Space.s1) {
      ForEach(Array(Calc.split(expr).enumerated()), id: \.offset) { _, seg in
        switch seg {
        case .text(let text):
          Text(text)
            .font(
              variant == .draft
                ? .tally(TallyFont.monoSemi, fontSize ?? Draft.fontSize)
                : .tally(TallyFont.mono, 12)
            )
            .monospacedDigit()
            .tracking(variant == .draft ? -0.8 : 0)
            .foregroundStyle(variant == .draft ? t.ink : ink)
            .lineLimit(1)

        case .ref(let id):
          if variant == .draft {
            draftPill(id)
          } else {
            Text(nameFor(id))
              // 11.5pt, a hair under the 12pt run beside it — the pill is a
              // name inside a calculation, not a second voice in it.
              .font(.tally(TallyFont.sansSemi, 11.5))
              .foregroundStyle(ink)
              .lineLimit(1)
              .padding(.vertical, Space.s1)
              .padding(.horizontal, Space.s2)
              .frame(maxWidth: 132, alignment: .leading)
              .fixedSize()
              .background(pillBackground, in: .rect(cornerRadius: Radius.sm))
          }
        }
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  /**
   The draft's pill, per the design: a link glyph, the line's name, and what it
   is worth right now. The value is what makes the pill a number in the sum —
   without it "1,200 + ⟨Rent⟩" can't be checked by eye against the preview.
   */
  private func draftPill(_ id: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
      Image(systemName: "link")
        .font(.system(size: 12, weight: .semibold))
      Text(nameFor(id))
        .font(.tally(TallyFont.sansSemi, 15))
        .lineLimit(1)
        .frame(maxWidth: 120, alignment: .leading)
        .fixedSize()
      if let value = valueFor?(id) {
        Text(Calc.fmt(value))
          .font(.tally(TallyFont.monoMedium, 15))
          .monospacedDigit()
          .foregroundStyle(t.ink)
      }
    }
    .foregroundStyle(t.accentInk)
    .padding(.vertical, Space.s1)
    .padding(.horizontal, Space.s2)
    .background(pillBackground, in: .rect(cornerRadius: Radius.md))
  }
}
