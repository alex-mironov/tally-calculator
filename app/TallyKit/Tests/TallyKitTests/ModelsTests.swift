// ModelsTests.swift — the persisted/wire JSON contract, against the documents
// the original JavaScript actually produces (Tools/gen-models-fixture.mjs).
//
// The contract is the *key set*, not just the values: `excluded` and `error`
// are written only when true, so a counted line is one with no `excluded` key
// at all. Swift's synthesised Codable would write `"excluded": false` and this
// suite is what stops it.
import Foundation
import Testing

@testable import TallyKit

struct ModelsFixture: Decodable {
  struct EntryCase: Decodable {
    let `case`: String
    let entry: Entry
    let keys: [String]
  }
  struct TabCase: Decodable {
    let `case`: String
    let tab: Tab
    let keys: [String]
    let resolvedTags: [String]
  }
  let version: Int
  let entries: [EntryCase]
  let tabs: [TabCase]
}

let modelsFixture: ModelsFixture = {
  let url = Bundle.module.url(forResource: "Fixtures/models", withExtension: "json")!
  return try! JSONDecoder().decode(ModelsFixture.self, from: Data(contentsOf: url))
}()

/// The keys a value encodes to, as JSON — which is the half of the contract
/// that a value-by-value comparison would miss.
func encodedKeys<T: Encodable>(_ value: T) throws -> [String] {
  let data = try JSONEncoder().encode(value)
  let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  return obj.keys.sorted()
}

@Suite("Persisted and wire JSON, against the JavaScript original")
struct ModelsTests {

  @Test("the fixture is the shape this suite was written for")
  func fixtureVersion() {
    #expect(modelsFixture.version == 1)
  }

  @Test("an entry encodes exactly the keys the original writes")
  func entryKeys() throws {
    for c in modelsFixture.entries {
      #expect(try encodedKeys(c.entry) == c.keys.sorted(), "\(c.case)")
    }
  }

  @Test("a tab encodes exactly the keys the original writes")
  func tabKeys() throws {
    for c in modelsFixture.tabs {
      // `tags` is always written by this app, even where the legacy document
      // being read had only the singular `tag` — a tab is migrated the next
      // time it is rewritten, which is exactly what encoding it is.
      var expected = Set(c.keys)
      expected.insert("tags")
      #expect(try Set(encodedKeys(c.tab)) == expected, "\(c.case)")
    }
  }

  @Test("excluded and error are never written as false")
  func falseFlagsAreAbsent() throws {
    for c in modelsFixture.entries {
      let keys = try encodedKeys(c.entry)
      if c.entry.excluded != true { #expect(!keys.contains("excluded"), "\(c.case)") }
      if c.entry.error != true { #expect(!keys.contains("error"), "\(c.case)") }
    }
    // The generator feeds in `excluded: false` explicitly for two cases; those
    // must decode to "counted", not to a flag that then gets written back.
    let falseCase = modelsFixture.entries.first { $0.case.contains("excluded false") }!
    #expect(falseCase.entry.excluded == nil)
    #expect(falseCase.entry.isCounted)
  }

  @Test("values survive the round trip")
  func roundTrip() throws {
    for c in modelsFixture.entries {
      let data = try JSONEncoder().encode(c.entry)
      #expect(try JSONDecoder().decode(Entry.self, from: data) == c.entry, "\(c.case)")
    }
    for c in modelsFixture.tabs {
      let data = try JSONEncoder().encode(c.tab)
      let back = try JSONDecoder().decode(Tab.self, from: data)
      // The legacy singular is dropped by encoding, having been folded into
      // `tags` — compare against what a migrated tab should be.
      #expect(back.id == c.tab.id && back.entries == c.tab.entries, "\(c.case)")
    }
  }

  @Test("tags resolve the same way tagsOf does, legacy singular included")
  func resolvedTags() {
    for c in modelsFixture.tabs {
      #expect(c.tab.resolvedTags == c.resolvedTags, "\(c.case)")
    }
  }

  @Test("a legacy tab keeps its singular tag until it is rewritten")
  func legacyTagPreservedOnRead() {
    let legacy = modelsFixture.tabs.first { $0.case.contains("legacy") }!.tab
    #expect(legacy.legacyTag == "Bills")
    #expect(legacy.tags.isEmpty)
    #expect(legacy.resolvedTags == ["Bills"])
    // Rewriting it migrates: `tags` is set and the singular goes.
    let migrated = legacy.migrated(to: legacy.resolvedTags)
    #expect(migrated.tags == ["Bills"])
    #expect(migrated.legacyTag == nil)
  }

  @Test("an entry missing note/expr entirely still loads")
  func toleratesMissingFields() throws {
    let json = #"{"id":"e1","value":7}"#.data(using: .utf8)!
    let e = try JSONDecoder().decode(Entry.self, from: json)
    #expect(e.id == "e1" && e.note.isEmpty && e.expr.isEmpty && e.value == 7 && e.num == nil)
  }

  @Test("tag names normalise and de-dupe the way the store expects")
  func tagNames() {
    #expect(normalizeTagName("  Trip  ") == "Trip")
    #expect(normalizeTagName("a\n\t  b") == "a b")
    #expect(normalizeTagName(String(repeating: "x", count: 40)).count == 22)
    #expect(normalizeTagName("   ").isEmpty)
    // First spelling seen wins.
    #expect(dedupeTags(["Trip", "trip", "TRIP", "Food"]) == ["Trip", "Food"])
  }
}
