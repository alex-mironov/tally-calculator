// ConfirmDeleteSheet.swift — "Delete ④ Taxi?" when other lines link the line
// being deleted (tally-app-v2.jsx, `confirmId`).
//
// A plain delete is one swipe with an Undo toast behind it, and stays that
// way. A line other lines are built on is different: deleting it leaves each
// of them holding its value as a fixed number — still right today, but no
// longer live — and that is worth one sentence before it happens. The sheet
// says which lines, and what they will keep.
//
// The design draws it as a card at the foot of the phone and a small form
// sheet on the iPad; here it is a native sheet in both places, fitted to what
// it says.
import SwiftUI
import TallyKit

struct ConfirmDeleteSheet: View {
  let entry: Entry
  /// Where the line stands, for its badge.
  let position: Int
  /// The lines that link it, with where they stand.
  let dependents: [(position: Int, entry: Entry)]
  let onDelete: () -> Void

  @Environment(\.theme) private var t
  @Environment(\.dismiss) private var dismiss

  @State private var contentHeight: CGFloat = 0

  var body: some View {
    let s = t.sheet

    VStack(alignment: .leading, spacing: Space.s3) {
      (Text("Delete ") + badge(position, in: s) + Text(" \(entry.note.isEmpty ? "line" : entry.note)?"))
        .tallyFont(TallyFont.textSemi, 20)
        .foregroundStyle(s.ink)
        .fixedSize(horizontal: false, vertical: true)

      explanation(s)
        .tallyFont(TallyFont.text, 15)
        .foregroundStyle(s.ink2)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: Space.s2) {
        Button {
          onDelete()
          dismiss()
        } label: {
          Text("Delete line")
            .tallyFont(TallyFont.textSemi, 16)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(s.danger, in: .capsule)
        }
        Button {
          dismiss()
        } label: {
          Text("Cancel")
            .tallyFont(TallyFont.textSemi, 16)
            .foregroundStyle(s.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(s.field, in: .capsule)
        }
      }
      .buttonStyle(.plain)
      .padding(.top, Space.s2)
    }
    // The design's 24 / 20 / 16.
    .padding(.top, Space.s6)
    .padding(.horizontal, Space.s5)
    .padding(.bottom, Space.s4)
    .dynamicTypeSize(...TypeCap.chrome)
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
    .frame(maxHeight: .infinity, alignment: .top)
    .environment(\.theme, s)
    .modifier(Sizing(contentHeight: contentHeight))
    .presentationBackground(s.screen)
  }

  /// "It's linked in ⑤ Taxi tip, which will keep 1.82 as a fixed number."
  private func explanation(_ s: Theme) -> Text {
    guard dependents.count == 1, let only = dependents.first else {
      return Text(
        "It’s linked in \(dependents.count) lines. They’ll keep their current values as fixed numbers.")
    }
    let rest = Text(", which will keep \(Calc.fmt(only.entry.value)) as a fixed number.")
    // An unnamed line has only its number to go by, which the badge already
    // is — "linked in line ⑨", rather than the design's "⑨ another line".
    guard !only.entry.note.isEmpty else {
      return Text("It’s linked in line ") + badge(only.position, in: s) + rest
    }
    return Text("It’s linked in ") + badge(only.position, in: s) + Text(" \(only.entry.note)") + rest
  }

  /**
   A line's number inline in a sentence. The rows' `LineBadge` is a view and
   can't sit in a run of text, so up to 50 it is SF Symbols' own numbered
   circle in the deep tone — the same shape — and past that the words.
   */
  private func badge(_ n: Int, in s: Theme) -> Text {
    guard n <= 50 else { return Text("line \(n)") }
    return Text(Image(systemName: "\(n).circle.fill")).foregroundStyle(s.deep)
  }

  /// A detent the height of what the sheet says on a phone; a narrow form
  /// sheet, centred, on an iPad (the design's 420pt).
  private struct Sizing: ViewModifier {
    let contentHeight: CGFloat
    @Environment(\.layoutMode) private var layout

    func body(content: Content) -> some View {
      if layout.isPad {
        content
          .frame(width: 420, height: max(contentHeight, 1))
          .presentationSizing(.form.fitted(horizontal: true, vertical: true))
      } else {
        // Measured. iOS 26 floats a sheet this short clear of the home
        // indicator, so the content's own 16pt foot is the whole margin.
        content.presentationDetents([.height(max(contentHeight, 1))])
      }
    }
  }
}
