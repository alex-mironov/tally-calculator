// CalculatorScreen+Layout.swift — how the calculator's parts are arranged: one
// column on a phone; one wider column with a centred dock on an iPad in
// portrait; the tab and the entry pane side by side on an iPad in landscape.
// The parts themselves live in their own files; this only places them.
import SwiftUI

extension CalculatorScreen {
  /// Phone, and any compact window: one column — the hero total under the
  /// bar, the lines on the canvas, and the dock at the foot, stowable.
  var compactLayout: some View {
    VStack(spacing: 0) {
      if showsHero { heroTotal }
      listOrEmpty
        // Above the dock, over the foot of the list: where the thumb that
        // tapped the total can see it without it covering the number.
        .overlay(alignment: .bottom) { copiedToast }
      inputDock()
    }
  }

  /**
   iPad in portrait (tally-app-v2.jsx, `portrait`): still one column, but not
   a stretched phone. The hero and the rows sit further in from the edges, and
   the dock is a centred block of its own rather than running the window's
   width — at 834pt a full-width keypad has keys twice as wide as a thumb
   needs. The archive is an overlay, so nothing shares the width.
   */
  var portraitLayout: some View {
    VStack(spacing: 0) {
      if showsHero { heroTotal(inset: Self.portraitHeroInset) }
      listOrEmpty
        // The design's 32pt list padding; the rows carry 20 of it themselves.
        .padding(.horizontal, Space.s3)
        .overlay(alignment: .bottom) { copiedToast }
      inputDock(keyHeight: Self.portraitKeyHeight, margin: 0, bottomMargin: Space.s6)
        .frame(width: min(Self.portraitDockWidth, width - 2 * Space.s6))
    }
  }

  /// The portrait dock's cap. A window too narrow for it (none in this band
  /// is) would keep a 24pt margin either side instead.
  static let portraitDockWidth: CGFloat = 560

  /// The design's 58pt portrait keys, onto the grid. The radius stays half of
  /// it, so they are still pills.
  static let portraitKeyHeight: CGFloat = 56

  /// The design's 10 / 36 / 22, onto the grid as 12 / 36 / 24.
  static let portraitHeroInset = EdgeInsets(
    top: Space.s3, leading: 36, bottom: Space.s6, trailing: 36)

  /**
   iPad in landscape: the tab on the leading side, the thing you type into on
   the trailing side.

   Used when `layout` says so — which `RootView` decides from the window's
   width, not this screen's. That distinction is the whole fix, and is worth
   keeping because the failure was so misleading.

   While this screen was the detail column of a `NavigationSplitView`, four
   ways of working the width out from *here* all failed the same way: the size
   class (which reads "regular" for a 504pt column, leaving the list 134pt wide
   and one digit per line), a GeometryReader through `@State`, a GeometryReader
   read straight off the proxy, and `ViewThatFits` (a `List`'s ideal width is
   unbounded, so the wide arm always "fits" and overflowed). The third was
   disproved outright: a red background on this layout never appeared while a
   debug title in the same `body` read `w=834 WIDE`. A detail column's width is
   re-proposed by the split view as the sidebar comes and goes, and the width
   that reached the branch disagreed with the width its container was laid out
   at.

   The split view is gone. `RootView` measures the window — which nothing
   re-proposes — subtracts a fixed sidebar, and passes the answer down.
   */
  var wideLayout: some View {
    // No rule between the columns, per the design: the pane is the phone's
    // bottom band standing on the screen's own background, and a hairline
    // down the middle only fenced the keypad off from the lines it adds to.
    HStack(spacing: 0) {
      // The hero heads the main column, as it heads the phone's.
      VStack(spacing: 0) {
        if showsHero { heroTotal }
        listOrEmpty
      }

      VStack(spacing: 0) {
        Spacer(minLength: 0)
        // Above the dock, as on the other two layouts — the design hangs the
        // toast off the dock itself, so here it belongs in the pane, not at
        // the foot of the list a column away from the keys that made it.
        copiedToast
        // 16pt off the window's trailing edge and foot, as the design's pane
        // insets its dock. Nothing to stow here — the keys have a column of
        // their own and take nothing from the list — so no grabber either.
        inputDock(margin: Space.s4)
      }
      .frame(width: Self.entryPaneWidth)
    }
  }

  /**
   The trailing pane's width — the design's 400pt cap on the iPad keypad.

   Less the dock's 16pt insets, the keypad's 12pt padding and its 8pt gaps,
   that puts each key at 80pt, a little wider than the same keypad on a 393pt
   iPhone. The pad keeps the proportions it was designed with instead of being
   stretched to whatever is left over — which is exactly what made the iPad
   build before this look like a blown-up phone.
   */
  static let entryPaneWidth: CGFloat = 400
}
