// saved.tsx — the Saved calculations archive (2026 refresh), multi-tag aware.
// Lists the tabs you've filed away with the current unsaved draft pinned to the
// top so work is never lost. Search matches names and tags; a single-select
// filter bar narrows to one tag. Cards carry iOS-native gestures: swipe left to
// delete, long-press for an action sheet, tap to open. Presented as a modal
// over the calculator.
import { Button, Host } from '@expo/ui/swift-ui';
import { labelStyle, tint } from '@expo/ui/swift-ui/modifiers';
import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import {
  ActionSheetIOS,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import ReanimatedSwipeable, {
  type SwipeableMethods,
} from 'react-native-gesture-handler/ReanimatedSwipeable';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { SaveSheet } from '@/components/tally/save-sheet';
import { TagFilterBarGlass } from '@/components/tally/tag-filter-glass';
import { TagChip } from '@/components/tally/tags';
import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import { presentTagSheet } from '@/lib/present-sheet';
import { tagsOf, useTally, type Entry, type Tab } from '@/lib/tally-store';

const DESTRUCTIVE = '#e5484d';

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

const totalOf = (entries: Entry[]) => (entries || []).reduce((a, e) => a + (e.value || 0), 0);

export default function SavedScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const {
    theme: t,
    themeMode,
    tabs,
    activeId,
    tabName,
    entries: draftEntries,
    catalog,
    addCatalogTag,
    setTabTags,
    openTab,
    newTab,
    deleteTab,
  } = useTally();

  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<string | null>(null);
  const [editId, setEditId] = useState<string | null>(null);
  const [saveOpen, setSaveOpen] = useState(false);

  const hasDraft = activeId == null && draftEntries.length > 0;

  // newest-first, then apply search (name + tags) and the single tag filter
  const q = query.trim().toLowerCase();
  const list = [...tabs]
    .sort((a, b) => (b.savedAt || 0) - (a.savedAt || 0))
    .filter((tb) => {
      const tgs = tagsOf(tb);
      if (filter && !tgs.includes(filter)) return false;
      if (q) {
        const hay = ((tb.name || '') + ' ' + tgs.join(' ')).toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });

  const editTab = tabs.find((x) => x.id === editId) || null;

  function handleOpen(id: string) {
    openTab(id);
    router.back();
  }
  function handleNew() {
    newTab();
    router.back();
  }

  // Long-press a card → native action sheet: Open / Edit tags / Delete.
  function cardActions(tb: Tab) {
    const title = tb.name || 'Untitled tab';
    const message = Calc.fmt(totalOf(tb.entries));
    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(
        {
          title,
          message,
          options: ['Open', 'Edit tags', 'Delete', 'Cancel'],
          destructiveButtonIndex: 2,
          cancelButtonIndex: 3,
        },
        (i) => {
          if (i === 0) handleOpen(tb.id);
          else if (i === 1) setEditId(tb.id);
          else if (i === 2) deleteTab(tb.id);
        },
      );
    } else {
      Alert.alert(title, message, [
        { text: 'Open', onPress: () => handleOpen(tb.id) },
        { text: 'Edit tags', onPress: () => setEditId(tb.id) },
        { text: 'Delete', style: 'destructive', onPress: () => deleteTab(tb.id) },
        { text: 'Cancel', style: 'cancel' },
      ]);
    }
  }

  return (
    // Solid screen background (not the absolute ScreenBackground bloom): the
    // bloom layer would be the root's first subview, and react-native-screens
    // only follows subviews[0] to find the scroll view that drives the native
    // large-title collapse — so the ScrollView must be the first child.
    <View style={[styles.root, { backgroundColor: t.screen }]}>
      {/* Real iOS nav bar: native large title + system back chevron, with a
          "+ New tab" pill in the trailing slot (the screen is pushed, so the
          back button is supplied automatically). */}
      <Stack.Screen
        options={{
          headerShown: true,
          headerLargeTitle: true,
          title: 'Saved',
          headerStyle: { backgroundColor: t.screen },
          headerShadowVisible: false,
          headerLargeTitleShadowVisible: false,
          headerTintColor: t.accent,
          headerLargeTitleStyle: { color: t.ink, fontFamily: TallyFonts.serif },
          headerTitleStyle: { color: t.ink, fontFamily: TallyFonts.sansSemi },
          headerBackButtonDisplayMode: 'minimal',
          // Native SwiftUI icon-only button: a plain "+" SF Symbol (VoiceOver
          // still reads "New tab"), tinted with the accent.
          headerRight: () => (
            <Host matchContents>
              <Button
                label="New tab"
                systemImage="plus"
                onPress={handleNew}
                modifiers={[labelStyle('iconOnly'), tint(t.accent)]}
              />
            </Host>
          ),
        }}
      />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      <ScrollView
        style={styles.bodyScroll}
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ paddingBottom: insets.bottom + 24 }}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag">
        <Text style={[styles.hSub, { color: t.ink2 }]}>Search, or filter by tag.</Text>

        {/* search */}
        <View style={[styles.search, { backgroundColor: t.card, borderColor: t.line }]}>
          <SearchGlyph color={t.ink3} />
          <TextInput
            style={[styles.searchInput, { color: t.ink }]}
            value={query}
            placeholder="Search tabs…"
            placeholderTextColor={t.ink3}
            onChangeText={setQuery}
            returnKeyType="search"
            clearButtonMode="while-editing"
          />
        </View>

        {/* single-select tag filter — native SwiftUI liquid-glass capsules */}
        <TagFilterBarGlass
          theme={t}
          mode={themeMode}
          tabs={tabs}
          catalog={catalog}
          active={filter}
          onChange={setFilter}
        />

        <View style={styles.list}>
        {hasDraft && !filter && !q && (
          <View style={[styles.draftCard, { backgroundColor: t.accent2 }]}>
            <View style={styles.draftTop}>
              <Text style={[styles.draftLab, { color: t.accentInk }]}>Current · unsaved</Text>
              <Text style={[styles.draftTot, { color: t.ink }]}>{Calc.fmt(totalOf(draftEntries))}</Text>
            </View>
            <Text style={[styles.draftSub, { color: t.ink2 }]}>
              {tabName ? tabName + ' — ' : ''}
              {draftEntries.length} item{draftEntries.length === 1 ? '' : 's'} on the tab
            </Text>
            <Pressable style={[styles.saveBtn, { backgroundColor: t.accent }]} onPress={() => setSaveOpen(true)}>
              <Text style={styles.saveBtnText}>Save this tab</Text>
            </Pressable>
          </View>
        )}

        {list.map((tb) => (
          <SavedCard
            key={tb.id}
            tab={tb}
            theme={t}
            selected={tb.id === activeId}
            onOpen={() => handleOpen(tb.id)}
            onDelete={() => deleteTab(tb.id)}
            onEditTags={() => setEditId(tb.id)}
            onLongPress={() => cardActions(tb)}
          />
        ))}

        {list.length === 0 && (
          <View style={styles.empty}>
            <Text style={[styles.emptyTitle, { color: t.ink2 }]}>
              {filter ? `No tabs tagged “${filter}”.` : q ? 'No matches.' : 'Nothing filed away yet.'}
            </Text>
            <Text style={[styles.emptySub, { color: t.ink3 }]}>
              {filter || q
                ? 'Try clearing the filter, or tag more tabs.'
                : 'Name the tab you’re on, then save it here to start a clean one.'}
            </Text>
          </View>
        )}
        </View>
      </ScrollView>

      {/* save sheet for the draft (name + tags) */}
      <SaveSheet visible={saveOpen} onClose={() => setSaveOpen(false)} />

      {/* edit-tags sheet for an existing card (native SwiftUI) */}
      <EditTagsSheet
        tab={editTab}
        theme={t}
        isDark={themeMode === 'dark'}
        catalog={catalog}
        addCatalogTag={addCatalogTag}
        onChange={(next) => editTab && setTabTags(editTab.id, next)}
        onClose={() => setEditId(null)}
      />
    </View>
  );
}

