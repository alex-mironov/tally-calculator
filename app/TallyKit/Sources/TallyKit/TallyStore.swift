// TallyStore.swift — shared state for the running tab: the live list of
// entries, the saved-tabs archive, the tag catalog and the user's preferences.
//
// Ported from mobile/src/lib/tally-store.tsx, where it was a React context. The
// React version is full of notes about keeping the React Compiler happy — no
// lint suppressions, no `try/finally`, no hoisted functions reached from an
// effect — none of which apply here; what survives is the behaviour those
// contortions were protecting.
//
// The one rule worth restating: **every write to the live list goes through
// `pipeline(from:to:)`** (see Pipeline.swift), so the reference invariants hold
// no matter which screen made the change. Nothing assigns to `entries` directly.
import Foundation
import Observation

@MainActor
@Observable
public final class TallyStore {

  // MARK: - The live tab

  public private(set) var entries: [Entry] = []

  /// The total of the live tab: every counted line.
  public var total: Double { totalOf(entries) }

  // MARK: - Saved tabs

  /// The archive as stored. `tabs` folds the live edits into the active one.
  private var rawTabs: [Tab] = []
  public private(set) var activeID: String?

  /**
   Bumped every time the working tab is swapped out from under the editor —
   opened, replaced by a new one, or deleted.

   `activeID` cannot stand in for this: starting a new tab while already on an
   unsaved one leaves it nil on both sides, so a watcher keyed on it would miss
   the swap entirely. Anything holding uncommitted state about the tab (the
   calculator's draft line) resets when this changes.
   */
  public private(set) var tabEpoch = 0

  public private(set) var tabName = ""
  /// Tags on the live (in-progress or active) tab.
  public private(set) var tags: [String] = []

  /**
   The archive, with the live edits folded into whichever tab is active.

   The active tab's authoritative state is `entries` / `tabName` / `tags`; that
   is folded in on read rather than mirrored back into `rawTabs`, which keeps
   the Saved list and the on-disk copy in step without duplicating state.
   Deliberately does *not* touch `savedAt` — reading a tab is not saving it.
   */
  public var tabs: [Tab] {
    guard let activeID else { return rawTabs }
    return rawTabs.map { tb in
      guard tb.id == activeID else { return tb }
      var out = tb.migrated(to: tags)
      out.name = tabName
      out.entries = entries
      return out
    }
  }

  // MARK: - Tag catalog

  /// Seed catalog of known tag names, shared across every tab.
  static let defaultCatalog = ["Trip", "Bills", "Food", "Work", "Personal"]
  public private(set) var catalog: [String] = TallyStore.defaultCatalog

  // MARK: - Preferences

  public private(set) var themeMode: ThemeMode = .light
  /// The chosen accent's hue, as a hex string. Always a resolved one.
  public private(set) var accentHex: String = Accent.default.accent
  public var accent: Accent { Accent.resolve(accentHex) }
  public private(set) var showExpr = true
  public private(set) var showTotal = true

  // MARK: - Identity

  /**
   Entry ids are `e`-prefixed and minted in sequence, starting past anything
   already on disk (see `syncIDCounter`). In the React version this counter was
   module-global; here it belongs to the store, which is the only minter.
   */
  private var lastID = 100

  public func mintID() -> String {
    lastID += 1
    return "e\(lastID)"
  }

  /// Keep the id counter ahead of any persisted ids so new rows never collide.
  private func syncIDCounter(_ entries: [Entry]) {
    for e in entries {
      guard e.id.hasPrefix("e"), let n = Int(e.id.dropFirst()) else { continue }
      lastID = max(lastID, n)
    }
  }

  // MARK: - Lifecycle

  private let storage: Storage
  /// Nothing is persisted until the first load has finished, or the seed and
  /// the defaults would clobber what is already on disk before hydration ends.
  private var hydrated = false

