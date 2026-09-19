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
  /// Display name for a reference id — a note, "#4", or "Σ total".
  let nameFor: (String) -> String
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
          Text(nameFor(id))
            .font(
              variant == .draft
                ? .tally(TallyFont.sansSemi, 16)
                // 11.5pt, a hair under the 12pt run beside it — the pill is a
                // name inside a calculation, not a second voice in it.
                : .tally(TallyFont.sansSemi, 11.5)
            )
            .foregroundStyle(variant == .draft ? t.accentInk : ink)
            .lineLimit(1)
            .padding(.vertical, Space.s1)
            .padding(.horizontal, Space.s2)
            .frame(maxWidth: variant == .draft ? 152 : 132, alignment: .leading)
            .fixedSize()
            .background(
              pillBackground,
              in: .rect(cornerRadius: variant == .draft ? Radius.md : Radius.sm))
        }
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}
