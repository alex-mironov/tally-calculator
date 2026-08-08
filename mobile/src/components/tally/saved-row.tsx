// saved-row.tsx — one saved calculation. Like SwipeRow, this is only the
// *contents* of a row: the card, separators, fill, swipe actions and context
// menu all come from GroupedRow, so the archive and the running tab are the
// same list with different things in it.
//
// Swipe left for Delete, swipe right for Tags, long-press for the context menu:
// Open · Tags ▸ · Delete. The Tags submenu is the quick path — a checkmark per
// catalog tag, toggled in place — and "Manage tags…" at its foot opens the tag
// catalog screen, where tags can be created, renamed, deleted and applied.
import { Button, Divider, Menu } from '@expo/ui/swift-ui';
import { StyleSheet, Text, View } from 'react-native';

import { GroupedRow } from '@/components/tally/grouped-list';
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

  return (
    <GroupedRow
      theme={t}
      // the open calculation is tinted through the cell, so the fill covers the
      // row edge to edge and clips to the card's rounded ends
      fill={selected ? t.accent2 : undefined}
      onPress={onOpen}
      menu={
        <>
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
        </>
      }
      swipeTrailing={<Button label="Delete" systemImage="trash" role="destructive" onPress={onDelete} />}
      // a visible affordance for tagging, so it isn't hidden behind the
      // long-press alone
      swipeLeading={<Button label="Tags" systemImage="tag" onPress={onManageTags} />}>
      <View style={styles.lhs}>
        <Text style={[styles.name, { color: t.ink }]} numberOfLines={1}>
          {tab.name || 'Untitled tab'}
        </Text>
        <View style={styles.meta}>
          {selected && <Text style={[styles.badge, { color: t.accentInk, backgroundColor: t.screen }]}>Open</Text>}
          <Text style={[styles.metaText, { color: t.ink2 }]}>
            {count} item{count === 1 ? '' : 's'}
          </Text>
          <Text style={[styles.metaText, { color: t.ink3 }]}>·</Text>
          <Text style={[styles.metaText, { color: t.ink2 }]}>{relDate(tab.savedAt)}</Text>
        </View>
        {/* tags are shown, never edited here: the row is one tap target so the
            SwiftUI gestures above own everything else */}
        {tgs.length > 0 && (
          <View style={styles.tagRow}>
            {tgs.map((n) => (
              <TagChip key={n} name={n} theme={t} size="sm" />
            ))}
          </View>
        )}
      </View>
      <Text style={[styles.total, { color: t.ink }]}>{Calc.fmt(totalOf(tab.entries))}</Text>
    </GroupedRow>
  );
}

const styles = StyleSheet.create({
  lhs: { flex: 1, minWidth: 0, gap: 4 },
  name: { fontFamily: TallyFonts.serif, fontSize: 16.5, lineHeight: 19, letterSpacing: -0.2 },
  meta: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  metaText: { fontFamily: TallyFonts.sans, fontSize: 12.5 },
  badge: {
    fontFamily: TallyFonts.sansSemi,
    fontSize: 11,
    borderRadius: 8,
    paddingHorizontal: 8,
    paddingVertical: 4,
    overflow: 'hidden',
  },
  total: { fontFamily: TallyFonts.monoSemi, fontSize: 17, fontVariant: ['tabular-nums'], letterSpacing: -0.2 },
  tagRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8, marginTop: 4 },
});
