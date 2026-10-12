// CalculatorScreen+Keyboard.swift — a hardware keyboard driving the pad. The
// focus that makes `.onKeyPress` reachable at all is taken in CalculatorScreen's
// body; this maps the keys.
import SwiftUI
import TallyKit

extension CalculatorScreen {
  // MARK: - Hardware keyboard

  /**
   Map a physical key onto a pad key.

   Ignored entirely while the note field is up: those keystrokes belong to the
   field being typed into, not to the pad behind it.
   */
  func handleKeyPress(_ event: KeyPress) -> KeyPress.Result {
    guard !noteOpen else { return .ignored }
    // Escape backs out of reference mode before it clears anything.
    if referencing && event.key == .escape {
      setReferencing(false)
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
        case "\r", "\n": .enter
        case "+": .plus
        case "-", "−": .minus
        case "*", "x", "×": .multiply
        case "/", "÷": .divide
        // A comma is the decimal separator on a great many keyboards, and
        // nothing else on this pad wants it.
        case ".", ",": .dot
        case "%": .percent
        case "c", "C": .clear
        default: Key(rawValue: event.characters)  // the digits
        }
      }

    guard let key else { return .ignored }
    press(key)
    return .handled
  }
}
