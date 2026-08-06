// swipe-row.tsx — a single line in the running tab, rendered as a native
// SwiftUI list row. Swipe left for a native Delete action, long-press for a
// native context menu (Edit / Delete), tap to edit. The row's visual is the
// existing RN layout embedded via RNHostView, so the custom fonts and the expr
// chip survive while the gestures are pure SwiftUI. Must be rendered inside a
// SwiftUI `List` + `Section` (see index.tsx) — SwipeActions only works there.
//
// In select mode the row is a different animal: a leading selection circle
// appears, the tap toggles instead of editing, and both the context menu and
// the swipe action are withheld. Selecting is a read-only lens over the tab, so
// nothing that edits or deletes a line should be one gesture away while it's on.
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
import { Icon } from '@/components/tally/icon';
import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { type Entry } from '@/lib/tally-store';

// The grouped card is drawn here in RN, not by `listStyle('insetGrouped')`.
// SwiftUI's card geometry never reaches a hosted row: the section inset moves
// the cell's *background*, but the RNHostView inside keeps being laid out at
// the list's full width — same blind spot the file already had to work around
// for `listRowInsets`. The visible result was a card whose text sat flush on
// its left edge and overran its right one. So the list stays `plain` and these
// three numbers own the geometry outright.
//
// CARD_INSET is the card's margin from the screen edge, ROW_PAD the text's
// margin from the card edge — matching what iOS uses for an inset-grouped list.
const CARD_INSET = 16;
const ROW_PAD = 16;
const CARD_RADIUS = 12;

// The selection circle is a touch target as much as a symbol, so it's drawn a
// good bit larger than IconSize.row — this is the control the whole mode is
// about, not a row affordance sitting next to the label.
const TICK_SIZE = 24;

// Half the vertical padding `.contextMenu` puts around its trigger, measured
// off the gap it left between cards. Applied as a negative row inset per side.
// The one number here off the 4pt grid, and deliberately: it isn't a metric
// we're choosing, it's the cancellation of one UIKit chose for us. Rounding it
// up to 4 would over-pull the cell and let the next card cover this row's
// separator hairline.
const MENU_PLATTER_PAD = 3.5;

type Props = {
  entry: Entry;
  selected: boolean;
  showExpr: boolean;
  /** the first row in the list — rounds the card's top corners */
  first?: boolean;
  /** the final row rounds the bottom corners and draws no divider beneath it */
  last?: boolean;
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
  first,
  last,
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

  // the editing highlight is meaningless while selecting — the entry card it
  // refers to is off screen, and a second kind of lit row would just compete
  // with the ticks
  const lit = selected && !selectMode;

  const body = (
    <RNHostView matchContents>
      {/* padding on a wrapper, not a margin on the row: a margin inside a
          matchContents host narrows the row without offsetting it, so it drifts
          left */}
      <View style={styles.rowWrap}>
        {/* One continuous card across the whole section: each row paints the
            same fill, and only the ends round off. `overflow: hidden` is what
            lets the row fills — the editing tint, the just-added flash — run
            edge to edge without escaping the rounded corners. */}
        <View
          style={[
            styles.card,
            { backgroundColor: t.card },
            first && styles.cardFirst,
            last && styles.cardLast,
          ]}>
          <Pressable
            onPress={() => (selectMode ? onTogglePick(e) : onEdit(e))}
            accessibilityRole="button"
            accessibilityState={selectMode ? { selected: !!picked } : undefined}
            style={({ pressed }) => [
              styles.row,
              lit && { backgroundColor: t.rowSel },
              pressed && styles.pressed,
            ]}>
            <Animated.View style={[styles.glow, glowStyle]} pointerEvents="none" />
            {/* Inset to the text and flush to the card's trailing edge, the way
                a grouped list draws its own — a border on the row itself ran
                the full width and read as a rule between two cards rather than
                a division inside one. The last row has nothing to divide from. */}
            {!last && !lit && (
              <View style={[styles.sep, { backgroundColor: t.line }]} pointerEvents="none" />
            )}
            {/* Apple's own edit modes (Mail, Photos) let the leading circle
                carry the state on its own rather than filling the row. Ticked
                is the *filled* symbol — the accent becomes the circle's fill
                and the checkmark is knocked out of it, which reads across the
                room in a way an outlined tick of the same size doesn't. */}
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
          </Pressable>
        </View>
      </View>
    </RNHostView>
  );

  const rowModifiers = [
    // Vertical insets do two jobs here.
    //
    // 0.01, not 0, is the baseline: @expo/ui's ListRowInsets modifier no-ops
    // when every value is exactly 0 ("if top != 0 || … else { content }"),
    // which would leave SwiftUI's default ~11pt insets on the cell.
    //
    // The negative value is for the context menu. `.contextMenu` pads its
    // trigger so the lifted preview platter has a margin, and that padding
    // sits *outside* the row's card — which is why the cards had a gap
    // between them in normal mode but sat flush in select mode, where the
    // menu isn't attached. Pulling the cell in by the same amount cancels it.
    listRowInsets(
      selectMode
        ? { top: 0.01, leading: 0.01, bottom: 0.01, trailing: 0.01 }
        : { top: -MENU_PLATTER_PAD, leading: 0.01, bottom: -MENU_PLATTER_PAD, trailing: 0.01 },
    ),
    // The cell itself stays clear — the card fill is the RN view's, so it lands
    // on the same geometry as the text inside it. A cell-level fill sat on the
    // list's full width instead, which is what put the card's edges and its
    // content on two different rulers.
    listRowBackground('transparent'),
    listRowSeparator('hidden'),
  ];

  // Select mode: no context menu, no swipe-to-delete. Editing, deleting and
  // "Use as reference" all act on a draft the mode has put away, so the row is
  // reduced to the one gesture the mode is about.
  if (selectMode) {
    return <SwipeActions modifiers={rowModifiers}>{body}</SwipeActions>;
  }

  return (
    <SwipeActions modifiers={rowModifiers}>
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
  rowWrap: { paddingHorizontal: CARD_INSET },
  card: { overflow: 'hidden' },
  cardFirst: { borderTopLeftRadius: CARD_RADIUS, borderTopRightRadius: CARD_RADIUS },
  cardLast: { borderBottomLeftRadius: CARD_RADIUS, borderBottomRightRadius: CARD_RADIUS },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
    // 44 is the HIG floor for a row you can tap; 12 keeps a two-line row
    // breathing without pushing it past it.
    minHeight: 44,
    paddingVertical: 12,
    paddingHorizontal: ROW_PAD,
  },
  sep: { position: 'absolute', left: ROW_PAD, right: 0, bottom: 0, height: StyleSheet.hairlineWidth },
  // Icon draws its glyph centred in a box 1.6× the point size, so the negative
  // margins pull that slack back out: up, to line the circle up with the note's
  // first line rather than the row's top edge, and in on both sides so the
  // symbol — not its padding — sets the gap to the text.
  tick: { marginTop: -8, marginLeft: -8, marginRight: -4 },
  // design press feedback — the row squishes slightly rather than fading
  pressed: { transform: [{ scale: 0.985 }] },
  // just-added flash — fills the row, clipped by the card's rounded corners
  glow: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
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
  amt: { fontFamily: TallyFonts.monoMedium, fontSize: 13.5, fontVariant: ['tabular-nums'], marginTop: 0 },
});
