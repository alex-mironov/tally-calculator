// DesignSystemScreen.swift — every token the app draws with, on one screen.
//
// This is Phase 2's deliverable and Phase 3's reference. It exists because the
// design system is otherwise only visible in the places that happen to use it:
// a palette that reads fine on the calculator can be quietly broken on the
// scheme nobody tests with. Here all four schemes are one scroll apart.
//
// It is also the only screen in the app that is allowed to show a colour
// swatch. Everything else reads `\.theme`.
import SwiftUI
import TallyKit

struct DesignSystemScreen: View {
  @Environment(TallyStore.self) private var store
  @Environment(\.theme) private var t

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.s8) {
        schemePicker
        typeScale
        surfaces
        accentRow
        schemes
        haptics
      }
      .padding(Space.s4)
      .padding(.bottom, Space.s12)
    }
    .background(ScreenBackground())
    .navigationTitle("Design system")
    .navigationBarTitleDisplayMode(.large)
  }

  // MARK: - Sections

  private var schemePicker: some View {
    section("Scheme") {
      Picker(
        "Scheme",
        selection: Binding(get: { store.scheme.id }, set: { store.setScheme($0) })
      ) {
        ForEach(Scheme.all) { scheme in
          Text(scheme.name).tag(scheme.id)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  private var typeScale: some View {
    section("Type") {
      VStack(alignment: .leading, spacing: Space.s3) {
        specimen("displayLg / serif", TallyFont.serif, TextScale.displayLg, "Nothing added yet.")
        specimen("bodyLg / sans", TallyFont.sans, TextScale.bodyLg, "Dinner · split 4")
        specimen("bodySm / sansSemi", TallyFont.sansSemi, TextScale.bodySm, "Saved calculations")
        specimen("numXl / monoSemi", TallyFont.monoSemi, TextScale.numXl, "1,284.50")
        specimen("numLg / monoSemi", TallyFont.monoSemi, TextScale.numLg, "42.20")
        specimen("label / mono", TallyFont.mono, TextScale.label, "TOTAL")
      }
    }
  }

  private var surfaces: some View {
    section("Surfaces") {
      VStack(alignment: .leading, spacing: Space.s3) {
        // The card, the way every list row and the entry card draw it.
        RoundedRectangle(cornerRadius: Radius.md)
          .fill(t.card)
          .frame(height: 56)
          .overlay(alignment: .leading) {
            HStack {
              Text("Card · t.card")
                .font(.tally(TallyFont.sans, TextScale.bodyMd))
                .foregroundStyle(t.ink)
              Spacer()
              Text("18.00")
                .font(.tally(TallyFont.monoSemi, TextScale.bodyLg))
                .monospacedDigit()
                .foregroundStyle(t.ink)
            }
            .padding(.horizontal, Space.s4)
          }
          .elevation(.glass)

        // Liquid Glass, unconditional on iOS 26 — the reason the deployment
        // floor was set there. No availability check, no opaque twin.
        RoundedRectangle(cornerRadius: Radius.xl)
          .fill(.clear)
          .glassEffect(.regular, in: .rect(cornerRadius: Radius.xl))
          .frame(height: 64)
          .overlay {
            Text("Liquid Glass · .glassEffect()")
              .font(.tally(TallyFont.sans, TextScale.bodyMd))
              .foregroundStyle(t.ink)
          }

        // The inverted surface: the total bar and the ↵ key.
        RoundedRectangle(cornerRadius: Radius.md)
          .fill(t.totalBg)
          .frame(height: 56)
          .overlay(alignment: .leading) {
            HStack {
              Text("Total")
                .font(.tally(TallyFont.sansMedium, TextScale.bodySm))
                .foregroundStyle(t.totalSub)
              Spacer()
              Text(Calc.fmt(store.total))
                .font(.tally(TallyFont.monoSemi, TextScale.numLg))
                .monospacedDigit()
                .foregroundStyle(t.totalInk)
            }
            .padding(.horizontal, Space.s4)
          }

        swatchRow
      }
    }
  }

  private var swatchRow: some View {
    HStack(spacing: Space.s2) {
      swatch("screen", t.screen)
      swatch("card", t.card)
      swatch("line", t.line)
      swatch("ink2", t.ink2)
      swatch("dock", t.dock)
      swatch("op", t.op)
      swatch("cta", t.cta)
      swatch("chipBg", t.chipBg)
      swatch("danger", t.danger)
    }
  }

  private var accentRow: some View {
    section("Accent") {
      // What the accent role has to survive: its readable shade on the soft
      // surface and on the plain card, and the call to action's own ink.
      HStack(spacing: Space.s2) {
        chip("Trip", on: t.accent2, ink: t.accentInk)
        chip("On card", on: t.card, ink: t.accentInk)
        chip("On cta", on: t.cta, ink: t.ctaInk)
        chip("Op", on: t.op, ink: t.opInk)
      }
    }
  }

  /**
   All four schemes at once, each drawn in its own palette whatever the app is
   in: its screen, with a dock on it carrying a plain key, an operator and the
   call to action. The parts that decide whether a scheme works are the ones
   that sit on each other, so that is how they are shown.
   */
  private var schemes: some View {
    section("Schemes") {
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: Space.s2), GridItem(.flexible())],
        spacing: Space.s2
      ) {
        ForEach(Scheme.all) { scheme in
          schemeTile(Theme.resolve(scheme: scheme), name: scheme.name)
        }
      }
    }
  }

  private func schemeTile(_ s: Theme, name: String) -> some View {
    VStack(alignment: .leading, spacing: Space.s2) {
      HStack {
        Text(name)
          .font(.tally(TallyFont.sansSemi, TextScale.bodySm))
          .foregroundStyle(s.ink)
        Spacer()
        Text(s.isDark ? "dark" : "light")
          .font(.tally(TallyFont.mono, TextScale.labelSm))
          .foregroundStyle(s.ink2)
      }
      HStack(spacing: Space.s1) {
        key("7", fill: s.pill, ink: s.pillInk)
        key("+", fill: s.op, ink: s.opInk)
        key("↵", fill: s.cta, ink: s.ctaInk)
      }
      .padding(Space.s2)
      .background(s.dock, in: .rect(cornerRadius: Radius.lg))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(s.dockLine, lineWidth: 1)
      }
      .shadow(s.dockShadow)
    }
    .padding(Space.s3)
    .background(s.screen, in: .rect(cornerRadius: Radius.md))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.md).strokeBorder(t.line, lineWidth: 1)
    }
  }

  private func key(_ label: String, fill: Color, ink: Color) -> some View {
    Text(label)
      .font(.tally(TallyFont.monoSemi, TextScale.bodyLg))
      .foregroundStyle(ink)
      .frame(maxWidth: .infinity, minHeight: Space.s8)
      .background(fill, in: .capsule)
  }

  private var haptics: some View {
    section("Haptics") {
      HStack(spacing: Space.s2) {
        ForEach(
          [("tap", Haptic.tap), ("select", .select), ("impact", .impact), ("error", .error)],
          id: \.0
        ) { name, haptic in
          Button(name) { haptic.play() }
            .font(.tally(TallyFont.sansMedium, TextScale.bodySm))
            .buttonStyle(.bordered)
        }
        Button("click") { KeyClick.play() }
          .font(.tally(TallyFont.sansMedium, TextScale.bodySm))
          .buttonStyle(.bordered)
      }
    }
  }

  // MARK: - Pieces

  private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: Space.s3) {
      Text(title.uppercased())
        .font(.tally(TallyFont.mono, TextScale.label))
        .tracking(Tracking.pt(Tracking.eyebrow, at: TextScale.label))
        .foregroundStyle(t.ink3)
      content()
    }
  }

  private func specimen(_ label: String, _ face: String, _ size: CGFloat, _ sample: String)
    -> some View
  {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.tally(TallyFont.mono, TextScale.labelSm))
        .foregroundStyle(t.ink3)
      Text(sample)
        .font(.tally(face, size))
        .foregroundStyle(t.ink)
    }
  }

  private func swatch(_ name: String, _ color: Color) -> some View {
    VStack(spacing: Space.s1) {
      RoundedRectangle(cornerRadius: Radius.xs)
        .fill(color)
        .strokeBorder(t.line, lineWidth: 1)
        .frame(height: Space.s8)
      Text(name)
        .font(.tally(TallyFont.mono, TextScale.micro))
        .foregroundStyle(t.ink3)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
  }

  private func chip(_ label: String, on background: Color, ink: Color) -> some View {
    Text(label)
      .font(.tally(TallyFont.mono, TextScale.caption))
      .foregroundStyle(ink)
      .padding(.vertical, Space.s1)
      .padding(.horizontal, Space.s3)
      .background(background, in: .rect(cornerRadius: Radius.sm))
  }
}

#Preview {
  NavigationStack { DesignSystemScreen() }
    .environment(TallyStore(storage: Storage(local: MemoryStore())))
    .tallyTheme(.fallback)
}
