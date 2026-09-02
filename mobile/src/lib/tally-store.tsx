// tally-store.tsx — shared state for the running tab: the live list of entries,
// the saved tabs archive, the user's preferences, and the resolved theme. Lives
// in a context so the calculator screen, the Saved overlay and the settings
// modal stay in sync, and is persisted through `storage` (a local AsyncStorage
// cache mirrored to the iCloud key-value store) so tabs and preferences survive
// app restarts and follow the user across their devices.
import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';

import { ACCENTS, resolveAccent, resolveTheme, type TallyTheme, type ThemeMode } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import * as Storage from '@/lib/storage';

export type Entry = {
  id: string;
  /** short label, e.g. "Coffee" — optional */
  note: string;
  /**
   * the raw expression when it's more than a plain number, e.g. "60÷4".
   * May embed reference tokens — `{e123}` for another line's value, `{sum}`
   * for the running total of the lines above — which keep the value live.
   */
  expr: string;
  value: number;
  /**
   * sticky line number, assigned once at commit and never reshuffled —
   * deleting line 2 leaves a gap rather than renaming every reference.
   * Older persisted entries may lack it; the pipeline backfills in order.
   */
  num?: number;
};

/** A saved calculation — a named, optionally tagged snapshot of a tab. */
export type Tab = {
  id: string;
  name: string;
  /** tag names filed on this tab; [] when untagged */
  tags: string[];
  entries: Entry[];
  savedAt: number;
  /** legacy singular tag written by older builds; read through `tagsOf` and
   *  migrated to `tags` lazily on the next write. */
  tag?: string;
};

/**
 * Normalize a tab's tags for reading. New tabs carry `tags: string[]`; older
 * ones had a singular `tag: string`. We never bulk-migrate — `tags` is written
 * the next time a tab (or the catalog) is touched.
 */
export function tagsOf(tb: { tags?: string[]; tag?: string } | null | undefined): string[] {
  if (!tb) return [];
  if (Array.isArray(tb.tags)) return tb.tags;
  if (tb.tag) return [tb.tag];
  return [];
}

/** Seed catalog of known tag names, shared across every tab. */
const DEFAULT_CATALOG = ['Trip', 'Bills', 'Food', 'Work', 'Personal'];

/** Trim, collapse whitespace and cap length so names stay chip-sized. */
export function normalizeTagName(raw: string): string {
  return (raw || '').trim().replace(/\s+/g, ' ').slice(0, 22);
}

/** Case-insensitive de-dupe that keeps the first spelling seen. */
function dedupeTags(names: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const n of names) {
    const k = n.toLowerCase();
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(n);
  }
  return out;
}

/** Drop the legacy singular `tag` field once a tab is being rewritten. */
function migrate(tb: Tab, tags: string[]): Tab {
  const { tag: _legacy, ...rest } = tb;
  return { ...rest, tags };
}

const ENTRIES_KEY = 'tally:entries';
const CONFIG_KEY = 'tally:config';
const TABS_KEY = 'tally:tabs';
const CATALOG_KEY = 'tally:tagcatalog';

let _id = 100;
export const uid = () => 'e' + ++_id;

/** Keep the id counter ahead of any persisted ids so new rows never collide. */
function syncIdCounter(entries: Entry[]) {
  for (const e of entries) {
    const m = /^e(\d+)$/.exec(e.id);
    if (m) _id = Math.max(_id, parseInt(m[1], 10));
  }
}

// ── live references ─────────────────────────────────────────────────────────
// Entries can reference each other ({e123}) or the running subtotal ({sum}).
// Every write to the live list runs through this pipeline so the invariants
// hold no matter which screen made the change:
//   1. every line has a sticky number (backfilled for pre-reference data)
//   2. references to lines that just vanished freeze into their last value
//   3. every referencing line's value is recomputed in one forward pass —
//      the picker only offers lines *above* the one being written, so list
//      order is evaluation order and cycles can't exist by construction.

function assignNums(list: Entry[]): Entry[] {
  let next = list.reduce((m, e) => Math.max(m, e.num ?? 0), 0) + 1;
  let changed = false;
  const out = list.map((e) => {
    if (e.num != null) return e;
    changed = true;
    return { ...e, num: next++ };
  });
  return changed ? out : list;
}