  public init(storage: Storage, seeded: Bool = true) {
    self.storage = storage
    if seeded { entries = pipeline(from: [], to: TallyStore.seed()) }
  }

  /// The sample tab a fresh install opens on.
  static func seed() -> [Entry] {
    [
      Entry(id: "e1", note: "Coffee", value: 4.5),
      Entry(id: "e2", note: "Groceries", value: 42.2),
      Entry(id: "e3", note: "Taxi home", value: 18),
      Entry(id: "e4", note: "Dinner · split 4", expr: "60÷4", value: 15),
      Entry(id: "e5", note: "Gig tickets ×2", expr: "45×2", value: 90),
    ]
  }

  /// Read everything off disk, then start listening for pushes from the user's
  /// other devices. Call once, at launch.
  public func load() {
    let stored = storage.all()
    for key in StorageKey.allCases { apply(key, stored[key]) }
    hydrated = true

    storage.observeExternalChanges { [weak self] changed in
      guard let self else { return }
      for key in changed { self.apply(key, self.storage.string(for: key)) }
    }
  }

  // MARK: - Hydration

  /**
   Fold one persisted document into state. Shared by the initial load and by
   live iCloud pushes, so both paths stay identical.

   A missing, corrupt or wrongly shaped value leaves the current state alone
   rather than resetting it — a half-synced or hand-edited document should cost
   the user nothing.
   */
  // Not private: the tests drive this directly to stand in for an iCloud push,
  // which is otherwise only reachable through a real ubiquitous store.
  func apply(_ key: StorageKey, _ raw: String?) {
    guard let data = raw?.data(using: .utf8) else { return }
    let decoder = JSONDecoder()

    switch key {
    case .entries:
      guard let list = try? decoder.decode([Entry].self, from: data) else { return }
      syncIDCounter(list)
      setEntries(list)

    case .tabs:
      guard let list = try? decoder.decode([Tab].self, from: data) else { return }
      list.forEach { syncIDCounter($0.entries) }
      rawTabs = list

    case .catalog:
      guard let names = try? decoder.decode(CatalogDocument.self, from: data).names,
        !names.isEmpty
      else { return }
      catalog = dedupeTags(names)

    case .config:
      guard let c = try? decoder.decode(ConfigDocument.self, from: data) else { return }
      if let mode = c.themeMode { themeMode = mode }
      // Through `resolve`, so a hex from the retired palette lands on its
      // replacement instead of snapping everyone back to the default.
      if let hex = c.accent { accentHex = Accent.resolve(hex).accent }
      if let v = c.showExpr { showExpr = v }
      if let v = c.showTotal { showTotal = v }
      if c.hasActiveIDKey { activeID = c.activeId }
      if let name = c.tabName { tabName = name }
      if let t = c.tags { tags = t }
      else if let legacy = c.tag, !legacy.isEmpty { tags = [legacy] }
    }
  }

  // MARK: - Persistence

  private func write<T: Encodable>(_ value: T, to key: StorageKey) {
    guard hydrated, let data = try? JSONEncoder().encode(value),
      let json = String(data: data, encoding: .utf8)
    else { return }
    storage.set(json, for: key)
  }

  private func saveEntries() { write(entries, to: .entries) }
  private func saveTabs() { write(tabs, to: .tabs) }
  private func saveCatalog() { write(catalog.map(CatalogDocument.Item.init(name:)), to: .catalog) }

  private func saveConfig() {
    write(
      ConfigDocument(
        themeMode: themeMode, accent: accentHex, showExpr: showExpr, showTotal: showTotal,
        activeId: activeID, tabName: tabName, tags: tags),
      to: .config)
  }

  /// The live list is part of the active tab's stored snapshot, so a change to
  /// it is a change to two documents.
  private func saveLiveTab() {
    saveEntries()
    saveTabs()
  }

  // MARK: - Writing the live list

  /// Replace the live list. Always through the reference pipeline.
  public func setEntries(_ next: [Entry]) {
    entries = pipeline(from: entries, to: next)
    saveLiveTab()
  }

