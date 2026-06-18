// tally-store.tsx — shared state for the running tab: the list of entries and
// the user's preferences, plus the resolved theme. Lives in a context so the
// calculator screen and the settings modal stay in sync, and is persisted to
// the device with AsyncStorage so a tab survives app restarts.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';

import { ACCENTS, resolveTheme, type TallyTheme, type ThemeMode } from '@/constants/tally-theme';

export type Entry = {
  id: string;
  /** short label, e.g. "Coffee" — optional */
  note: string;
  /** the raw expression when it's more than a plain number, e.g. "60÷4" */
  expr: string;
  value: number;
};

const ENTRIES_KEY = 'tally:entries';
const CONFIG_KEY = 'tally:config';

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
};

type TallyContextValue = {
  entries: Entry[];
  setEntries: React.Dispatch<React.SetStateAction<Entry[]>>;
  total: number;

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
  const [themeMode, setThemeMode] = useState<ThemeMode>('light');
  const [accent, setAccent] = useState<string>(ACCENTS[0].accent);
  const [showExpr, setShowExpr] = useState(true);
  const [showTotal, setShowTotal] = useState(true);

  // Don't persist until we've loaded once, or the initial seed/defaults would
  // clobber what's already on disk before hydration finishes.
  const hydrated = useRef(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [eRaw, cRaw] = await Promise.all([
          AsyncStorage.getItem(ENTRIES_KEY),
          AsyncStorage.getItem(CONFIG_KEY),
        ]);
        if (cancelled) return;
        if (eRaw) {
          const arr = JSON.parse(eRaw);
          if (Array.isArray(arr)) {
            syncIdCounter(arr);
            setEntries(arr);
          }
        }
        if (cRaw) {
          const c = JSON.parse(cRaw) as Partial<PersistedConfig>;
          if (c.themeMode) setThemeMode(c.themeMode);
          if (c.accent) setAccent(c.accent);
          if (typeof c.showExpr === 'boolean') setShowExpr(c.showExpr);
          if (typeof c.showTotal === 'boolean') setShowTotal(c.showTotal);
        }
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

  useEffect(() => {
    if (!hydrated.current) return;
    AsyncStorage.setItem(ENTRIES_KEY, JSON.stringify(entries)).catch(() => {});
  }, [entries]);

  useEffect(() => {
    if (!hydrated.current) return;
    const cfg: PersistedConfig = { themeMode, accent, showExpr, showTotal };
    AsyncStorage.setItem(CONFIG_KEY, JSON.stringify(cfg)).catch(() => {});
  }, [themeMode, accent, showExpr, showTotal]);

  const total = useMemo(() => entries.reduce((a, e) => a + (e.value || 0), 0), [entries]);
  const theme = useMemo(() => resolveTheme(themeMode, accent), [themeMode, accent]);

  const value: TallyContextValue = {
    entries,
    setEntries,
    total,
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