/** Replace references to removed lines with their last known value. */
function freezeRefs(prev: Entry[], list: Entry[]): Entry[] {
  const kept = new Set(list.map((e) => e.id));
  const removed = new Map(prev.filter((e) => !kept.has(e.id)).map((e) => [e.id, e.value]));
  if (removed.size === 0) return list;
  return list.map((e) => {
    if (!e.expr) return e;
    const expr = e.expr.replace(Calc.REF_RE, (tok, id) =>
      removed.has(id) ? Calc.plain(removed.get(id)!) : tok,
    );
    if (expr === e.expr) return e;
    // a pure reference may have frozen into a bare number — no longer worth
    // showing as an expression under the amount
    const keepExpr = Calc.hasOperator(expr) || Calc.refsIn(expr).length > 0;
    return { ...e, expr: keepExpr ? expr : '' };
  });
}

/** Recompute referencing lines top-to-bottom; plain lines keep their value. */
function recalc(list: Entry[]): Entry[] {
  const vals = new Map<string, number>();
  let changed = false;
  const out = list.map((e, i) => {
    let v = e.value;
    if (e.expr && Calc.refsIn(e.expr).length > 0) {
      const r = Calc.evaluate(e.expr, (id) => {
        if (id === 'sum') {
          let sum = 0;
          for (let k = 0; k < i; k++) sum += vals.get(list[k].id) ?? list[k].value;
          return sum;
        }
        // only lines above have resolved — a forward reference (impossible
        // through the UI) falls back to the cached value via null
        return vals.get(id) ?? null;
      });
      if (r != null) v = r;
    }
    vals.set(e.id, v);
    if (v !== e.value) changed = true;
    return v === e.value ? e : { ...e, value: v };
  });
  return changed ? out : list;
}

function pipeline(prev: Entry[], next: Entry[]): Entry[] {
  return recalc(freezeRefs(prev, assignNums(next)));
}

function seed(): Entry[] {
  return [
    { id: 'e1', note: 'Coffee', expr: '', value: 4.5 },
    { id: 'e2', note: 'Groceries', expr: '', value: 42.2 },
    { id: 'e3', note: 'Taxi home', expr: '', value: 18 },
    { id: 'e4', note: 'Dinner · split 4', expr: '60÷4', value: 15 },
    { id: 'e5', note: 'Gig tickets ×2', expr: '45×2', value: 90 },
  ];
}

type PersistedConfig = {
  themeMode: ThemeMode;
  accent: string;
  showExpr: boolean;
  showTotal: boolean;
  activeId: string | null;
  tabName: string;
  tags: string[];
  /** legacy singular tag from older builds */
  tag?: string;
};

/** One persisted key, parsed and shape-checked. */
type Persisted =
  | { kind: 'entries'; entries: Entry[] }
  | { kind: 'tabs'; tabs: Tab[] }
  | { kind: 'catalog'; names: string[] }
  | { kind: 'config'; config: Partial<PersistedConfig> };

/**
 * Parse one persisted key's raw JSON into a checked shape — or null when the
 * value is missing, corrupt, or the wrong shape, in which case the current
 * state is left in place. Also brings the id counter up to date with any
 * entries it reads, so ids minted afterwards can't collide with them.
 *
 * Kept at module scope on purpose: the React Compiler can't yet lower a
 * conditional inside a try/catch, and having this inside the provider was
 * enough to make it skip memoising the whole thing.
 */
function readPersisted(key: string, raw: string | null): Persisted | null {
  if (raw == null) return null;
  try {
    if (key === ENTRIES_KEY) {
      const arr = JSON.parse(raw);
      if (!Array.isArray(arr)) return null;
      syncIdCounter(arr);
      return { kind: 'entries', entries: arr };
    }
    if (key === TABS_KEY) {
      const arr = JSON.parse(raw) as Tab[];
      if (!Array.isArray(arr)) return null;
      arr.forEach((tb) => syncIdCounter(tb.entries || []));
      return { kind: 'tabs', tabs: arr };
    }
    if (key === CATALOG_KEY) {
      // stored as [{ name }] — tolerate a bare string array too
      const arr = JSON.parse(raw);
      if (!Array.isArray(arr)) return null;
      const names = arr
        .map((x) => (typeof x === 'string' ? x : x && typeof x.name === 'string' ? x.name : null))
        .filter((n): n is string => !!n);
      return names.length ? { kind: 'catalog', names: dedupeTags(names) } : null;
    }
    if (key === CONFIG_KEY) {
      const c = JSON.parse(raw) as Partial<PersistedConfig> | null;
      return c && typeof c === 'object' ? { kind: 'config', config: c } : null;
    }
    return null;
  } catch {
    return null; // corrupt value
  }
}

