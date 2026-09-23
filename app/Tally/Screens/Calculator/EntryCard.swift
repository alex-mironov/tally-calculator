// EntryCard.swift — the in-progress entry: the note chip, the live result, and
// the draft line itself.
//
// Referencing lives elsewhere now: the keypad's Σ key drops in the running
// total, and a row's context menu offers "Use as reference" for one line. The
// card used to carry a Σ menu of every line as well; the design dropped it,
// and the row menu already reaches the same lines from where they are shown.
//
// Liquid Glass, unconditionally. The border turns accent on an invalid commit
// (the flash) and while a row is being edited.
//
// ── What this replaces ──────────────────────────────────────────────────────
// The React Native version had to draw its tap target as an `absoluteFill`
// *sibling* under the contents, with `box-none` on the row, because a scroll
// view under a `Pressable` ancestor never scrolls on the new architecture — so
// wrapping the card in a Pressable made the draft line undraggable. Here the
// card's background takes the tap and the line takes its own; there is no
// responder to fight over.
import SwiftUI
import TallyKit

struct EntryCard: View {
  @Binding var draft: String
  @Binding var note: String
  @Binding var noteOpen: Bool

  /// Accent border: an invalid commit was just refused, or a row is being edited.
  let highlighted: Bool
  /// The keypad is away, so the card doubles as the way back to it.
  let padStowed: Bool
  let nameFor: (String) -> String

  var onTapCard: () -> Void

  @Environment(\.theme) private var t
  @FocusState private var noteFocused: Bool

  private var preview: Double? { Calc.evaluate(draft, resolve: resolveForPreview) }
  private let resolveForPreview: Calc.RefResolver

  init(
    draft: Binding<String>, note: Binding<String>, noteOpen: Binding<Bool>,
    highlighted: Bool, padStowed: Bool, nameFor: @escaping (String) -> String,
    resolve: @escaping Calc.RefResolver,
    onTapCard: @escaping () -> Void
  ) {
    _draft = draft
    _note = note
    _noteOpen = noteOpen
    self.highlighted = highlighted
    self.padStowed = padStowed
    self.nameFor = nameFor
    self.resolveForPreview = resolve
    self.onTapCard = onTapCard
  }

  /// The result only shows once the line is actually a calculation — a bare
  /// number does not need to be told what it equals.
  private var showsResult: Bool {
    preview != nil && (Calc.hasOperator(draft) || !Calc.refs(in: draft).isEmpty)
  }

  private var draftSize: CGFloat {
    Draft.fontSize(forLength: Draft.length(draft, nameFor: nameFor))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Space.s1) {
      topRow
        // Above the draft line, so the chips' enlarged 44pt targets win the
        // few points where they overlap it. The draft line comes later in the
        // stack and would otherwise sit on top and swallow the lower edge of
        // both targets — found by tapping just below the Σ chip.
        .zIndex(1)
      draftLine
    }
    .padding(.vertical, Space.s3)
    .padding(.horizontal, Space.s4)
    .glassEffect(.regular, in: .rect(cornerRadius: Radius.lg + Space.s1))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.lg + Space.s1)
        .strokeBorder(highlighted ? t.accentInk : t.line, lineWidth: 1)
    }
    .elevation(.glass)
    .padding(.horizontal, Space.s4)
    .padding(.bottom, Space.s2)
    .animation(.easeOut(duration: 0.18), value: highlighted)
    // The chips, the note field and the result grow with the user's text size,
    // within reason; the card sits between the list and the keypad and has to
    // leave both some room.
    .dynamicTypeSize(...TypeCap.chrome)
  }

  // MARK: - Pieces

  private var topRow: some View {
    HStack(spacing: Space.s3) {
      noteControl
        .frame(maxWidth: .infinity, alignment: .leading)

      if showsResult {
        Text("= \(Calc.fmt(preview))")
          .font(.tally(TallyFont.monoMedium, TextScale.bodySm))
          .monospacedDigit()
          .foregroundStyle(t.accentInk)
          .transition(.opacity)
      }
    }
    .frame(minHeight: Space.s8)
    .animation(.easeOut(duration: 0.15), value: showsResult)
  }

  @ViewBuilder
  private var noteControl: some View {
    if noteOpen {
      TextField("Add a note", text: $note)
        .font(.tally(TallyFont.sansSemi, TextScale.bodyMd))
        .foregroundStyle(t.ink)
        .focused($noteFocused)
        .submitLabel(.done)
        .onSubmit { noteOpen = false }
        .task { noteFocused = true }
    } else {
      Button {
        noteOpen = true
      } label: {
        // The design's "Add note" chip: a 32pt soft-accent pill that shows the
        // note itself once there is one. The ✎ key it replaces is now Σ.
        Text(note.isEmpty ? "Add note" : note)
          .font(.tally(TallyFont.sansSemi, TextScale.bodyMd))
          .foregroundStyle(t.accentInk)
          .lineLimit(1)
          .frame(maxWidth: note.isEmpty ? nil : 160, alignment: .leading)
          .padding(.horizontal, Space.s3)
          .frame(height: Space.s8)
          .background(t.accent2, in: .rect(cornerRadius: Radius.md))
          .hitTarget()
      }
      .buttonStyle(.plain)
    }
  }

  private var draftLine: some View {
    DraftLine(draft: draft, onTap: onTapCard) {
      if !Calc.refs(in: draft).isEmpty {
        ExprView(expr: draft, nameFor: nameFor, variant: .draft, fontSize: draftSize)
      } else {
        Text(draft.isEmpty ? "0" : draft)
          .font(.tally(TallyFont.monoSemi, draftSize))
          .monospacedDigit()
          .tracking(-0.8)
          .foregroundStyle(draft.isEmpty ? t.ink3 : t.ink)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    // Tighter than the rest of the card: the line box is a fixed 44pt, and it
    // is the digits being typed that would clip.
    .dynamicTypeSize(...TypeCap.draft)
    // Read as what it is, with the line spoken the way the row will be.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Current entry")
    .accessibilityValue(draft.isEmpty ? "empty" : Calc.text(draft, nameFor: nameFor))
  }
}

extension View {
  /**
   Grow the tappable area to the 44pt HIG minimum without growing what is drawn.

   The chips in the entry card are drawn at 32pt tall on purpose — they are
   labels on a card, not buttons in a toolbar — but a 25pt target is a miss
   waiting to happen. The padding extends the hit shape; the negative padding
   takes the layout back, so nothing around the chip moves.
   */
  func hitTarget(minimum: CGFloat = 44) -> some View {
    padding(.vertical, 9)
      .padding(.horizontal, 4)
      .contentShape(.rect)
      .padding(.vertical, -9)
      .padding(.horizontal, -4)
  }
}
