// Route.swift — the screens the calculator can push.
//
// An enum rather than a `NavigationLink(destination:)` at each call site,
// because two of these are reachable from more than one place (Saved from both
// the leading bar button and the More menu) and the destination should be
// declared once.
import SwiftUI

enum Route: Hashable {
  case saved
  case settings
  case tags
}

extension View {
  /// The app's one navigation table.
  func tallyRoutes() -> some View {
    navigationDestination(for: Route.self) { route in
      switch route {
      case .saved: PlaceholderScreen(title: "Saved calculations", phase: 4)
      case .settings: DesignSystemScreen()
      case .tags: PlaceholderScreen(title: "Tags", phase: 4)
      }
    }
  }
}

/// A screen that Phase 4 will build. Present so the navigation structure is
/// real and testable now, rather than being wired up at the end.
struct PlaceholderScreen: View {
  let title: String
  let phase: Int

  @Environment(\.theme) private var t

  var body: some View {
    ZStack {
      ScreenBackground()
      VStack(spacing: Space.s3) {
        Image(systemName: "hammer")
          .font(.system(size: 28, weight: .light))
          .foregroundStyle(t.ink3)
        Text(title)
          .font(.tally(TallyFont.serif, TextScale.displayMd))
          .foregroundStyle(t.ink2)
        Text("Arrives in phase \(phase).")
          .font(.tally(TallyFont.sans, TextScale.bodySm))
          .foregroundStyle(t.ink3)
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
