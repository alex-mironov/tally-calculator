// LinksTests.swift — Calculator v2's brackets and live links
// (tally-links.jsx): brackets in the engine, the bracket keys, link mode's
// toggle, the Group first chip, and the brackets-key preference. None of this
// is in the TypeScript fixtures, which predate it, so the rules are stated here.
import Foundation
import Testing

@testable import TallyKit

@Suite("Brackets and links")
struct LinksTests {

  // MARK: - The engine

  @Test("brackets evaluate first")
  func brackets() {
    #expect(Calc.evaluate("(42.8+9)×10%") == 5.18)
    #expect(Calc.evaluate("2×(3+4)") == 14)
    #expect(Calc.evaluate("(1+2)×(3+4)") == 21)
    #expect(Calc.evaluate("((2))") == 2)
    #expect(Calc.evaluate("−(2+3)") == -5)
    #expect(Calc.evaluate("10−(2+3)") == 5)
  }

  @Test("an incomplete bracket is tolerated as the keypad leaves it")
  func incomplete() {
    #expect(Calc.evaluate("(42.8+9") == 51.8, "an open bracket closes at the end")
    #expect(Calc.evaluate("5×(") == 5, "an empty bracket is dropped like a trailing operator")
    #expect(Calc.evaluate("5×(2+") == 10)
    #expect(Calc.evaluate("(") == nil)
    #expect(Calc.evaluate("5)") == nil, "a stray close has nothing to close")
  }

  @Test("percent after a bracket, and inside one")
  func percent() {
    #expect(Calc.evaluate("200+(5+5)%") == 220, "a bracket's percent is of the left-hand side")
    #expect(Calc.evaluate("(200+10%)") == 220)
    #expect(Calc.evaluate("(50)%") == 0.5)
  }

  @Test("references inside brackets resolve, and still poison when they can't")
  func references() {
    let vals = ["e1": 18.2, "e2": 9.0]
    #expect(Calc.evaluate("({e1}+{e2})×2") { vals[$0] } == 54.4)
    #expect(Calc.evaluate("({e1}+{e9})×2") { vals[$0] } == nil)
  }

  @Test("division by zero inside a bracket is still nil")
  func divideByZero() {
    #expect(Calc.evaluate("2×(1÷0)") == nil)
  }

  @Test("an operation reaching a bracket counts as maths")
  func hasOperator() {
    #expect(Calc.hasOperator("(1+2)×3"))
    #expect(Calc.hasOperator("(5)×(3)"))
    #expect(!Calc.hasOperator("(5)"))
  }

  // MARK: - The bracket keys

  @Test("the brackets key opens or closes as it makes sense")
  func bracketsKey() {
    #expect(Draft.apply(.brackets, to: "") == "(")
    #expect(Draft.apply(.brackets, to: "42.8+") == "42.8+(")
    #expect(Draft.apply(.brackets, to: "2") == "2×(", "after a value it multiplies")
    #expect(Draft.apply(.brackets, to: "(42.8+9") == "(42.8+9)")
    #expect(Draft.apply(.brackets, to: "(42.8+") == "(42.8+(", "nothing to close after an operator")
    #expect(Draft.apply(.brackets, to: "(1+2)") == "(1+2)×(")
  }

  @Test("a hardware keyboard's own brackets")
  func keyboardBrackets() {
    #expect(Draft.apply(.open, to: "{e1}") == "{e1}×(")
    #expect(Draft.apply(.close, to: "(1+2") == "(1+2)")
    #expect(Draft.apply(.close, to: "1+2") == "1+2", "nothing open")
    #expect(Draft.apply(.close, to: "(1+") == "(1+", "not after an operator")
  }

  @Test("what may follow a bracket")
  func afterBrackets() {
    #expect(Draft.apply(.minus, to: "(") == "(−", "a sign")
    #expect(Draft.apply(.plus, to: "(") == "(")
    #expect(Draft.apply(.multiply, to: "(−") == "(", "the sign goes for any other operator")
    #expect(Draft.apply(.minus, to: "(−") == "(−")
    #expect(Draft.apply(.seven, to: "(1+2)") == "(1+2)×7")
    #expect(Draft.apply(.dot, to: "(1+2)") == "(1+2)×0.")
    #expect(Draft.apply(.dot, to: "(") == "(0.")
    #expect(Draft.apply(.percent, to: "(1+2)") == "(1+2)%")
    #expect(Draft.insertRef("e1", into: "2×(") == "2×({e1}")
  }