type TallyContextValue = {
  // ---- the live tab ----
  entries: Entry[];
  setEntries: React.Dispatch<React.SetStateAction<Entry[]>>;
  total: number;

  // ---- saved tabs ----
  tabs: Tab[];
  activeId: string | null;
  /**
   * Bumped every time the working tab is swapped out from under the editor —
   * opened, replaced by a new one, or deleted. `activeId` can't stand in for
   * this: starting a new tab while already on an unsaved one leaves it null
   * either side, so a watcher keyed on it would miss the swap entirely.
   * Anything holding uncommitted state about the tab (the calculator's draft
   * line) resets when this changes.
   */
  tabEpoch: number;
  tabName: string;
  setTabName: (n: string) => void;
  /** tags on the live (in-progress or active) tab */
  tags: string[];
  setTags: (next: string[]) => void;
  /** toggle a single tag on the live tab */
  toggleTag: (name: string) => void;
  /** set the tags on any saved tab (or the live tab when it's active) */
  setTabTags: (id: string, next: string[]) => void;

  // ---- tag catalog (shared) ----
  catalog: string[];
  addCatalogTag: (raw: string) => string | null;
  removeCatalogTag: (name: string) => void;
  renameCatalogTag: (name: string, next: string) => void;

  /** Commit the live tab as a saved snapshot. Pass overrides to apply a fresh
   *  name/tags atomically (avoids reading not-yet-flushed state). */
  saveDraft: (override?: { name?: string; tags?: string[] }) => void;
  openTab: (id: string) => void;
  newTab: () => void;
  deleteTab: (id: string) => void;
  /** file a shared snapshot as a new saved tab and open it; returns its id */
  importTab: (name: string, tags: string[], entries: Entry[]) => string;

  // ---- preferences ----
  themeMode: ThemeMode;
  setThemeMode: (m: ThemeMode) => void;
  accent: string;
  setAccent: (a: string) => void;
  showExpr: boolean;
  setShowExpr: (v: boolean) => void;
  showTotal: boolean;
  setShowTotal: (v: boolean) => void;

  theme: TallyTheme;
};

const TallyContext = createContext<TallyContextValue | null>(null);

