// tally-store.tsx — shared state for the running tab: the live list of entries,
// the saved tabs archive, the user's preferences, and the resolved theme. Lives
// in a context so the calculator screen, the Saved overlay and the settings
// modal stay in sync, and is persisted through `storage` (a local AsyncStorage
// cache mirrored to the iCloud key-value store) so tabs and preferences survive
// app restarts and follow the user across their devices.
import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';

import { ACCENTS, resolveTheme, type TallyTheme, type ThemeMode } from '@/constants/tally-theme';
import * as Storage from '@/lib/storage';

export type Entry = {
  id: string;
  /** short label, e.g. "Coffee" — optional */
  note: string;
  /** the raw expression when it's more than a plain number, e.g. "60÷4" */
  expr: string;
  value: number;
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

type TallyContextValue = {
  // ---- the live tab ----
  entries: Entry[];
  setEntries: React.Dispatch<React.SetStateAction<Entry[]>>;
  total: number;

  // ---- saved tabs ----
  tabs: Tab[];
  activeId: string | null;
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

  saveDraft: () => void;
  openTab: (id: string) => void;
  newTab: () => void;
  deleteTab: (id: string) => void;

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
  const [entries, setEntries] = useState<Entry[]>(seed);
  const [rawTabs, setRawTabs] = useState<Tab[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
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
  function applyPersisted(key: string, raw: string | null) {
    if (raw == null) return;
    try {
      if (key === ENTRIES_KEY) {
        const arr = JSON.parse(raw);
        if (Array.isArray(arr)) {
          syncIdCounter(arr);
          setEntries(arr);
        }
      } else if (key === TABS_KEY) {
        const arr = JSON.parse(raw) as Tab[];
        if (Array.isArray(arr)) {
          arr.forEach((tb) => syncIdCounter(tb.entries || []));
          setRawTabs(arr);
        }
      } else if (key === CATALOG_KEY) {
        // stored as [{ name }] — tolerate a bare string array too
        const arr = JSON.parse(raw);
        if (Array.isArray(arr)) {
          const names = arr
            .map((x) => (typeof x === 'string' ? x : x && typeof x.name === 'string' ? x.name : null))
            .filter((n): n is string => !!n);
          if (names.length) setCatalog(dedupeTags(names));
        }
      } else if (key === CONFIG_KEY) {
        const c = JSON.parse(raw) as Partial<PersistedConfig>;
        if (c.themeMode) setThemeMode(c.themeMode);
        if (c.accent) setAccent(c.accent);
        if (typeof c.showExpr === 'boolean') setShowExpr(c.showExpr);
        if (typeof c.showTotal === 'boolean') setShowTotal(c.showTotal);
        if (typeof c.activeId === 'string' || c.activeId === null) setActiveId(c.activeId ?? null);
        if (typeof c.tabName === 'string') setTabName(c.tabName);
        if (Array.isArray(c.tags)) setTags(c.tags);
        else if (typeof c.tag === 'string' && c.tag) setTags([c.tag]);
      }
    } catch {
      // ignore corrupt values — leave the current state in place
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
      } finally {
        if (!cancelled) hydrated.current = true;
      }
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
  function syncActiveInto(list: Tab[]): Tab[] {
    if (activeId == null) return list;
    return list.map((tb) => (tb.id === activeId ? { ...migrate(tb, tags), name: tabName, entries } : tb));
  }

  const tabs = useMemo(
    () => syncActiveInto(rawTabs),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rawTabs, activeId, tabName, tags, entries],
  );

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

  function saveDraft() {
    if (!entries.length) return;
    const id = activeId || uid();
    const name = (tabName || '').trim() || defaultTabName();
    const snap: Tab = { id, name, tags, entries, savedAt: Date.now() };
    setRawTabs((list) =>
      list.some((tb) => tb.id === id) ? list.map((tb) => (tb.id === id ? snap : tb)) : [snap, ...list],
    );
    setActiveId(id);
    setTabName(name);
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
  }

  function newTab() {
    commitActive();
    setEntries([]);
    setTabName('');
    setTags([]);
    setActiveId(null);
  }

  function deleteTab(id: string) {
    setRawTabs((list) => list.filter((x) => x.id !== id));
    if (id === activeId) {
      setActiveId(null);
      setEntries([]);
      setTabName('');
      setTags([]);
    }
  }

  const value: TallyContextValue = {
    entries,
    setEntries,
    total,

    tabs,
    activeId,
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
