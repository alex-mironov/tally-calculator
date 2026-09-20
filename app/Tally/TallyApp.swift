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

/**
 The app's root, and the only place that decides how wide anything is.

 On a phone this is one `NavigationStack`. On an iPad the archive gets a
 permanent column beside the calculator — but built as a plain `HStack`, *not*
 a `NavigationSplitView`.

 That is a deliberate retreat from the obvious API, and the reason is worth
 keeping. As a split view, the calculator was the detail column, and a detail
 column's width is re-proposed by the split view as the sidebar comes and goes.
 Four different ways of reading that width from inside the calculator
 disagreed with the width its own container was laid out at, so the side-by-side
 layout could never be switched on. (Written up on `wideLayout` in
 CalculatorScreen.)

 Here the only measurement is of the window, which nothing is re-proposing, and
 the arithmetic is done once: the sidebar is a known width, so what is left for
 the calculator is a subtraction rather than a second measurement. The
 calculator takes the answer as a plain parameter and does no geometry at all.

 What this costs is the system's own sidebar toggle and its presentation
 behaviours; the toggle is drawn in the calculator's toolbar instead.
 */
struct RootView: View {
  @Binding var pendingShare: String?

  /// The archive's column. Fixed, so the calculator's share of the window is
  /// known without measuring it.
  private static let sidebarWidth: CGFloat = 320

  /// Below this the window is a phone, or a window the shape of one.
  private static let tabletWidth: CGFloat = 700

  /**
   Whether the archive column is showing.

   `nil` until the user expresses a preference, so the first launch adapts to
   the window: both columns if there is room for the sidebar *and* a split
   calculator, sidebar alone otherwise. Once toggled, the choice sticks.
   */
  @State private var sidebarPreference: Bool?

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let isTablet = width >= Self.tabletWidth
      let roomForBoth = width >= Self.sidebarWidth + CalculatorScreen.splitWidth
      let sidebarShown = isTablet && (sidebarPreference ?? roomForBoth)
      // What the calculator actually gets, by subtraction rather than by a
      // second measurement.
      let calculatorWidth = width - (sidebarShown ? Self.sidebarWidth : 0)

      HStack(spacing: 0) {
        if sidebarShown {
          NavigationStack {
            SavedScreen(inSidebar: true)
              .tallyRoutes()
          }
          .frame(width: Self.sidebarWidth)
          .transition(.move(edge: .leading))

          Divider().ignoresSafeArea()
        }

        NavigationStack {
          CalculatorScreen(
            splitEntryPane: calculatorWidth >= CalculatorScreen.splitWidth,
            sidebar: isTablet
              ? Binding(
                get: { sidebarShown },
                set: { sidebarPreference = $0 }
              )
              : nil
          )
          .tallyRoutes()
        }
        .frame(maxWidth: .infinity)
      }
      // A GeometryReader proposes nothing to its child, so the stack has to be
      // told to fill it or it lays out at its ideal size — which, for a
      // NavigationStack, is nothing at all.
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .shareImport($pendingShare)
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
