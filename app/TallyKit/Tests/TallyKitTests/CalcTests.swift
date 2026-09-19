// CalcTests.swift — the Swift engine against the golden fixture produced
// by running the original TypeScript engine (Tools/gen-engine-fixture.mjs).
//
// There are no hand-written expectations here on purpose. The engine decides
// what people's money adds up to, and the same expressions are re-rendered by
// the web share page, so "looks right" is not the bar — every case has to agree
// with what the shipped app actually produced, digit for digit.
import Foundation
import Testing

@testable import TallyKit

struct Fixture: Decodable {
  struct Segment: Decodable {
    let text: String?
    let ref: String?
  }
  struct Case: Decodable {
    let expr: String
    let value: Double?
    let refs: [String]
    let hasOperator: Bool
    let segments: [Segment]
    let text: String
  }
  struct Number: Decodable {
    /// A finite value, or "Infinity" / "-Infinity" / "NaN" — neither of which
    /// JSON can carry.
    let n: JSONNumber
    let fmt: String
    let plain: String?
    /// Marked where the Swift port deliberately differs; see the generator.
    let divergent: Bool?
  }

  let version: Int
  let refs: [String: Double]
  let names: [String: String]
  let cases: [Case]
  let numbers: [Number]
}

/// A number that may arrive as a JSON number or as a tagged non-finite string.
enum JSONNumber: Decodable {
  case value(Double)

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let d = try? c.decode(Double.self) {
      self = .value(d)
    } else {
      switch try c.decode(String.self) {
      case "Infinity": self = .value(.infinity)
      case "-Infinity": self = .value(-.infinity)
      default: self = .value(.nan)
      }
    }
  }

  var double: Double {
    if case .value(let d) = self { return d }
    return .nan
  }
}

let fixture: Fixture = {
  let url = Bundle.module.url(forResource: "Fixtures/engine", withExtension: "json")!
  return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
}()

/// The resolver the fixture was generated against. An id that isn't in the
/// table is unresolvable, which must poison the expression holding it.
func fixtureResolve(_ id: String) -> Double? { fixture.refs[id] }
func fixtureName(_ id: String) -> String { fixture.names[id] ?? "#?" }

@Suite("Calc engine, against the TypeScript original")
struct CalcTests {

  @Test("the fixture is the shape this suite was written for")
  func fixtureVersion() {
    #expect(fixture.version == 1)
    #expect(fixture.cases.count > 2000)
  }

  // Compared exactly, not with a tolerance: both engines perform the same
  // operations in the same order on the same doubles, so any difference at all
  // means the port reordered something.
  @Test("evaluate")
  func evaluate() {
    for c in fixture.cases {
      let got = Calc.evaluate(c.expr, resolve: fixtureResolve)
      #expect(got == c.value, "evaluate(\(c.expr.debugDescription))")
    }
  }

  @Test("refs(in:)")
  func refs() {
    for c in fixture.cases {
      #expect(Calc.refs(in: c.expr) == c.refs, "refs(\(c.expr.debugDescription))")
    }
  }

  @Test("hasOperator")
  func hasOperator() {
    for c in fixture.cases {
      #expect(
        Calc.hasOperator(c.expr) == c.hasOperator, "hasOperator(\(c.expr.debugDescription))")
    }
  }

  @Test("split")
  func split() {
    for c in fixture.cases {
      let expected: [Calc.Segment] = c.segments.map {
        if let t = $0.text { return .text(t) }
        return .ref($0.ref!)
      }
      #expect(Calc.split(c.expr) == expected, "split(\(c.expr.debugDescription))")
    }
  }

  @Test("text")
  func text() {
    for c in fixture.cases {
      #expect(
        Calc.text(c.expr, nameFor: fixtureName) == c.text, "text(\(c.expr.debugDescription))")
    }
  }

  @Test("fmt")
  func fmt() {
    for num in fixture.numbers where num.divergent != true {
      #expect(Calc.fmt(num.n.double) == num.fmt, "fmt(\(num.n.double))")
    }
  }

  @Test("plain")
  func plain() {
    for num in fixture.numbers where num.divergent != true {
      guard let expected = num.plain else { continue }  // non-finite: not plain's job
      #expect(Calc.plain(num.n.double) == expected, "plain(\(num.n.double))")
    }
  }

  @Test("the one divergence from the original is the one we documented")
  func documentedDivergence() {
    // JavaScript's toFixed goes exponential at 1e21, and the original fmt then
    // prints the string "1e+21.undefined". This formats it properly.
    let divergent = fixture.numbers.filter { $0.divergent == true }
    #expect(divergent.count == 1)
    #expect(divergent.first?.fmt == "1e+21.undefined")
    #expect(Calc.fmt(1e21) == "1,000,000,000,000,000,000,000.00")
  }

  @Test("nil and empty are not zero")
  func emptyIsNil() {
    #expect(Calc.evaluate(nil) == nil)
    #expect(Calc.evaluate("") == nil)
    #expect(Calc.fmt(nil) == "0.00")
  }
}
