// KeyCatcher.swift — a hardware keyboard's way in to a screen with no text
// field: a UIKit first responder that takes key presses and never raises the
// software keyboard.
import SwiftUI
import UIKit

/**
 Holds first responder while `isActive`, and hands each key pressed on a
 hardware keyboard to `onKey` — which says whether it used it. A key it
 doesn't use goes on up the responder chain, so ⌘ shortcuts still find their
 `.keyboardShortcut`s.

 Why not SwiftUI's own `.focusable()` + `.onKeyPress`, which the calculator
 used first: focusing a view makes SwiftUI's *hosting view* the window's first
 responder, and a hosting view can't be told what to show as its keyboard.
 Alone that was harmless — the hosting view isn't a text input, so nothing came
 up for it. But a menu opened from the bar lends its type-to-select (letters
 jump to an item) to whatever is first responder: UIKit's
 `_UITypeSelectKeyInput`, which *is* a key input. On a phone with no hardware
 keyboard, a first responder taking key input is exactly what raises the
 software one — so opening the title menu put a full keyboard over the pad with
 nothing to type into. Seen in lldb: the first responder is the same hosting
 view before and during the menu; only its `_keyboardResponder` changes, to
 the type-select input.

 This view is the first responder instead, and it can say what its keyboard
 is: `inputView`, an empty view. When something does lend it key input, that
 nothing is what UIKit shows in the keyboard's place. A hardware keyboard is
 unaffected — it never shows an input view — and the menu's type-select keeps
 working on it.

 Holding first responder only while there are keys to take, too: a text field
 that takes it (the note, a sheet's) has it handed straight back by
 `isActive` turning true again, with no focus state in between to agree with.
 */
struct KeyCatcher: UIViewRepresentable {
  var isActive: Bool
  var onKey: (UIKey) -> Bool

  func makeUIView(context: Context) -> CatcherView { CatcherView() }

  func updateUIView(_ view: CatcherView, context: Context) {
    view.onKey = onKey
    view.isActive = isActive
  }

  final class CatcherView: UIView {
    var onKey: (UIKey) -> Bool = { _ in false }
    var isActive = false {
      didSet { claim() }
    }
    /// Presses `onKey` used, so their ends don't reach a responder that never
    /// saw them begin.
    private var used: Set<UIPress> = []
    private let noKeyboard = UIView(frame: .zero)

    override var canBecomeFirstResponder: Bool { true }
    override var inputView: UIView? { noKeyboard }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      claim()
    }

    private func claim() {
      // Off-window, becomeFirstResponder fails; didMoveToWindow asks again.
      guard window != nil else { return }
      if isActive, !isFirstResponder {
        becomeFirstResponder()
      } else if !isActive, isFirstResponder {
        resignFirstResponder()
      }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      var rest: Set<UIPress> = []
      for press in presses {
        if let key = press.key, onKey(key) { used.insert(press) } else { rest.insert(press) }
      }
      if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      let rest = presses.subtracting(used)
      if !rest.isEmpty { super.pressesChanged(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      let rest = presses.subtracting(used)
      used.subtract(presses)
      if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      let rest = presses.subtracting(used)
      used.subtract(presses)
      if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }
  }
}
