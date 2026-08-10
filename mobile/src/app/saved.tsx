// saved.tsx — the Saved calculations archive (2026 refresh), multi-tag aware.
// Lists the calculations you've filed away with the current unsaved draft pinned
// above them so work is never lost. A tag strip across the top filters the list
// to one tag; the nav bar's search matches names and tags.
//
// The list itself is a native SwiftUI `List` (see components/tally/saved-row):
// every row gets real swipe actions and a real long-press context menu, with
// Tags ▸ as a submenu for quick tagging and "Manage tags…" opening the tag
// catalog screen for anything heavier.
import { Button, Host, Image } from '@expo/ui/swift-ui';
import {
  accessibilityLabel,
  buttonStyle,
  contentShape,
  controlSize,
  frame,
  shapes,
  tint,
} from '@expo/ui/swift-ui/modifiers';
import { Stack, useRouter } from 'expo-router';
import { useHeaderHeight } from 'expo-router/react-navigation';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { GroupedList } from '@/components/tally/grouped-list';
import { SaveSheet } from '@/components/tally/save-sheet';
import { SavedRow } from '@/components/tally/saved-row';
import { TagFilterBarGlass } from '@/components/tally/tag-glass';
import { TallyFonts } from '@/constants/tally-theme';
import * as Calc from '@/lib/calc-engine';
import * as Haptic from '@/lib/haptics';
import { tagsOf, useTally, type Entry } from '@/lib/tally-store';

const totalOf = (entries: Entry[]) => (entries || []).reduce((a, e) => a + (e.value || 0), 0);

