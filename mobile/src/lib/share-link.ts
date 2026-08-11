// share-link.ts — client for the tally-share Worker (web/ in this repo).
// Sharing POSTs a frozen snapshot of the tab and hands the returned link to
// the system share sheet; importing (tally://share/<id>, routed through
// app/share/[id]) fetches the snapshot back and re-ids it locally.
import { Share } from 'react-native';

import { uid, type Entry } from '@/lib/tally-store';

export const SHARE_ORIGIN = 'https://tally-share.myronov-alexander.workers.dev';

type ShareInput = {
  name: string;
  tags: string[];
  entries: Entry[];
  savedAt?: number;
  /** the sender's accent hex — themes the web page to match their app */
  accent?: string;
};

export type ShareSnapshot = {
  name: string;
  tags: string[];
  entries: Entry[];
};

/** POST the snapshot; resolves to the public share URL. */
export async function createShareLink(input: ShareInput): Promise<string> {
  const res = await fetch(`${SHARE_ORIGIN}/api/shares`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      v: 1,
      name: input.name,
      tags: input.tags,
      entries: input.entries.map((e) => ({ id: e.id, note: e.note, expr: e.expr, value: e.value, num: e.num })),
      savedAt: input.savedAt,
      accent: input.accent,
    }),
  });
  if (!res.ok) throw new Error(`share failed (${res.status})`);
  const data = (await res.json()) as { url?: string };
  if (!data.url) throw new Error('share failed (no url)');
  return data.url;
}

/** Create the link and hand it straight to the system share sheet. */
export async function shareCalculation(input: ShareInput): Promise<void> {
  const url = await createShareLink(input);
  await Share.share({ url });
}

/** Fetch a shared snapshot back for import. */
export async function fetchShare(id: string): Promise<ShareSnapshot> {
  const res = await fetch(`${SHARE_ORIGIN}/api/shares/${encodeURIComponent(id)}`);
  if (!res.ok) throw new Error(res.status === 404 ? 'not-found' : `fetch failed (${res.status})`);
  const data = (await res.json()) as Partial<ShareSnapshot>;
  if (!Array.isArray(data.entries)) throw new Error('bad snapshot');
  return {
    name: typeof data.name === 'string' ? data.name : '',
    tags: Array.isArray(data.tags) ? data.tags.filter((t): t is string => typeof t === 'string') : [],
    entries: data.entries as Entry[],
  };
}

/**
 * Give imported entries fresh local ids so they can't collide with ids already
 * minted on this device, rewriting `{e123}` reference tokens to match. `{sum}`
 * tokens pass through untouched.
 */
export function remapEntries(entries: Entry[]): Entry[] {
  const idMap = new Map(entries.map((e) => [e.id, uid()]));
  return entries.map((e) => ({
    ...e,
    id: idMap.get(e.id)!,
    expr: e.expr ? e.expr.replace(/\{(e\d+)\}/g, (tok, old) => (idMap.has(old) ? `{${idMap.get(old)}}` : tok)) : e.expr,
  }));
}
