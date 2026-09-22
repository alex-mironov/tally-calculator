// Tags.swift — the tag chip and the filter strip, shared by the Saved archive
// and anywhere else a tag is shown.
//
// Tags share one colour: the live theme accent. Labels are monospaced, regular
// weight, slightly tracked, always in the "soft" style — accent-tint
// background, accent ink. A chooser's selected state keeps the soft fill and
// adds a check and a heavier weight, as the design does.
//
// Ported from mobile/src/components/tally/tags.tsx and tag-glass.tsx. Those two
// files existed as a pair because hosted SwiftUI glass inside a scroll view made
// iOS draw a grey backdrop across the whole group, so the glass strip needed
// `expo-glass-effect` while the fallback needed a drawn twin. Neither problem
// exists here, so the pair collapses into one file.
import SwiftUI
import TallyKit

/// A single tag chip. `selected` adds a check; the fill stays soft.
struct TagChip: View {
  let name: String
  var selected = false
  var size: Size = .medium

  enum Size { case small, medium }

  @Environment(\.theme) private var t

  private var fontSize: CGFloat { size == .small ? 12 : 14 }

  var body: some View {
    HStack(spacing: Space.s1) {
      if selected {
        Image(systemName: "checkmark")
          .font(.system(size: fontSize - 1, weight: .bold))
      }
      Text(name)
        .font(.tally(selected ? TallyFont.monoMedium : TallyFont.mono, fontSize))
        .tracking(0.01 * fontSize)
    }
    .foregroundStyle(t.accentInk)
    .padding(.vertical, Space.s1)
    .padding(.horizontal, size == .small ? Space.s2 : Space.s3)
    .background(t.accent2, in: .capsule)
  }
}

/**
 The Saved screen's quick filter: one 44pt pill per tag in use, pinned above the
 list so it stays reachable however far down you have scrolled. Idle pills are
 card-filled with a quiet label; the active one takes the soft accent.

 Only tags that are actually on a calculation appear — a catalog entry nobody
 has used yet would filter to nothing, which is a dead control.
 */
struct TagFilterBar: View {
  let tabs: [TallyKit.Tab]
  let catalog: [String]
  @Binding var active: String?

  @Environment(\.theme) private var t

  /// Tags in use: catalog order first, then any in use that the catalog no
  /// longer lists, so a tag still on a calculation can always be filtered to.
  private var inUse: [String] {
    let used = Set(tabs.flatMap(\.resolvedTags))
    let known = catalog.filter(used.contains)
    let stray = tabs.flatMap(\.resolvedTags).filter { !catalog.contains($0) }
    var seen = Set<String>()
    return known + stray.filter { seen.insert($0).inserted }
  }

  var body: some View {
    if !inUse.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: Space.s2) {
          capsule(label: "All", isOn: active == nil) { active = nil }
          ForEach(inUse, id: \.self) { name in
            capsule(label: name, isOn: active == name) {
              active = active == name ? nil : name
            }
          }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s1)
        .padding(.bottom, Space.s2)
      }
      .scrollIndicators(.hidden)
    }
  }

  private func capsule(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button {
      Haptic.select.play()
      action()
    } label: {
      Text(label)
        .font(.tally(isOn ? TallyFont.monoMedium : TallyFont.mono, 15))
        .foregroundStyle(isOn ? t.accentInk : t.ink2)
        .frame(height: 44)
        .padding(.horizontal, Space.s5)
        .background(isOn ? t.accent2 : t.card, in: .capsule)
        .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    // Dynamic Type grows the label, not the pill: 44pt is the strip's height.
    .dynamicTypeSize(...TypeCap.chrome)
    .accessibilityAddTraits(isOn ? [.isSelected] : [])
  }
}