export function TallyProvider({ children }: { children: ReactNode }) {
  const [entries, setEntriesRaw] = useState<Entry[]>(() => pipeline([], seed()));

  // Every live-list write funnels through the reference pipeline (see above),
  // so callers can keep treating this as a plain state setter.
  const setEntries: React.Dispatch<React.SetStateAction<Entry[]>> = (action) =>
    setEntriesRaw((prev) => {
      const next = typeof action === 'function' ? action(prev) : action;
      return next === prev ? prev : pipeline(prev, next);
    });
  const [rawTabs, setRawTabs] = useState<Tab[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  // see `tabEpoch` on the context type
  const [tabEpoch, setTabEpoch] = useState(0);
  const swapTab = () => setTabEpoch((n) => n + 1);
  const [tabName, setTabName] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [catalog, setCatalog] = useState<string[]>(DEFAULT_CATALOG);

  const [themeMode, setThemeMode] = useState<ThemeMode>('light');
  const [accent, setAccent] = useState<string>(ACCENTS[0].accent);
  const [showExpr, setShowExpr] = useState(true);
  const [showTotal, setShowTotal] = useState(true);

  // Don't persist until we've loaded once, or the initial seed/defaults would
  // clobber what's already on disk before hydration finishes.
  const hydrated = useRef(false);

  // Fold one persisted key's raw JSON into state. Shared by the initial hydrate
  // and by live iCloud pushes from other devices, so both paths stay identical.
  // Parsing and validation live in `readPersisted` at module scope; this only
  // applies what it hands back.
  function applyPersisted(key: string, raw: string | null) {
    const read = readPersisted(key, raw);
    if (!read) return;
    if (read.kind === 'entries') setEntries(read.entries);
    else if (read.kind === 'tabs') setRawTabs(read.tabs);
    else if (read.kind === 'catalog') setCatalog(read.names);
    else {
      const c = read.config;
      if (c.themeMode) setThemeMode(c.themeMode);
      // through resolveAccent, so a hex from the retired palette lands on its
      // replacement instead of snapping everyone back to the default
      if (c.accent) setAccent(resolveAccent(c.accent).accent);
      if (typeof c.showExpr === 'boolean') setShowExpr(c.showExpr);
      if (typeof c.showTotal === 'boolean') setShowTotal(c.showTotal);
      if (typeof c.activeId === 'string' || c.activeId === null) setActiveId(c.activeId ?? null);
      if (typeof c.tabName === 'string') setTabName(c.tabName);
      if (Array.isArray(c.tags)) setTags(c.tags);
      else if (typeof c.tag === 'string' && c.tag) setTags([c.tag]);
    }
  }

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const vals = await Storage.multiGet([ENTRIES_KEY, TABS_KEY, CATALOG_KEY, CONFIG_KEY]);
        if (cancelled) return;
        applyPersisted(ENTRIES_KEY, vals[ENTRIES_KEY]);
        applyPersisted(TABS_KEY, vals[TABS_KEY]);
        applyPersisted(CATALOG_KEY, vals[CATALOG_KEY]);
        applyPersisted(CONFIG_KEY, vals[CONFIG_KEY]);
      } catch {
        // ignore corrupt/missing storage — fall back to the seed + defaults
      }
      // was a `finally` — same effect, since the catch above swallows
      // everything, but the React Compiler can't lower a finalizer and was
      // skipping the whole provider because of it
      if (!cancelled) hydrated.current = true;
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Live sync: when iCloud pushes a write made on another device, pull the changed
  // keys (this also refreshes the local cache) and fold them into state.
  useEffect(() => {
    if (!Storage.isICloudAvailable) return;
    const PERSISTED = [ENTRIES_KEY, TABS_KEY, CATALOG_KEY, CONFIG_KEY];
    const sub = Storage.addChangeListener(({ keys }) => {
      const changed = keys.length ? keys.filter((k) => PERSISTED.includes(k)) : PERSISTED;
      changed.forEach(async (key) => applyPersisted(key, await Storage.getItem(key)));
    });
    return () => sub.remove();
  }, []);

  useEffect(() => {
    if (!hydrated.current) return;
    Storage.setItem(ENTRIES_KEY, JSON.stringify(entries));
  }, [entries]);

  useEffect(() => {
    if (!hydrated.current) return;
    Storage.setItem(CATALOG_KEY, JSON.stringify(catalog.map((name) => ({ name }))));
  }, [catalog]);

  useEffect(() => {
    if (!hydrated.current) return;
    const cfg: PersistedConfig = { themeMode, accent, showExpr, showTotal, activeId, tabName, tags };
    Storage.setItem(CONFIG_KEY, JSON.stringify(cfg));
  }, [themeMode, accent, showExpr, showTotal, activeId, tabName, tags]);

  // The active tab's authoritative state is the live `entries`/`tabName`/`tags`;
  // we fold that into its stored snapshot on read (and at persist time) rather
  // than mirroring it back into state with an effect. This keeps the Saved list
  // and the on-disk copy in step without duplicating state.
  //
  // Written inline rather than through a helper so the memo's deps are exactly
  // what it reads, with no lint suppression — one suppression is enough for the
  // React Compiler to skip the whole provider.
  const tabs = useMemo(() => {
    if (activeId == null) return rawTabs;
    return rawTabs.map((tb) => (tb.id === activeId ? { ...migrate(tb, tags), name: tabName, entries } : tb));
  }, [rawTabs, activeId, tabName, tags, entries]);

  useEffect(() => {
    if (!hydrated.current) return;
    Storage.setItem(TABS_KEY, JSON.stringify(tabs));
  }, [tabs]);

  const total = useMemo(() => entries.reduce((a, e) => a + (e.value || 0), 0), [entries]);
  const theme = useMemo(() => resolveTheme(themeMode, accent), [themeMode, accent]);

  function defaultTabName() {
    return new Date().toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
  }

  // ── tag catalog ──────────────────────────────────────────────────────────
  // The catalog is the source of truth for the chooser, the filter bar and
  // Settings. A tab may only reference catalog names; creating a tag adds it to
  // the catalog first, then assigns it.

  function addCatalogTag(raw: string): string | null {
    const name = normalizeTagName(raw);
    if (!name) return null;
    const existing = catalog.find((c) => c.toLowerCase() === name.toLowerCase());
    if (existing) return existing;
    setCatalog((l) => [...l, name]);
    return name;
  }

  /** Delete a catalog tag and cascade the removal to every tab that used it. */
  function removeCatalogTag(name: string) {
    setCatalog((l) => l.filter((c) => c !== name));
    setRawTabs((list) =>
      list.map((tb) => {
        const next = tagsOf(tb).filter((x) => x !== name);
        return next.length === tagsOf(tb).length && Array.isArray(tb.tags) ? tb : migrate(tb, next);
      }),
    );
    setTags((cur) => cur.filter((x) => x !== name));
  }

  /** Rename a catalog tag and cascade the new name through every tab. */
  function renameCatalogTag(name: string, rawNext: string) {
    const next = normalizeTagName(rawNext);
    if (!next || next === name) return;
    setCatalog((l) => dedupeTags(l.map((c) => (c === name ? next : c))));
    const rename = (arr: string[]) => dedupeTags(arr.map((x) => (x === name ? next : x)));
    setRawTabs((list) =>
      list.map((tb) => (tagsOf(tb).includes(name) || tb.tag === name ? migrate(tb, rename(tagsOf(tb))) : tb)),
    );
    setTags((cur) => rename(cur));
  }

  function toggleTag(name: string) {
    setTags((cur) => (cur.includes(name) ? cur.filter((x) => x !== name) : [...cur, name]));
  }

  /** Set the tags on a saved tab — or the live tab when that tab is active. */
  function setTabTags(id: string, next: string[]) {
    if (id === activeId) {
      setTags(next);
      return;
    }
    setRawTabs((list) => list.map((tb) => (tb.id === id ? migrate(tb, next) : tb)));
  }

  function saveDraft(override?: { name?: string; tags?: string[] }) {
    if (!entries.length) return;
    const id = activeId || uid();
    const nextTags = override?.tags ?? tags;
    const name = ((override?.name ?? tabName) || '').trim() || defaultTabName();
    const snap: Tab = { id, name, tags: nextTags, entries, savedAt: Date.now() };
    setRawTabs((list) =>
      list.some((tb) => tb.id === id) ? list.map((tb) => (tb.id === id ? snap : tb)) : [snap, ...list],
    );
    setActiveId(id);
    setTabName(name);
    setTags(nextTags);
  }

  /** Fold the current live edits back into whichever tab we're leaving. */
  function commitActive() {
    if (activeId == null) {
      if (entries.length) saveDraft();
    } else {
      setRawTabs((list) =>
        list.map((tb) => (tb.id === activeId ? { ...migrate(tb, tags), name: tabName, entries, savedAt: Date.now() } : tb)),
      );
    }
  }

  function openTab(id: string) {
    if (id === activeId) return; // already open — nothing to load
    const tb = rawTabs.find((x) => x.id === id);
    if (!tb) return;
    commitActive(); // never lose the tab we're leaving
    setEntries((tb.entries || []).map((e) => ({ ...e })));
    setTabName(tb.name || '');
    setTags(tagsOf(tb));
    setActiveId(id);
    swapTab();
  }

  function newTab() {
    commitActive();
    setEntries([]);
    setTabName('');
    setTags([]);
    setActiveId(null);
    swapTab();
  }

  /**
   * File an externally sourced snapshot (a share link) as a new saved tab and
   * open it. Entries must already carry fresh local ids (see share-link's
   * remapEntries). Unknown tags join the catalog — a tab may only reference
   * catalog names.
   */
  function importTab(name: string, importedTags: string[], imported: Entry[]): string {
    const id = uid();
    const cleanTags = dedupeTags(importedTags.map(normalizeTagName).filter(Boolean));
    const snap: Tab = {
      id,
      name: (name || '').trim() || defaultTabName(),
      tags: cleanTags,
      entries: imported,
      savedAt: Date.now(),
    };
    commitActive(); // never lose the tab we're leaving — same as openTab
    if (cleanTags.length) setCatalog((l) => dedupeTags([...l, ...cleanTags]));
    setRawTabs((list) => [snap, ...list]);
    setEntries(imported.map((e) => ({ ...e })));
    setTabName(snap.name);
    setTags(cleanTags);
    setActiveId(id);
    swapTab();
    return id;
  }

  function deleteTab(id: string) {
    setRawTabs((list) => list.filter((x) => x.id !== id));
    if (id === activeId) {
      setActiveId(null);
      setEntries([]);
      setTabName('');
      setTags([]);
      swapTab();
    }
  }

  const value: TallyContextValue = {
    entries,
    setEntries,
    total,

    tabs,
    activeId,
    tabEpoch,
    tabName,
    setTabName,
    tags,
    setTags,
    toggleTag,
    setTabTags,

    catalog,
    addCatalogTag,
    removeCatalogTag,
    renameCatalogTag,

    saveDraft,
    openTab,
    newTab,
    deleteTab,
    importTab,

    themeMode,
    setThemeMode,
    accent,
    setAccent,
    showExpr,
    setShowExpr,
    showTotal,
    setShowTotal,

    theme,
  };

  return <TallyContext.Provider value={value}>{children}</TallyContext.Provider>;
}

export function useTally(): TallyContextValue {
  const ctx = useContext(TallyContext);
  if (!ctx) throw new Error('useTally must be used within a TallyProvider');
  return ctx;
}
