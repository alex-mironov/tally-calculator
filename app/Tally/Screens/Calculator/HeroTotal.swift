// HeroTotal.swift — the one dominant number: the tab's running total, at the
// head of the screen (tally-app-v2.jsx, `hero`): a label with the copy circle
// beside it, and the number. Nothing under it — the earlier v2 board's
// "+42.80 last · 4 lines" sub-line is gone from the design. In link mode its label
// becomes the instruction — the total itself is not a thing to link: a line
// links lines, and v2 dropped linking the running total. Select mode leaves it
// alone, as the design does: the subtotal is the footer's, and the whole stays
// up here beside it.
//
// The view takes everything it shows as plain inputs; `CalculatorScreen.heroTotal`
// below works those out from the screen's state, so a layout — the phone column
// today, the iPad's main column later — only has to decide where it goes.
import SwiftUI
import TallyKit

struct HeroTotal: View {
  enum Mode: Equatable {
    case total
    /// Link mode: the label says what to do, and a tap does nothing.
    case referencing
  }

  let mode: Mode
  let label: String
  let value: Double
  /// Copies the figure. Not while linking.
  let onTap: () -> Void
  /// How far in from the column's edges. The design's 6 / 24 / 16 (the top
  /// onto the grid as 8) on a phone and in the iPad's landscape column; the
  /// portrait iPad sits it further in.
  var inset = Self.standardInset

  static let standardInset = EdgeInsets(
    top: Space.s2, leading: Space.s6, bottom: Space.s4, trailing: Space.s6)

  @Environment(\.theme) private var t

  private var referencing: Bool { mode == .referencing }

  /// The 36pt circle beside the label. Scaled, so it keeps pace with the
  /// label beside it.
  @ScaledMetric(relativeTo: .subheadline) private var actionSize: CGFloat = 36

  private var formatted: String { Calc.fmt(value) }

  /**
   The figure steps down as it grows, so a long total stays on one line rather
   than shrinking continuously as each digit lands. The design's steps are
   60/52/44/38 by character count; 38 is rounded onto the grid as 40.
   */
  private var numberSize: CGFloat {
    switch formatted.count {
    case ...8: 60
    case ...10: 52
    case ...12: 44
    default: 40
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Space.s3) {
        Text(label)
          .tallyFont(TallyFont.textMedium, 15)
          .foregroundStyle(referencing ? t.ink : t.ink2)
          .lineLimit(1)
          .contentTransition(.opacity)
        Spacer(minLength: 0)
        Image(systemName: "doc.on.doc")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(t.pillInk)
          .frame(width: actionSize, height: actionSize)
          .background(t.pill, in: .circle)
      }

      // The total rolls: only the digits that changed turn over, up when it
      // grows and down when it shrinks. This reverses an earlier call — when the
      // total was a 22pt line wedged between the list and the entry card it
      // landed on its new value outright, because a tween there was motion in
      // the corner of the eye. v2 makes it the one dominant number on the
      // screen and rolls it on purpose (tally-motion.jsx, RollingNumber, which
      // is itself a stand-in for this transition): at 60pt, the digit turning
      // over is how you see which part of the sum a line moved.
      Text(formatted)
        .tallyFont(TallyFont.displayMedium, numberSize, relativeTo: .largeTitle)
        .tracking(-0.04 * numberSize)
        .foregroundStyle(t.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .contentTransition(.numericText(value: value))
        .padding(.top, Space.s1)
        .animation(.snappy(duration: 0.32), value: value)
        .animation(.easeOut(duration: 0.2), value: numberSize)
    }
    .padding(inset)
    .frame(maxWidth: .infinity, alignment: .leading)
    // The hero keeps its height whatever the keypad does — the list is what
    // gives way. Without this a raised keypad squeezed the column and the
    // figure's minimumScaleFactor shrank it to fit.
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(.rect)
    // Tap the total to copy the plain number, so
    // it pastes cleanly into spreadsheets and other apps; the "Total copied"
    // toast is the confirmation. Not while linking: the total is not a line.
    .onTapGesture { if !referencing { onTap() } }
    .animation(.easeOut(duration: 0.15), value: referencing)
    // A 60pt figure has nowhere left to grow on a phone; the label grows with the user's text size to the same cap as the rest of the chrome.
    .dynamicTypeSize(...TypeCap.chrome)
    // "Total, 199.20" as one stop, with the copy gesture offered as an action
    // rather than left to a tap VoiceOver users would not know about.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label), \(formatted)")
    .accessibilityAddTraits(referencing ? [] : .isButton)
    .accessibilityAction(named: "Copy") { if !referencing { onTap() } }
  }
}

