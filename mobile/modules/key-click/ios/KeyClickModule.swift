import ExpoModulesCore
import UIKit

// KeyClick — the standard keyboard "tock" for Tally's custom keypad.
//
// HIG "Virtual keyboards" ▸ Custom input views: "Play the standard keyboard
// sound while people type… they're likely to expect the same sound when they
// tap keys in your custom input view. People can turn keyboard sounds off for
// all keyboard interactions in Settings > Sounds."
//
// That last sentence is the whole reason this is a native module rather than an
// AudioServicesPlaySystemSound(1104) one-liner: the system sound API would
// happily play over the top of a user who has switched keyboard clicks off.
// UIDevice.playInputClick() is the only API that honours the preference, and
// UIKit only acts on it when the call comes from a visible UIInputView whose
// enableInputClicksWhenVisible is true. Tally's keypad is a React Native view,
// not a UIInputView, so we park a 1×1 effectively-invisible one in the key
// window purely to satisfy that requirement.
//
// If a future iOS tightens the "visible input view" rule, the failure mode is
// silence — never a click that ignores the user's setting.

final class ClickFeedbackView: UIInputView, UIInputViewAudioFeedback {
  var enableInputClicksWhenVisible: Bool { true }
}

public class KeyClickModule: Module {
  private var clicker: ClickFeedbackView?

  public func definition() -> ModuleDefinition {
    Name("KeyClick")

    Function("play") {
      DispatchQueue.main.async { [weak self] in
        self?.attachIfNeeded()
        UIDevice.current.playInputClick()
      }
    }
  }

  private func attachIfNeeded() {
    // Re-attach if the window went away (backgrounding, scene changes).
    guard clicker?.window == nil else { return }
    guard let window = Self.keyWindow else { return }

    clicker?.removeFromSuperview()
    let view = ClickFeedbackView(
      frame: CGRect(x: 0, y: 0, width: 1, height: 1),
      inputViewStyle: .keyboard
    )
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    view.alpha = 0.01 // non-zero: UIKit requires the input view to be "visible"
    window.addSubview(view)
    window.sendSubviewToBack(view)
    clicker = view
  }

  private static var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
  }
}
