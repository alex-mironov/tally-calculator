// expr-view.tsx — renders an expression that may contain reference tokens
// ({e123} / {sum}) as literal text runs interleaved with named pills, so
// "7092.3−{e103}" reads as  7092.3 − ⟨Rent⟩  instead of leaking token syntax.
// Two variants: the big draft line in the entry card, and the small expression
// chip under a committed row.
//
// The draft is always ONE line: its runs never wrap or shrink, and it is drawn
// inside a DraftLine, which anchors the tail to the card's trailing edge, lets
// a long sum run off the leading edge under a fade, and scrolls it back.
import { StyleSheet, Text, View } from 'react-native';

import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';

/** the draft's resting size; `draftFontSize` steps down from here */
export const DRAFT_FONT_SIZE = 36;

/**
 * Rendered width of a draft, in characters. Reference tokens count as the name
 * actually drawn in the pill, not as their `{e123}` source — otherwise a draft
 * holding one short pill would be treated as long and shrink for no reason.
 */
export function draftLength(expr: string, nameFor: (id: string) => string): number {
  return Calc.splitExpr(expr).reduce(
    (n, s) => n + (s.type === 'text' ? s.text.length : nameFor(s.id).length + 1),
    0,
  );
}

/**
 * One step down once the line is long enough to crowd the card, mirroring the
 * design's 40 → 30. Past that the line stops shrinking and starts running off
 * the leading edge (see DraftLine): shrinking all the way to fit would make a
 * long sum unreadable, and the head of it matters far less than the digits
 * still being typed.
 */
export const draftFontSize = (len: number): number => (len > 11 ? 27 : DRAFT_FONT_SIZE);

type Props = {
  expr: string;
  /** display name for a reference id — a note, '#4', or 'Σ total' */
  nameFor: (id: string) => string;
  theme: TallyTheme;
  variant: 'draft' | 'chip';
  /** draft only — from `draftFontSize`, so both draft paths step together */
  fontSize?: number;
  /**
   * accent — the workings of a live line (default)
   * muted — a line that doesn't count toward the total
   * error — a line whose expression can't be evaluated
   */
  tone?: 'accent' | 'muted' | 'error';
};

export function ExprView({ expr, nameFor, theme: t, variant, tone = 'accent', fontSize }: Props) {
  const segs = Calc.splitExpr(expr);
  const draft = variant === 'draft';
  const ink = tone === 'error' ? t.danger : tone === 'muted' ? t.ink2 : t.accentInk;
  const pillBg = tone === 'muted' ? t.line : t.accent2;
  return (
    <View style={draft ? styles.draftRow : styles.chipRow}>
      {segs.map((s, i) =>
        s.type === 'text' ? (
          <Text
            key={i}
            style={
              draft
                ? [styles.draftText, { color: t.ink }, fontSize != null && { fontSize }]
                : [styles.chipText, { color: ink }]
            }
            numberOfLines={draft ? 1 : undefined}
            maxFontSizeMultiplier={draft ? 1.15 : undefined}>
            {s.text}
          </Text>
        ) : (
          <View key={i} style={[draft ? styles.draftPill : styles.chipPill, { backgroundColor: pillBg }]}>
            <Text
              style={draft ? [styles.draftPillText, { color: t.accentInk }] : [styles.chipPillText, { color: ink }]}
              numberOfLines={1}
              maxFontSizeMultiplier={draft ? 1.15 : undefined}>
              {nameFor(s.id)}
            </Text>
          </View>
        ),
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  // the entry card's big line — one row, never wrapped, measured at its full
  // width (`flexShrink: 0` on every run) so DraftLine's scroll view can carry
  // what doesn't fit rather than squeezing it. The type mirrors index.tsx's
  // `draftBig`, the same line drawn for a draft that holds no reference pills.
  draftRow: {
    flexDirection: 'row',
    flexWrap: 'nowrap',
    alignItems: 'center',
    columnGap: 4,
  },
  draftText: {
    fontFamily: TallyFonts.monoSemi,
    fontSize: DRAFT_FONT_SIZE,
    lineHeight: 44,
    fontVariant: ['tabular-nums'],
    letterSpacing: -0.8,
    flexShrink: 0,
  },
  draftPill: { borderRadius: 12, paddingHorizontal: 8, paddingVertical: 4, maxWidth: 152, flexShrink: 0 },
  draftPillText: { fontFamily: TallyFonts.sansSemi, fontSize: 16 },

  // the row chip — small, inline with the note column. 12pt floor to match
  // swipe-row's plain expr chip: below that the calculation is unreadable.
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', columnGap: 4, rowGap: 4 },
  chipText: { fontFamily: TallyFonts.mono, fontSize: 12 },
  chipPill: { borderRadius: 8, paddingHorizontal: 8, paddingVertical: 4, maxWidth: 132 },
  chipPillText: { fontFamily: TallyFonts.sansSemi, fontSize: 11.5 },
});
