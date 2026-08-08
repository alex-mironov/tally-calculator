// grouped-list.tsx — the app's one list. Every list surface goes through this:
// the calculator's running tab, the Saved archive, anything after them.
//
// It is a native SwiftUI inset-grouped `List`, and the point of routing
// everything through it is that SwiftUI owns the chrome — the card, its rounded
// ends, its 1pt separators, its row fills. We only supply the contents of a row.
//
// That division matters more than it sounds, because of one quirk: a row hosted
// from React Native (`RNHostView`) is *not* laid out inside the section's inset.
// SwiftUI insets the cell — its background, its separators, its corners — while
// the hosted view keeps being measured at the list's full width. Hand-drawing
// the card in RN to compensate looked right until a `.contextMenu` was attached
// to a row: `.contextMenu` pads its trigger so the lifted preview platter has a
// margin, that padding lives inside the cell but outside the hosted content, and
// an RN-drawn card left it showing as a grey band between every pair of rows.
//
// `listRowBackground` has no such blind spot — it fills the entire cell, padding
// included — so the fill is SwiftUI's and the rows can never drift apart again.
// The only thing left for us is to push the row's *content* inward by the inset
// SwiftUI already applied to everything else, which is what ROW_INSET is for.
import { ContextMenu, Host, List, RNHostView, Section, SwipeActions } from '@expo/ui/swift-ui';
import {
  listRowBackground,
  listRowInsets,
  listRowSeparator,
  listRowSpacing,
  listSectionMargins,
  listSectionSpacing,
  listStyle,
  scrollContentBackground,
} from '@expo/ui/swift-ui/modifiers';
import { forwardRef, type ReactNode } from 'react';
import { Pressable, StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native';

import { type TallyTheme } from '@/constants/tally-theme';

/**
 * SwiftUI's own horizontal inset for an inset-grouped section on iPhone —
 * measured at 16pt on iOS 26 (screenshot pixel-count on an iPhone 17), not the
 * classic 20. The RN twin below uses the same value so both renderers put the
 * card in the same place.
 */
const CELL_INSET = 16;
/** The row text's margin from the card's edge. */
const ROW_PAD = 16;
/** Matches the corner SwiftUI rounds an inset-grouped section to. */
const CARD_RADIUS = 12;
/** Vertical padding and tap floor, shared by both renderers. */
const ROW_PAD_V = 12;
const ROW_MIN_H = 44;

/**
 * What a hosted row pads to sit ROW_PAD inside the card: the cell inset SwiftUI
 * applied to the card but not to us, plus the margin we actually want. Exported
 * so a row's own inner decoration (a full-bleed highlight, say) can line up
 * with the card rather than with the list.
 */
export const ROW_INSET = CELL_INSET + ROW_PAD;

/** The card's own margin from the screen edge, for the RN renderer below. */
export const CARD_INSET = CELL_INSET;

type ListProps = {
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
  /**
   * Drop the ~35pt of top padding SwiftUI gives the first inset-grouped
   * section, for screens that stack their own chrome (a filter bar, a pinned
   * card) right above the list and want to own that gap themselves.
   */
  trimTop?: boolean;
};

/**
 * The list itself. Full-bleed on purpose — the scroll indicator rides the
 * host's trailing edge, and the card's inset from the screen is SwiftUI's, not
 * padding of ours. The wrapper `View` exists so callers have a react tag to
 * hand the ListScroll native module (a `Host` doesn't expose one), and is
 * `collapsable={false}` so RN can't flatten it away.
 */
export const GroupedList = forwardRef<View, ListProps>(function GroupedList(
  { children, style, trimTop },
  ref,
) {
  return (
    <View ref={ref} style={[styles.wrap, style]} collapsable={false}>
      <Host style={styles.host}>
        <List
          modifiers={[
            listStyle('insetGrouped'),
            scrollContentBackground('hidden'),
            listRowSpacing(0),
            listSectionSpacing(0),
          ]}>
          {/* the margin modifier is per-section content, so it lives on the
              Section — on the List it's silently ignored */}
          <Section modifiers={trimTop ? [listSectionMargins({ length: 0, edges: 'top' })] : undefined}>
            {children}
          </Section>
        </List>
      </Host>
    </View>
  );
});

type RowProps = {
  theme: TallyTheme;
  /** first row of the card — suppresses the leading separator */
  first?: boolean;
  /**
   * Tint for this row, applied as the *cell's* background so it fills the whole
   * cell and clips to the card's rounded ends. An RN fill inside the row can't
   * do either — it stops at the content and squares off the corners.
   */
  fill?: string;
  onPress?: () => void;
  accessibilityLabel?: string;
  /** ticked in a multi-select — announced once, by the row */
  selected?: boolean;
  /** SwiftUI `Button`s for the long-press context menu; omit for no menu */
  menu?: ReactNode;
  /** SwiftUI `Button`s revealed by a swipe from each edge */
  swipeLeading?: ReactNode;
  swipeTrailing?: ReactNode;
  children: ReactNode;
};

/**
 * One row. `children` is plain RN — fonts, chips, whatever the screen needs —
 * and everything around it is the system's.
 */
export function GroupedRow({
  theme: t,
  first,
  fill,
  onPress,
  accessibilityLabel,
  selected,
  menu,
  swipeLeading,
  swipeTrailing,
  children,
}: RowProps) {
  const body = (
    <RNHostView matchContents>
      <Pressable
        onPress={onPress}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        accessibilityState={selected == null ? undefined : { selected }}
        style={({ pressed }) => [styles.row, pressed && styles.pressed]}>
        {/* our own hairline, same geometry as the system's (text inset to the
            card's trailing edge) but in the design's line colour */}
        {!first && <View style={[styles.rowSep, { backgroundColor: t.line }]} pointerEvents="none" />}
        {children}
      </Pressable>
    </RNHostView>
  );

  return (
    <SwipeActions
      modifiers={[
        // 0.01, not 0: @expo/ui's ListRowInsets modifier no-ops when every value
        // is exactly 0 ("if top != 0 || … else { content }"), which would leave
        // SwiftUI's default ~11pt vertical insets on the cell.
        listRowInsets({ top: 0.01, leading: 0.01, bottom: 0.01, trailing: 0.01 }),
        listRowBackground(fill ?? t.card),
        // The system separator is hidden and redrawn in RN above: @expo/ui has
        // no listRowSeparatorTint, and UIKit's separator grey reads far darker
        // than the design's t.line hairline.
        listRowSeparator('hidden'),
      ]}>
      {menu ? (
        <ContextMenu>
          <ContextMenu.Items>{menu}</ContextMenu.Items>
          <ContextMenu.Trigger>{body}</ContextMenu.Trigger>
        </ContextMenu>
      ) : (
        body
      )}

      {swipeTrailing ? <SwipeActions.Actions edge="trailing">{swipeTrailing}</SwipeActions.Actions> : null}
      {swipeLeading ? (
        <SwipeActions.Actions edge="leading" allowsFullSwipe={false}>
          {swipeLeading}
        </SwipeActions.Actions>
      ) : null}
    </SwipeActions>
  );
}

// ---------------------------------------------------------------------------
// The same card, drawn in React Native.
//
// Two screens can't take the SwiftUI list above and it's worth saying why, so
// nobody "fixes" it later: Settings and the Tags catalog both use
// `headerLargeTitle`, and only an RN ScrollView can drive a large title's
// collapse — a SwiftUI List would leave it permanently expanded (the same
// reason the tab and Saved run inline titles instead). Tags additionally edits
// and creates tags through inline TextInputs, which would end up inside hosted
// rows and fight the list for focus.
//
// So those screens get a second renderer rather than a second design: the card
// inset, corner, row padding, tap floor and separator inset are the constants
// above, so the two can't drift apart. What they give up is what SwiftUI's list
// is actually for — swipe actions and context menus — which neither screen has.

/** The card. Wraps `CardRow`s inside a ScrollView. */
export function GroupedCard({
  theme: t,
  style,
  children,
}: {
  theme: TallyTheme;
  style?: StyleProp<ViewStyle>;
  children: ReactNode;
}) {
  return <View style={[styles.card, { backgroundColor: t.card }, style]}>{children}</View>;
}

/** One row in a `GroupedCard`. `first` suppresses the leading separator. */
export function CardRow({
  theme: t,
  first,
  onPress,
  disabled,
  style,
  children,
  ...a11y
}: {
  theme: TallyTheme;
  first?: boolean;
  onPress?: () => void;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  children: ReactNode;
} & Pick<
  React.ComponentProps<typeof Pressable>,
  'accessibilityRole' | 'accessibilityState' | 'accessibilityLabel'
>) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled ?? !onPress}
      style={({ pressed }) => [styles.cardRow, onPress && pressed && styles.rowPressed, style]}
      {...a11y}>
      {/* inset to the text and flush to the card's trailing edge, the way a
          grouped list draws its own */}
      {!first && <View style={[styles.cardSep, { backgroundColor: t.line }]} pointerEvents="none" />}
      {children}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1 },
  host: { flex: 1, backgroundColor: 'transparent' },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
    // 44 is the HIG floor for a row you can tap
    minHeight: ROW_MIN_H,
    paddingVertical: ROW_PAD_V,
    paddingHorizontal: ROW_INSET,
  },
  // design press feedback — the row squishes slightly rather than fading
  pressed: { transform: [{ scale: 0.99 }] },
  // the hosted row spans the full list width (see header comment), so the line
  // runs from the text inset to the card's trailing edge, like the system's
  rowSep: {
    position: 'absolute',
    top: 0,
    left: ROW_INSET,
    right: CELL_INSET,
    height: StyleSheet.hairlineWidth,
  },

  // the RN twin — same numbers, but the card is ours to draw, so the inset is
  // a margin rather than something to pad the content past
  card: { marginHorizontal: CELL_INSET, borderRadius: CARD_RADIUS, overflow: 'hidden' },
  cardRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    minHeight: ROW_MIN_H,
    paddingVertical: ROW_PAD_V,
    paddingHorizontal: ROW_PAD,
  },
  rowPressed: { opacity: 0.6 },
  cardSep: { position: 'absolute', left: ROW_PAD, right: 0, top: 0, height: StyleSheet.hairlineWidth },
});
