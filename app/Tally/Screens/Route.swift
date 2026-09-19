// Route.swift — the screens the calculator can push.
//
// An enum rather than a `NavigationLink(destination:)` at each call site,
// because most of these are reachable from more than one place — Saved from
// both the leading bar button and the More menu, Tags from Settings, a saved
// row's swipe action and its context menu — and a destination should be
// declared once.
import SwiftUI
import TallyKit

enum Route: Hashable {
  case saved
  case settings
  /// The tag catalog. With a calculation's id it doubles as that calculation's
  /// tag picker: rows carry a checkmark and tapping one files or unfiles it.
  case tags(applyingTo: String? = nil)
}

extension View {
  /// The app's one navigation table.
  func tallyRoutes() -> some View {
    navigationDestination(for: Route.self) { route in
      switch route {
      case .saved: SavedScreen()
      case .settings: SettingsScreen()
      case .tags(let applyingTo): TagsScreen(applyingTo: applyingTo)
      }
    }
  }
}
