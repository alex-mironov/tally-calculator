// storage.ts — the persistence layer behind the tally store. Writes go through to
// two places: AsyncStorage (a fast, always-available local cache) and the iCloud
// key-value store (so a user's tabs and preferences follow them across devices).
//
// Reads prefer iCloud when it has a value — that's the cross-device source of
// truth — and mirror it back into the local cache. When the cloud has nothing for
// a key (offline, signed out of iCloud, or a key only ever written locally) we
// fall back to the local copy, so the app is fully functional without iCloud.
import AsyncStorage from '@react-native-async-storage/async-storage';

import * as Cloud from '../../modules/icloud-kv';

export type { CloudChangePayload } from '../../modules/icloud-kv';

/** True on an iOS build with the iCloud entitlement; false on Android/web. */
export const isICloudAvailable = Cloud.isICloudAvailable;

export async function getItem(key: string): Promise<string | null> {
  if (Cloud.isICloudAvailable) {
    try {
      const cloud = await Cloud.getItem(key);
      if (cloud != null) {
        AsyncStorage.setItem(key, cloud).catch(() => {});
        return cloud;
      }
    } catch {
      // fall through to the local cache
    }
  }
  return AsyncStorage.getItem(key);
}

export async function multiGet(keys: string[]): Promise<Record<string, string | null>> {
  let cloud: Record<string, string> = {};
  if (Cloud.isICloudAvailable) {
    try {
      cloud = await Cloud.multiGet(keys);
    } catch {
      // fall through to per-key local reads
    }
  }
  const out: Record<string, string | null> = {};
  await Promise.all(
    keys.map(async (key) => {
      const fromCloud = cloud[key];
      if (fromCloud != null) {
        out[key] = fromCloud;
        AsyncStorage.setItem(key, fromCloud).catch(() => {});
      } else {
        out[key] = await AsyncStorage.getItem(key);
      }
    }),
  );
  return out;
}

/** Write-through: local first (instant, offline-safe), then push to iCloud. */
export function setItem(key: string, value: string): void {
  AsyncStorage.setItem(key, value).catch(() => {});
  if (Cloud.isICloudAvailable) Cloud.setItem(key, value).catch(() => {});
}

export function removeItem(key: string): void {
  AsyncStorage.removeItem(key).catch(() => {});
  if (Cloud.isICloudAvailable) Cloud.removeItem(key).catch(() => {});
}

/** Subscribe to writes pushed from another device. No-op subscription off-iCloud. */
export const addChangeListener = Cloud.addChangeListener;
