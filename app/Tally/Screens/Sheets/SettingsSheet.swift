// SettingsSheet.swift — Settings on an iPad: a form sheet over the calculator
// rather than a push (tally-app-v2.jsx, `FormSheet`).
//
// The same SettingsScreen a phone pushes, in a NavigationStack of its own, so
// its large title survives and its Tags row pushes the catalog *inside* the
// sheet — the design's "Manage tags" — rather than dismissing it to push on the
// calculator underneath.
//
// Settings apply as they are changed, so there is nothing to confirm or cancel;
// the bar's one control is the ✓ that closes it.
import SwiftUI

struct SettingsSheet: View {
  @Environment(\.theme) private var t
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    // On Midnight a step up from the black screen behind it, so the sheet has
    // an edge (Theme.sheet); the light schemes' sheet is their screen.
    let s = t.sheet

    NavigationStack {
      SettingsScreen()
        .tallyRoutes()
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(role: .confirm) { dismiss() }
              .accessibilityLabel("Done")
          }
        }
    }
    .environment(\.theme, s)
    // The scheme can change *from inside* this sheet. The root's
    // preferredColorScheme does reach a presented sheet, but not while it is
    // up: switching Midnight → Lilac here left the rows' labels in the dark
    // appearance's white, on Lilac's white cards. Asking again from the
    // sheet's own content re-resolves it as the swatch is tapped.
    .preferredColorScheme(s.colorScheme)
    .presentationSizing(.form)
    .presentationBackground(s.screen)
  }
}
