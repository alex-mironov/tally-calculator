// CalculatorScreen+Select.swift — select mode, a read-only lens over the tab.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Multi-select
  //
  // "What do these three come to?" — a question the running total can't answer.
  // It used to open a sheet over the tab, which meant re-reading the same list
  // in a second copy of itself. Now the tab *becomes* the answer: the keypad
  // stows, the entry card steps out of the way, every row grows a selection
  // circle and the total bar turns into a subtotal. Nothing is re-laid-out, so
  // the lines being picked stay exactly where they already were.

  var subtotal: Double {
    store.entries.reduce(0) { $0 + (picked.contains($1.id) ? $1.value : 0) }
  }

  var allPicked: Bool {
    !store.entries.isEmpty && picked.count == store.entries.count
  }

  func startSelect(seed: Entry? = nil) {
    Haptic.select.play()
    // The draft itself is left alone — it is still there when Done gives the
    // card back — but a live note field would keep the keyboard up over a
    // screen that no longer has anywhere to type.
    noteOpen = false
    setReferencing(false)
    picked = seed.map { [$0.id] } ?? []
    withAnimation(.easeOut(duration: 0.22)) { selectMode = true }
    setPad(1, silent: true)  // the tick above already covered this
  }

  func endSelect() {
    // No haptic: Done is a button, and the keypad coming back is the feedback.
    withAnimation(.easeOut(duration: 0.22)) { selectMode = false }
    picked = []
    setPad(0, silent: true)
  }

  func togglePick(_ entry: Entry) {
    Haptic.select.play()
    if picked.contains(entry.id) { picked.remove(entry.id) } else { picked.insert(entry.id) }
  }
}