  /// Transform the live list. Always through the reference pipeline.
  public func updateEntries(_ transform: ([Entry]) -> [Entry]) {
    setEntries(transform(entries))
  }

  public func append(_ entry: Entry) {
    setEntries(entries + [entry])
  }

  public func replace(_ entry: Entry) {
    setEntries(entries.map { $0.id == entry.id ? entry : $0 })
  }

  public func delete(id: String) {
    setEntries(entries.filter { $0.id != id })
  }

  /**
   "Don't count in total" — the line stays, stays referenceable, and drops out
   of the total and of `{sum}`. That is what makes an input line ("People 4"), a
   subtotal mirror, or a number that is really a note possible without it adding
   itself to the bill.
   */
  public func toggleExcluded(id: String) {
    setEntries(
      entries.map { e in
        guard e.id == id else { return e }
        var out = e
        out.excluded = e.excluded == true ? nil : true
        return out
      })
  }

  // MARK: - Preferences

  public func setThemeMode(_ mode: ThemeMode) {
    themeMode = mode
    saveConfig()
  }

  public func setAccent(_ hex: String) {
    accentHex = Accent.resolve(hex).accent
    saveConfig()
  }

  public func setShowExpr(_ v: Bool) {
    showExpr = v
    saveConfig()
  }

  public func setShowTotal(_ v: Bool) {
    showTotal = v
    saveConfig()
  }

  // MARK: - The live tab's name and tags

  public func setTabName(_ name: String) {
    tabName = name
    saveConfig()
    saveTabs()
  }

  public func setTags(_ next: [String]) {
    tags = next
    saveConfig()
    saveTabs()
  }

  public func toggleTag(_ name: String) {
    setTags(tags.contains(name) ? tags.filter { $0 != name } : tags + [name])
  }

  /// Set the tags on any saved tab — or on the live tab when that tab is active.
  public func setTags(_ next: [String], forTab id: String) {
    if id == activeID {
      setTags(next)
      return
    }
    rawTabs = rawTabs.map { $0.id == id ? $0.migrated(to: next) : $0 }
    saveTabs()
  }

  // MARK: - The tag catalog
  //
  // The catalog is the source of truth for the chooser, the filter bar and
  // Settings. A tab may only reference catalog names, so creating a tag adds it
  // to the catalog first and then assigns it.

  /// Add a name to the catalog, or return the existing spelling of it.
  @discardableResult
  public func addCatalogTag(_ raw: String) -> String? {
    let name = normalizeTagName(raw)
    guard !name.isEmpty else { return nil }
    if let existing = catalog.first(where: { $0.lowercased() == name.lowercased() }) {
      return existing
    }
    catalog.append(name)
    saveCatalog()
    return name
  }

  /// Delete a catalog tag and cascade the removal to every tab that used it.
  public func removeCatalogTag(_ name: String) {
    catalog.removeAll { $0 == name }
    rawTabs = rawTabs.map { tb in
      let next = tb.resolvedTags.filter { $0 != name }
      return next.count == tb.resolvedTags.count && tb.legacyTag == nil ? tb : tb.migrated(to: next)
    }
    tags.removeAll { $0 == name }
    saveCatalog()
    saveConfig()
    saveTabs()
  }

  /// Rename a catalog tag and cascade the new name through every tab.
  public func renameCatalogTag(_ name: String, to rawNext: String) {
    let next = normalizeTagName(rawNext)
    guard !next.isEmpty, next != name else { return }
    let rename = { (arr: [String]) in dedupeTags(arr.map { $0 == name ? next : $0 }) }
    catalog = dedupeTags(catalog.map { $0 == name ? next : $0 })
    rawTabs = rawTabs.map { tb in
      tb.resolvedTags.contains(name) || tb.legacyTag == name
        ? tb.migrated(to: rename(tb.resolvedTags)) : tb
    }
    tags = rename(tags)
    saveCatalog()
    saveConfig()
    saveTabs()
  }