/// "Total copied" — a capsule floating just above the dock. Floating chrome,
/// so it is system glass, the one place on this screen that is.
struct CopiedToast: View {
  @Environment(\.theme) private var t

  var body: some View {
    Label("Total copied", systemImage: "checkmark")
      .tallyFont(TallyFont.textMedium, 14)
      .foregroundStyle(t.ink)
      .padding(.vertical, Space.s2)
      .padding(.horizontal, Space.s4)
      .glassEffect(.regular, in: .capsule)
      .dynamicTypeSize(...TypeCap.chrome)
      .accessibilityAddTraits(.isStaticText)
  }
}

/// "Line deleted · Undo" — the same glass capsule, with the undo as a cta pill
/// inside it (tally-app-v2.jsx, the toast's `undo` arm). ⌘Z presses it.
struct UndoToast: View {
  var onUndo: () -> Void

  @Environment(\.theme) private var t

  var body: some View {
    HStack(spacing: Space.s3) {
      Text("Line deleted")
        .tallyFont(TallyFont.textMedium, 14)
        .foregroundStyle(t.ink)
      Button(action: onUndo) {
        Text("Undo")
          .tallyFont(TallyFont.textSemi, 14)
          .foregroundStyle(t.ctaInk)
          // The design's 6, off the grid: with the 14pt label it makes the
          // pill the copied toast's height, so the two toasts match.
          .padding(.vertical, 6)
          .padding(.horizontal, Space.s3)
          .background(t.cta, in: .capsule)
          .hitTarget()
      }
      .buttonStyle(.plain)
      .keyboardShortcut("z", modifiers: .command)
      .accessibilityHint("Puts the line back")
    }
    // The design's 5 / 5 / 5 / 14, on the grid: the pill's 4 all round, the
    // label's 16 on the leading side as the copied toast has.
    .padding(Space.s1)
    .padding(.leading, Space.s3)
    .glassEffect(.regular, in: .capsule)
    .dynamicTypeSize(...TypeCap.chrome)
  }
}

/// "Updated ⑤ Taxi tip" / "Updated 3 linked lines" — the same glass capsule.
struct NoticeToast: View {
  let notice: Notice

  @Environment(\.theme) private var t

  var body: some View {
    HStack(spacing: Space.s2) {
      switch notice.kind {
      case .one(let position, let note):
        Text("Updated")
        LineBadge(position: position, size: Space.s5)
        Text(note.isEmpty ? "linked line" : note).lineLimit(1)
      case .many(let n):
        Text("Updated \(n) linked lines")
      }
    }
    .tallyFont(TallyFont.textMedium, 14)
    .foregroundStyle(t.ink)
    .padding(.vertical, Space.s2)
    .padding(.horizontal, Space.s4)
    .glassEffect(.regular, in: .capsule)
    .dynamicTypeSize(...TypeCap.chrome)
    .accessibilityElement(children: .combine)
  }
}

extension CalculatorScreen {
  /// Whether the hero is on screen. It can be switched off in Settings, but
  /// link mode keeps it, for the instruction its label carries. Select mode
  /// doesn't — its subtotal is the footer's.
  var showsHero: Bool { store.showTotal || referencing }

  var heroTotal: some View { heroTotal(inset: HeroTotal.standardInset) }

  func heroTotal(inset: EdgeInsets) -> some View {
    HeroTotal(
      mode: referencing ? .referencing : .total,
      label: referencing ? "Tap lines to link them" : "Total",
      value: store.total,
      onTap: { copyTotal(store.total) },
      inset: inset
    )
  }

  /**
   The toast, positioned by the layout just above the dock: "Total copied",
   "Line deleted · Undo" while a delete can still be taken back, or "Updated…"
   after a commit moved linked lines. One at a time, in that order, as the
   design has it — the clocks underneath keep running.
   */
  @ViewBuilder
  var copiedToast: some View {
    Group {
      if copied {
        CopiedToast()
      } else if undo != nil, !selectMode {
        UndoToast(onUndo: undoDelete)
      } else if let notice, !selectMode {
        NoticeToast(notice: notice)
      }
    }
    .padding(.bottom, Space.s3)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  func copyTotal(_ value: Double) {
    UIPasteboard.general.string = String(format: "%.2f", value)
    Haptic.select.play()
    withAnimation(.snappy(duration: 0.24)) { copied = true }
    Task {
      try? await Task.sleep(for: .milliseconds(1600))
      withAnimation(.easeOut(duration: 0.2)) { copied = false }
    }
  }
}
