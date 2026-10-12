// LayoutMode.swift — the three shapes the app takes, decided once, from the
// window's width.
//
// Width rather than orientation or size class, as the design settles it
// (docs/v2-design.md, "iPad modes"): an iPad in portrait running two apps side
// by side is a phone-shaped window, and a 13-inch iPad in portrait is as wide as
// an 11-inch one in landscape. The size class cannot tell any of those apart —
// it reads "regular" for all of them.
import SwiftUI

enum LayoutMode: Equatable {
  /// A phone, or any window the shape of one: one column, Saved pushed.
  case phone
  /// An iPad window 700–1023pt wide: one full-width column with a centred
  /// dock, and Saved as an overlay from the leading edge.
  case padPortrait
  /// 1024pt and up: Saved as a permanent sidebar, the dock in a column of its
  /// own on the trailing side.
  case padLandscape

  init(windowWidth width: CGFloat) {
    switch width {
    case 1024...: self = .padLandscape
    case 700...: self = .padPortrait
    default: self = .phone
    }
  }

  /// Either iPad shape — where Settings and the tag pickers are form sheets
  /// over the calculator rather than a push and a full-height sheet.
  var isPad: Bool { self != .phone }
}

extension EnvironmentValues {
  /// Set once by `RootView`, for the views that only need to know *how* to
  /// present something — a sheet's sizing — rather than how wide they are.
  @Entry var layoutMode: LayoutMode = .phone
}

extension View {
  /**
   A sheet's size on iPad: the ~540pt form sheet the design centres over the
   calculator (tally-app-v2.jsx, `FormSheet`). On a phone it changes nothing —
   the sheet keeps whatever detents it asked for.
   */
  func padFormSheet() -> some View {
    modifier(PadFormSheet())
  }
}

private struct PadFormSheet: ViewModifier {
  @Environment(\.layoutMode) private var layout

  func body(content: Content) -> some View {
    if layout.isPad {
      content.presentationSizing(.form)
    } else {
      content
    }
  }
}
