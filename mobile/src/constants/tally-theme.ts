// tally-theme.ts — palette, accents and fonts for the Tally
// running-tab calculator. Ported from the concept prototype (tally-app.jsx).

export type ThemeMode = 'light' | 'dark';

/**
 * Font families. These names must match the keys the fonts are registered
 * under in the root layout (see _layout.tsx). With custom fonts the family
 * carries the weight, so we expose one entry per weight we actually use.
 * The whole app runs on Geist:
 *   - serif  → Geist Medium (display headings — the old serif role)
 *   - sans   → Geist (UI text)
 *   - mono   → Geist Mono (numbers & labels)
 */
export const TallyFonts = {
  serif: 'Geist-Medium',

  sans: 'Geist-Regular',
  sansMedium: 'Geist-Medium',
  sansSemi: 'Geist-SemiBold',
  sansBold: 'Geist-Bold',

  mono: 'GeistMono-Regular',
  monoMedium: 'GeistMono-Medium',
  monoSemi: 'GeistMono-SemiBold',
} as const;

// Cool-neutral gray palette (2026 refresh, 24 Jun). The neutrals are theme
// chrome; the raspberry accent and its soft tints live in ACCENTS below.
const BASE = {
  light: {
    screen: '#ececef',
    ink: '#1a1a1d',
    ink2: '#6b6b73',
    ink3: '#a6a6af',
    line: '#e4e4ea',
    card: '#ffffff',
    key: '#ffffff',
    keyLine: 'rgba(0,0,0,0.05)',
    totalBg: '#1b1b1e',
    totalInk: '#f4f4f6',
    totalSub: '#a0a0a8',
    rowSel: 'rgba(179,71,106,0.07)',
    deep: '#1b1b1e',
    deepInk: '#f4f4f6',
  },
  dark: {
    screen: '#161618',
    ink: '#f3f3f5',
    ink2: '#a4a4ac',
    ink3: '#65656e',
    line: '#2a2a2e',
    card: '#1f1f22',
    key: '#242428',
    keyLine: 'rgba(255,255,255,0.05)',
    totalBg: '#b3476a',
    totalInk: '#ffffff',
    totalSub: '#f0c2d0',
    rowSel: 'rgba(217,107,142,0.13)',
    deep: '#f3f3f5',
    deepInk: '#161618',
  },
};

export type Accent = {
  name: string;
  accent: string;
  softLight: string;
  softDark: string;
  inkLight: string;
  inkDark: string;
};

export const ACCENTS: Accent[] = [
  { name: 'Raspberry', accent: '#b3476a', softLight: '#f4dbe2', softDark: '#3a1c26', inkLight: '#9c3458', inkDark: '#f0a8bd' },
  { name: 'Magenta', accent: '#c33a6e', softLight: '#f6d6e3', softDark: '#3a1722', inkLight: '#a82a5a', inkDark: '#f3a0bf' },
  { name: 'Plum', accent: '#864a7a', softLight: '#ecd9e8', softDark: '#2f2030', inkLight: '#6e3a64', inkDark: '#d6a6cd' },
  { name: 'Wine', accent: '#9c3a48', softLight: '#f1d6d9', softDark: '#341a1d', inkLight: '#852e3a', inkDark: '#e6a0a8' },
  { name: 'Ink', accent: '#2a2420', softLight: '#e6ddcf', softDark: '#2a2420', inkLight: '#2a2420', inkDark: '#d8cdbb' },
];

export type TallyTheme = (typeof BASE)['light'] & {
  accent: string;
  accent2: string;
  accentInk: string;
};

/** Compose a base palette with the chosen accent, mirroring the prototype. */
export function resolveTheme(mode: ThemeMode, accentHex: string): TallyTheme {
  const base = BASE[mode];
  const ac = ACCENTS.find((a) => a.accent === accentHex) ?? ACCENTS[0];
  return {
    ...base,
    accent: ac.accent,
    accent2: mode === 'dark' ? ac.softDark : ac.softLight,
    accentInk: mode === 'dark' ? ac.inkDark : ac.inkLight,
    totalBg: mode === 'dark' ? ac.accent : base.totalBg,
  };
}
