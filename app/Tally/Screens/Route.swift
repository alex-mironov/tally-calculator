// Route.swift — the screens the calculator can push.
//
// An enum rather than a `NavigationLink(destination:)` at each call site,
// because these are reachable from more than one place — Saved from both the
// leading bar button and the calculator's menu, Settings from the menu on
// either layout — and a destination should be declared once.
//
// Tagging one calculation is not a route: "Tags…" and a saved row's "Edit
// tags" present the catalog as a sheet (TagsSheet), so the only push left to
// Tags is the catalog itself, from Settings.
import SwiftUI
import TallyKit

enum Route: Hashable {
  case saved
  case settings
  /// The tag catalog.
  case tags
}

extension View {
  /// The app's one navigation table.
  func tallyRoutes() -> some View {
    navigationDestination(for: Route.self) { route in
      switch route {
      case .saved: SavedScreen()
      case .settings: SettingsScreen()
      case .tags: TagsScreen()
      }
    }
  }
}
