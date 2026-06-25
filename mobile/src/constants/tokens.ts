// tokens.ts — Tally Design System v2 (2026 refresh): the single source of truth
// for the spatial, type, radius, colour and elevation scales. Ported from the
// handoff's tokens.css so engineering and design share one vocabulary.
//
// Notes on fidelity:
//   • The prototype's artboards are pixel-tuned and frequently sit *off* the 4px
//     grid (e.g. 13.5pt note text, 7pt row padding). We keep those exact values
//     in the screens to stay pixel-faithful; this scale documents the canonical
//     rungs the design system snaps *new* work to.
//   • Type families are intentionally Geist / Geist Mono here, not the design's
//     System (SF) / Spline Sans Mono — see TallyFonts in tally-theme.ts for the
//     rationale. The numeric scale below is family-agnostic.

import type { TextStyle } from 'react-native';

/** Type scale — size in pt. Hierarchy leans on weight, not size (DS v2). */
export const TextScale = {
  displayXl: 34, // hero statement      — display
  displayLg: 28, // screen title        — display (≈ iOS Large Title)
  displayMd: 20, // tab name            — display
  numXl: 36, // live draft amount       — mono
  numLg: 22, // running total           — mono
  bodyLg: 16, // primary body / note
  bodyMd: 14, // default UI text
  bodySm: 13, // secondary / buttons
  caption: 12, // chips, fine print
  label: 11, // mono eyebrow / meta (uppercase, tracked)
  labelSm: 10, // mono micro-label
  micro: 9, // badges
} as const;

/** Letter-spacing tokens, expressed in pt for the size they pair with. */
export const Tracking = {
  tight: -0.02, // display, as a ratio of font size
  label: 0.14, // mono labels (em)
  eyebrow: 0.22, // mono eyebrows (em)
} as const;

/** Spacing — the 4px grid. Numeric (pt) so it drops straight into styles. */
export const Space = {
  s0: 0,
  s1: 4,
  s2: 8,
  s3: 12,
  s4: 16,
  s5: 20,
  s6: 24,
  s7: 28,
  s8: 32,
  s10: 40,
  s12: 48,
} as const;

/** Corner radii. `pill` is the fully-rounded sentinel. */
export const Radius = {
  xs: 6,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 22, // glass cards / keypad keys
  pill: 999,
} as const;

/** Device canvas the artboards were laid out against (iPhone 15 logical pt). */
export const Frame = { width: 393, height: 852 } as const;

/** Cool-neutral neutrals + inverted "deep" surface, per theme. */
export const Neutral = {
  light: {
    screen: '#ececef',
    ink: '#1a1a1d',
    ink2: '#6b6b73',
    ink3: '#a6a6af',
    line: '#e4e4ea',
    card: '#ffffff',
    key: '#ffffff',
    keyLine: 'rgba(0,0,0,0.05)',
    deep: '#1b1b1e', // inverted surface (CTAs, total bar)
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
    deep: '#f3f3f5',
    deepInk: '#161618',
  },
} as const;

export type AccentToken = {
  name: string;
  accent: string;
  softLight: string;
  softDark: string;
  inkLight: string;
  inkDark: string;
};

/** Five interchangeable accents; Raspberry is the brand default. */
export const Accents: AccentToken[] = [
  { name: 'Raspberry', accent: '#b3476a', softLight: '#f4dbe2', softDark: '#3a1c26', inkLight: '#9c3458', inkDark: '#f0a8bd' },
  { name: 'Magenta', accent: '#c33a6e', softLight: '#f6d6e3', softDark: '#3a1722', inkLight: '#a82a5a', inkDark: '#f3a0bf' },
  { name: 'Plum', accent: '#864a7a', softLight: '#ecd9e8', softDark: '#2f2030', inkLight: '#6e3a64', inkDark: '#d6a6cd' },
  { name: 'Wine', accent: '#9c3a48', softLight: '#f1d6d9', softDark: '#341a1d', inkLight: '#852e3a', inkDark: '#e6a0a8' },
  { name: 'Ink', accent: '#2a2420', softLight: '#e6ddcf', softDark: '#2a2420', inkLight: '#2a2420', inkDark: '#d8cdbb' },
];

type Shadow = Pick<TextStyle, 'shadowColor' | 'shadowOpacity' | 'shadowRadius'> & {
  shadowOffset: { width: number; height: number };
  elevation: number;
};

/**
 * Elevation — the three lifts the design uses, as ready-to-spread RN shadow
 * props. `glass` is the frosted card/sheet lift, `cta` the tinted press under a
 * deep-ink button (pass the deep colour at the call site), `pop` the popover
 * float. CSS counterparts: --shadow-glass / --shadow-cta / --shadow-pop.
 */
export const Elevation = {
  glass: {
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 28,
    shadowOffset: { width: 0, height: 12 },
    elevation: 3,
  } as Shadow,
  cta: {
    shadowOpacity: 0.4,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 6 },
    elevation: 4,
  } as Omit<Shadow, 'shadowColor'>,
  pop: {
    shadowColor: '#0c0c14',
    shadowOpacity: 0.42,
    shadowRadius: 30,
    shadowOffset: { width: 0, height: 18 },
    elevation: 8,
  } as Shadow,
} as const;
