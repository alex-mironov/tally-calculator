// SchemeTests.swift — the four schemes, and the migration onto them.
//
// The migration table is spelled out by hand rather than derived from
// `Accent.resolve`, so a change to either side shows up here as a decision
// rather than passing quietly: every hex an install can hold — the current
// palette and every retired one — in both of the old themes.
import Foundation
import Testing

@testable import TallyKit

@Suite("Scheme")
struct SchemeTests {

  /// Every accent hex an install can hold → the scheme it lands on in light.
  /// In dark, every one of them lands on Midnight.
  static let lightTable: [(String, Scheme.ID)] = [
    // The current palette.
    ("#d2fc4a", .midnight),  // Lime — dark-only, so Midnight in either theme
    ("#156cdd", .paper),  // Blue
    ("#6b58d9", .lilac),  // Violet
    // The same three before the "Refined" retune.
    ("#e8ff77", .midnight),  // Lime
    ("#2f6fe4", .paper),  // Blue
    ("#6b6bf0", .lilac),  // Violet
    // The six-accent palette.
    ("#0a7aff", .paper),  // Blue
    ("#dd1b80", .lilac),  // Magenta → Violet
    ("#00c2a0", .paper),  // Teal → Blue
    ("#6b00d0", .lilac),  // Purple → Violet
    ("#e6b800", .paper),  // Amber → Blue
    ("#4a5560", .paper),  // Graphite → Blue
    // The raspberry family before it.
    ("#b3476a", .lilac),  // Raspberry → Violet
    ("#c33a6e", .lilac),  // Magenta → Violet
    ("#864a7a", .lilac),  // Plum → Violet
    ("#9c3a48", .lilac),  // Wine → Violet
    ("#2a2420", .paper),  // Ink → Blue
  ]

  @Test("the table covers every hex the accent palette knows")
  func tableIsComplete() {
    let known = Set(Accent.all.map(\.accent)).union(Accent.legacy.keys)
    #expect(Set(Self.lightTable.map(\.0)) == known)
  }

  @Test("an old accent in light lands on its nearest scheme", arguments: lightTable)
  func migratesLight(hex: String, expected: Scheme.ID) {
    #expect(Scheme.migrating(accent: hex, mode: .light).id == expected)
  }

  @Test("an old accent in dark always lands on Midnight", arguments: lightTable.map(\.0))
  func migratesDark(hex: String) {
    #expect(Scheme.migrating(accent: hex, mode: .dark).id == .midnight)
  }

  @Test("partial and empty configs")
  func partialConfigs() {
    // Nothing stored: the old default accent, Lime, so Midnight.
    #expect(Scheme.migrating(accent: nil, mode: nil).id == .midnight)
    #expect(Scheme.migrating(accent: nil, mode: .light).id == .midnight)
    #expect(Scheme.migrating(accent: nil, mode: .dark).id == .midnight)
    // A theme never written reads as the old store's default, light.
    #expect(Scheme.migrating(accent: "#6b58d9", mode: nil).id == .lilac)
    // A hex nobody ever shipped falls back to Lime, like the old resolve did.
    #expect(Scheme.migrating(accent: "#123456", mode: .light).id == .midnight)
  }

  @Test("every scheme writes back as an accent that migrates to a scheme of the same darkness")
  func writeBackIsStable() {
    for scheme in Scheme.all {
      let back = Scheme.migrating(accent: scheme.legacyAccent.accent, mode: scheme.legacyMode)
      #expect(back.isDark == scheme.isDark, "\(scheme.name)")
      // Sand is the one that cannot come back as itself: it shares Blue.
      if scheme.id != .sand { #expect(back.id == scheme.id, "\(scheme.name)") }
    }
  }

  @Test("four schemes, one dark, ids unique and in Settings order")
  func theFour() {
    #expect(Scheme.all.map(\.id) == Scheme.ID.allCases)
    #expect(Scheme.all.filter(\.isDark).map(\.id) == [.midnight])
    #expect(Scheme.default.id == .midnight)
    for id in Scheme.ID.allCases { #expect(Scheme.named(id).id == id) }
    // Only the dark scheme needs a raised sheet surface.
    #expect(Scheme.all.filter { $0.elevated != nil }.map(\.id) == [.midnight])
  }

  @Test("every token is a #rrggbb or #rrggbbaa hex")
  func tokensAreHex() {
    let pattern = /^#[0-9a-f]{6}([0-9a-f]{2})?$/
    for s in Scheme.all {
      let tokens = Mirror(reflecting: s).children.compactMap { $0.value as? String }
        .filter { $0.hasPrefix("#") }
      // 27 colour tokens plus the swatch.
      #expect(tokens.count == 28, "\(s.name)")
      for hex in tokens { #expect(hex.wholeMatch(of: pattern) != nil, "\(s.name) \(hex)") }
      for shadow in [s.shadow] + [s.dockShadow].compactMap({ $0 }) {
        #expect(shadow.color.wholeMatch(of: pattern) != nil, "\(s.name) shadow")
      }
    }
  }

  @Test("rgba packs into #rrggbbaa the way the design means it")
  func rgba() {
    #expect(Scheme.rgba(255, 255, 255, 0.06) == "#ffffff0f")
    #expect(Scheme.rgba(94, 46, 90, 0.16) == "#5e2e5a29")
    #expect(Scheme.rgba(0, 0, 0, 1) == "#000000ff")
  }
}
