// StoreTests.swift — the store and its persistence.
//
// Unlike the engine, pipeline and JSON suites, these expectations are written
// by hand: the behaviours here are decisions the app makes rather than numbers
// it has to reproduce. What they guard is the set of rules that were only
// discoverable from the React version's comments — the ones a reimplementation
// would quietly drop:
//
//   · tabEpoch, not activeID, is what says "the tab was swapped"
//   · nothing persists until the first load has finished
//   · a corrupt or half-synced document leaves state alone
//   · the active tab's live edits are folded into `tabs` on read
//   · leaving a tab never loses it
import Foundation
import Testing

@testable import TallyKit

@MainActor
private func makeStore(
  _ seeded: [StorageKey: String] = [:], loaded: Bool = true, seedEntries: Bool = false
) -> (TallyStore, MemoryStore) {
  let backing = MemoryStore(Dictionary(uniqueKeysWithValues: seeded.map { ($0.rawValue, $1) }))
  let store = TallyStore(storage: Storage(local: backing), seeded: seedEntries)
  if loaded { store.load() }
  return (store, backing)
}

private func json(_ value: some Encodable) -> String {
  String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
}

@MainActor
@Suite("TallyStore")
struct StoreTests {

  // MARK: - The live list

  @Test("every write to the live list runs the reference pipeline")
  func writesRunThePipeline() {
    let (store, _) = makeStore()
    // Ids are always `e<digits>` — that is the only shape `{…}` matches as a
    // reference, and the only shape the store mints.
    store.setEntries([Entry(id: "e1", value: 10), Entry(id: "e2", expr: "{e1}×3", value: 0)])
    // The pipeline assigned sticky numbers and recomputed the reference — none
    // of which the caller did.
    #expect(store.entries.map(\.num) == [1, 2])
    #expect(store.entries[1].value == 30)
    #expect(store.total == 40)
  }

