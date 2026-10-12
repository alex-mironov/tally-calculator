// TotalBar.swift — the tab's running total, which doubles as a selection's
// subtotal in select mode and as something to pick in reference mode.
//
// The view takes everything it shows as plain inputs; `CalculatorScreen.totalBar`
// below works those out from the screen's state.
import SwiftUI
import TallyKit

struct TotalBar: View {
  enum Mode: Equatable {
    case total
    /// Reference mode: the bar is one of the things to pick.
    case referencing
    /// Select mode: the bar reads out what is ticked.
    case selecting(anyPicked: Bool)
  }

  let mode: Mode
  let label: String
  let value: Double
  /// The label has just turned to "Copied".
  let copied: Bool
  /// Copies the figure — or, in reference mode, references the total.
  let onTap: () -> Void

  @Environment(\.theme) private var t

  private var referencing: Bool { mode == .referencing }

  private var valueInk: Color {
    switch mode {
    case .total: t.ink
    case .referencing: t.accentInk
    case .selecting(let anyPicked): anyPicked ? t.accentInk : t.ink3
    }
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
      Text(label)
        .tallyFont(referencing ? TallyFont.textSemi : TallyFont.textMedium, TextScale.bodySm)
        .foregroundStyle(copied || referencing ? t.accentInk : t.ink2)
        .lineLimit(1)
        .contentTransition(.opacity)
      Spacer()
      HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
        if referencing {
          Image(systemName: "link")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(t.accentInk)
            .transition(.opacity)
        }
        // The total lands on its new value outright — no count-up tween, no
        // scale pulse: it is a number you read, not an event.
        Text(Calc.fmt(value))
          .tallyFont(TallyFont.displayMedium, TextScale.numLg)
          .monospacedDigit()
          .tracking(-0.2)
          .foregroundStyle(valueInk)
      }
    }
    .padding(.top, Space.s2)
    .padding(.horizontal, Space.s5)
    .padding(.bottom, Space.s2)
    .overlay(alignment: .top) {
      Rectangle().fill(t.line).frame(height: 1 / 3).padding(.horizontal, Space.s5)
    }
    .contentShape(.rect)
    // Tap the running total — or a selection's subtotal — to copy the plain
    // number, so it pastes cleanly into spreadsheets and other apps. The label
    // turning to "Copied" is the confirmation.
    // In reference mode the same tap references the total instead.
    .onTapGesture(perform: onTap)
    .animation(.easeOut(duration: 0.2), value: copied)
    .animation(.easeOut(duration: 0.15), value: referencing)
    // The total is one line that has to stay one line between the list and the
    // entry card; it grows with the user's text size to the same cap as the card.
    .dynamicTypeSize(...TypeCap.chrome)
    // "Total, 199.20" as one stop, with the copy gesture offered as an action
    // rather than left to a long press VoiceOver users would never find.
    .accessibilityElement(children: .combine)
    .accessibilityAction(named: referencing ? "Add to entry" : "Copy", onTap)
  }
}

extension CalculatorScreen {
  var totalBar: some View {
    // While referencing, the figure is what a `sum` pill would be worth —
    // only the lines above the edit point when editing.
    let value = selectMode ? subtotal : referencing ? (resolveRef("sum") ?? 0) : store.total
    return TotalBar(
      mode: selectMode
        ? .selecting(anyPicked: !picked.isEmpty) : referencing ? .referencing : .total,
      label: totalLabel,
      value: value,
      copied: copied,
      onTap: { referencing ? insertRef("sum", note: nil) : copyTotal(value) }
    )
  }

  private var totalLabel: String {
    if copied { return "Copied" }
    if referencing { return "Tap a line to insert" }
    guard selectMode else { return "Total" }
    return picked.isEmpty
      ? "Tap lines to add them up"
      : "\(picked.count) of \(store.entries.count) selected"
  }

  func copyTotal(_ value: Double) {
    UIPasteboard.general.string = String(format: "%.2f", value)
    Haptic.select.play()
    copied = true
    Task {
      try? await Task.sleep(for: .milliseconds(1200))
      copied = false
    }
  }
}
