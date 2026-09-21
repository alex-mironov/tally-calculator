// EntryCard.swift — the in-progress entry: the note chip, the Σ reference menu,
// the live result, and the draft line itself.
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
  /// Lines this draft may reference — above the edit point, newest first.
  let referenceable: [Entry]
  /// The running total of the lines this draft can see.
  let referenceSum: Double

  var onTapCard: () -> Void
  var onInsertRef: (String, String?) -> Void

  @Environment(\.theme) private var t
  @FocusState private var noteFocused: Bool

  private var preview: Double? { Calc.evaluate(draft, resolve: resolveForPreview) }
  private let resolveForPreview: Calc.RefResolver

  init(
    draft: Binding<String>, note: Binding<String>, noteOpen: Binding<Bool>,
    highlighted: Bool, padStowed: Bool, nameFor: @escaping (String) -> String,
    referenceable: [Entry], referenceSum: Double,
    resolve: @escaping Calc.RefResolver,
    onTapCard: @escaping () -> Void, onInsertRef: @escaping (String, String?) -> Void
  ) {
    _draft = draft
    _note = note
    _noteOpen = noteOpen
    self.highlighted = highlighted
    self.padStowed = padStowed
    self.nameFor = nameFor
    self.referenceable = referenceable
    self.referenceSum = referenceSum
    self.resolveForPreview = resolve
    self.onTapCard = onTapCard
    self.onInsertRef = onInsertRef
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
      HStack(spacing: Space.s2) {
        noteControl
        // Hidden while the note field is typing — the row is the field's.
        if !noteOpen && !referenceable.isEmpty { referenceMenu }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if showsResult {
        Text("= \(Calc.fmt(preview))")
          .font(.tally(TallyFont.monoMedium, TextScale.bodySm))
          .monospacedDigit()
          .foregroundStyle(t.accentInk)
          .transition(.opacity)
      }
    }
    .frame(minHeight: Space.s6)
    .animation(.easeOut(duration: 0.15), value: showsResult)
  }

  @ViewBuilder
  private var noteControl: some View {
    if noteOpen {
      TextField("add a note…", text: $note)
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
        Text(note.isEmpty ? "+ note" : note)
          .font(.tally(TallyFont.sansSemi, 12.5))
          .foregroundStyle(t.accentInk)
          .lineLimit(1)
          .frame(maxWidth: note.isEmpty ? nil : 120, alignment: .leading)
          .padding(.vertical, Space.s1)
          .padding(.horizontal, Space.s3)
          .background(t.accent2, in: .rect(cornerRadius: Radius.sm))
      }
      .buttonStyle(.plain)
    }
  }

  /**
   Σ — reference an earlier line.

   A menu of this tab's rows, newest first, plus the running subtotal. Picking
   one drops a *reference token* into the draft — a live link rendered as a
   named pill, so the row recomputes whenever the referenced line changes. A
   line may only reference lines above it, which is also what makes reference
   cycles impossible. Capped at twelve so the menu stays a menu, not an archive.
   */
  private var referenceMenu: some View {
    Menu {
      Button("Total so far — \(Calc.fmt(referenceSum))") { onInsertRef("sum", nil) }
      Divider()
      ForEach(referenceable) { e in
        Button("\(e.note.isEmpty ? "#\(e.num ?? 0)" : e.note) — \(Calc.fmt(e.value))") {
          onInsertRef(e.id, e.note.isEmpty ? nil : e.note)
        }
      }
    } label: {
      Image(systemName: "sum")
        .font(.footnote)
        .foregroundStyle(t.accentInk)
        .frame(width: 36, height: 28)
        .contentShape(.rect)
        .background(t.accent2, in: .rect(cornerRadius: Radius.sm))
    }
    .accessibilityLabel("Reference an earlier line")
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
  }
}