  // MARK: - Saving, opening and starting tabs

  /// The name a tab takes when the user never gave it one — today's date.
  func defaultTabName(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_GB")
    f.setLocalizedDateFormatFromTemplate("EEEdMMM")
    return f.string(from: date)
  }

  /**
   Commit the live tab as a saved snapshot.

   `name` and `tags` may be passed to apply a fresh name or tag set atomically —
   the save sheet hands back both at once, and reading them from state would
   read what has not been set yet.
   */
  public func saveDraft(name overrideName: String? = nil, tags overrideTags: [String]? = nil) {
    guard !entries.isEmpty else { return }
    let id = activeID ?? mintID()
    let nextTags = overrideTags ?? tags
    let trimmed = (overrideName ?? tabName).trimmingCharacters(in: .whitespacesAndNewlines)
    let name = trimmed.isEmpty ? defaultTabName() : trimmed

    let snap = Tab(
      id: id, name: name, tags: nextTags, entries: entries, savedAt: Self.now())
    if rawTabs.contains(where: { $0.id == id }) {
      rawTabs = rawTabs.map { $0.id == id ? snap : $0 }
    } else {
      rawTabs.insert(snap, at: 0)
    }
    activeID = id
    tabName = name
    tags = nextTags
    saveConfig()
    saveTabs()
  }

  /// Fold the current live edits back into whichever tab is being left.
  private func commitActive() {
    guard let activeID else {
      if !entries.isEmpty { saveDraft() }
      return
    }
    rawTabs = rawTabs.map { tb in
      guard tb.id == activeID else { return tb }
      var out = tb.migrated(to: tags)
      out.name = tabName
      out.entries = entries
      out.savedAt = Self.now()
      return out
    }
  }

  public func openTab(id: String) {
    guard id != activeID, let tb = rawTabs.first(where: { $0.id == id }) else { return }
    commitActive()  // never lose the tab being left
    setEntries(tb.entries)
    tabName = tb.name
    tags = tb.resolvedTags
    activeID = id
    swapTab()
  }

  public func newTab() {
    commitActive()
    setEntries([])
    tabName = ""
    tags = []
    activeID = nil
    swapTab()
  }

  public func deleteTab(id: String) {
    rawTabs.removeAll { $0.id == id }
    if id == activeID {
      activeID = nil
      setEntries([])
      tabName = ""
      tags = []
      swapTab()
    }
    saveConfig()
    saveTabs()
  }

  /**
   File an externally sourced snapshot (a share link) as a new saved tab and
   open it. Unknown tags join the catalog, since a tab may only reference
   catalog names.
   */
  @discardableResult
  public func importTab(name: String, tags importedTags: [String], entries imported: [Entry])
    -> String
  {
    let id = mintID()
    let cleanTags = dedupeTags(importedTags.map(normalizeTagName).filter { !$0.isEmpty })
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

    // Fresh local ids, so an imported line cannot collide with one already
    // minted here, with reference tokens rewritten to match.
    let localised = remapIDs(imported)

    let snap = Tab(
      id: id, name: trimmed.isEmpty ? defaultTabName() : trimmed, tags: cleanTags,
      entries: localised, savedAt: Self.now())

    commitActive()  // never lose the tab being left — same as openTab
    if !cleanTags.isEmpty { catalog = dedupeTags(catalog + cleanTags) }
    rawTabs.insert(snap, at: 0)
    setEntries(localised)
    tabName = snap.name
    tags = cleanTags
    activeID = id
    swapTab()
    saveCatalog()
    saveConfig()
    saveTabs()
    return id
  }

