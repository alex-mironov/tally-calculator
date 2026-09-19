// Storage.swift — persistence for the store: a fast local cache, mirrored to
// the iCloud key-value store so a user's tabs and preferences follow them
// across devices.
//
// Ported from mobile/src/lib/storage.ts, and deliberately keeping its
// asymmetry: reads *prefer* iCloud when it has a value (that is the
// cross-device source of truth) and mirror what they find back into the local
// cache; writes go to the local cache first (instant, offline-safe) and then to
// iCloud. When the cloud has nothing for a key — offline, signed out, or a key
// only ever written locally — the local copy answers, so the app is fully
// functional without iCloud.
//
// ── Why the keys matter ─────────────────────────────────────────────────────
// The iCloud store is *shared with the React Native build*: the same container,
// the same four keys. During a rollout a user can have the old app on one
// device and this one on another, and each must read what the other wrote. The
// key names and the JSON under them are a compatibility surface, not an
// implementation detail. See Models.swift.
import Foundation

/// The four documents the app persists. Named here so nothing else has to
/// spell them, and so the set is obvious when migrating.
public enum StorageKey: String, CaseIterable, Sendable {
  case entries = "tally:entries"
  case tabs = "tally:tabs"
  case catalog = "tally:tagcatalog"
  case config = "tally:config"
}

/// The narrow slice of a key-value store this app needs. Two implementations
/// ship (`UserDefaults` and `NSUbiquitousKeyValueStore`); tests substitute
/// their own.
public protocol KeyValueBacking: AnyObject {
  func string(forKey key: String) -> String?
  func set(_ value: String, forKey key: String)
  func removeObject(forKey key: String)
  /// Push pending writes. A local store can no-op; iCloud cannot.
  @discardableResult func synchronize() -> Bool
}

extension UserDefaults: KeyValueBacking {
  public func set(_ value: String, forKey key: String) {
    set(value as Any?, forKey: key)
  }
}

extension NSUbiquitousKeyValueStore: KeyValueBacking {
  public func set(_ value: String, forKey key: String) {
    set(value as Any?, forKey: key)
  }
}

@MainActor
public final class Storage {

  /// The app's storage: local `UserDefaults`, mirrored to iCloud.
  public static let shared = Storage(
    local: UserDefaults.standard,
    cloud: NSUbiquitousKeyValueStore.default
  )

  private let local: any KeyValueBacking
  private let cloud: (any KeyValueBacking)?
  // `nonisolated(unsafe)` so `deinit`, which is not main-actor isolated, can
  // still unhook the observer. The token is written only from the main actor
  // and read only here and there, so the unchecked access is genuinely safe.
  private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

  /// True when writes are being mirrored to iCloud. False in tests, and on a
  /// build without the entitlement.
  public var isCloudAvailable: Bool { cloud != nil }

  public init(local: any KeyValueBacking, cloud: (any KeyValueBacking)? = nil) {
    self.local = local
    self.cloud = cloud
  }

  // MARK: - Reading

  /// One key, preferring iCloud and mirroring what it finds back into the cache.
  public func string(for key: StorageKey) -> String? {
    if let cloud, let value = cloud.string(forKey: key.rawValue) {
      local.set(value, forKey: key.rawValue)
      return value
    }
    return local.string(forKey: key.rawValue)
  }

  /// Every key at once — what hydration uses.
  public func all() -> [StorageKey: String] {
    var out: [StorageKey: String] = [:]
    for key in StorageKey.allCases {
      if let value = string(for: key) { out[key] = value }
    }
    return out
  }

  // MARK: - Writing

  /// Write-through: the local cache first, then iCloud.
  public func set(_ value: String, for key: StorageKey) {
    local.set(value, forKey: key.rawValue)
    cloud?.set(value, forKey: key.rawValue)
    cloud?.synchronize()
  }

  public func remove(_ key: StorageKey) {
    local.removeObject(forKey: key.rawValue)
    cloud?.removeObject(forKey: key.rawValue)
    cloud?.synchronize()
  }

  // MARK: - Changes pushed from another device

  /**
   Subscribe to writes made on the user's other devices.

   `handler` receives the keys iCloud says changed — or all of them, when it
   doesn't say (an initial sync, or a quota/account change), which matches what
   the React Native build did with the same notification.

   Only one subscription is kept; the store is the only subscriber.
   */
  public func observeExternalChanges(
    _ handler: @escaping @Sendable @MainActor ([StorageKey]) -> Void
  ) {
    guard let cloud else { return }
    stopObserving()
    observer = NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: cloud,
      queue: .main
    ) { note in
      let names = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
      let changed =
        names.isEmpty
        ? StorageKey.allCases
        : names.compactMap(StorageKey.init(rawValue:))
      guard !changed.isEmpty else { return }
      MainActor.assumeIsolated { handler(changed) }
    }
    // Pull anything already waiting in the cloud.
    cloud.synchronize()
  }

  public func stopObserving() {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}

// MARK: - Test double

/// An in-memory backing, for tests and previews.
public final class MemoryStore: KeyValueBacking {
  public private(set) var values: [String: String]

  public init(_ values: [String: String] = [:]) { self.values = values }

  public func string(forKey key: String) -> String? { values[key] }
  public func set(_ value: String, forKey key: String) { values[key] = value }
  public func removeObject(forKey key: String) { values[key] = nil }
  @discardableResult public func synchronize() -> Bool { true }
}
