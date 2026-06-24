import ExpoModulesCore

// Thin wrapper around NSUbiquitousKeyValueStore — iCloud's key-value store. Good
// for small, structured data (the app's tabs + prefs are JSON strings, well under
// the 1 MB / 1024-key budget). Values sync automatically across the user's devices
// when they're signed into iCloud; when they're not, it degrades to local storage.
public class IcloudKvModule: Module {
  private let store = NSUbiquitousKeyValueStore.default

  public func definition() -> ModuleDefinition {
    Name("IcloudKv")

    // Fired when iCloud pushes a change made on another device (or initial sync).
    Events("onChange")

    AsyncFunction("getItem") { (key: String) -> String? in
      return self.store.string(forKey: key)
    }

    AsyncFunction("multiGet") { (keys: [String]) -> [String: String] in
      var out: [String: String] = [:]
      for key in keys {
        if let value = self.store.string(forKey: key) {
          out[key] = value
        }
      }
      return out
    }

    AsyncFunction("setItem") { (key: String, value: String) in
      self.store.set(value, forKey: key)
      self.store.synchronize()
    }

    AsyncFunction("removeItem") { (key: String) in
      self.store.removeObject(forKey: key)
      self.store.synchronize()
    }

    // Force a flush; returns false if iCloud isn't available for this app.
    Function("synchronize") { () -> Bool in
      return self.store.synchronize()
    }

    OnStartObserving("onChange") {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(self.storeDidChange(_:)),
        name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: self.store
      )
      // Pull anything already waiting in the cloud.
      self.store.synchronize()
    }

    OnStopObserving("onChange") {
      NotificationCenter.default.removeObserver(
        self,
        name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: self.store
      )
    }
  }

  @objc
  private func storeDidChange(_ notification: Notification) {
    let info = notification.userInfo
    let keys = info?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
    let reason = info?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int ?? -1
    sendEvent("onChange", [
      "keys": keys,
      "reason": reason,
    ])
  }
}
