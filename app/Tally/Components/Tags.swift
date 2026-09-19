// Tags.swift — the tag chip and the filter strip, shared by the Saved archive
// and anywhere else a tag is shown.
//
// Tags share one colour: the live theme accent. Labels are monospaced, regular
// weight, slightly tracked. The "soft" style — accent-tint background, accent
// ink — is the default; a chooser's selected state flips to solid accent with a
// knocked-out check so it stays legible.
//
// Ported from mobile/src/components/tally/tags.tsx and tag-glass.tsx. Those two
// files existed as a pair because hosted SwiftUI glass inside a scroll view made
// iOS draw a grey backdrop across the whole group, so the glass strip needed
// `expo-glass-effect` while the fallback needed a drawn twin. Neither problem
// exists here, so the pair collapses into one file.
import SwiftUI
import TallyKit

/// A single tag chip. Soft by default; `selected` flips it to the solid accent.
struct TagChip: View {
  let name: String
  var selected = false
  var size: Size = .medium

  enum Size { case small, medium }

  @Environment(\.theme) private var t

  private var fontSize: CGFloat { size == .small ? 11 : 12.5 }

  var body: some View {
    HStack(spacing: Space.s1) {
      if selected {
        Image(systemName: "checkmark")
          .font(.system(size: fontSize - 1, weight: .bold))
      }
      Text(name)
        .font(.tally(TallyFont.mono, fontSize))
        .tracking(Tracking.pt(Tracking.label, at: fontSize))
    }
    // onAccent, not white — the tick and label have to hold up on the bright
    // hues (teal, amber) as well as the deep ones.
    .foregroundStyle(selected ? t.onAccent : t.accentInk)
    .padding(.vertical, size == .small ? Space.s1 : Space.s2)
    .padding(.horizontal, size == .small ? Space.s2 : Space.s3)
    .background(selected ? t.accent : t.accent2, in: .capsule)
  }
}

/**
 The Saved screen's quick filter: one glass capsule per tag in use, pinned above
 the list so it stays reachable however far down you have scrolled.

 Only tags that are actually on a calculation appear — a catalog entry nobody
 has used yet would filter to nothing, which is a dead control.
 */
struct TagFilterBar: View {
  let tabs: [TallyKit.Tab]
  let catalog: [String]
  @Binding var active: String?

  @Environment(\.theme) private var t

  /// Tags in use, in catalog order, with how many calculations carry each.
  private var inUse: [(name: String, count: Int)] {
    var counts: [String: Int] = [:]
    for tab in tabs {
      for name in tab.resolvedTags { counts[name, default: 0] += 1 }
    }
    return catalog.compactMap { name in
      counts[name].map { (name, $0) }
    }
  }

  var body: some View {
    if !inUse.isEmpty {
      GlassEffectContainer(spacing: Space.s2) {
        ScrollView(.horizontal) {
          HStack(spacing: Space.s2) {
            capsule(label: "All", isOn: active == nil) { active = nil }
            ForEach(inUse, id: \.name) { tag in
              capsule(label: "\(tag.name) \(tag.count)", isOn: active == tag.name) {
                active = active == tag.name ? nil : tag.name
              }
            }
          }
          .padding(.horizontal, Space.s4)
          .padding(.vertical, Space.s2)
        }
        .scrollIndicators(.hidden)
      }
    }
  }

  private func capsule(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button {
      Haptic.select.play()
      action()
    } label: {
      Text(label)
        .font(.tally(TallyFont.mono, 12.5))
        .tracking(Tracking.pt(Tracking.label, at: 12.5))
        .foregroundStyle(isOn ? t.onAccent : t.accentInk)
        .padding(.vertical, Space.s2)
        .padding(.horizontal, Space.s3)
        .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .background(isOn ? AnyShapeStyle(t.accent) : AnyShapeStyle(.clear), in: .capsule)
    .glassEffect(isOn ? .identity : .regular, in: .capsule)
    .accessibilityAddTraits(isOn ? [.isSelected] : [])
  }
}
