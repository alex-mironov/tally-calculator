// expr-view.tsx — renders an expression that may contain reference tokens
// ({e123} / {sum}) as literal text runs interleaved with named pills, so
// "7092.3−{e103}" reads as  7092.3 − ⟨Rent⟩  instead of leaking token syntax.
// Two variants: the big draft line in the entry card, and the small expression
// chip under a committed row.
import { StyleSheet, Text, View } from 'react-native';

import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';

type Props = {
  expr: string;
  /** display name for a reference id — a note, '#4', or 'Σ total' */
  nameFor: (id: string) => string;
  theme: TallyTheme;
  variant: 'draft' | 'chip';
};

export function ExprView({ expr, nameFor, theme: t, variant }: Props) {
  const segs = Calc.splitExpr(expr);
  const draft = variant === 'draft';
  return (
    <View style={draft ? styles.draftRow : styles.chipRow}>
      {segs.map((s, i) =>
        s.type === 'text' ? (
          <Text
            key={i}
            style={draft ? [styles.draftText, { color: t.ink }] : [styles.chipText, { color: t.accentInk }]}
            maxFontSizeMultiplier={draft ? 1.15 : undefined}>
            {s.text}
          </Text>
        ) : (
          <View
            key={i}
            style={[draft ? styles.draftPill : styles.chipPill, { backgroundColor: t.accent2 }]}>
            <Text
              style={draft ? [styles.draftPillText, { color: t.accentInk }] : [styles.chipPillText, { color: t.accentInk }]}
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
  // the entry card's big line — right-aligned like the plain draft text;
  // wraps rather than clips when a long expression outgrows the card
  draftRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    alignItems: 'center',
    columnGap: 4,
    minHeight: 44,
  },
  draftText: {
    fontFamily: TallyFonts.monoSemi,
    fontSize: 36,
    lineHeight: 44,
    fontVariant: ['tabular-nums'],
    letterSpacing: -0.8,
  },
  draftPill: { borderRadius: 12, paddingHorizontal: 8, paddingVertical: 4, maxWidth: 152 },
  draftPillText: { fontFamily: TallyFonts.sansSemi, fontSize: 16 },

  // the row chip — small, inline with the note column. 12pt floor to match
  // swipe-row's plain expr chip: below that the calculation is unreadable.
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', columnGap: 4, rowGap: 4 },
  chipText: { fontFamily: TallyFonts.mono, fontSize: 12 },
  chipPill: { borderRadius: 8, paddingHorizontal: 8, paddingVertical: 4, maxWidth: 132 },
  chipPillText: { fontFamily: TallyFonts.sansSemi, fontSize: 11.5 },
});
