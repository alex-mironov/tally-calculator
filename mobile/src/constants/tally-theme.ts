// tally-theme.ts — palette, accents and fonts for the Tally
// running-tab calculator. The colour scales live in the Design System v2 token
// module (constants/tokens.ts); this file composes them with the chosen accent
// into the runtime `TallyTheme` the screens consume.
import { Accents, LegacyAccents, Neutral, type AccentToken } from '@/constants/tokens';

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

const BASE: { light: Omit<BasePalette, 'rowSel'>; dark: Omit<BasePalette, 'rowSel'> } = {
  light: {
    ...Neutral.light,
    totalBg: Neutral.light.deep,
    totalInk: Neutral.light.deepInk,
    totalSub: '#a0a0a8',
  },
  dark: {
    ...Neutral.dark,
    totalBg: Neutral.dark.deep,
    totalInk: Neutral.dark.deepInk,
    totalSub: '#a0a0a8',
  },
};

export type Accent = AccentToken;

export const ACCENTS: Accent[] = Accents;

export type TallyTheme = BasePalette & {
  /** The hue as a fill — swatches, solid chips, tinted containers. */
  accent: string;
  /** Soft tinted surface for accent-coloured content to sit on. */
  accent2: string;
  /** The readable shade: accent-coloured text, glyphs and hairlines. */
  accentInk: string;
  /** Foreground for content drawn on top of `accent`. */
  onAccent: string;
  /**
   * The accent shade white always reads on, in either theme — for the system
   * controls that draw their own white label over a tint (`borderedProminent`
   * / `glassProminent` buttons, the segmented picker) and so can't be handed a
   * bright fill.
   */
  accentSolid: string;
};

/** rgba() string from a #rrggbb hex, for the low-alpha washes below. */
function alpha(hex: string, a: number): string {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

/** The stored accent hex → its token, forgiving a palette the app has retired. */
export function resolveAccent(accentHex: string): Accent {
  const hex = LegacyAccents[accentHex] ?? accentHex;
  return ACCENTS.find((a) => a.accent === hex) ?? ACCENTS[0];
}

/** Compose a base palette with the chosen accent, mirroring the prototype. */
export function resolveTheme(mode: ThemeMode, accentHex: string): TallyTheme {
  const base = BASE[mode];
  const ac = resolveAccent(accentHex);
  const dark = mode === 'dark';
  return {
    ...base,
    accent: ac.accent,
    accent2: dark ? ac.softDark : ac.softLight,
    accentInk: dark ? ac.inkDark : ac.inkLight,
    onAccent: ac.onAccent,
    accentSolid: ac.inkLight,
    // the selected row is a wash of the accent, so it has to follow it: the
    // readable shade in dark (the raw hue disappears into the surface there),
    // the hue itself in light
    rowSel: dark ? alpha(ac.inkDark, 0.13) : alpha(ac.accent, 0.07),
    totalBg: dark ? ac.accent : base.totalBg,
    totalInk: dark ? ac.onAccent : base.totalInk,
    totalSub: dark ? alpha(ac.onAccent, 0.72) : base.totalSub,
  };
}
