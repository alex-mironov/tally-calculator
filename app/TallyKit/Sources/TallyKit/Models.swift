// Models.swift — the persisted and shared shapes: a line, a saved calculation,
// and the preferences blob.
//
// ── Why the hand-written coding ─────────────────────────────────────────────
// These types are not free to be whatever Swift finds convenient. The same JSON
// is read and written by three other things:
//
//   · the iCloud key-value store, which is *shared* with the React Native build
//     — mid-rollout a user may have the old app on one device and this one on
//     another, and each has to read what the other wrote;
//   · the share API (`POST /api/shares`), which is frozen;
//   · the web share page (web/src/lib/share.ts), which decodes `Entry` directly.
//
// The trap is `excluded` and `error`. The original writes them only when true
// (`...(e.excluded ? { excluded: true } : null)`), so "counted" is the *absence*
// of the key. Swift's synthesised `Codable` would happily write
// `"excluded": false`, which the web page's `e.excluded ? …` reads the same way
// — but it inflates every payload and, more to the point, means the two sides
// are no longer writing the same document. So the encoding is explicit, and
// `EntryCodingTests` holds it to the original's output byte for byte.
import Foundation

/// One line of a running tab.
public struct Entry: Identifiable, Equatable, Codable, Sendable {
  public var id: String
  /// short label, e.g. "Coffee" — may be empty
  public var note: String
  /**
   The raw expression when it's more than a plain number, e.g. "60÷4". May
   embed reference tokens — `{e123}` for another line's value, `{sum}` for the
   running total of the lines above — which keep the value live.
   */
  public var expr: String
  public var value: Double
  /**
   Sticky line number, assigned once at commit and never reshuffled — deleting
   line 2 leaves a gap rather than renaming every reference. Older persisted
   entries may lack it; the pipeline backfills in order.
   */
  public var num: Int?
  /**
   Left out of the total and of `{sum}` — an input other lines reference
   ("People 4"), a subtotal mirror, a number that is really a note. Still
   referenceable, still shown, drawn muted. Absent means counted, and it is
   written only when true.
   */
  public var excluded: Bool?
  /**
   Set by the recalc pass when the expression can no longer be evaluated — a
   token that resolves to nothing, or a division by a line that went to zero.
   `value` is 0 while this is set, so nothing stale leaks into the total.
   Written only when true.
   */
  public var error: Bool?

  public init(
    id: String, note: String = "", expr: String = "", value: Double,
    num: Int? = nil, excluded: Bool? = nil, error: Bool? = nil
  ) {
    self.id = id
    self.note = note
    self.expr = expr
    self.value = value
    self.num = num
    self.excluded = excluded
    self.error = error
  }

  enum CodingKeys: String, CodingKey { case id, note, expr, value, num, excluded, error }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    // Tolerated as missing: JavaScript reads `e.note` and `e.expr` as falsy
    // when absent, so data written by any older build must still load.
    note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    expr = try c.decodeIfPresent(String.self, forKey: .expr) ?? ""
    value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
    num = try c.decodeIfPresent(Int.self, forKey: .num)
    // `excluded: false` is not something this app writes, but a hand-edited or
    // future payload could carry it — normalise it back to absent so a
    // round-trip is stable.
    excluded = (try c.decodeIfPresent(Bool.self, forKey: .excluded) == true) ? true : nil
    error = (try c.decodeIfPresent(Bool.self, forKey: .error) == true) ? true : nil
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    // Encoded in the original's key order. Nothing depends on it — JSON is
    // unordered — but a diff of two payloads should be about the values.
    try c.encode(id, forKey: .id)
    try c.encode(note, forKey: .note)
    try c.encode(expr, forKey: .expr)
    try c.encode(value, forKey: .value)
    try c.encodeIfPresent(num, forKey: .num)
    if excluded == true { try c.encode(true, forKey: .excluded) }
    if error == true { try c.encode(true, forKey: .error) }
  }

  /// Counted lines are those not explicitly excluded. A line in error carries 0.
  public var isCounted: Bool { excluded != true }
}

/// The total of a list: every counted line.
public func totalOf(_ list: [Entry]) -> Double {
  list.reduce(0) { $0 + ($1.isCounted ? $1.value : 0) }
}

/// A saved calculation — a named, optionally tagged snapshot of a tab.
public struct Tab: Identifiable, Equatable, Codable, Sendable {
  public var id: String
  public var name: String
  /// Tag names filed on this tab; empty when untagged.
  public var tags: [String]
  public var entries: [Entry]
  /// Milliseconds since the epoch, matching JavaScript's `Date.now()`.
  public var savedAt: Int
  /**
   Legacy singular tag written by builds before multi-tagging. Read through
   `resolvedTags`; never written by this app, but preserved on decode so a tab
   this device merely *reads* doesn't lose it for the older build still syncing
   against the same iCloud store.
   */
  public var legacyTag: String?

  public init(
    id: String, name: String, tags: [String] = [], entries: [Entry] = [],
    savedAt: Int, legacyTag: String? = nil
  ) {
    self.id = id
    self.name = name
    self.tags = tags
    self.entries = entries
    self.savedAt = savedAt
    self.legacyTag = legacyTag
  }

  enum CodingKeys: String, CodingKey {
    case id, name, tags, entries, savedAt
    case legacyTag = "tag"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
    savedAt = try c.decodeIfPresent(Int.self, forKey: .savedAt) ?? 0
    legacyTag = try c.decodeIfPresent(String.self, forKey: .legacyTag)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(tags, forKey: .tags)
    try c.encode(entries, forKey: .entries)
    try c.encode(savedAt, forKey: .savedAt)
    try c.encodeIfPresent(legacyTag, forKey: .legacyTag)
  }

  /**
   This tab's tags, however they were stored. New tabs carry `tags`; older ones
   had a singular `tag`. Nothing is bulk-migrated — `tags` is written the next
   time the tab is touched, which is what `migrated(to:)` does.
   */
  public var resolvedTags: [String] {
    if !tags.isEmpty { return tags }
    if let legacyTag, !legacyTag.isEmpty { return [legacyTag] }
    return []
  }

  /// The same tab with `tags` set and the legacy singular dropped — used
  /// whenever a tab is being rewritten anyway.
  public func migrated(to tags: [String]) -> Tab {
    var out = self
    out.tags = tags
    out.legacyTag = nil
    return out
  }

  public var total: Double { totalOf(entries) }
}

// MARK: - Tag names

/// Trim, collapse whitespace and cap length so names stay chip-sized.
public func normalizeTagName(_ raw: String) -> String {
  let collapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  return String(collapsed.prefix(22))
}

/// Case-insensitive de-dupe that keeps the first spelling seen.
public func dedupeTags(_ names: [String]) -> [String] {
  var seen = Set<String>()
  var out: [String] = []
  for n in names where seen.insert(n.lowercased()).inserted { out.append(n) }
  return out
}
