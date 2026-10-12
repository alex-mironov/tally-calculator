// HeroTotal.swift — the one dominant number: the tab's running total, at the
// head of the screen (tally-app-v2.jsx, `hero`). It doubles as something to
// pick in reference mode. Select mode leaves it alone, as the design does: the
// subtotal is the footer's, and the whole stays up here beside it.
//
// The view takes everything it shows as plain inputs; `CalculatorScreen.heroTotal`
// below works those out from the screen's state, so a layout — the phone column
// today, the iPad's main column later — only has to decide where it goes.
import SwiftUI
import TallyKit

struct HeroTotal: View {
  enum Mode: Equatable {
    case total
    /// Reference mode: the total is one of the things to pick.
    case referencing
  }

  let mode: Mode
  let label: String
  let value: Double
  /// The last line's value, for the sub-line's "+42.80 last". Nil hides the
  /// sub-line's contents (an empty tab) but keeps its height,
  /// so the number does not jump when the first line lands.
  let last: Double?
  let lineCount: Int
  /// Copies the figure — or, in reference mode, references the total.
  let onTap: () -> Void
  /// How far in from the column's edges. The design's 6 / 24 / 16 (the top
  /// onto the grid as 8) on a phone and in the iPad's landscape column; the
  /// portrait iPad sits it further in.
  var inset = Self.standardInset

  static let standardInset = EdgeInsets(
    top: Space.s2, leading: Space.s6, bottom: Space.s4, trailing: Space.s6)

  @Environment(\.theme) private var t

  private var referencing: Bool { mode == .referencing }

  /// The 36pt circle beside the label, and the 24pt one on the sub-line.
  /// Scaled, so they keep pace with the text beside them.
  @ScaledMetric(relativeTo: .subheadline) private var actionSize: CGFloat = 36
  @ScaledMetric(relativeTo: .subheadline) private var trendSize: CGFloat = 24

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
        Image(systemName: referencing ? "link" : "doc.on.doc")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(referencing ? t.ctaInk : t.pillInk)
          .frame(width: actionSize, height: actionSize)
          .background(referencing ? t.cta : t.pill, in: .circle)
          .contentTransition(.symbolEffect(.replace))
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

      HStack(spacing: Space.s2) {
        if let last {
          Image(systemName: last < 0 ? "arrow.down" : "arrow.up")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(t.pillInk)
            .frame(width: trendSize, height: trendSize)
            .background(t.pill, in: .circle)
          Text((last < 0 ? "−" : "+") + Calc.fmt(abs(last)))
            .tallyFont(TallyFont.monoMedium, 15)
            .foregroundStyle(t.ink)
          Group {
            Text("last")
            Text("·").opacity(0.6)
            Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
          }
          .tallyFont(TallyFont.mono, 15)
          .foregroundStyle(t.ink2)
        }
      }
      .lineLimit(1)
      .frame(minHeight: trendSize)
      .padding(.top, Space.s3)
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
    // toast is the confirmation. In reference mode the same tap links the total.
    .onTapGesture(perform: onTap)
    .animation(.easeOut(duration: 0.15), value: referencing)
    // A 60pt figure has nowhere left to grow on a phone; the label and sub-line
    // grow with the user's text size to the same cap as the rest of the chrome.
    .dynamicTypeSize(...TypeCap.chrome)
    // "Total, 199.20" as one stop, with the copy gesture offered as an action
    // rather than left to a tap VoiceOver users would not know about.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label), \(formatted)")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(named: referencing ? "Link the total" : "Copy", onTap)
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

extension CalculatorScreen {
  /// Whether the hero is on screen. It can be switched off in Settings, but
  /// reference mode needs it regardless: the total is a thing to pick there.
  /// Select mode doesn't — its subtotal is the footer's.
  var showsHero: Bool { store.showTotal || referencing }

  var heroTotal: some View { heroTotal(inset: HeroTotal.standardInset) }

  func heroTotal(inset: EdgeInsets) -> some View {
    // While referencing, the figure is what a `sum` pill would be worth —
    // only the lines above the edit point when editing.
    let value = referencing ? (resolveRef("sum") ?? 0) : store.total
    return HeroTotal(
      mode: referencing ? .referencing : .total,
      label: referencing ? "Tap the total or a line to link it" : "Total",
      value: value,
      last: store.entries.last?.value,
      lineCount: store.entries.count,
      onTap: { referencing ? insertRef("sum", note: nil) : copyTotal(value) },
      inset: inset
    )
  }

  /**
   The toast, positioned by the layout just above the dock: "Total copied", or
   "Line deleted · Undo" while a delete can still be taken back. One at a time,
   copying winning for its 1.6s, as the design has it — the undo's clock keeps
   running underneath.
   */
  @ViewBuilder
  var copiedToast: some View {
    Group {
      if copied {
        CopiedToast()
      } else if undo != nil, !selectMode {
        UndoToast(onUndo: undoDelete)
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
