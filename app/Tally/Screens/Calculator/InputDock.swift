// InputDock.swift — Calculator v2's one floating input dock: everything the
// user types into, in one opaque surface in the thumb zone.
//
// Top to bottom: the grabber (tap to stow the keys), the entry row (the note
// chip, and what the line will make), note suggestions while a note is being
// typed, the draft, and the keys. With the keys stowed the dock keeps the first
// three, so the line being typed never leaves the screen.
//
// The keys are the caller's — they come in as `keys`, already collapsed as far
// as the stow and the system keyboard ask (CalculatorScreen+Dock.swift owns
// that) — so this view only draws the dock and what sits in it.
//
// ── What this replaces ──────────────────────────────────────────────────────
// v1 split the same job three ways: a seam with the grabber and the total, a
// Liquid Glass entry card, and a keypad band across the screen's foot behind a
// hairline. v2 folds them into one opaque surface (docs/v2-design.md, "Keys &
// dock"), so the card's glass, its border flash and the seam's hairline are all
// gone. An invalid commit shakes the draft instead; editing an existing line
// rings the dock in the call to action.
import SwiftUI
import TallyKit

struct InputDock<Keys: View>: View {
  @Binding var draft: String
  @Binding var note: String
  @Binding var noteOpen: Bool

  /// An existing line is being edited: the dock is ringed and offers Cancel.
  let editing: Bool
  /// Bumped on every refused commit.
  let shakes: Int
  /// Phone and iPad portrait. The iPad's landscape pane has no keys to stow.
  let showsGrabber: Bool
  let padStowed: Bool
  /// "= 12.50" while the draft is a calculation, "Total 340.00" — what the tab
  /// will come to — while it is a bare amount; nil for nothing.
  let trailing: String?
  /// Recent notes matching what is typed, while the note field is open.
  let suggestions: [String]
  let nameFor: (String) -> String
  let resolve: Calc.RefResolver
  /// The vertical drag that stows the keys, from the grabber or the entry row.
  /// Live only where there is a grabber.
  let stowDrag: AnyGesture<Void>

  var onToggleStow: () -> Void
  var onCancelEdit: () -> Void
  /// The draft was tapped — with the keys stowed, that brings them back.
  var onTapDraft: () -> Void
  var onSwipeDelete: () -> Void

  @ViewBuilder var keys: Keys

  @Environment(\.theme) private var t
  @FocusState private var noteFocused: Bool

  /**
   The dock's outline. The design's radius is 40, but it ignores the bottom
   safe area and sits 8pt off the device's own rounded corners — so the bottom
   corners are concentric with the display rather than a fixed 40. On an
   iPhone 17 Pro the display's ~62pt corner less the 8pt margin is ~54, which
   is what `.concentric` resolves to there; a fixed 40 left a visibly thicker
   wedge of screen at the corners than along the sides. The top corners are
   nowhere near a container corner, so they take the 40 minimum — the
   design's radius, and concentric with the 24pt keys 12pt (+4) inside.
   */
  private var shape: ConcentricRectangle { .dock }

  private var draftSize: CGFloat {
    Draft.fontSize(forLength: Draft.length(draft, nameFor: nameFor))
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        if showsGrabber { grabber } else { Color.clear.frame(height: Space.s2) }
        entryRow
        if noteOpen && !suggestions.isEmpty { suggestionRow }
      }
      // The grabber and the entry row are the handle: a vertical drag from
      // either stows or raises the keys, the way the seam did.
      .contentShape(.rect)
      .gesture(stowDrag, isEnabled: showsGrabber)
      // Above the draft, so the chips' enlarged 44pt targets win the few points
      // where they overlap it.
      .zIndex(1)

