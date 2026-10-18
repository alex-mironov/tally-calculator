// CalculatorScreen+Keyboard.swift — a hardware keyboard driving the pad. The
// keys arrive through the `KeyCatcher` behind CalculatorScreen's body; this
// says when it takes them, and maps them.
import SwiftUI
import TallyKit
import UIKit

extension CalculatorScreen {
  // MARK: - Hardware keyboard

  /**
   Whether the pad's `KeyCatcher` holds first responder: while this screen is
   showing and nothing over it has keys of its own. The note field and the
   rename sheet type into themselves; the other sheets and the alert get the
   keys out of the pad's way, so Return there isn't a commit behind them.
   */
  var takesKeys: Bool {
    shown && !noteOpen && !renameOpen && !tagsOpen && !settingsOpen
      && confirmDelete == nil && share == nil && !shareFailed
  }

  /**
   Map a physical key onto a pad key — or, for a letter, onto the note.

   Ignored entirely while the note field is up: those keystrokes belong to the
   field being typed into, not to the pad behind it. And left alone with ⌘, ⌃
   or ⌥ held: those are shortcuts (⌘Z is the undo toast's), not keys of the pad.
   */
  func handleKey(_ event: UIKey) -> Bool {
    guard !noteOpen else { return false }
    guard event.modifierFlags.isDisjoint(with: [.command, .control, .alternate]) else { return false }
    let escape = event.keyCode == .keyboardEscape
    // Select mode has nothing to type into; Escape is its Done.
    if selectMode {
      guard escape else { return false }
      endSelect()
      return true
    }
    // From here on it is typing, which lands in the frame (Motion.swift) —
    // a letter opening the note included, so the field is there at full
    // width for the letter that opened it.
    return withTransaction(\.typing, true) { type(event, escape: escape) }
  }

  private func type(_ event: UIKey, escape: Bool) -> Bool {
    // Escape backs out of link mode before it clears anything.
    if referencing && escape {
      setReferencing(false)
      return true
    }
    // A letter starts the note — or carries on the one already there — with
    // that letter in it, the field taking the keys from the next one on. Which
    // is why no letter is a pad key: "x" for × and "c" for clear made a note
    // starting "Coffee" untypeable.
    if event.characters.count == 1, let ch = event.characters.first, ch.isLetter {
      setReferencing(false)
      note += event.characters
      noteOpen = true
      return true
    }

    let key: Key? =
      switch event.keyCode {
      case .keyboardReturnOrEnter, .keypadEnter: .enter
      case .keyboardDeleteOrBackspace: .backspace
      case .keyboardEscape: .clear
      default:
        switch event.characters {
        // Deliberately *not* '='. It commits on a desk calculator, but on most
        // keyboards '+' is Shift-'=', so '=' meant a mistimed Shift filed the
        // line you were in the middle of — found by typing "12+3" and watching
        // "12" commit. Return (and the numeric pad's Enter) commits instead.
        // v2's prototype maps '=' to ↵ again; the keyboards haven't changed,
        // so neither has this.
        case "\r", "\n": .enter
        case "+": .plus
        case "-", "−": .minus
        case "*", "×": .multiply
        case "/", "÷": .divide
        // A comma is the decimal separator on a great many keyboards, and
        // nothing else on this pad wants it.
        case ".", ",": .dot
        case "%": .percent
        // Brackets type whether or not the pad shows its brackets key: the
        // setting is about the pad's room, and a keyboard has the keys anyway.
        case "(": .open
        case ")": .close
        // '#' for "line number": the link key, as the design maps it.
        case "#": .ref
        default: Key(rawValue: event.characters)  // the digits
        }
      }

    guard let key else { return false }
    press(key)
    return true
  }
}
