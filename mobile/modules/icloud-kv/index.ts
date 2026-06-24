// icloud-kv — JS surface for the NSUbiquitousKeyValueStore native module.
//
// The native module is iOS-only. We load it optionally so the same import works
// on Android/web (and on an iOS build without the entitlement): there it resolves
// to null and every call below becomes a no-op, leaving the caller's local cache
// (AsyncStorage) as the single source of truth.
import { requireOptionalNativeModule } from 'expo';
import type { EventSubscription } from 'expo-modules-core';

import type { IcloudKvModule } from './src/IcloudKvModule';

export type { CloudChangePayload } from './src/IcloudKv.types';
import type { CloudChangePayload } from './src/IcloudKv.types';

const native = requireOptionalNativeModule<IcloudKvModule>('IcloudKv');

/** True when the iCloud key-value store is linked (an iOS build with the entitlement). */
export const isICloudAvailable = native != null;

export function getItem(key: string): Promise<string | null> {
  return native ? native.getItem(key) : Promise.resolve(null);
}

export function multiGet(keys: string[]): Promise<Record<string, string>> {
  return native ? native.multiGet(keys) : Promise.resolve({});
}

export function setItem(key: string, value: string): Promise<void> {
  return native ? native.setItem(key, value) : Promise.resolve();
}

export function removeItem(key: string): Promise<void> {
  return native ? native.removeItem(key) : Promise.resolve();
}

/** Force-flush pending writes to iCloud. No-op (returns false) when unavailable. */
export function synchronize(): boolean {
  return native ? native.synchronize() : false;
}

const NOOP_SUBSCRIPTION: EventSubscription = { remove() {} };

/** Subscribe to changes pushed from another device. Returns a removable subscription. */
export function addChangeListener(listener: (payload: CloudChangePayload) => void): EventSubscription {
  return native ? native.addListener('onChange', listener) : NOOP_SUBSCRIPTION;
}