      draftLine
      keys
    }
    // The design's 6 / 12 / 12, with the top on the grid; the grabber's own
    // zone makes up the rest.
    .padding(.top, Space.s1)
    .padding(.horizontal, Space.s3)
    .padding(.bottom, Space.s3)
    .background {
      shape.fill(t.dock).shadow(t.dockShadow)
    }
    .overlay {
      // The design's `0 0 0 2px cta` ring. A centred stroke rather than an
      // outset one — half of it lands on the dock's edge, which at 2pt reads
      // the same and keeps the ring inside the dock's frame.
      if editing { shape.stroke(t.cta, lineWidth: 2) }
    }
    .animation(.easeOut(duration: 0.2), value: editing)
    .animation(.easeOut(duration: 0.15), value: trailing)
    .animation(.easeOut(duration: 0.15), value: noteOpen)
    // The row's chips, the note field and the result grow with the user's text
    // size, within reason; the dock has to leave the list some room.
    .dynamicTypeSize(...TypeCap.chrome)
  }

  // MARK: - Pieces

  private var grabber: some View {
    Button(action: onToggleStow) {
      Capsule()
        .fill(t.dockLine)
        .frame(width: 36, height: Space.s1)
        // The design's grab zone: 2 above, 6 below, on the grid as 4 and 8.
        .padding(.top, Space.s1)
        .padding(.bottom, Space.s2)
        .frame(maxWidth: .infinity)
        .hitTarget()
    }
    .buttonStyle(.plain)
    .accessibilityLabel(padStowed ? "Show keypad" : "Hide keypad")
    .accessibilityHint("Hiding the keypad gives the list of amounts the rest of the screen")
  }

  private var entryRow: some View {
    HStack(spacing: Space.s2) {
      if noteOpen {
        noteField
      } else {
        noteChip
        Spacer(minLength: 0)
        if let trailing {
          Text(trailing)
            .tallyFont(TallyFont.displayMedium, TextScale.bodyLg)
            .foregroundStyle(t.dockInk2)
            .lineLimit(1)
            .transition(.opacity)
        }
        if editing {
          Button("Cancel", action: onCancelEdit)
            .tallyFont(TallyFont.textSemi, TextScale.bodyMd)
            .foregroundStyle(t.dockInk)
            .padding(.horizontal, Space.s1)
            .hitTarget()
            .buttonStyle(.plain)
        }
      }
    }
    .frame(minHeight: Space.s8)
    .padding(.horizontal, Space.s1)
  }

  /// The design's outline note chip: a pencil and the note, or a prompt for
  /// one, on no fill inside a hairline.
  private var noteChip: some View {
    Button {
      noteOpen = true
    } label: {
      HStack(spacing: Space.s1) {
        Image(systemName: "pencil")
          .font(.system(size: 12, weight: .semibold))
        Text(note.isEmpty ? "Add note" : note)
          .tallyFont(TallyFont.textMedium, TextScale.bodyMd)
          .lineLimit(1)
      }
      .foregroundStyle(note.isEmpty ? t.dockInk2 : t.dockInk)
      .frame(maxWidth: 168, alignment: .leading)
      .padding(.horizontal, Space.s3)
      .frame(height: Space.s8)
      .overlay { Capsule().strokeBorder(t.dockLine, lineWidth: 1) }
      .fixedSize()
      .hitTarget()
    }
    .buttonStyle(.plain)
    .accessibilityLabel(note.isEmpty ? "Add note" : "Note, \(note)")
  }

  private var noteField: some View {
    HStack(spacing: Space.s2) {
      TextField("Add a note", text: $note)
        .tallyFont(TallyFont.textMedium, TextScale.bodyLg)
        .foregroundStyle(t.dockInk)
        .focused($noteFocused)
        .submitLabel(.done)
        .onSubmit { noteOpen = false }
        .task { noteFocused = true }
      if !note.isEmpty {
        Button {
          note = ""
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(t.dock)
            .frame(width: Space.s5, height: Space.s5)
            .background(t.dockInk2, in: .circle)
            .hitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear note")
      }
    }
  }

  /// Up to three recent notes, as tonal chips. Picking one fills the note and
  /// closes the field, as the design's does — a suggestion is a whole answer.
  private var suggestionRow: some View {
    ScrollView(.horizontal) {
      HStack(spacing: Space.s2) {
        ForEach(suggestions, id: \.self) { name in
          Button {
            note = name
            noteOpen = false
          } label: {
            Text(name)
              .tallyFont(TallyFont.textMedium, TextScale.bodyMd)
              .foregroundStyle(t.opInk)
              .lineLimit(1)
              .padding(.horizontal, Space.s3)
              .frame(height: Space.s8)
              .background(t.op, in: .capsule)
          }
          .buttonStyle(.plain)
          .accessibilityHint("Use this note")
        }
      }
      .padding(.horizontal, Space.s1)
    }
    .scrollIndicators(.hidden)
    .padding(.top, Space.s2)
    .transition(.opacity)
  }

  private var draftLine: some View {
    DraftLine(
      draft: draft, caret: !noteOpen, typeSize: draftSize, shakes: shakes, onTap: onTapDraft,
      onSwipeDelete: onSwipeDelete
    ) {
      if !Calc.refs(in: draft).isEmpty {
        ExprView(
          expr: draft, nameFor: nameFor, valueFor: resolve, variant: .draft, fontSize: draftSize)
      } else {
        Text(draft.isEmpty ? "0" : draft)
          .tallyFont(TallyFont.display, draftSize)
          // The design's −0.03em.
          .tracking(-0.03 * draftSize)
          .foregroundStyle(draft.isEmpty ? t.dockInk2 : t.dockInk)
          .lineLimit(1)
      }
    }
    .animation(.easeOut(duration: 0.16), value: draftSize)
    // Tighter than the rest of the dock: the line box is fixed, and it is the
    // digits being typed that would clip.
    .dynamicTypeSize(...TypeCap.draft)
    // Read as what it is, with the line spoken the way the row will be.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Current entry")
    .accessibilityValue(draft.isEmpty ? "empty" : Calc.text(draft, nameFor: nameFor))
    .accessibilityAction(named: "Delete last character", onSwipeDelete)
  }
}

extension ConcentricRectangle {
  /// The dock's outline (see `InputDock.shape`), shared with select mode's
  /// footer, which stands in the dock's place and so takes its shape.
  static var dock: ConcentricRectangle {
    ConcentricRectangle(corners: .concentric(minimum: .fixed(Space.s10)))
  }
}

extension View {
  /**
   Grow the tappable area to the 44pt HIG minimum without growing what is drawn.

   The dock's chips are drawn at 32pt tall on purpose — they are labels in the
   dock, not buttons in a toolbar — but a 32pt target is a miss waiting to
   happen. The padding extends the hit shape; the negative padding takes the
   layout back, so nothing around the chip moves. (6 a side takes 32 to 44.)
   */
  func hitTarget() -> some View {
    padding(.vertical, 6)
      .padding(.horizontal, Space.s1)
      .contentShape(.rect)
      .padding(.vertical, -6)
      .padding(.horizontal, -Space.s1)
  }
}
