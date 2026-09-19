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
      Section {
        Picker(
          "Theme",
          selection: Binding(get: { store.themeMode }, set: { store.setThemeMode($0) })
        ) {
          ForEach(ThemeMode.allCases, id: \.self) { mode in
            Text(mode.rawValue.capitalized).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        // The picker fills its selected segment with the tint and writes a
        // white label over it, so it takes accentSolid rather than the raw hue.
        .tint(t.accentSolid)
      } header: {
        Text("Appearance")
      }

      // The accent gets a section to itself rather than a row inside
      // Appearance: it is a palette, not a setting with a value, and it needs
      // the width of the row to lay its swatches out.
      Section {
        swatches
      } header: {
        Text("Accent colour")
      } footer: {
        Text("Controls across the app use the selected accent colour.")
      }

      Section("Tags") {
        NavigationLink(value: Route.tags()) {
          LabeledContent("Tags", value: "\(store.catalog.count)")
        }
      }

      Section("The tab") {
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
      }
      .tint(t.accent)

      Section {
      } footer: {
        Text("Tally · v\(Self.version)\nSettings sync with iCloud")
          .font(.tally(TallyFont.sans, TextScale.caption))
      }
    }
    .scrollContentBackground(.hidden)
    .background { ScreenBackground() }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.large)
  }

  private var swatches: some View {
    // Spread rather than a fixed gap: six 40pt swatches plus gaps overrun the
    // row on a 375pt screen, and space-between closes up instead of wrapping.
    HStack {
      ForEach(Accent.all) { accent in
        let on = accent.accent == store.accentHex
        Spacer(minLength: 0)
        Button {
          Haptic.select.play()
          store.setAccent(accent.accent)
        } label: {
          Circle()
            .fill(Color(hex: accent.accent))
            .frame(width: 40, height: 40)
            .overlay {
              if on {
                // onAccent, not white — the tick has to hold up on the bright
                // hues (teal, amber) as well as the deep ones.
                Image(systemName: "checkmark")
                  .font(.system(size: 15, weight: .bold))
                  .foregroundStyle(Color(hex: accent.onAccent))
              }
            }
            .overlay {
              // The selected ring sits 4pt outside the 40pt swatch, so its
              // radius is derived from the shape rather than chosen.
              if on {
                Circle()
                  .strokeBorder(Color(hex: accent.accent), lineWidth: 2)
                  .padding(-4)
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.name)
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