export default function SavedScreen() {
  const router = useRouter();
  // iOS 26 floats the nav bar over the screen's content, and the usual fix —
  // contentInsetAdjustmentBehavior on a React Native ScrollView — isn't
  // available to a SwiftUI List, so the whole body is pushed down by hand.
  const headerHeight = useHeaderHeight();
  const {
    theme: t,
    themeMode,
    tabs,
    activeId,
    tabName,
    entries: draftEntries,
    catalog,
    setTabTags,
    openTab,
    newTab,
    deleteTab,
  } = useTally();

  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<string | null>(null);
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

  function handleOpen(id: string) {
    Haptic.tap();
    openTab(id);
    router.back();
  }
  function handleNew() {
    Haptic.impact();
    newTab();
    router.back();
  }
  function handleDelete(id: string) {
    Haptic.impact();
    deleteTab(id);
  }

  /** Quick path from the row's Tags submenu — flip one tag on or off in place. */
  function handleToggleTag(id: string, name: string) {
    const tb = tabs.find((x) => x.id === id);
    if (!tb) return;
    const cur = tagsOf(tb);
    Haptic.select();
    setTabTags(id, cur.includes(name) ? cur.filter((x) => x !== name) : [...cur, name]);
  }

  /** The heavier door: the tag catalog, in "apply to this calculation" mode. */
  function handleManageTags(id: string) {
    Haptic.tap();
    router.push({ pathname: '/tags', params: { tab: id } });
  }

  return (
    <View style={[styles.root, { backgroundColor: t.screen, paddingTop: headerHeight }]}>
      {/* Real iOS nav bar with a "+ New" button in the trailing slot (the screen
          is pushed, so the back button is supplied automatically). The title is
          inline rather than large: the body is a SwiftUI List, and only a React
          Native ScrollView can drive the large-title collapse — a large title
          here would simply sit there, permanently expanded. */}
      <Stack.Screen
        options={{
          headerShown: true,
          title: 'Saved',
          headerStyle: { backgroundColor: t.screen },
          headerShadowVisible: false,
          headerTintColor: t.accentInk,
          headerTitleStyle: { color: t.ink, fontFamily: TallyFonts.sansSemi },
          headerBackButtonDisplayMode: 'minimal',
          // Real UISearchBar in the nav bar, same as the Tags screen — it brings
          // the system clear button, cancel button, "search" return key and
          // no-autocapitalize/no-autocorrect behaviour for free, none of which
          // the hand-rolled search box had.
          headerSearchBarOptions: {
            placeholder: 'Search calculations',
            tintColor: t.accentInk,
            textColor: t.ink,
            hideWhenScrolling: false,
            onChangeText: (e) => setQuery(e.nativeEvent.text),
          },
          // Native SwiftUI icon-only button: a plain "+" SF Symbol (VoiceOver
          // still reads "New calculation"), tinted with the accent.
          headerRight: () => (
            <Host style={{ width: 44, height: 44 }}>
              {/* the icon is the button's label (children, not `label=`): a
                  string-label Button hit-tests only the glyph, so sizing the
                  label itself is what makes the whole 44pt box tappable */}
              <Button onPress={handleNew}>
                <Image
                  systemName="plus"
                  size={17}
                  color={t.accentInk}
                  modifiers={[
                    frame({ width: 44, height: 44 }),
                    contentShape(shapes.rectangle()),
                    accessibilityLabel('New calculation'),
                  ]}
                />
              </Button>
            </Host>
          ),
        }}
      />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      {/* the quick filter: one glass capsule per tag in use, pinned above the
          list so it stays reachable however far down you've scrolled */}
      <TagFilterBarGlass
        theme={t}
        mode={themeMode}
        tabs={tabs}
        catalog={catalog}
        active={filter}
        onChange={setFilter}
      />

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
          {/* the card's one action, and the most likely thing to do on this
              screen — so it takes the prominent button style HIG reserves for
              exactly that, drawn by SwiftUI rather than mimicked */}
          <Host matchContents style={styles.saveBtn}>
            <Button
              label="Save this calculation"
              onPress={() => setSaveOpen(true)}
              modifiers={[buttonStyle('borderedProminent'), controlSize('large'), tint(t.accentSolid)]}
            />
          </Host>
        </View>
      )}

      {list.length === 0 ? (
        // The empty state can't live inside the SwiftUI List (rows there are
        // hosted RN views sized by the list), so it stands in for it entirely.
        <ScrollView
          contentContainerStyle={styles.emptyScroll}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag">
          <View style={styles.empty}>
            <Text style={[styles.emptyTitle, { color: t.ink2 }]}>
              {filter ? `Nothing tagged “${filter}”.` : q ? 'No matches.' : 'Nothing filed away yet.'}
            </Text>
            <Text style={[styles.emptySub, { color: t.ink3 }]}>
              {filter || q
                ? 'Try clearing the filter, or tag more calculations.'
                : 'Name the calculation you’re on, then save it here to start a clean one.'}
            </Text>
          </View>
        </ScrollView>
      ) : (
        <GroupedList trimTop>
          {list.map((tb, i) => (
            <SavedRow
              key={tb.id}
              tab={tb}
              theme={t}
              first={i === 0}
              selected={tb.id === activeId}
              catalog={catalog}
              onOpen={() => handleOpen(tb.id)}
              onDelete={() => handleDelete(tb.id)}
              onToggleTag={(name) => handleToggleTag(tb.id, name)}
              onManageTags={() => handleManageTags(tb.id)}
            />
          ))}
        </GroupedList>
      )}

      {/* save sheet for the draft (name + tags) */}
      <SaveSheet visible={saveOpen} onClose={() => setSaveOpen(false)} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },

  draftCard: {
    marginHorizontal: 16,
    marginTop: 4,
    marginBottom: 12,
    paddingTop: 16,
    paddingHorizontal: 16,
    paddingBottom: 16,
    borderRadius: 16,
  },
  draftTop: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 },
  draftLab: { fontFamily: TallyFonts.sansSemi, fontSize: 13 },
  draftTot: { fontFamily: TallyFonts.monoSemi, fontSize: 19, fontVariant: ['tabular-nums'] },
  draftSub: { fontFamily: TallyFonts.sans, fontSize: 13, marginTop: 4 },
  saveBtn: { marginTop: 12, alignSelf: 'flex-start' },

  emptyScroll: { flexGrow: 1, justifyContent: 'center' },
  empty: { alignItems: 'center', paddingVertical: 40, paddingHorizontal: 20, gap: 8 },
  emptyTitle: { fontFamily: TallyFonts.serif, fontSize: 22, lineHeight: 24, textAlign: 'center', maxWidth: 220 },
  emptySub: { fontFamily: TallyFonts.sans, fontSize: 13, lineHeight: 19, textAlign: 'center', maxWidth: 220 },
});
