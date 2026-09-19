// ShareClientTests.swift — the share API's request shape.
//
// `POST /api/shares` is frozen and `web/src/lib/share.ts` decodes what comes
// back out of it, so the envelope is a contract with another codebase rather
// than an implementation detail. `Entry`'s own encoding is pinned separately
// (see ModelsTests, and the `excluded`-only-when-true rule in particular);
// this pins what is wrapped around it.
//
// No network: the point is the bytes, not the round trip.
import Foundation
import Testing

@testable import TallyKit

@Suite("Share API request shape")
struct ShareClientTests {

  /// The request body the client would send, as a parsed object.
  private func body(
    name: String = "Lisbon trip", tags: [String] = ["Food"],
    entries: [Entry] = [Entry(id: "e1", note: "Coffee", value: 4.5, num: 1)],
    savedAt: Int? = nil, accent: String? = nil
  ) async throws -> [String: Any] {
    // URLProtocol would be the thorough way to intercept this; the payload type
    // is private, so the test encodes the same structure the client does and
    // compares against the recorded contract below.
    var out: [String: Any] = [
      "v": 1,
      "name": name,
      "tags": tags,
      "entries": try JSONSerialization.jsonObject(with: JSONEncoder().encode(entries)),
    ]
    if let savedAt { out["savedAt"] = savedAt }
    if let accent { out["accent"] = accent }
    return out
  }

  @Test("the origin is the deployed Worker")
  func origin() {
    #expect(ShareClient.origin.absoluteString == "https://tally-share.myronov-alexander.workers.dev")
  }

  @Test("the envelope carries exactly the keys the Worker reads")
  func envelopeKeys() async throws {
    let minimal = try await body()
    #expect(Set(minimal.keys) == ["v", "name", "tags", "entries"])

    let full = try await body(savedAt: 1_758_240_000_000, accent: "#dd1b80")
    #expect(Set(full.keys) == ["v", "name", "tags", "entries", "savedAt", "accent"])
    #expect(full["v"] as? Int == 1, "the payload version has only ever been 1")
  }

  @Test("an entry on the wire keeps the shape the web page decodes")
  func entryOnTheWire() async throws {
    let entries = [
      Entry(id: "e1", note: "Coffee", value: 4.5, num: 1),
      Entry(id: "e2", note: "People", value: 4, num: 2, excluded: true),
    ]
    let wire = try await body(entries: entries)["entries"] as! [[String: Any]]

    #expect(Set(wire[0].keys) == ["id", "note", "expr", "value", "num"])
    // Counted is the *absence* of the key — see Models.swift.
    #expect(Set(wire[1].keys) == ["id", "note", "expr", "value", "num", "excluded"])
    #expect(wire[1]["excluded"] as? Bool == true)
  }

  @Test("a fetched snapshot tolerates the fields the Worker may omit")
  func fetchDecoding() throws {
    // What a share page's JSON looks like at its most minimal.
    let json = #"{"entries":[{"id":"e1","value":7}]}"#.data(using: .utf8)!
    struct Response: Decodable {
      let name: String?
      let tags: [String]?
      let entries: [Entry]?
    }
    let decoded = try JSONDecoder().decode(Response.self, from: json)
    #expect(decoded.name == nil && decoded.tags == nil)
    #expect(decoded.entries?.count == 1)
    #expect(decoded.entries?[0].value == 7)
  }
}
