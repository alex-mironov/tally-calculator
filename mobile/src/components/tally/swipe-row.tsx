// swipe-row.tsx — a single line in the running tab. The list chrome (card,
// separators, row fill, swipe actions, context menu) is GroupedRow's; this file
// is only what goes *inside* the row, plus the two highlight animations that
// have to stay in React Native because they're driven per frame.
//
// In select mode the row is a different animal: a leading selection circle
// appears, the tap toggles instead of editing, and both the context menu and
// the swipe action are withheld. Selecting is a read-only lens over the tab, so
// nothing that edits or deletes a line should be one gesture away while it's on.
import { Button } from '@expo/ui/swift-ui';
import { useEffect, useRef } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import Animated, {
  Easing,
  interpolateColor,
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withSequence,
  withTiming,
} from 'react-native-reanimated';

import { ExprView } from '@/components/tally/expr-view';
import { GroupedRow, ROW_INSET } from '@/components/tally/grouped-list';
import { Icon } from '@/components/tally/icon';
import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { type Entry } from '@/lib/tally-store';

// The selection circle is a touch target as much as a symbol, so it's drawn a
// good bit larger than IconSize.row — this is the control the whole mode is
// about, not a row affordance sitting next to the label.
const TICK_SIZE = 24;

type Props = {
  entry: Entry;
  selected: boolean;
  showExpr: boolean;
  /** freshly committed — flash the selection tint once to draw the eye */
  justAdded?: boolean;
  /** display name for a reference id in this row's expression */
  nameFor: (id: string) => string;
  theme: TallyTheme;
  /** the draft is allowed to reference this line (it sits above the edit point) */
  canReference?: boolean;
  /** the tab is in multi-select: show the circle, toggle instead of edit */
  selectMode?: boolean;
  /** ticked in the current selection */
  picked?: boolean;
  onEdit: (e: Entry) => void;
  onDelete: (id: string) => void;
  onSelect: (e: Entry) => void;
  onTogglePick: (e: Entry) => void;
  onReference: (e: Entry) => void;
};

