// PipelineTests.swift — the reference pipeline against the golden fixture
// produced by running the original TypeScript (Tools/gen-pipeline-fixture.mjs).
//
// Same bar as the engine: no hand-written expectations. These three passes
// decide what happens to a user's saved work when a referenced line is deleted,
// and getting them subtly wrong would corrupt tabs rather than crash.
import Foundation
import Testing

@testable import TallyKit

struct PipelineFixture: Decodable {
  struct Case: Decodable {
    let name: String
    let prev: [Entry]
    let next: [Entry]
    let out: [Entry]
  }
  let version: Int
  let cases: [Case]
}

let pipelineFixture: PipelineFixture = {
  let url = Bundle.module.url(forResource: "Fixtures/pipeline", withExtension: "json")!
  return try! JSONDecoder().decode(PipelineFixture.self, from: Data(contentsOf: url))
}()

@Suite("Reference pipeline, against the TypeScript original")
struct PipelineTests {

  @Test("the fixture is the shape this suite was written for")
  func fixtureVersion() {
    #expect(pipelineFixture.version == 1)
    #expect(pipelineFixture.cases.count > 400)
  }

  @Test("pipeline(from:to:)")
  func wholePass() {
    for c in pipelineFixture.cases {
      #expect(pipeline(from: c.prev, to: c.next) == c.out, "\(c.name)")
    }
  }

  // The named scenarios are the ones a reader should be able to find by name
  // when a rule is questioned later; the randomised bulk is covered above.
  @Test("every named scenario, reported individually")
  func namedScenarios() {
    for c in pipelineFixture.cases where !c.name.hasPrefix("random #") {
      let got = pipeline(from: c.prev, to: c.next)
      #expect(got == c.out, "\(c.name)\n  got:      \(got)\n  expected: \(c.out)")
    }
  }

  @Test("a counted line is one that is not explicitly excluded")
  func counting() {
    let list = [
      Entry(id: "a", value: 10),
      Entry(id: "b", value: 4, excluded: true),
      Entry(id: "c", value: 1),
    ]
    #expect(totalOf(list) == 11)
    #expect(list.filter(\.isCounted).count == 2)
  }
}
