// tally-theme.ts — palette, accents and fonts for the Tally
// running-tab calculator. The colour scales live in the Design System v2 token
// module (constants/tokens.ts); this file composes them with the chosen accent
// into the runtime `TallyTheme` the screens consume.
import { Accents, Neutral, type AccentToken } from '@/constants/tokens';

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

// Cool-neutral gray palette (Design System v2). The neutral chrome comes
// straight from the token module; we layer on the running-total surface and the
// selected-row tint, which are theme-derived rather than raw tokens.
type BasePalette = {
  screen: string;
  ink: string;
  ink2: string;
  ink3: string;
  line: string;
  card: string;
  key: string;
  keyLine: string;
  deep: string;
  deepInk: string;
  totalBg: string;
  totalInk: string;
  totalSub: string;
  rowSel: string;
};

const BASE: { light: BasePalette; dark: BasePalette } = {
  light: {
    ...Neutral.light,
    totalBg: Neutral.light.deep,
    totalInk: Neutral.light.deepInk,
    totalSub: '#a0a0a8',
    rowSel: 'rgba(179,71,106,0.07)',
  },
  dark: {
    ...Neutral.dark,
    totalBg: '#b3476a',
    totalInk: '#ffffff',
    totalSub: '#f0c2d0',
    rowSel: 'rgba(217,107,142,0.13)',
  },
};

export type Accent = AccentToken;

export const ACCENTS: Accent[] = Accents;

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
