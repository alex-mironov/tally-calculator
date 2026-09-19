// TallyApp.swift — the app entry point.
//
// One store, created here and handed down through the environment, and one
// theme resolved from it. Replaces mobile/src/app/_layout.tsx, which also had
// to hold the splash screen until `useFonts` resolved and wrap everything in a
// GestureHandlerRootView; neither has an equivalent here.
import SwiftUI
import TallyKit

@main
struct TallyApp: App {
  @State private var store = TallyStore(storage: .shared)
  /// Set when a share link arrives before the store has finished loading, so
  /// the import can wait for real data rather than landing on the seed.
  @State private var pendingShare: String?

  private var theme: Theme {
    .resolve(mode: store.themeMode, accent: store.accent)
  }

  var body: some Scene {
    WindowGroup {
      RootView(pendingShare: $pendingShare)
        .environment(store)
        // One call, and every sheet, menu, alert and bar in the app draws in
        // the app's palette rather than the system's. See Theme.swift.
        .tallyTheme(theme)
        .task {
          #if DEBUG
            TallyFont.assertAvailable()
          #endif
          store.load()
        }
        .onOpenURL { url in
          guard let id = Self.shareID(from: url) else { return }
          pendingShare = id
        }
    }
  }

  /**
   The share id in `tally://share/<id>`.

   Both schemes the React Native build registered are still accepted, because
   links already in the wild use them. A `tally://` URL puts "share" in the
   host and the id in the path, which is why this reads both.
   */
  static func shareID(from url: URL) -> String? {
    var parts = url.pathComponents.filter { $0 != "/" }
    if let host = url.host(), !host.isEmpty { parts.insert(host, at: 0) }
    guard parts.first == "share", parts.count >= 2 else { return nil }
    return parts[1]
  }
}

/// The app's root. Phase 3 replaces this with the calculator; for now it is the
/// design system, which is what Phase 2 has to prove renders.
struct RootView: View {
  @Binding var pendingShare: String?

  var body: some View {
    // Each screen draws its own ScreenBackground rather than inheriting one
    // from here: the bloom has to sit *behind* that screen's chrome, including
    // the transparent nav bar it runs under.
    NavigationStack {
      DesignSystemScreen()
    }
  }
}
