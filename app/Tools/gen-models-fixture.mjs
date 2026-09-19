// gen-models-fixture.mjs — golden fixture for the persisted/wire JSON
// (TallyKit/Tests/TallyKitTests/Fixtures/models.json).
//
// The JSON these types encode is not private to this app. The same documents
// are read and written by the React Native build through the *shared* iCloud
// key-value store (mid-rollout, one device may be on each), by the frozen share
// API, and by the web share page. So the contract under test is not "can Swift
// round-trip its own output" but "does Swift write the document JavaScript
// writes, key for key".
//
// The specific trap: the original writes `excluded` and `error` only when true,
// so *counted* is the absence of the key. Swift's synthesised Codable would
// write `"excluded": false` instead, which is a different document.
//
//   node app/Tools/gen-models-fixture.mjs
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '..', 'TallyKit', 'Tests', 'TallyKitTests', 'Fixtures', 'models.json');

// ---------------------------------------------------------------------------
// How the app actually serialises an entry, lifted from share-link.ts (the wire
// form) — which is the same shape the store persists.
const encodeEntry = (e) => ({
  id: e.id,
  note: e.note,
  expr: e.expr,
  value: e.value,
  num: e.num,
  ...(e.excluded ? { excluded: true } : null),
  ...(e.error ? { error: true } : null),
});

const ENTRIES = [
  { case: 'plain line', entry: { id: 'e1', note: 'Coffee', expr: '', value: 4.5, num: 1 } },
  { case: 'computed line', entry: { id: 'e2', note: 'Dinner · split 4', expr: '60÷4', value: 15, num: 2 } },
  { case: 'reference line', entry: { id: 'e3', note: '', expr: '{e1}×3', value: 13.5, num: 3 } },
  {
    case: 'excluded is written only as true',
    entry: { id: 'e4', note: 'People', expr: '', value: 4, num: 4, excluded: true },
  },
  {
    case: 'excluded false must not appear at all',
    entry: { id: 'e5', note: '', expr: '', value: 1, num: 5, excluded: false },
  },
  {
    case: 'error is written only as true',
    entry: { id: 'e6', note: '', expr: '{gone}+1', value: 0, num: 6, error: true },
  },
  {
    case: 'error false must not appear at all',
    entry: { id: 'e7', note: '', expr: '', value: 2, num: 7, error: false },
  },
  {
    case: 'both flags at once',
    entry: { id: 'e8', note: 'x', expr: '{e1}', value: 0, num: 8, excluded: true, error: true },
  },
  { case: 'no sticky number yet (legacy data)', entry: { id: 'e9', note: '', expr: '', value: 3 } },
  { case: 'negative value', entry: { id: 'e10', note: 'Refund', expr: '', value: -12.34, num: 10 } },
  { case: 'integral value', entry: { id: 'e11', note: '', expr: '', value: 100, num: 11 } },
  { case: 'zero', entry: { id: 'e12', note: '', expr: '', value: 0, num: 12 } },
  {
    case: 'unicode in the note',
    entry: { id: 'e13', note: 'Café · 2× 🍰', expr: '', value: 9.9, num: 13 },
  },
];

const TABS = [
  {
    case: 'saved tab with tags',
    tab: {
      id: 't1',
      name: 'Lisbon trip',
      tags: ['Trip', 'Food'],
      entries: [ENTRIES[0].entry, ENTRIES[3].entry],
      savedAt: 1758240000000,
    },
  },
  {
    case: 'untagged tab',
    tab: { id: 't2', name: 'Tuesday', tags: [], entries: [], savedAt: 1758240000001 },
  },
  {
    case: 'legacy singular tag, preserved on read',
    tab: { id: 't3', name: 'Old', entries: [], savedAt: 1758240000002, tag: 'Bills' },
  },
];

const fixture = {
  version: 1,
  entries: ENTRIES.map((e) => ({
    case: e.case,
    entry: e.entry,
    json: encodeEntry(e.entry),
    // The exact key set the original produces — the thing most likely to drift.
    keys: Object.keys(encodeEntry(e.entry)).filter((k) => encodeEntry(e.entry)[k] !== undefined),
  })),
  tabs: TABS.map((t) => ({
    case: t.case,
    tab: t.tab,
    json: { ...t.tab, entries: (t.tab.entries || []).map(encodeEntry) },
    keys: Object.keys(t.tab),
    // What `tagsOf` resolves to — new `tags`, else the legacy singular.
    resolvedTags: Array.isArray(t.tab.tags) ? t.tab.tags : t.tab.tag ? [t.tab.tag] : [],
  })),
};

writeFileSync(OUT, JSON.stringify(fixture, null, 2) + '\n');
console.log(
  `wrote ${fixture.entries.length} entry cases + ${fixture.tabs.length} tab cases → ${OUT}`,
);
