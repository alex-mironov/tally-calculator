// ShareImportScreen.swift — where a share link lands.
//
// Fetches the snapshot from the tally-share Worker, files it as a new saved
// calculation (with fresh local ids, so its references keep working), opens it
// and gets out of the way. On screen only long enough to show a spinner — or
// the error, when the link has expired.
//
// Ported from mobile/src/app/share/[id].tsx.
import SwiftUI
import TallyKit

struct ShareImportScreen: View {
  let id: String
  var onDone: () -> Void

  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t

  @State private var error: String?

  var body: some View {
    ZStack {
      ScreenBackground()

      if let error {
        ContentUnavailableView {
          Text("Couldn’t open that link")
            .font(.tally(TallyFont.serif, TextScale.displayMd))
        } description: {
          Text(error).font(.tally(TallyFont.sans, TextScale.bodySm))
        } actions: {
          Button("Back to my tab", action: onDone)
            .buttonStyle(.borderedProminent)
            .tint(t.accentSolid)
        }
      } else {
        VStack(spacing: Space.s4) {
          ProgressView()
          Text("Opening shared calculation…")
            .font(.tally(TallyFont.sans, TextScale.bodySm))
            .foregroundStyle(t.ink2)
        }
      }
    }
    .navigationBarBackButtonHidden(error == nil)
    // `.task(id:)` rather than `.onAppear`: it is cancelled if the view goes
    // away, and it runs once per id, so a re-render cannot file the same
    // snapshot twice.
    .task(id: id) {
      do {
        let snapshot = try await ShareClient.fetch(id: id)
        guard !Task.isCancelled else { return }
        store.importTab(
          name: snapshot.name, tags: snapshot.tags, entries: snapshot.entries)
        Haptic.success.play()
        onDone()
      } catch {
        guard !Task.isCancelled else { return }
        Haptic.error.play()
        self.error = (error as? LocalizedError)?.errorDescription
          ?? "Check your connection and try again."
      }
    }
  }
}
