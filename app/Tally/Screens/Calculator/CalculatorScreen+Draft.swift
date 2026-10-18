// CalculatorScreen+Draft.swift — what the keys do to the line being typed:
// pressing, committing, clearing, editing an existing line, deleting one, and
// the links a draft can carry.
//
// ── Links ───────────────────────────────────────────────────────────────────
// A line can link lines above it (Calculator v2, tally-links.jsx): the link is
// a `{e123}` token in its expression, so it stays live — change the linked
// line and every line built on it recomputes. Link mode, from the keypad's
// link key, makes the rows the picker: a tap links a line, a second tap
// unlinks it, and the mode stays on so a sum of several lines is one trip.
// The keypad folds to the operators that join them meanwhile.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Keys

  /**
   Whether the link key has anything to offer: a line the draft may link. A
   line may only link lines above it (all of them for a new line, the ones
   above the edit point when editing), which is also what makes cycles
   impossible; a line in error resolves to nothing, so it doesn't count.
   */
  var canReference: Bool {
    let editIndex = editingID.flatMap { id in store.entries.firstIndex { $0.id == id } }
    let visible = editIndex.map { Array(store.entries.prefix($0)) } ?? store.entries
    return visible.contains { $0.error != true }
  }

  /// Every pad key, from the keypad, a hardware keyboard or the draft's swipe.
  /// A keystroke, so whatever it changes lands in the frame (Motion.swift).
  func press(_ key: Key) {
    withTransaction(\.typing, true) {
      // Link mode's bar is the operators that join links, ↵, and "123" (the
      // link key's place) back to the numbers. Anything else — a digit from a
      // hardware keyboard — means the user has moved on to typing.
      if referencing && !key.isOperator && key != .enter {
        setReferencing(false)
        if key == .ref { return }  // "123" is only the way out
      }
      switch key {
      case .clear: clearDraft()
      case .ref: if canReference && !referencing { setReferencing(true) }
      case .enter: commit()
      default:
        // A key the draft ignores (a second '.', '%' after an operator) writes
        // nothing, so it invalidates nothing.
        if let next = Draft.apply(key, to: draft), next != draft { draft = next }
      }
    }
  }

  private func commit() {
    // Filed tidy: no trailing operator, and any bracket still open closed —
    // what the result beside the draft was already showing.
    let draft = Draft.normalized(self.draft)
    guard !draft.isEmpty, let value = Calc.evaluate(draft, resolve: resolveRef) else {
      Haptic.error.play()
      // The draft shakes its head: the one motion a key may start in the
      // dock, so it steps out of the keystroke's transaction to keep it.
      withTransaction(\.typing, false) { shakes += 1 }
      return
    }

    // An edit keeps the line's sticky number and its counted state — only new
    // lines get a fresh number, and every new line counts.
    let existing = editingID.flatMap { id in store.entries.first { $0.id == id } }
    let entry = Entry(
      id: editingID ?? store.mintID(),
      note: note.trimmingCharacters(in: .whitespacesAndNewlines),
      // References must survive in `expr` even without an operator — a bare
      // ⟨Rent⟩ line is a live mirror, not a copy.
      expr: (Calc.hasOperator(draft) || !Calc.refs(in: draft).isEmpty) ? draft : "",
      value: value,
      num: existing?.num,
      excluded: existing?.excluded
    )

    // Which other lines this moves: the ones built on an edited line.
    let before = Dictionary(store.entries.map { ($0.id, $0.value) }, uniquingKeysWith: { a, _ in a })
    if editingID != nil {
      store.replace(entry)
    } else {
      store.append(entry)
      // Edits happen on a row already on screen (the user just tapped it) —
      // only a brand-new entry needs the scroll and the flash.
      justAddedID = entry.id
      Task {
        try? await Task.sleep(for: .milliseconds(1400))
        if justAddedID == entry.id { justAddedID = nil }
      }
    }
    Haptic.success.play()
    clearDraft()
    announceRipple(from: before, except: entry.id)
  }

  /**
   "Updated ⑤ Taxi tip" — or "Updated 3 linked lines" — when a commit moved
   lines built on the one just changed (tally-app-v2.jsx, `commit`'s `say`).
   The rows flash themselves (EntryRow's value pulse); this says why.
   */
  private func announceRipple(from before: [String: Double], except id: String) {
    let moved = store.entries.enumerated().filter { _, e in
      guard e.id != id, let was = before[e.id] else { return false }
      return abs(e.value - was) > 1e-9
    }
    guard let first = moved.first else { return }
    let next =
      moved.count == 1
      ? Notice(kind: .one(position: first.offset + 1, note: first.element.note))
      : Notice(kind: .many(moved.count))
    withAnimation(Motion.toastIn) { notice = next }
    Task {
      try? await Task.sleep(for: .milliseconds(1500))
      if notice == next { withAnimation(.easeOut(duration: 0.2)) { notice = nil } }
    }
  }

  func clearDraft() {
    draft = ""
    note = ""
    noteOpen = false
    editingID = nil
    setReferencing(false)
  }

  /**
   Link mode on or off — and the two are not mirror images.

   Into it is a mode change, started by the link key or '#': the pad folds to
   the link bar and the dock's top edge glides down with it, on one clock
   (`Motion.surface`). The next thing done there is tapping a line, not a key.

   Out of it is always a way back to typing — "123", Esc, a digit, ↵ — so the
   full pad is back in the very next frame, with every key where the finger
   expects it. It used to unfold on three clocks: 0.15s here, the keypad's own
   0.26s, and the pad's measured height a layout pass after both, so the digit
   rows were still travelling up to ~224pt as the next one was tapped (and
   hit-testing already used where they would end up).
   */
  func setReferencing(_ on: Bool) {
    guard on != referencing else { return }
    if on {
      // A key starts it, so it steps out of the keystroke's transaction.
      // Under Reduce Motion the dock doesn't glide; the bar is simply there.
      let fold = UIAccessibility.isReduceMotionEnabled ? nil : Motion.surface
      withTransaction(\.typing, false) {
        withAnimation(fold) { referencing = true }
      }
    } else {
      referencing = false
    }
  }

  /// No haptic from either entry point (the row's tap, the context menu's
  /// Edit): the row lighting up and the draft filling in are the feedback.
  func edit(_ entry: Entry) {
    draft = entry.expr.isEmpty ? Calc.plain(entry.value) : entry.expr
    note = entry.note
    editingID = entry.id
    noteOpen = false
    showPad(silent: true)  // the keypad returning is part of the same tap
  }

  /// Delete a line — after a word of warning if other lines link it, since
  /// they will be left holding its value as a fixed number.
  func delete(_ entry: Entry) {
    if store.dependents(of: entry.id).isEmpty {
      deleteNow(entry)
    } else {
      confirmDelete = entry
    }
  }

  func deleteNow(_ entry: Entry) {
    confirmDelete = nil
    Haptic.impact.play()
    guard let receipt = store.delete(id: entry.id) else { return }
    if editingID == entry.id {
      clearDraft()
    } else if draft.contains("{\(entry.id)}") {
      // A draft linking the line keeps its value, as the lines did.
      draft = draft.replacingOccurrences(of: "{\(entry.id)}", with: Calc.plain(entry.value))
    }
    offerUndo(receipt)
  }

  // MARK: - Undo
  //
  // A delete is one swipe, and the swipe is easy to make by accident — so for
  // 4.5s a "Line deleted · Undo" toast sits above the dock, and ⌘Z does the
  // same from a keyboard. Only the latest delete is offered: a second delete
  // replaces the first's toast, as the design's does. The store's receipt is
  // what makes the undo whole — the line back in its place, and the lines that
  // referenced it live again rather than left holding a frozen number.

  private func offerUndo(_ receipt: TallyStore.DeletedLine) {
    withAnimation(Motion.toastIn) { undo = receipt }
    Task {
      try? await Task.sleep(for: .milliseconds(4500))
      // Only if it is still this delete's toast; a newer one keeps its own clock.
      if undo == receipt { withAnimation(.easeOut(duration: 0.2)) { undo = nil } }
    }
  }

  func undoDelete() {
    guard let receipt = undo else { return }
    Haptic.tap.play()
    store.restore(receipt)
    withAnimation(.easeOut(duration: 0.2)) { undo = nil }
  }

  /// Link mode's tap on a row: link it, or unlink it if the draft already
  /// does. The mode stays on, so several lines can be linked in one go.
  func toggleLink(_ id: String) {
    Haptic.select.play()
    draft = Draft.toggleRef(id, in: draft)
  }

  /// The row menu's "Link in new line": a fresh line that starts as this one.
  func linkInNewLine(_ entry: Entry) {
    clearDraft()
    draft = "{\(entry.id)}"
    showPad(silent: true)
  }

  // MARK: - References

  /**
   Resolver for the draft's reference tokens.

   Entry ids look up the current value; `sum` is the running total of the
   counted lines the draft can see — all of them for a new line, only the ones
   above when editing, which matches the forward-pass evaluation order in the
   store. A line in error resolves to nothing, so the draft cannot be committed
   on top of it.
   */
  func resolveRef(_ id: String) -> Double? {
    if id == "sum" {
      let upto = editingID.flatMap { eid in store.entries.firstIndex { $0.id == eid } }
      return totalOf(upto.map { Array(store.entries.prefix($0)) } ?? store.entries)
    }
    guard let src = store.entries.first(where: { $0.id == id }), src.error != true else {
      return nil
    }
    return src.value
  }

  /// A draft pill's label: the line's note, or what its row calls an unnamed
  /// line ("Line 4", by position). `{sum}` — the running total, which older
  /// builds could link — is "Total".
  func nameFor(_ id: String) -> String {
    if id == "sum" { return "Total" }
    guard let index = store.entries.firstIndex(where: { $0.id == id }) else { return "Missing" }
    let note = store.entries[index].note
    return note.isEmpty ? "Line \(index + 1)" : note
  }

  /// Where a linked line stands, 1-based — the number its badge carries.
  func positionFor(_ id: String) -> Int? {
    store.entries.firstIndex { $0.id == id }.map { $0 + 1 }
  }
}