  @Test("deleting a referenced line freezes its value rather than breaking it")
  func deleteFreezes() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 10), Entry(id: "e2", expr: "{e1}×3", value: 0)])
    store.delete(id: "e1")
    #expect(store.entries.count == 1)
    #expect(store.entries[0].expr == "10×3")
    #expect(store.entries[0].error == nil)
  }

  @Test("excluding a line drops it from the total but keeps it referenceable")
  func excluding() {
    let (store, _) = makeStore()
    store.setEntries([
      Entry(id: "e1", value: 10), Entry(id: "e2", value: 4),
      Entry(id: "e3", expr: "{sum}÷{e2}", value: 0),
    ])
    #expect(store.entries[2].value == 3.5)  // (10 + 4) ÷ 4
    store.toggleExcluded(id: "e2")
    #expect(store.entries[2].value == 2.5)  // 10 ÷ 4 — e2 is referenced, not counted
    #expect(store.total == 12.5)
    store.toggleExcluded(id: "e2")
    #expect(store.entries[1].excluded == nil)
  }

  @Test("ids are minted past anything already on disk")
  func idCounter() {
    let stored = [Entry(id: "e900", value: 1)]
    let (store, _) = makeStore([.entries: json(stored)])
    #expect(store.mintID() == "e901")
  }

  // MARK: - Swapping tabs

  @Test("tabEpoch, not activeID, is what marks a swap")
  func epochMarksSwaps() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 1)])
    store.saveDraft(name: "One")
    let firstID = store.activeID

    let before = store.tabEpoch
    store.newTab()
    // The case activeID cannot express: a new tab started from an already-saved
    // one leaves activeID nil, and starting *another* leaves it nil again.
    #expect(store.activeID == nil)
    #expect(store.tabEpoch == before + 1)

    store.setEntries([Entry(id: "e2", value: 2)])
    let second = store.tabEpoch
    store.newTab()
    #expect(store.activeID == nil)  // unchanged either side…
    #expect(store.tabEpoch == second + 1)  // …but the editor still learns of it
    #expect(firstID != nil)
  }

  @Test("leaving a tab never loses it")
  func leavingCommits() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 5)])
    store.saveDraft(name: "Groceries")
    let saved = store.activeID!

    // Edit it, then walk away without saving.
    store.append(Entry(id: "e2", value: 7))
    store.newTab()
    #expect(store.entries.isEmpty)

    // The edit is in the archive, not gone.
    let archived = store.tabs.first { $0.id == saved }!
    #expect(archived.entries.count == 2)
    #expect(archived.total == 12)
  }

  @Test("an unsaved tab is filed rather than dropped when a new one starts")
  func unsavedTabIsFiled() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 3)])
    #expect(store.tabs.isEmpty)
    store.newTab()
    #expect(store.tabs.count == 1)
    // It took today's date as a name, having never been given one.
    #expect(!store.tabs[0].name.isEmpty)
  }

  @Test("the active tab's live edits are folded into `tabs` on read")
  func activeTabFolds() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 1)])
    store.saveDraft(name: "Trip", tags: ["Trip"])
    let id = store.activeID!

    store.append(Entry(id: "e2", value: 2))
    store.setTabName("Lisbon")

    let folded = store.tabs.first { $0.id == id }!
    #expect(folded.name == "Lisbon")
    #expect(folded.entries.count == 2)
    #expect(folded.tags == ["Trip"])
  }

  @Test("opening a tab is a no-op when it is already open")
  func openingActiveIsNoop() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 1)])
    store.saveDraft(name: "One")
    let epoch = store.tabEpoch
    store.openTab(id: store.activeID!)
    #expect(store.tabEpoch == epoch)
  }

  @Test("deleting the open tab clears the editor")
  func deletingActive() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 1)])
    store.saveDraft(name: "One")
    let id = store.activeID!
    store.deleteTab(id: id)
    #expect(store.activeID == nil)
    #expect(store.entries.isEmpty)
    #expect(store.tabs.isEmpty)
  }

  // MARK: - Importing a shared snapshot

  @Test("an import gets fresh local ids, with its references rewritten")
  func importRemapsIDs() {
    let (store, _) = makeStore()
    let shared = [
      Entry(id: "e1", note: "Bill", value: 80, num: 1),
      Entry(id: "e2", note: "Tip", expr: "{e1}×0.15", value: 12, num: 2),
      Entry(id: "e3", note: "Each", expr: "{sum}÷2", value: 46, num: 3),
    ]
    store.importTab(name: "Dinner", tags: ["Food"], entries: shared)

    // Nothing kept a source id…
    #expect(!store.entries.contains { ["e1", "e2", "e3"].contains($0.id) })
    // …and the reference still points at the right line, so it still computes.
    let tip = store.entries[1]
    #expect(tip.expr == "{\(store.entries[0].id)}×0.15")
    #expect(tip.value == 12)
    // `{sum}` is not an id and passes through untouched.
    #expect(store.entries[2].expr == "{sum}÷2")
    #expect(store.entries[2].value == 46)
    // An unknown tag joins the catalog, since a tab may only reference one.
    #expect(store.catalog.contains("Food"))
    #expect(store.tags == ["Food"])
  }

  // MARK: - The tag catalog

  @Test("creating a tag folds into an existing spelling rather than doubling it")
  func addCatalogTag() {
    let (store, _) = makeStore()
    #expect(store.addCatalogTag("  Trip  ") == "Trip")  // already seeded
    #expect(store.addCatalogTag("TRIP") == "Trip")  // case-insensitive
    #expect(store.addCatalogTag("   ") == nil)
    #expect(store.addCatalogTag("Fuel") == "Fuel")
    #expect(store.catalog.filter { $0.lowercased() == "trip" }.count == 1)
  }

  @Test("deleting a catalog tag cascades through every tab")
  func removeCatalogTagCascades() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 1)])
    store.saveDraft(name: "One", tags: ["Trip", "Food"])
    store.newTab()
    store.setEntries([Entry(id: "e2", value: 2)])
    store.saveDraft(name: "Two", tags: ["Trip"])

    store.removeCatalogTag("Trip")
    #expect(!store.catalog.contains("Trip"))
    #expect(store.tabs.allSatisfy { !$0.resolvedTags.contains("Trip") })
    #expect(store.tabs.first { $0.name == "One" }!.resolvedTags == ["Food"])
    #expect(store.tags == [])
  }

  @Test("renaming a catalog tag cascades, and cannot create a duplicate")
  func renameCatalogTagCascades() {
    let (store, _) = makeStore()
    store.setEntries([Entry(id: "e1", value: 1)])
    store.saveDraft(name: "One", tags: ["Trip", "Food"])

    store.renameCatalogTag("Trip", to: "Travel")
    #expect(store.catalog.contains("Travel") && !store.catalog.contains("Trip"))
    #expect(store.tabs[0].resolvedTags == ["Travel", "Food"])

    // Renaming onto a name the tab already has collapses rather than doubling.
    store.renameCatalogTag("Travel", to: "Food")
    #expect(store.tabs[0].resolvedTags == ["Food"])
  }

  // MARK: - Persistence

  @Test("nothing is written before the first load finishes")
  func noWritesBeforeHydration() {
    let (store, backing) = makeStore(loaded: false, seedEntries: true)
    store.setEntries([Entry(id: "e1", value: 99)])
    #expect(backing.values.isEmpty, "the seed must not clobber what is on disk")

    store.load()
    store.setEntries([Entry(id: "e2", value: 1)])
    #expect(backing.values[StorageKey.entries.rawValue] != nil)
  }

  @Test("hydration restores the live tab, the archive, the catalog and prefs")
  func hydration() {
    let entries = [Entry(id: "e7", note: "Rent", value: 900, num: 1)]
    let tabs = [Tab(id: "t1", name: "March", tags: ["Bills"], entries: entries, savedAt: 1)]
    let config = ConfigDocument(
      themeMode: .dark, accent: "#6b58d9", showExpr: false, showTotal: false,
      activeId: "t1", tabName: "March", tags: ["Bills"])

    let (store, _) = makeStore([
      .entries: json(entries),
      .tabs: json(tabs),
      .catalog: #"[{"name":"Bills"},{"name":"Rent"}]"#,
      .config: json(config),
    ])

    #expect(store.entries.count == 1 && store.entries[0].note == "Rent")
    #expect(store.tabs.count == 1 && store.activeID == "t1")
    #expect(store.catalog == ["Bills", "Rent"])
    #expect(store.themeMode == .dark)
    #expect(store.accent.name == "Violet")
    #expect(store.showExpr == false && store.showTotal == false)
    #expect(store.tags == ["Bills"])
  }

  @Test("a retired accent hex lands on its replacement, not on the default")
  func legacyAccent() {
    let config = ConfigDocument(
      themeMode: nil, accent: "#b3476a", showExpr: nil, showTotal: nil,
      activeId: nil, tabName: nil, tags: nil)  // Raspberry, retired
    let (store, _) = makeStore([.config: json(config)])
    #expect(store.accent.name == "Violet")
  }

  @Test("an accent from the six-accent palette never lands on dark-only Lime")
  func sixAccentPaletteAvoidsLime() {
    for hex in ["#0a7aff", "#dd1b80", "#00c2a0", "#6b00d0", "#e6b800", "#4a5560"] {
      #expect(!Accent.resolve(hex).darkOnly, "\(hex)")
    }
  }

  @Test("a corrupt document leaves the current state alone")
  func corruptDocumentsAreIgnored() {
    let (store, _) = makeStore(
      [
        .entries: "{ not json at all",
        .tabs: "null",
        .catalog: "[]",
        .config: "\"a string, not an object\"",
      ], seedEntries: true)

    // The seed survived rather than being wiped by the unreadable document.
    #expect(store.entries.count == 5)
    #expect(store.tabs.isEmpty)
    #expect(store.catalog == TallyStore.defaultCatalog)
    #expect(store.themeMode == .light)
  }

  @Test("the catalog tolerates a bare string array as well as [{name}]")
  func catalogShapes() {
    let (a, _) = makeStore([.catalog: #"["One","Two"]"#])
    #expect(a.catalog == ["One", "Two"])
    let (b, _) = makeStore([.catalog: #"[{"name":"One"},{"name":"one"}]"#])
    #expect(b.catalog == ["One"], "de-duped case-insensitively, first spelling kept")
  }

  @Test("a config that never mentions activeId must not close the open tab")
  func partialConfigKeepsActiveTab() {
    let tabs = [Tab(id: "t1", name: "March", entries: [], savedAt: 1)]
    let (store, _) = makeStore([
      .tabs: json(tabs),
      .config: #"{"activeId":"t1"}"#,
    ])
    #expect(store.activeID == "t1")

    // A later push carrying only a theme change leaves the tab open.
    store.apply(.config, #"{"themeMode":"dark"}"#)
    #expect(store.themeMode == .dark)
    #expect(store.activeID == "t1")

    // An explicit null, though, is a value and does close it.
    store.apply(.config, #"{"activeId":null}"#)
    #expect(store.activeID == nil)
  }

  @Test("the config document writes activeId as null, not as an absent key")
  func configWritesExplicitNull() throws {
    let doc = ConfigDocument(
      themeMode: .light, accent: "#156cdd", showExpr: true, showTotal: true,
      activeId: nil, tabName: "", tags: [])
    let obj =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
    #expect(obj.keys.contains("activeId"))
    #expect(obj["activeId"] is NSNull)
    #expect(!obj.keys.contains("tag"), "the legacy singular is never written")
  }

  @Test("a change pushed from another device is folded in the same way")
  func externalChange() {
    let (store, _) = makeStore()
    store.setThemeMode(.light)
    // What the iCloud listener does on a push, without needing iCloud.
    store.apply(.config, ##"{"themeMode":"dark","accent":"#156cdd"}"##)
    #expect(store.themeMode == .dark)
    #expect(store.accent.name == "Blue")
  }

  @Test("preferences survive a round trip through storage")
  func preferencesRoundTrip() {
    let (store, backing) = makeStore()
    store.setThemeMode(.dark)
    store.setAccent("#6b58d9")
    store.setShowExpr(false)

    let (reloaded, _) = makeStore(
      Dictionary(
        uniqueKeysWithValues: backing.values.compactMap { k, v in
          StorageKey(rawValue: k).map { ($0, v) }
        }))
    #expect(reloaded.themeMode == .dark)
    #expect(reloaded.accent.name == "Violet")
    #expect(reloaded.showExpr == false)
  }
}

@MainActor
@Suite("Storage")
struct StorageTests {

  @Test("a read prefers iCloud and mirrors what it finds into the local cache")
  func readPrefersCloud() {
    let local = MemoryStore([StorageKey.config.rawValue: "local"])
    let cloud = MemoryStore([StorageKey.config.rawValue: "cloud"])
    let storage = Storage(local: local, cloud: cloud)

    #expect(storage.string(for: .config) == "cloud")
    #expect(local.values[StorageKey.config.rawValue] == "cloud", "mirrored back")
  }

  @Test("the local cache answers when iCloud has nothing for a key")
  func fallsBackToLocal() {
    let local = MemoryStore([StorageKey.entries.rawValue: "local"])
    let storage = Storage(local: local, cloud: MemoryStore())
    #expect(storage.string(for: .entries) == "local")
  }

  @Test("the app works with no iCloud at all")
  func worksWithoutCloud() {
    let local = MemoryStore()
    let storage = Storage(local: local)
    #expect(!storage.isCloudAvailable)
    storage.set("x", for: .tabs)
    #expect(storage.string(for: .tabs) == "x")
  }

  @Test("a write goes to both, local first")
  func writeThrough() {
    let local = MemoryStore()
    let cloud = MemoryStore()
    let storage = Storage(local: local, cloud: cloud)
    storage.set("v", for: .catalog)
    #expect(local.values[StorageKey.catalog.rawValue] == "v")
    #expect(cloud.values[StorageKey.catalog.rawValue] == "v")

    storage.remove(.catalog)
    #expect(local.values[StorageKey.catalog.rawValue] == nil)
    #expect(cloud.values[StorageKey.catalog.rawValue] == nil)
  }

  @Test("the four keys are the ones the React Native build wrote")
  func keyNamesAreACompatibilitySurface() {
    #expect(StorageKey.entries.rawValue == "tally:entries")
    #expect(StorageKey.tabs.rawValue == "tally:tabs")
    #expect(StorageKey.catalog.rawValue == "tally:tagcatalog")
    #expect(StorageKey.config.rawValue == "tally:config")
    #expect(StorageKey.allCases.count == 4)
  }
}