  /**
   Give imported entries fresh local ids, rewriting `{e123}` reference tokens to
   match. `{sum}` tokens pass through untouched.
   */
  public func remapIDs(_ imported: [Entry]) -> [Entry] {
    var map: [String: String] = [:]
    for e in imported { map[e.id] = mintID() }
    return imported.map { e in
      var out = e
      out.id = map[e.id] ?? e.id
      if !e.expr.isEmpty {
        var rebuilt = ""
        var last = e.expr.startIndex
        for m in e.expr.matches(of: Calc.refPattern) {
          rebuilt += e.expr[last..<m.range.lowerBound]
          let id = String(m.1)
          rebuilt += map[id].map { "{\($0)}" } ?? String(m.0)
          last = m.range.upperBound
        }
        rebuilt += e.expr[last...]
        out.expr = rebuilt
      }
      return out
    }
  }

  private func swapTab() { tabEpoch += 1 }

  /// Milliseconds since the epoch, matching what `Date.now()` wrote.
  static func now() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
}

// MARK: - Persisted documents
//
// These mirror what the React Native build writes, exactly. See Models.swift on
// why that matters.

/// `tally:tagcatalog` — stored as `[{ name }]`, tolerating a bare string array.
struct CatalogDocument: Decodable {
  struct Item: Codable {
    let name: String
  }
  let names: [String]

  init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    var out: [String] = []
    while !c.isAtEnd {
      if let s = try? c.decode(String.self) {
        out.append(s)
      } else if let item = try? c.decode(Item.self) {
        out.append(item.name)
      } else {
        _ = try? c.decode(AnyCodable.self)  // skip something unrecognised
      }
    }
    names = out
  }

  private struct AnyCodable: Decodable {}
}

/// `tally:config` — preferences plus which tab is open.
struct ConfigDocument: Codable {
  var themeMode: ThemeMode?
  var accent: String?
  var showExpr: Bool?
  var showTotal: Bool?
  /// Written as `null` when no tab is active, so its presence and its value are
  /// different things — hence `hasActiveIDKey`.
  var activeId: String?
  var tabName: String?
  var tags: [String]?
  /// Legacy singular tag from older builds.
  var tag: String?

  /// True when the document actually carried the key, null or not. A document
  /// that never mentions `activeId` must not close the open tab.
  var hasActiveIDKey = false

  enum CodingKeys: String, CodingKey {
    case themeMode, accent, showExpr, showTotal, activeId, tabName, tags, tag
  }

  init(
    themeMode: ThemeMode?, accent: String?, showExpr: Bool?, showTotal: Bool?,
    activeId: String?, tabName: String?, tags: [String]?, tag: String? = nil
  ) {
    self.themeMode = themeMode
    self.accent = accent
    self.showExpr = showExpr
    self.showTotal = showTotal
    self.activeId = activeId
    self.tabName = tabName
    self.tags = tags
    self.tag = tag
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode)
    accent = try c.decodeIfPresent(String.self, forKey: .accent)
    showExpr = try c.decodeIfPresent(Bool.self, forKey: .showExpr)
    showTotal = try c.decodeIfPresent(Bool.self, forKey: .showTotal)
    activeId = try c.decodeIfPresent(String.self, forKey: .activeId)
    hasActiveIDKey = c.contains(.activeId)
    tabName = try c.decodeIfPresent(String.self, forKey: .tabName)
    tags = try c.decodeIfPresent([String].self, forKey: .tags)
    tag = try c.decodeIfPresent(String.self, forKey: .tag)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(themeMode, forKey: .themeMode)
    try c.encodeIfPresent(accent, forKey: .accent)
    try c.encodeIfPresent(showExpr, forKey: .showExpr)
    try c.encodeIfPresent(showTotal, forKey: .showTotal)
    // Explicitly, including null — "no tab is open" is a value the original
    // writes, not an absence.
    try c.encode(activeId, forKey: .activeId)
    try c.encodeIfPresent(tabName, forKey: .tabName)
    try c.encodeIfPresent(tags, forKey: .tags)
    // `tag` is never written; it only ever arrives from an older build.
  }
}
