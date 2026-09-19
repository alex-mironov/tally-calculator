// ShareClient.swift — client for the tally-share Worker (web/ in this repo).
//
// Sharing POSTs a frozen snapshot of the tab and hands back a public link;
// importing (tally://share/<id>) fetches the snapshot and re-ids it locally.
// The snapshot is frozen at the moment of sharing — later edits here don't
// travel.
//
// ── The wire shape is not ours to change ────────────────────────────────────
// `POST /api/shares` is frozen, and `web/src/lib/share.ts` decodes what goes
// into it. `Entry`'s encoding already matches (see Models.swift, and the
// `excluded`/`error`-only-when-true rule in particular); this adds the envelope
// around it.
import Foundation

public enum ShareClient {

  public static let origin = URL(string: "https://tally-share.myronov-alexander.workers.dev")!

  public struct Snapshot: Sendable {
    public let name: String
    public let tags: [String]
    public let entries: [Entry]

    public init(name: String, tags: [String], entries: [Entry]) {
      self.name = name
      self.tags = tags
      self.entries = entries
    }
  }

  public enum ShareError: Error, LocalizedError {
    case notFound
    case badSnapshot
    case server(Int)
    case noURL

    public var errorDescription: String? {
      switch self {
      case .notFound: return "That link has expired."
      case .badSnapshot: return "That link didn’t contain a calculation."
      case .server(let code): return "The server said \(code)."
      case .noURL: return "The server didn’t return a link."
      }
    }
  }

  /// What `POST /api/shares` takes. `v` is the payload version the Worker
  /// switches on; it has only ever been 1.
  private struct Payload: Encodable {
    let v = 1
    let name: String
    let tags: [String]
    let entries: [Entry]
    let savedAt: Int?
    /// The sender's accent hex — themes the web page to match their app.
    let accent: String?
  }

  private struct CreateResponse: Decodable {
    let url: String?
  }

  private struct FetchResponse: Decodable {
    let name: String?
    let tags: [String]?
    let entries: [Entry]?
  }

  /// POST the snapshot; returns the public share URL.
  public static func createLink(
    name: String, tags: [String], entries: [Entry], savedAt: Int? = nil, accent: String? = nil,
    session: URLSession = .shared
  ) async throws -> URL {
    var request = URLRequest(url: origin.appending(path: "api/shares"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      Payload(name: name, tags: tags, entries: entries, savedAt: savedAt, accent: accent))

    let (data, response) = try await session.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(code) else { throw ShareError.server(code) }

    guard let raw = try JSONDecoder().decode(CreateResponse.self, from: data).url,
      let url = URL(string: raw)
    else { throw ShareError.noURL }
    return url
  }

  /// Fetch a shared snapshot back, for import.
  public static func fetch(id: String, session: URLSession = .shared) async throws -> Snapshot {
    let path = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let (data, response) = try await session.data(from: origin.appending(path: "api/shares/\(path)"))
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    if code == 404 { throw ShareError.notFound }
    guard (200..<300).contains(code) else { throw ShareError.server(code) }

    let decoded = try JSONDecoder().decode(FetchResponse.self, from: data)
    guard let entries = decoded.entries else { throw ShareError.badSnapshot }
    return Snapshot(name: decoded.name ?? "", tags: decoded.tags ?? [], entries: entries)
  }
}
