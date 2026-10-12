// SettingsScreen.swift — appearance, and what shows on the tab.
//
// Ported from mobile/src/app/settings.tsx, where it was a hand-drawn stack of
// `GroupedCard`/`CardRow` — the *second* list renderer that grouped-list.tsx
// carried — because only a React Native ScrollView can drive a large title's
// collapse, and a hosted SwiftUI List would have left the title permanently
// expanded. That is why this screen and Tags looked like the rest of the app
// rather than being built from the same thing.
//
// Here it is a `Form` with a large title, and both halves of that sentence are
// free.
import SwiftUI
import TallyKit

struct SettingsScreen: View {
  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t

  var body: some View {
    Form {
      // A section to itself, as the accent palette had: a set of swatches is
      // not a setting with a value, and it needs the width of the row to lay
      // them out. There is no Light/Dark row beside it — the scheme decides
      // that, and only Midnight is dark.
      Section {
        swatches
      } header: {
        header("Colour scheme")
      }
      .listRowBackground(t.card)

      Section {
        NavigationLink(value: Route.tags()) {
          LabeledContent("Tags", value: "\(store.catalog.count)")
        }
      } header: {
        header("Tags")
      }
      .listRowBackground(t.card)

      Section {
        // HIG "Toggles": only the *on* tint may be themed. The off track and
        // the thumb stay system-drawn — the stock light-grey off state is what
        // gives the accent enough contrast to read at a glance.
        Toggle(
          isOn: Binding(get: { store.showTotal }, set: { store.setShowTotal($0) })
        ) {
          Text("Show running total")
          Text("The live sum above the keypad")
        }
        Toggle(
          isOn: Binding(get: { store.showExpr }, set: { store.setShowExpr($0) })
        ) {
          Text("Show the maths under each line")
          Text("e.g. 60 ÷ 4 beneath a split")
        }
      } header: {
        header("The tab")
      }
      .listRowBackground(t.card)
      .tint(t.accent)

      Section {
      } footer: {
        Text("Tally · v\(Self.version)\nSettings sync with iCloud")
          .font(.tally(TallyFont.sans, TextScale.caption))
          .foregroundStyle(t.ink2)
      }
    }
    // The rows take the scheme's card and the headers its second ink. Left to
    // the system, a Form's rows are white or grey and its headers grey —
    // right for the system's own palettes, and wrong on all four of these:
    // white cards on Paper's white screen vanish, and grey reads muddy on
    // Lilac and Sand.
    .scrollContentBackground(.hidden)
    .background { ScreenBackground() }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.large)
  }

  private func header(_ title: String) -> some View {
    Text(title).foregroundStyle(t.ink2)
  }

  private var swatches: some View {
    // Spread rather than a fixed gap, as the design's space-between: the
    // swatches sit evenly across the row whatever its width.
    HStack {
      ForEach(Scheme.all) { scheme in
        let on = scheme.id == store.scheme.id
        Spacer(minLength: 0)
        Button {
          Haptic.select.play()
          store.setScheme(scheme.id)
        } label: {
          Circle()
            .fill(Color(hex: scheme.swatch))
            .frame(width: 40, height: 40)
            .overlay {
              if on {
                // White on the one dark swatch, near-black on the light ones,
                // as the design's swatch set does.
                Image(systemName: "checkmark")
                  .font(.system(size: 15, weight: .bold))
                  .foregroundStyle(Color(hex: scheme.isDark ? "#ffffff" : "#111111"))
              }
            }
            .overlay {
              // The selected ring sits 4pt outside the 40pt swatch, so its
              // radius is derived from the shape rather than chosen. In ink,
              // not in the swatch's own colour as the design draws it: Sand and
              // Paper are pale enough that a ring in their colour disappears
              // into the row.
              if on {
                Circle()
                  .strokeBorder(t.ink, lineWidth: 2)
                  .padding(-4)
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scheme.name)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        Spacer(minLength: 0)
      }
    }
    // 16 top and bottom leaves the selected ring's 4pt of float clear of the
    // row's edges.
    .padding(.vertical, Space.s4)
  }

  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }
}
