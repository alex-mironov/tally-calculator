// DraftTests.swift — the keypad's effect on the draft, against the fixture
// generated from the original TypeScript (Tools/gen-draft-fixture.mjs).
//
// The table is exhaustive rather than sampled: every draft shape the rules
// distinguish, crossed with every one of the twenty keys.
import Foundation
import Testing

@testable import TallyKit

struct DraftFixture: Decodable {
  struct Case: Decodable {
    let draft: String
    let key: String
    let out: String?
  }
  struct Step: Decodable {
    let key: String
    let draft: String
  }
  struct Sequence: Decodable {
    let name: String
    let keys: [String]
    let steps: [Step]
  }
  struct Insert: Decodable {
    let draft: String
    let id: String
    let out: String
  }
  struct Backspace: Decodable {
    let draft: String
    let out: String?
  }
  struct Size: Decodable {
    let expr: String
    let length: Int
    let size: Double
  }

  let version: Int
  let names: [String: String]
  let cases: [Case]
  let sequences: [Sequence]
  let inserts: [Insert]
  let backspace: [Backspace]
  let sizes: [Size]
}

let draftFixture: DraftFixture = {
  let url = Bundle.module.url(forResource: "Fixtures/draft", withExtension: "json")!
  return try! JSONDecoder().decode(DraftFixture.self, from: Data(contentsOf: url))
}()

@Suite("Draft, against the TypeScript original")
struct DraftTests {

  @Test("the fixture is the shape this suite was written for")
  func fixtureVersion() {
    #expect(draftFixture.version == 1)
    #expect(draftFixture.cases.count == 600, "every draft shape × every one of the 20 keys")
  }

  @Test("every key against every draft shape")
  func everyKey() {
    for c in draftFixture.cases {
      let key = Key(rawValue: c.key)!
      #expect(
        Draft.apply(key, to: c.draft) == c.out,
        "\(c.key) on \(c.draft.debugDescription)")
    }
  }

  @Test("a command key never edits the draft")
  func commandsAreNotEdits() {
    for key in Key.allCases where key.isCommand {
      #expect(Draft.apply(key, to: "12.5") == nil, "\(key.rawValue)")
    }
    #expect(Key.allCases.filter(\.isCommand).map(\.rawValue).sorted() == ["AC", "ref", "↵"])
  }

  @Test("typing a line, keystroke by keystroke")
  func sequences() {
    for s in draftFixture.sequences {
      var d = ""
      for step in s.steps {
        if let next = Draft.apply(Key(rawValue: step.key)!, to: d) { d = next }
        #expect(d == step.draft, "\(s.name): after \(step.key.debugDescription)")
      }
    }
  }

  @Test("backspace takes a whole pill, or one character")
  func backspace() {
    for b in draftFixture.backspace {
      #expect(Draft.apply(.backspace, to: b.draft) == b.out, Comment(rawValue: b.draft.debugDescription))
    }
  }

  @Test("inserting a reference")
  func inserts() {
    for i in draftFixture.inserts {
      #expect(Draft.insertRef(i.id, into: i.draft) == i.out, "\(i.id) into \(i.draft.debugDescription)")
    }
  }

  @Test("the draft's rendered length, and the one size step it drives")
  func sizing() {
    let nameFor = { (id: String) in draftFixture.names[id] ?? "#?" }
    for s in draftFixture.sizes {
      #expect(Draft.length(s.expr, nameFor: nameFor) == s.length, Comment(rawValue: s.expr.debugDescription))
      #expect(
        Draft.fontSize(forLength: s.length) == CGFloat(s.size), Comment(rawValue: s.expr.debugDescription))
    }
  }

  // The rules most likely to be "tidied" by someone who has not read the
  // fixture, stated once in plain Swift so they survive a refactor.
  @Test("the rules a reader would otherwise have to infer")
  func namedRules() {
    // An operator on an empty draft: only minus survives, as a unary sign.
    #expect(Draft.apply(.minus, to: "") == "−")
    #expect(Draft.apply(.plus, to: "") == "")
    #expect(Draft.apply(.multiply, to: "") == "")

    // An operator onto a trailing operator replaces it.
    #expect(Draft.apply(.multiply, to: "5+") == "5×")

    // Percent needs a digit to apply to.
    #expect(Draft.apply(.percent, to: "") == "")
    #expect(Draft.apply(.percent, to: "5+") == "5+")
    #expect(Draft.apply(.percent, to: "20") == "20%")

    // The dot looks at the current term, not the whole draft.
    #expect(Draft.apply(.dot, to: "1.5+2") == "1.5+2.")
    #expect(Draft.apply(.dot, to: "1.5") == "1.5")
    #expect(Draft.apply(.dot, to: "") == "0.")
    #expect(Draft.apply(.dot, to: "{e101}") == "{e101}", "a pill is a finished number")

    // A digit after a pill starts a new term.
    #expect(Draft.apply(.seven, to: "{e101}") == "{e101}+7")

    // Backspace takes the pill whole.
    #expect(Draft.apply(.backspace, to: "2+{e101}") == "2+")
    #expect(Draft.apply(.backspace, to: "{notapill}") == "{notapill", "not a pill: one character")
    #expect(Draft.apply(.backspace, to: "") == "")
  }

  @Test("the pad is the shape the design draws")
  func padShape() {
    #expect(Key.rows.count == 5)
    #expect(Key.rows.allSatisfy { $0.count == 4 })
    #expect(Key.rows.flatMap { $0 }.count == Key.allCases.count)
    // Top row matches the iOS Calculator's, so muscle memory transfers.
    #expect(Key.rows[0] == [.backspace, .clear, .percent, .divide])
  }
}
