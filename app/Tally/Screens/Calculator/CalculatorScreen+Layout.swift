// CalculatorScreen+Layout.swift — how the calculator's parts are arranged: one
// column on a phone, the tab and the entry pane side by side on a wide iPad.
// The parts themselves live in their own files; this only places them.
import SwiftUI

extension CalculatorScreen {
  /// Phone, and any compact window: one column, keypad at the foot, stowable.
  var compactLayout: some View {
    VStack(spacing: 0) {
      listOrEmpty
      seam
      if !selectMode { entryCardSection }
      keypadSection
    }
  }

  /**
   iPad: the tab on the leading side, the thing you type into on the trailing
   side.

   Used when `splitEntryPane` says so — which `RootView` decides from the
   window's width, not this screen's. That distinction is the whole fix, and is
   worth keeping because the failure was so misleading.

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
      VStack(spacing: 0) {
        listOrEmpty
      }

      VStack(spacing: 0) {
        Spacer(minLength: 0)
        // The total sits directly above the card, as it does on the phone, so
        // the trailing pane is the phone's bottom band — total, card, keypad —
        // unchanged. It used to stay under the list on the theory that it is
        // the list's answer, and ended up stranded in the bottom-left corner,
        // level with the keypad's last row and nowhere near the lines it adds.
        if store.showTotal || selectMode || referencing { totalBar }
        if !selectMode { entryCardSection }
        keypadSection
      }
      .frame(width: Self.entryPaneWidth)
      // The design's 8pt trailing inset, so the pad doesn't run into the
      // window edge harder than the list does on the other side.
      .padding(.trailing, Space.s2)
    }
  }

  /**
   The trailing pane's width — the design's 400pt cap on the iPad keypad.

   With the keypad's own 16pt side padding and 8pt gaps that puts each key at
   86pt, a few points wider than the same keypad on a 393pt iPhone. The pad
   keeps the proportions it was designed with instead of being stretched to
   whatever is left over — which is exactly what made the iPad build before
   this look like a blown-up phone.
   */
  static let entryPaneWidth: CGFloat = 400

  /// The width this screen needs before the list and the entry pane can sit
  /// side by side: the entry pane, plus the narrowest list still worth reading
  /// (a note and an amount need roughly 320). `RootView` applies it.
  static let splitWidth: CGFloat = entryPaneWidth + Space.s2 + 320
}
