import ExpoModulesCore
import UIKit

// ListScroll — programmatic "scroll to newest row" for Tally's running list.
//
// The list is a native SwiftUI `List` (via @expo/ui) because that's the only
// place SwipeActions and row context menus exist. But SwiftUI has no working
// programmatic-scroll story for `List` that reaches across the RN bridge:
// `.scrollPosition(id:anchor:)` is ScrollView-only (Apple DTS confirms List is
// unsupported), and `ScrollViewReader` needs a proxy captured inside the
// SwiftUI view builder, which @expo/ui doesn't expose.
//
// So this reaches under SwiftUI instead: `List` is backed by a plain
// `UICollectionView` (a `UIScrollView`), and scrolling *that* is a two-line
// UIKit job. JS hands over the react tag of a wrapper view around the Host,
// we walk its subtree for the first scroll view, and animate it to the end.
//
// The failure mode if a future iOS restructures List's internals is a silent
// no-op — the list simply doesn't auto-scroll — never a crash.
public class ListScrollModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ListScroll")

    AsyncFunction("scrollToEnd") { (viewTag: Int, animated: Bool) in
      guard
        let root = self.appContext?.findView(withTag: viewTag, ofType: UIView.self),
        let scroll = Self.findScrollView(in: root)
      else { return }

      // Make sure the just-inserted row is part of the content size before
      // measuring how far "the end" is.
      scroll.layoutIfNeeded()

      let insets = scroll.adjustedContentInset
      let bottomY = scroll.contentSize.height + insets.bottom - scroll.bounds.height
      // A list shorter than its viewport has nothing to scroll — clamp to top.
      let target = CGPoint(x: -insets.left, y: max(bottomY, -insets.top))
      scroll.setContentOffset(target, animated: animated)
    }.runOnQueue(.main)
  }

  /// Breadth-first search for the first `UIScrollView` under `root` — for a
  /// SwiftUI `List`, that's the `UICollectionView` holding the rows.
  private static func findScrollView(in root: UIView) -> UIScrollView? {
    var queue: [UIView] = [root]
    while !queue.isEmpty {
      let view = queue.removeFirst()
      if let scroll = view as? UIScrollView { return scroll }
      queue.append(contentsOf: view.subviews)
    }
    return nil
  }
}