  @Test("open brackets are counted outside tokens")
  func openCount() {
    #expect(Draft.openCount("((1+2)") == 1)
    #expect(Draft.openCount("1+2") == 0)
    #expect(Draft.openCount("({e1}") == 1)
  }

  @Test("a draft is tidied as it is filed")
  func normalized() {
    #expect(Draft.normalized("(1+2") == "(1+2)")
    #expect(Draft.normalized("5+3+") == "5+3")
    #expect(Draft.normalized("5×(") == "5")
    #expect(Draft.normalized("((1+2)×(") == "((1+2))")
    #expect(Draft.normalized("{e1}×10%") == "{e1}×10%")
  }

  // MARK: - Link mode

  @Test("a tap links a line, and a second tap unlinks it with its operator")
  func toggle() {
    var d = ""
    d = Draft.toggleRef("e2", in: d)
    #expect(d == "{e2}")
    d = Draft.toggleRef("e4", in: d)
    #expect(d == "{e2}+{e4}")
    d = Draft.toggleRef("e2", in: d)
    #expect(d == "{e4}", "the operator after it goes when there is none before")
    d = Draft.apply(.multiply, to: d)!
    d = Draft.toggleRef("e1", in: d)
    #expect(d == "{e4}×{e1}")
    d = Draft.toggleRef("e1", in: d)
    #expect(d == "{e4}", "the operator before it goes with it")
    #expect(Draft.toggleRef("e4", in: d) == "")
    #expect(Draft.toggleRef("e3", in: "12") == "12+{e3}")
  }

  @Test("a draft with links steps between its own two sizes")
  func linkedSize() {
    let name = { (_: String) in "Taxi" }
    // A pill counts as nine characters, so one link is 9 and two are 19.
    #expect(Draft.fontSize(for: "{e4}×10%", nameFor: name) == 32)
    #expect(Draft.fontSize(for: "{e2}+{e4}", nameFor: name) == 28)
    #expect(Draft.fontSize(for: "1200+45", nameFor: name) == 44, "no links: the usual steps")
  }

  // MARK: - Group first

  @Test("Group first brackets the sum ahead of × or ÷")
  func groupFirst() {
    #expect(Draft.groupedFirst("42.8+9×10%") == "(42.8+9)×10%")
    #expect(Draft.groupedFirst("1+2+3÷4") == "(1+2+3)÷4")
    #expect(Draft.groupedFirst("{e1}+{e2}×2") == "({e1}+{e2})×2")
    #expect(Draft.groupedFirst("2×3") == nil, "no sum to group")
    #expect(Draft.groupedFirst("1+2") == nil, "nothing after it to group for")
    #expect(Draft.groupedFirst("−2×3") == nil, "a leading sign is not a sum")
    #expect(Draft.groupedFirst("(1+2)×3") == nil, "already grouped")
  }

  @Test("Ungroup is the way back")
  func ungroup() {
    #expect(Draft.ungrouped("(42.8+9)×10%") == "42.8+9×10%")
    #expect(Draft.ungrouped("(1+2)+3") == nil)
    #expect(Draft.ungrouped("1+(2)×3") == nil)
    #expect(Draft.ungrouped("({e1}+2)÷2") == "{e1}+2÷2")
  }
}

@MainActor
@Suite("The brackets-key preference")
struct BracketsKeyPreferenceTests {
  @Test("is off by default, persists, and survives a document without it")
  func preference() {
    let kv = MemoryStore()
    let store = TallyStore(storage: Storage(local: kv), seeded: false)
    store.load()
    #expect(store.bracketsKey == false)
    store.setBracketsKey(true)
    #expect(kv.values["tally:config"]?.contains("\"bracketsKey\":true") == true)

    // An older build writes the config back without the key.
    store.apply(.config, #"{"showExpr":true,"showTotal":true,"activeId":null}"#)
    #expect(store.bracketsKey == true)
  }
}
