// saved-row.tsx — one saved calculation, rendered as a native SwiftUI list row
// (the same construction as the calculator's SwipeRow). Swipe left for Delete,
// swipe right for Tags, long-press for the context menu: Open · Tags ▸ · Delete.
//
// The Tags submenu is the quick path — a checkmark per catalog tag, toggled in
// place — and "Manage tags…" at its foot opens the tag catalog screen, where
// tags can be created, renamed, deleted, searched and applied.
//
// The row's visual is the existing React Native card embedded via RNHostView, so
// the custom fonts and the tag chips survive while the gestures are pure
// SwiftUI. Must be rendered inside a SwiftUI `List` + `Section` (see saved.tsx)
// — SwipeActions only works there.
import { Button, ContextMenu, Divider, Menu, RNHostView, SwipeActions } from '@expo/ui/swift-ui';
import { listRowBackground, listRowInsets, listRowSeparator } from '@expo/ui/swift-ui/modifiers';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { TagChip } from '@/components/tally/tags';
import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { tagsOf, type Entry, type Tab } from '@/lib/tally-store';

// A context menu is a menu, not an archive: past a dozen entries the tag list
// stops being scannable and "Manage tags…" is the better door.
const SUBMENU_TAGS = 12;

const totalOf = (entries: Entry[]) => (entries || []).reduce((a, e) => a + (e.value || 0), 0);