function SavedCard({
  tab,
  theme: t,
  selected,
  onOpen,
  onDelete,
  onEditTags,
  onLongPress,
}: {
  tab: Tab;
  theme: TallyTheme;
  selected: boolean;
  onOpen: () => void;
  onDelete: () => void;
  onEditTags: () => void;
  onLongPress: () => void;
}) {
  const ref = useRef<SwipeableMethods>(null);
  const count = (tab.entries || []).length;
  const tgs = tagsOf(tab);

  function renderRightActions() {
    return (
      <Pressable
        style={styles.delAction}
        accessibilityLabel="Delete"
        onPress={() => {
          ref.current?.close();
          onDelete();
        }}>
        <TrashGlyph color="#fff" />
        <Text style={styles.delText}>Delete</Text>
      </Pressable>
    );
  }

  return (
    <ReanimatedSwipeable
      ref={ref}
      friction={2}
      rightThreshold={44}
      overshootRight={false}
      renderRightActions={renderRightActions}
      containerStyle={styles.swipeContainer}>
      <Pressable
        onPress={onOpen}
        onLongPress={onLongPress}
        delayLongPress={460}
        style={({ pressed }) => [
          styles.card,
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

        {/* tag chips + the edit affordance; the chip stops the card's own tap */}
        <View style={styles.tagRow}>
          {tgs.map((n) => (
            <TagChip key={n} name={n} theme={t} size="sm" />
          ))}
          <Pressable
            onPress={onEditTags}
            hitSlop={6}
            style={[styles.editTag, { borderColor: t.ink3 }]}>
            <Text style={[styles.editTagText, { color: t.ink3 }]}>
              {tgs.length ? '+ Edit tags' : '+ Add tag'}
            </Text>
          </Pressable>
        </View>
      </Pressable>
    </ReanimatedSwipeable>
  );
}

// Headless presenter: when a card's tags are being edited, raise the native
// SwiftUI sheet (tags only, no name field). Done commits the selection; a
// swipe-away discards it.
function EditTagsSheet({
  tab,
  theme: t,
  isDark,
  catalog,
  onChange,
  addCatalogTag,
  onClose,
}: {
  tab: Tab | null;
  theme: TallyTheme;
  isDark: boolean;
  catalog: string[];
  onChange: (next: string[]) => void;
  addCatalogTag: (raw: string) => string | null;
  onClose: () => void;
}) {
  const presenting = useRef(false);
  const tabId = tab?.id ?? null;

  useEffect(() => {
    if (!tab || presenting.current) return;
    presenting.current = true;
    presentTagSheet({
      theme: t,
      isDark,
      title: tab.name || 'Untitled tab',
      subtitle: 'Add or remove tags to find it later.',
      showName: false,
      catalog,
      selected: tagsOf(tab),
      primaryLabel: 'Done',
    })
      .then((res) => {
        if (res.action !== 'save') return;
        const finalTags = res.tags.map((name) => addCatalogTag(name) ?? name);
        onChange(finalTags);
      })
      .finally(() => {
        presenting.current = false;
        onClose();
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tabId]);

  return null;
}

/** Magnifier drawn with views (circle + handle) to match the design's stroked
 *  icon without pulling in an SVG dependency. */
function SearchGlyph({ color }: { color: string }) {
  return (
    <View style={mag.wrap}>
      <View style={[mag.lens, { borderColor: color }]} />
      <View style={[mag.handle, { backgroundColor: color }]} />
    </View>
  );
}

const mag = StyleSheet.create({
  wrap: { width: 17, height: 17, alignItems: 'center', justifyContent: 'center' },
  lens: { width: 11, height: 11, borderRadius: 5.5, borderWidth: 1.7, marginTop: -1, marginLeft: -1 },
  handle: {
    position: 'absolute',
    width: 5,
    height: 1.7,
    borderRadius: 1,
    right: 1,
    bottom: 2.5,
    transform: [{ rotate: '45deg' }],
  },
});

/** Minimal monochrome trash can, drawn with views to avoid an SVG/emoji. */
function TrashGlyph({ color }: { color: string }) {
  return (
    <View style={trash.wrap}>
      <View style={[trash.handle, { borderColor: color }]} />
      <View style={[trash.lid, { backgroundColor: color }]} />
      <View style={[trash.body, { borderColor: color }]} />
    </View>
  );
}

const trash = StyleSheet.create({
  wrap: { width: 18, height: 19, alignItems: 'center' },
  handle: {
    width: 7,
    height: 3.5,
    borderWidth: 1.7,
    borderBottomWidth: 0,
    borderTopLeftRadius: 1.5,
    borderTopRightRadius: 1.5,
  },
  lid: { width: 15, height: 1.8, borderRadius: 1, marginTop: 0.5 },
  body: {
    width: 12,
    height: 11,
    borderWidth: 1.7,
    borderTopWidth: 0,
    borderBottomLeftRadius: 2.5,
    borderBottomRightRadius: 2.5,
    marginTop: 0.5,
  },
});

const styles = StyleSheet.create({
  root: { flex: 1 },

  hSub: { fontFamily: TallyFonts.sans, fontSize: 13.5, paddingHorizontal: 16, paddingTop: 4, paddingBottom: 8 },

  search: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
    marginHorizontal: 16,
    marginBottom: 10,
    paddingVertical: 9,
    paddingHorizontal: 14,
    borderRadius: 13,
    borderWidth: 1,
  },
  searchInput: { flex: 1, fontFamily: TallyFonts.sans, fontSize: 14.5, padding: 0 },

  bodyScroll: { flex: 1 },
  list: { paddingHorizontal: 16, paddingTop: 8 },

  swipeContainer: { overflow: 'hidden', borderRadius: 18, marginBottom: 10 },
  card: {
    gap: 10,
    padding: 15,
    borderRadius: 18,
    borderWidth: 1,
  },
  cardPressed: { opacity: 0.7 },
  cardTop: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  cardLhs: { flex: 1, minWidth: 0 },
  cName: { fontFamily: TallyFonts.serif, fontSize: 17, lineHeight: 19, letterSpacing: -0.2 },
  cMeta: { flexDirection: 'row', alignItems: 'center', gap: 7, marginTop: 4 },
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
  editTag: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 3.5,
    paddingHorizontal: 11,
    borderRadius: 999,
    borderWidth: 1,
    borderStyle: 'dashed',
  },
  editTagText: { fontFamily: TallyFonts.sansSemi, fontSize: 12 },

  delAction: {
    width: 96,
    backgroundColor: DESTRUCTIVE,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 3,
  },
  delText: { color: '#fff', fontFamily: TallyFonts.sansSemi, fontSize: 11 },

  draftCard: { paddingTop: 16, paddingHorizontal: 16, paddingBottom: 14, borderRadius: 18, marginBottom: 14 },
  draftTop: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 10 },
  draftLab: { fontFamily: TallyFonts.sansSemi, fontSize: 13 },
  draftTot: { fontFamily: TallyFonts.monoSemi, fontSize: 19, fontVariant: ['tabular-nums'] },
  draftSub: { fontFamily: TallyFonts.sans, fontSize: 13, marginTop: 4 },
  saveBtn: { marginTop: 12, paddingVertical: 12, borderRadius: 13, alignItems: 'center' },
  saveBtnText: { color: '#fff', fontFamily: TallyFonts.sansSemi, fontSize: 14 },

  empty: { alignItems: 'center', paddingVertical: 40, paddingHorizontal: 20, gap: 9 },
  emptyTitle: { fontFamily: TallyFonts.serif, fontSize: 22, lineHeight: 24, textAlign: 'center', maxWidth: 220 },
  emptySub: { fontFamily: TallyFonts.sans, fontSize: 13, lineHeight: 19, textAlign: 'center', maxWidth: 220 },
});
