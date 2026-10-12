// CalculatorScreen+Draft.swift — what the keys do to the line being typed:
// pressing, committing, clearing, editing an existing line, deleting one, and
// the reference tokens a draft can carry.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Keys

  /**
   Whether the reference key has anything to offer: a line the draft may see.
   A line may only reference lines above it (all of them for a new line, the
   ones above the edit point when editing), which is also what makes reference
   cycles impossible; a line in error resolves to nothing, so it doesn't count.
   Picking one drops a *reference token* into the draft — a live link drawn as
   a pill, so the row recomputes whenever the referenced line changes.
   */
  var canReference: Bool {
    let editIndex = editingID.flatMap { id in store.entries.firstIndex { $0.id == id } }
    let visible = editIndex.map { Array(store.entries.prefix($0)) } ?? store.entries
    return visible.contains { $0.error != true }
  }

  func press(_ key: Key) {
    // Only the reference key keeps the mode; typing anything else means the
    // user has moved on without picking.
    if key != .ref { setReferencing(false) }
    switch key {
    case .clear: clearDraft()
    case .ref: if canReference || referencing { setReferencing(!referencing) }
    case .enter: commit()
    default:
      if let next = Draft.apply(key, to: draft) { draft = next }
    }
  }

  private func commit() {
    guard !draft.isEmpty, let value = Calc.evaluate(draft, resolve: resolveRef) else {
      Haptic.error.play()
      shakes += 1  // the draft shakes its head
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
  }

  func clearDraft() {
    draft = ""
    note = ""
    noteOpen = false
    editingID = nil
    setReferencing(false)
  }

  func setReferencing(_ on: Bool) {
    guard on != referencing else { return }
    withAnimation(.easeOut(duration: 0.15)) { referencing = on }
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

  func delete(_ entry: Entry) {
    Haptic.impact.play()
    guard let receipt = store.delete(id: entry.id) else { return }
    if editingID == entry.id { clearDraft() }
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
    withAnimation(.snappy(duration: 0.24)) { undo = receipt }
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

  /// No haptic: the pill landing in the draft is the feedback. Ends reference
  /// mode — one pick per press of the key, as the design has it.
  func insertRef(_ id: String, note sourceNote: String?) {
    setReferencing(false)
    draft = Draft.insertRef(id, into: draft)
    // An unnamed draft borrows the source's note.
    if let sourceNote, !sourceNote.isEmpty, note.isEmpty { note = sourceNote }
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

  /// Display name for a reference id — a note, "Line 4", or the subtotal. An
  /// unnamed line is called what its row calls it (EntryRow's `title`): its
  /// sticky number, which is also what the stored reference is pinned to.
  func nameFor(_ id: String) -> String {
    if id == "sum" { return "Total" }
    guard let src = store.entries.first(where: { $0.id == id }) else { return "#?" }
    if src.note.isEmpty { return "Line \(src.num.map(String.init) ?? "?")" }
    return src.note.count > 16 ? String(src.note.prefix(15)) + "…" : src.note
  }
}
