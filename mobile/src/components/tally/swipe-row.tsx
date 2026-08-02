// swipe-row.tsx — a single line in the running tab, rendered as a native
// SwiftUI list row. Swipe left for a native Delete action, long-press for a
// native context menu (Edit / Delete), tap to edit. The row's visual is the
// existing RN layout embedded via RNHostView, so the custom fonts and the expr
// chip survive while the gestures are pure SwiftUI. Must be rendered inside a
// SwiftUI `List` + `Section` (see index.tsx) — SwipeActions only works there.
import { Button, ContextMenu, RNHostView, SwipeActions } from '@expo/ui/swift-ui';
import { listRowBackground, listRowInsets, listRowSeparator } from '@expo/ui/swift-ui/modifiers';
import { useEffect, useRef } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
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
import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { type Entry } from '@/lib/tally-store';

// The list's 16pt content margin lives on the row rather than on the RN wrapper
// around the Host: the host has to run edge-to-edge so the scroll indicator sits
// on the screen edge, not 16pt inside it (see `list` in index.tsx). It's a
// margin on the RN row and not `listRowInsets` — a leading/trailing inset there
// doesn't move an RNHostView row. Rows are transparent for a related reason: an
// opaque row fill painted a flat panel over the screen's accent bloom, and the
// seam between the two showed along the inset edges.
const ROW_INSET = 16;

type Props = {
  entry: Entry;
  selected: boolean;
  showExpr: boolean;
  /** the final row in the list draws no divider beneath it */
  last?: boolean;
  /** freshly committed — flash the selection tint once to draw the eye */
  justAdded?: boolean;
  /** display name for a reference id in this row's expression */
  nameFor: (id: string) => string;
  theme: TallyTheme;
  /** the draft is allowed to reference this line (it sits above the edit point) */
  canReference?: boolean;
  onEdit: (e: Entry) => void;
  onDelete: (id: string) => void;
  onSelect: (e: Entry) => void;
  onReference: (e: Entry) => void;
};

export function SwipeRow({
  entry: e,
  selected,
  showExpr,
  last,
  justAdded,
  nameFor,
  theme: t,
  canReference,
  onEdit,
  onDelete,
  onSelect,
  onReference,
}: Props) {
  // One-shot highlight, shared by two moments that deserve the eye:
  //  · a freshly committed row — swells in, holds while the list finishes
  //    scrolling the row into view, then fades
  //  · a live-reference ripple — this row's value just recomputed because a
  //    line it references changed
  // Rendered as its own overlay so it never fights the static row background.
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

  const lit = selected;

  const body = (
    <RNHostView matchContents>
      {/* padding on a wrapper, not a margin on the row: a margin inside a
          matchContents host narrows the row without offsetting it, so it drifts
          left */}
      <View style={styles.rowWrap}>
        <Pressable
          onPress={() => onEdit(e)}
          accessibilityRole="button"
          style={({ pressed }) => [
            styles.row,
            { borderBottomColor: t.line },
            (lit || last) && { borderBottomColor: 'transparent' },
            lit && { backgroundColor: t.rowSel, borderRadius: 10 },
            pressed && styles.pressed,
          ]}>
          <Animated.View style={[styles.glow, glowStyle]} pointerEvents="none" />
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
        </Pressable>
      </View>
    </RNHostView>
  );

  return (
    <SwipeActions
      modifiers={[
        // 0.01, not 0: @expo/ui's ListRowInsets modifier no-ops when every value
        // is exactly 0 ("if top != 0 || … else { content }"), which leaves
        // SwiftUI's default ~11pt vertical insets on the cell. A hundredth of a
        // point is invisible but keeps the modifier applied.
        listRowInsets({ top: 0.01, leading: 0.01, bottom: 0.01, trailing: 0.01 }),
        listRowBackground('transparent'),
        listRowSeparator('hidden'),
      ]}>
      {/* long-press → native context menu; the row itself is the trigger */}
      <ContextMenu>
        <ContextMenu.Items>
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
        </ContextMenu.Items>
        <ContextMenu.Trigger>{body}</ContextMenu.Trigger>
      </ContextMenu>

      {/* swipe left → native Delete */}
      <SwipeActions.Actions edge="trailing">
        <Button label="Delete" systemImage="trash" role="destructive" onPress={() => onDelete(e.id)} />
      </SwipeActions.Actions>
    </SwipeActions>
  );
}

const styles = StyleSheet.create({
  rowWrap: { paddingHorizontal: ROW_INSET },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
    paddingVertical: 7,
    paddingHorizontal: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  // design press feedback — the row squishes slightly rather than fading
  pressed: { transform: [{ scale: 0.985 }] },
  // just-added flash — same radius as the selected state so the two read as one
  glow: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, borderRadius: 10 },
  rowLhs: { flex: 1, minWidth: 0 },
  noteRow: { flexDirection: 'row', alignItems: 'baseline', gap: 5 },
  note: { fontFamily: TallyFonts.sansMedium, fontSize: 13.5, flexShrink: 1 },
  noteEmpty: { fontStyle: 'italic' },
  num: { fontFamily: TallyFonts.mono, fontSize: 10.5 },
  exprWrap: { marginTop: 3 },
  // 12pt floor — the 10pt chips read as decoration, not as the calculation
  expr: {
    alignSelf: 'flex-start',
    fontFamily: TallyFonts.mono,
    fontSize: 12,
    paddingVertical: 2,
    paddingHorizontal: 6,
    borderRadius: 6,
    marginTop: 3,
    overflow: 'hidden',
  },
  amt: { fontFamily: TallyFonts.monoMedium, fontSize: 13.5, fontVariant: ['tabular-nums'], marginTop: 1 },
});
