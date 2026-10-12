// CalculatorScreen+Keyboard.swift — a hardware keyboard driving the pad. The
// focus that makes `.onKeyPress` reachable at all is taken in CalculatorScreen's
// body; this maps the keys.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Hardware keyboard

  /**
   Map a physical key onto a pad key — or, for a letter, onto the note.

   Ignored entirely while the note field is up: those keystrokes belong to the
   field being typed into, not to the pad behind it. And left alone with ⌘, ⌃
   or ⌥ held: those are shortcuts (⌘Z is the undo toast's), not keys of the pad.
   */
  func handleKeyPress(_ event: KeyPress) -> KeyPress.Result {
    guard !noteOpen else { return .ignored }
    guard event.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
    // Select mode has nothing to type into; Escape is its Done.
    if selectMode {
      guard event.key == .escape else { return .ignored }
      endSelect()
      return .handled
    }
    // Escape backs out of reference mode before it clears anything.
    if referencing && event.key == .escape {
      setReferencing(false)
      return .handled
    }
    // A letter starts the note — or carries on the one already there — with
    // that letter in it, the field taking the keys from the next one on. Which
    // is why no letter is a pad key: "x" for × and "c" for clear made a note
    // starting "Coffee" untypeable.
    if event.characters.count == 1, let ch = event.characters.first, ch.isLetter {
      setReferencing(false)
      note += event.characters
      noteOpen = true
      return .handled
    }

    let key: Key? =
      switch event.key {
      case .return: .enter
      case .delete: .backspace
      case .escape: .clear
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
        default: Key(rawValue: event.characters)  // the digits
        }
      }

    guard let key else { return .ignored }
    press(key)
    return .handled
  }
}
