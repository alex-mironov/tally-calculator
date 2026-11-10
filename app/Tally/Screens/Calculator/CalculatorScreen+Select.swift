// CalculatorScreen+Select.swift — select mode, a read-only lens over the tab,
// and the footer that reads out what is ticked.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Multi-select
  //
  // "What do these three come to?" — a question the running total can't answer.
  // It used to open a sheet over the tab, which meant re-reading the same list
  // in a second copy of itself. Now the tab *becomes* the answer: the bar turns
  // into Select all / "N selected" / ✓, every row's circle becomes a tick, and
  // the dock gives its place to a footer with the subtotal (tally-app-v2.jsx,
  // `selFoot`). The hero keeps the tab's own total above, as the design's does,
  // so the part and the whole are on screen together. Nothing is re-laid-out,
  // so the lines being picked stay exactly where they already were.

  var subtotal: Double {
    store.entries.reduce(0) { $0 + (picked.contains($1.id) ? $1.value : 0) }
  }

  var allPicked: Bool {
    !store.entries.isEmpty && picked.count == store.entries.count
  }

  func startSelect(seed: Entry? = nil) {
    Haptic.select.play()
    // The draft itself is left alone — it is still there when Done gives the
    // dock back — but a live note field would keep the keyboard up over a
    // screen that no longer has anywhere to type.
    noteOpen = false
    setReferencing(false)
    picked = seed.map { [$0.id] } ?? []
    // One clock for the whole swap: the dock leaving, the footer arriving and
    // the list taking the room between them (Motion.swift, "one event, one
    // clock"). The keys are stowed in the same breath, so that Done brings
    // back a dock with its keys up. No tick for that: the one above covers it.
    withAnimation(Motion.surface) {
      selectMode = true
      stow = 1
    }
  }

  func endSelect() {
    // No haptic: Done is a button, and the keypad coming back is the feedback.
    withAnimation(Motion.surface) {
      selectMode = false
      stow = 0
    }
    picked = []
  }

  func togglePick(_ entry: Entry) {
    Haptic.select.play()
    withAnimation(Motion.flip) {
      if picked.contains(entry.id) { picked.remove(entry.id) } else { picked.insert(entry.id) }
    }
  }
}

/// Select mode's stand-in for the dock: the same surface, carrying "2 of 6"
/// and what the ticked lines come to.
struct SelectFooter: View {
  let picked: Int
  let of: Int
  let subtotal: Double

  @Environment(\.theme) private var t

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
      Text("\(picked) of \(of)")
        .tallyFont(TallyFont.text, 15)
        .foregroundStyle(t.dockInk2)
        .contentTransition(.numericText(value: Double(picked)))
      Spacer(minLength: 0)
      // Rolls like the hero does, for the same reason: the digit turning over
      // is how you see what the line just ticked was worth.
      Text(Calc.fmt(subtotal))
        .tallyFont(TallyFont.displayMedium, 36, relativeTo: .largeTitle)
        // The design's −0.03em.
        .tracking(-0.03 * 36)
        .foregroundStyle(picked == 0 ? t.dockInk2 : t.dockInk)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .contentTransition(.numericText(value: subtotal))
    }
    .animation(Motion.roll, value: subtotal)
    .animation(Motion.roll, value: picked)
    // The design's 20 / 24.
    .padding(.vertical, Space.s5)
    .padding(.horizontal, Space.s6)
    .frame(maxWidth: .infinity)
    .background { ConcentricRectangle.dock.fill(t.dock).shadow(t.dockShadow) }
    .dynamicTypeSize(...TypeCap.chrome)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(picked) of \(of) lines selected")
    .accessibilityValue(Calc.fmt(subtotal))
  }
}