function relDate(ts: number): string {
  if (!ts) return '';
  const d = new Date(ts);
  const now = new Date();
  const diff = (now.getTime() - d.getTime()) / 1000;
  if (diff < 60) return 'Just now';
  if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
  if (diff < 86400 && now.getDate() === d.getDate()) return Math.floor(diff / 3600) + 'h ago';
  const y = new Date(now);
  y.setDate(now.getDate() - 1);
  if (d.getDate() === y.getDate() && d.getMonth() === y.getMonth()) return 'Yesterday';
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

type Props = {
  tab: Tab;
  theme: TallyTheme;
  /** this calculation is the one currently open on the calculator */
  selected: boolean;
  catalog: string[];
  onOpen: () => void;
  onDelete: () => void;
  onToggleTag: (name: string) => void;
  onManageTags: () => void;
};

export function SavedRow({
  tab,
  theme: t,
  selected,
  catalog,
  onOpen,
  onDelete,
  onToggleTag,
  onManageTags,
}: Props) {
  const count = (tab.entries || []).length;
  const tgs = tagsOf(tab);

  // `inset` is the difference between the row as it sits in the list and the
  // row as the context menu lifts it — see the Preview slot below.
  const card = (inset: boolean) => (
    <RNHostView matchContents>
      <Pressable
        onPress={onOpen}
        style={({ pressed }) => [
          styles.card,
          inset && styles.cardInset,
          { backgroundColor: selected ? t.accent2 : t.card, borderColor: selected ? t.accent : t.line },
          pressed && styles.cardPressed,
        ]}>
        <View style={styles.cardTop}>
          <View style={styles.cardLhs}>
            <Text style={[styles.cName, { color: t.ink }]} numberOfLines={1}>
              {tab.name || 'Untitled tab'}
            </Text>
            <View style={styles.cMeta}>
              {selected && (
                <Text style={[styles.badge, { color: t.accentInk, backgroundColor: t.screen }]}>Open</Text>
              )}
              <Text style={[styles.cMetaText, { color: t.ink2 }]}>
                {count} item{count === 1 ? '' : 's'}
              </Text>
              <Text style={[styles.cMetaText, { color: t.ink3 }]}>·</Text>
              <Text style={[styles.cMetaText, { color: t.ink2 }]}>{relDate(tab.savedAt)}</Text>
            </View>
          </View>
          <Text style={[styles.cTotal, { color: t.ink }]}>{Calc.fmt(totalOf(tab.entries))}</Text>
        </View>

        {/* tags are shown, never edited here: the row is one tap target so
            the SwiftUI gestures above own everything else */}
        {tgs.length > 0 && (
          <View style={styles.tagRow}>
            {tgs.map((n) => (
              <TagChip key={n} name={n} theme={t} size="sm" />
            ))}
          </View>
        )}
      </Pressable>
    </RNHostView>
  );

  return (
    <SwipeActions
      modifiers={[
        listRowInsets({ top: 0, leading: 0, bottom: 0, trailing: 0 }),
        // clear, not the screen colour: an opaque row fill flattens the accent
        // bloom the background paints behind the cards
        listRowBackground('transparent'),
        listRowSeparator('hidden'),
      ]}>
      <ContextMenu>
        <ContextMenu.Items>
          <Button label="Open" systemImage="arrow.up.forward.app" onPress={onOpen} />
          {/* nested Menu → a real iOS submenu inside the context menu */}
          <Menu label="Tags" systemImage="tag">
            {catalog.slice(0, SUBMENU_TAGS).map((n) => (
              // A checkmark-imaged Button, not a Toggle: hosted SwiftUI Toggles
              // reach UIKit as plain menu rows, so their on-state never draws.
              <Button
                key={n}
                label={n}
                systemImage={tgs.includes(n) ? 'checkmark' : undefined}
                onPress={() => onToggleTag(n)}
              />
            ))}
            {catalog.length > 0 && <Divider />}
            <Button label="Manage tags…" systemImage="tag.circle" onPress={onManageTags} />
          </Menu>
          <Divider />
          <Button label="Delete" systemImage="trash" role="destructive" onPress={onDelete} />
        </ContextMenu.Items>

        {/* The lifted preview is the card *without* its list margins. iOS
            snapshots the trigger's whole box onto a platter filled with the
            system background, so with the margins still on it the platter drew a
            white border all the way around the card. Handing `.contextMenu` an
            explicit preview lets the platter hug the card exactly. */}
        <ContextMenu.Preview>{card(false)}</ContextMenu.Preview>

        <ContextMenu.Trigger>{card(true)}</ContextMenu.Trigger>
      </ContextMenu>

      {/* swipe left → Delete */}
      <SwipeActions.Actions edge="trailing">
        <Button label="Delete" systemImage="trash" role="destructive" onPress={onDelete} />
      </SwipeActions.Actions>

      {/* swipe right → the tag catalog, so tagging has a visible affordance and
          isn't hidden behind the long-press alone */}
      <SwipeActions.Actions edge="leading" allowsFullSwipe={false}>
        <Button label="Tags" systemImage="tag" onPress={onManageTags} />
      </SwipeActions.Actions>
    </SwipeActions>
  );
}

const styles = StyleSheet.create({
  // A saved calculation is a three-line summary, so the card is kept tight —
  // the padding used to give each one about a fifth of the screen, which turned
  // a list of five into a scroll.
  card: {
    gap: 7,
    paddingVertical: 10,
    paddingHorizontal: 14,
    borderRadius: 16,
    borderWidth: 1,
  },
  // Only the row in the list carries the margins; the lifted context-menu
  // preview drops them so the platter has nothing to paint around.
  cardInset: { marginHorizontal: 16, marginBottom: 8 },
  // design press feedback — the card squishes slightly rather than fading
  cardPressed: { transform: [{ scale: 0.99 }] },
  cardTop: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  cardLhs: { flex: 1, minWidth: 0 },
  cName: { fontFamily: TallyFonts.serif, fontSize: 16.5, lineHeight: 19, letterSpacing: -0.2 },
  cMeta: { flexDirection: 'row', alignItems: 'center', gap: 7, marginTop: 2 },
  cMetaText: { fontFamily: TallyFonts.sans, fontSize: 12.5 },
  badge: {
    fontFamily: TallyFonts.sansSemi,
    fontSize: 11,
    borderRadius: 6,
    paddingHorizontal: 7,
    paddingVertical: 2,
    overflow: 'hidden',
  },
  cTotal: { fontFamily: TallyFonts.monoSemi, fontSize: 17, fontVariant: ['tabular-nums'], letterSpacing: -0.2 },

  tagRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 7 },
});
