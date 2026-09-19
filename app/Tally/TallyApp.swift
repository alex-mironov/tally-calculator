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

/// The app's root: the calculator, and the screens it can push.
struct RootView: View {
  @Binding var pendingShare: String?

  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    Group {
      if sizeClass == .regular {
        // On iPad the archive earns a permanent column: filing a calculation
        // and starting the next one is the loop this app is for, and a sidebar
        // makes "what have I got" and "what am I adding up" one glance rather
        // than a push and a back. The calculator keeps its own stack in the
        // detail column, so Settings and Tags still push over it.
        NavigationSplitView {
          NavigationStack {
            SavedScreen(inSidebar: true)
              .tallyRoutes()
          }
        } detail: {
          NavigationStack {
            CalculatorScreen()
              .tallyRoutes()
          }
        }
        .navigationSplitViewStyle(.balanced)
      } else {
        compact
      }
    }
    .shareImport($pendingShare)
  }

  private var compact: some View {
    // Each screen draws its own ScreenBackground rather than inheriting one
    // from here: the bloom has to sit *behind* that screen's chrome, including
    // the transparent nav bar it runs under.
    NavigationStack {
      CalculatorScreen()
        .tallyRoutes()
    }
  }
}

/// A share id that can drive `.fullScreenCover(item:)`.
private struct PendingShare: Identifiable {
  let id: String
}

extension View {
  /// A share link is a full-screen takeover rather than a push: it lands, files
  /// the snapshot, opens it and leaves. There is nothing to go back to, which
  /// is why it has no back button of its own — and why it covers the split view
  /// on iPad rather than landing in one of its columns.
  func shareImport(_ pending: Binding<String?>) -> some View {
    fullScreenCover(
      item: Binding(
        get: { pending.wrappedValue.map(PendingShare.init) },
        set: { pending.wrappedValue = $0?.id }
      )
    ) { p in
      ShareImportScreen(id: p.id) { pending.wrappedValue = nil }
    }
  }
}