export function SwipeRow({
  entry: e,
  selected,
  showExpr,
  justAdded,
  nameFor,
  theme: t,
  canReference,
  selectMode,
  picked,
  onEdit,
  onDelete,
  onSelect,
  onTogglePick,
  onReference,
}: Props) {
  // One-shot highlight, shared by two moments that deserve the eye:
  //  · a freshly committed row — swells in, holds while the list finishes
  //    scrolling the row into view, then fades
  //  · a live-reference ripple — this row's value just recomputed because a
  //    line it references changed
  // Rendered as its own overlay so it never fights the row's static fill. It's
  // pulled out to the card's edges (see ROW_INSET) so a flash covers the row
  // rather than just the text.
  const glow = useSharedValue(0);
  const pulse = (hold: number) => {
    glow.value = withSequence(
      withTiming(1, { duration: 180, easing: Easing.out(Easing.quad) }),
      withDelay(hold, withTiming(0, { duration: 480, easing: Easing.in(Easing.quad) })),
    );
  };
  useEffect(() => {
    if (justAdded) pulse(520);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [justAdded]);

  const prevValue = useRef(e.value);
  useEffect(() => {
    if (prevValue.current === e.value) return;
    prevValue.current = e.value;
    if (!justAdded) pulse(120); // recalc ripple — shorter than the added flash
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [e.value]);

  const glowStyle = useAnimatedStyle(() => ({
    backgroundColor: interpolateColor(glow.value, [0, 1], ['rgba(0,0,0,0)', t.rowSel]),
  }));

  // The editing highlight is meaningless while selecting — the entry card it
  // refers to is off screen, and a second kind of lit row would only compete
  // with the ticks. It's the *cell's* fill, so it covers the row edge to edge
  // and clips to the card's rounded ends.
  const lit = selected && !selectMode;

  return (
    <GroupedRow
      theme={t}
      fill={lit ? t.rowSel : undefined}
      onPress={() => (selectMode ? onTogglePick(e) : onEdit(e))}
      selected={selectMode ? !!picked : undefined}
      // Select mode: no context menu, no swipe-to-delete. Editing, deleting and
      // "Use as reference" all act on a draft the mode has put away, so the row
      // is reduced to the one gesture the mode is about.
      menu={
        selectMode ? undefined : (
          <>
            <Button label="Edit" systemImage="pencil" onPress={() => onEdit(e)} />
            {/* the second way to reference a line, next to the card's Σ menu:
                drops the same live reference pill into the draft. Absent for a
                line the draft may not see — a line only references lines above
                it, which is what keeps reference cycles impossible. */}
            {canReference && (
              <Button label="Use as reference" systemImage="sum" onPress={() => onReference(e)} />
            )}
            {/* the second way into multi-select, next to the header's Select —
                long-press is where iOS trains people to look for it */}
            <Button label="Select lines" systemImage="checkmark.circle" onPress={() => onSelect(e)} />
            <Button label="Delete" systemImage="trash" role="destructive" onPress={() => onDelete(e.id)} />
          </>
        )
      }
      swipeTrailing={
        selectMode ? undefined : (
          <Button label="Delete" systemImage="trash" role="destructive" onPress={() => onDelete(e.id)} />
        )
      }>
      <Animated.View style={[styles.glow, glowStyle]} pointerEvents="none" />
      {/* Apple's own edit modes (Mail, Photos) let the leading circle carry the
          state on its own rather than filling the row. Ticked is the *filled*
          symbol — the accent becomes the circle's fill and the checkmark is
          knocked out of it, which reads across the room in a way an outlined
          tick of the same size doesn't. */}
      {selectMode && (
        <Icon
          name={picked ? 'checkmark.circle.fill' : 'circle'}
          size={TICK_SIZE}
          color={picked ? t.accent : t.ink3}
          weight="regular"
          style={styles.tick}
        />
      )}
      <View style={styles.rowLhs}>
        <View style={styles.noteRow}>
          <Text
            style={[styles.note, { color: e.note ? t.ink2 : t.ink3 }, !e.note && styles.noteEmpty]}
            numberOfLines={1}>
            {e.note || 'No note'}
          </Text>
          {/* sticky line number — how unnamed lines are referenced */}
          {e.num != null && <Text style={[styles.num, { color: t.ink3 }]}>#{e.num}</Text>}
        </View>
        {!!e.expr &&
          showExpr &&
          (Calc.refsIn(e.expr).length > 0 ? (
            <View style={styles.exprWrap}>
              <ExprView expr={e.expr} nameFor={nameFor} theme={t} variant="chip" />
            </View>
          ) : (
            <Text style={[styles.expr, { color: t.accentInk, backgroundColor: t.accent2 }]}>{e.expr}</Text>
          ))}
      </View>
      <Text style={[styles.amt, { color: t.ink }]}>{Calc.fmt(e.value)}</Text>
    </GroupedRow>
  );
}

const styles = StyleSheet.create({
  // negative insets cancel the row's own padding, so the flash fills the row
  glow: { position: 'absolute', top: -12, bottom: -12, left: -ROW_INSET, right: -ROW_INSET },
  // Icon draws its glyph centred in a box 1.6× the point size, so the negative
  // margins pull that slack back out: up, to line the circle up with the note's
  // first line rather than the row's top edge, and in on both sides so the
  // symbol — not its padding — sets the gap to the text.
  tick: { marginTop: -8, marginLeft: -8, marginRight: -4 },
  rowLhs: { flex: 1, minWidth: 0 },
  noteRow: { flexDirection: 'row', alignItems: 'baseline', gap: 4 },
  note: { fontFamily: TallyFonts.sansMedium, fontSize: 13.5, flexShrink: 1 },
  noteEmpty: { fontStyle: 'italic' },
  num: { fontFamily: TallyFonts.mono, fontSize: 10.5 },
  exprWrap: { marginTop: 4 },
  // 12pt floor — the 10pt chips read as decoration, not as the calculation
  expr: {
    alignSelf: 'flex-start',
    fontFamily: TallyFonts.mono,
    fontSize: 12,
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderRadius: 8,
    marginTop: 4,
    overflow: 'hidden',
  },
  amt: { fontFamily: TallyFonts.monoMedium, fontSize: 13.5, fontVariant: ['tabular-nums'] },
});
