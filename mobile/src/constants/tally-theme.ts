// tally-theme.ts — palette, accents, currencies and fonts for the Tally
// running-tab calculator. Ported from the concept prototype (tally-app.jsx).

export type ThemeMode = 'light' | 'dark';

/**
 * Font families. These names must match the keys the fonts are registered
 * under in the root layout (see _layout.tsx). With custom fonts the family
 * carries the weight, so we expose one entry per weight we actually use:
 *   - serif  → Newsreader (display headings)
 *   - sans   → Hanken Grotesk (UI text)
 *   - mono   → Spline Sans Mono (numbers & labels)
 */
export const TallyFonts = {
  serif: 'Newsreader_400Regular',

  sans: 'HankenGrotesk_400Regular',
  sansMedium: 'HankenGrotesk_500Medium',
  sansSemi: 'HankenGrotesk_600SemiBold',
  sansBold: 'HankenGrotesk_700Bold',

  mono: 'SplineSansMono_400Regular',
  monoMedium: 'SplineSansMono_500Medium',
  monoSemi: 'SplineSansMono_600SemiBold',
} as const;

const BASE = {
  light: {
    screen: '#faf2e3',
    ink: '#1a1612',
    ink2: '#6b6258',
    ink3: '#a89c8b',
    line: '#e8dcc6',
    card: '#ffffff',
    key: '#ffffff',
    keyLine: 'rgba(0,0,0,0.05)',
    totalBg: '#161310',
    totalInk: '#faf2e3',
    totalSub: '#b3a08a',
    rowSel: 'rgba(179,71,106,0.07)',
    deep: '#161310',
    deepInk: '#faf2e3',
  },
  dark: {
    screen: '#161310',
    ink: '#faf2e3',
    ink2: '#a89c8b',
    ink3: '#6e6456',
    line: '#2c2620',
    card: '#211c17',
    key: '#241f19',
    keyLine: 'rgba(255,255,255,0.05)',
    totalBg: '#b3476a',
    totalInk: '#ffffff',
    totalSub: '#f0c2d0',
    rowSel: 'rgba(217,107,142,0.13)',
    deep: '#faf2e3',
    deepInk: '#161310',
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

export const CURRENCIES = [
  { sym: '£', name: 'GBP' },
  { sym: '$', name: 'USD' },
  { sym: '€', name: 'EUR' },
  { sym: '¥', name: 'JPY' },
] as const;

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
