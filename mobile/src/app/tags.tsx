// tags.tsx — the tag catalog as its own pushed screen (design "E · Manage
// tags"). Native large title + header search bar; the header's + starts a new
// tag and the pencil toggles edit mode (inline rename, red delete — both
// cascade through every tab via the store). The list groups Most Used first,
// then A–Z sections with a decorative letter rail, matching the design's
// TagSheet.
//
// Pushed with a `tab` param (from a saved calculation's context menu, or its
// leading swipe action) the screen doubles as the tag *picker* for that one
// calculation: rows carry a checkmark, tapping one files or unfiles the
// calculation, and a tag created here is applied straight away.
import { Button, Host, HStack, Image } from '@expo/ui/swift-ui';
import { accessibilityLabel, contentShape, frame, shapes } from '@expo/ui/swift-ui/modifiers';
import { Stack, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInput as RNTextInput,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CardRow, GroupedCard, ROW_INSET } from '@/components/tally/grouped-list';
import { Icon, IconSize } from '@/components/tally/icon';
import { TallyFonts } from '@/constants/tally-theme';
import * as Haptic from '@/lib/haptics';
import { tagsOf, useTally } from '@/lib/tally-store';

const DESTRUCTIVE = '#e0443e';

export default function TagsScreen() {
  const insets = useSafeAreaInsets();
  const {
    theme: t,
    themeMode,
    tabs,
    catalog,
    addCatalogTag,
    removeCatalogTag,
    renameCatalogTag,
    setTabTags,
  } = useTally();

  // Picker mode: the calculation we were pushed to tag, if any. Looked up on
  // every render so the checkmarks track the store rather than a local copy.
  const { tab: applyId } = useLocalSearchParams<{ tab?: string }>();
  const applyTab = (applyId && tabs.find((x) => x.id === applyId)) || null;
  const applied = tagsOf(applyTab);

  function toggleOnTab(name: string) {
    if (!applyTab) return;
    Haptic.select();
    setTabTags(applyTab.id, applied.includes(name) ? applied.filter((x) => x !== name) : [...applied, name]);
  }

  const [q, setQ] = useState('');
  const [editMode, setEditMode] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [adding, setAdding] = useState(false);
  const [addDraft, setAddDraft] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const renameRef = useRef<RNTextInput>(null);
  const addRef = useRef<RNTextInput>(null);
  const noticeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Tag usage, tallied once per visit and then held: in picker mode every tap
  // changes a count, and rows re-sorting out from under the finger is far worse
  // than a Most Used order that's a few seconds stale.
  const [counts] = useState<Record<string, number>>(() => {
    const c: Record<string, number> = {};
    tabs.forEach((tb) => tagsOf(tb).forEach((n) => (c[n] = (c[n] || 0) + 1)));
    return c;
  });

  useEffect(() => () => {
    if (noticeTimer.current) clearTimeout(noticeTimer.current);
  }, []);

  useEffect(() => {
    if (editing) renameRef.current?.focus();
  }, [editing]);
  useEffect(() => {
    if (adding) addRef.current?.focus();
  }, [adding]);

  // Rejected input used to vanish without a word. Both commits now say what
  // happened (HIG "Text fields": validate, and tell people when a value can't
  // be used) — an error tick plus a line of text that clears itself.
  function showNotice(message: string) {
    setNotice(message);
    if (noticeTimer.current) clearTimeout(noticeTimer.current);
    noticeTimer.current = setTimeout(() => setNotice(null), 2800);
  }

  function flagNotice(message: string) {
    Haptic.error();
    showNotice(message);
  }

  function commitRename() {
    const next = draft.trim();
    const from = editing;
    setEditing(null);
    setDraft('');
    if (!from || !next || next === from) return;
    const clash = catalog.find((c) => c !== from && c.toLowerCase() === next.toLowerCase());
    if (clash) {
      flagNotice(`“${clash}” already exists — ${from} was left as it is.`);
      return;
    }
    renameCatalogTag(from, next);
  }

  function commitAdd() {
    const typed = addDraft.trim();
    setAdding(false);
    setAddDraft('');
    if (!typed) return;
    const existing = catalog.find((c) => c.toLowerCase() === typed.toLowerCase());
    if (existing) {
      // In picker mode a name that already exists isn't really an error — the
      // user asked for that tag, so file the calculation under it and say so.
      if (applyTab && !applied.includes(existing)) {
        toggleOnTab(existing);
        showNotice(`“${existing}” already existed — added to this calculation.`);
        return;
      }
      flagNotice(`“${existing}” is already in your tags.`);
      return;
    }
    const name = addCatalogTag(typed);
    // A tag created from a calculation is created *for* it.
    if (name && applyTab) setTabTags(applyTab.id, [...applied, name]);
  }

  // Sections: a flat list while searching; otherwise Most Used (by how many
  // tabs carry each tag) then alphabetical letter groups.
  const query = q.trim().toLowerCase();
  let sections: { label: string | null; items: string[] }[];
  if (query) {
    sections = [{ label: null, items: catalog.filter((n) => n.toLowerCase().includes(query)) }];
  } else if (catalog.length === 0) {
    sections = [];
  } else {
    const mostUsed = [...catalog]
      .sort((a, b) => (counts[b] || 0) - (counts[a] || 0) || catalog.indexOf(a) - catalog.indexOf(b))
      .slice(0, 5);
    const byLetter: Record<string, string[]> = {};
    catalog.forEach((n) => {
      const L = (n[0] || '#').toUpperCase();
      (byLetter[L] = byLetter[L] || []).push(n);
    });
    const letters = Object.keys(byLetter).sort();
    sections = [
      { label: 'Most Used', items: mostUsed },
      ...letters.map((L) => ({ label: L, items: [...byLetter[L]].sort((a, b) => a.localeCompare(b)) })),
    ];
  }
  const railLetters = Array.from(new Set(catalog.map((n) => (n[0] || '#').toUpperCase()))).sort();

  return (
    <View style={[styles.root, { backgroundColor: t.screen }]}>
      <Stack.Screen
        options={{
          headerShown: true,
          headerLargeTitle: true,
          title: 'Tags',
          headerStyle: { backgroundColor: t.screen },
          headerShadowVisible: false,
          headerLargeTitleShadowVisible: false,
          headerTintColor: t.accent,
          headerLargeTitleStyle: { color: t.ink, fontFamily: TallyFonts.serif },
          headerTitleStyle: { color: t.ink, fontFamily: TallyFonts.sansSemi },
          headerBackButtonDisplayMode: 'minimal',
          // Real UISearchBar in the nav bar — the design's toolbar search.
          headerSearchBarOptions: {
            placeholder: 'Search tags',
            tintColor: t.accent,
            textColor: t.ink,
            hideWhenScrolling: false,
            onChangeText: (e) => setQ(e.nativeEvent.text),
          },
          // Native SwiftUI icon buttons: + adds a tag, the pencil flips edit
          // mode (checkmark while editing).
          headerRight: () => (
            <Host style={{ width: 92, height: 44 }}>
              <HStack spacing={4}>
                {/* icons are the buttons' labels (children, not `label=`): a
                    string-label Button hit-tests only the glyph, so sizing the
                    label itself is what makes the whole 44pt box tappable */}
                <Button
                  onPress={() => {
                    setAdding(true);
                    setEditMode(false);
                    setEditing(null);
                  }}>
                  <Image
                    systemName="plus"
                    size={17}
                    color={t.accent}
                    modifiers={[
                      frame({ width: 44, height: 44 }),
                      contentShape(shapes.rectangle()),
                      accessibilityLabel('Add tag'),
                    ]}
                  />
                </Button>
                <Button
                  onPress={() => {
                    Haptic.select();
                    setEditMode((m) => !m);
                    setEditing(null);
                  }}>
                  <Image
                    systemName={editMode ? 'checkmark' : 'pencil'}
                    size={17}
                    color={t.accent}
                    modifiers={[
                      frame({ width: 44, height: 44 }),
                      contentShape(shapes.rectangle()),
                      accessibilityLabel(editMode ? 'Done' : 'Edit tags'),
                    ]}
                  />
                </Button>
              </HStack>
            </Host>
          ),
        }}
      />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      <ScrollView
        style={styles.bodyScroll}
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ paddingBottom: insets.bottom + 26 }}
        keyboardShouldPersistTaps="handled">
        {adding && (
          <GroupedCard theme={t} style={styles.addGroup}>
            <CardRow theme={t} first>
              <TextInput
                ref={addRef}
                style={[styles.input, { color: t.ink, borderBottomColor: t.accent }]}
                value={addDraft}
                placeholder="New tag name…"
                placeholderTextColor={t.ink3}
                onChangeText={setAddDraft}
                onBlur={commitAdd}
                onSubmitEditing={commitAdd}
                returnKeyType="done"
                maxLength={22}
                autoCapitalize="words"
                autoCorrect={false}
                spellCheck={false}
                clearButtonMode="while-editing"
              />
            </CardRow>
          </GroupedCard>
        )}

        {notice && (
          <Text style={[styles.notice, { color: t.accentInk, backgroundColor: t.accent2 }]}>{notice}</Text>
        )}

        {/* picker mode says whose tags these are — otherwise a screen full of
            checkmarks has no visible subject */}
        {applyTab && (
          <Text style={[styles.applyLead, { color: t.ink2 }]}>
            Tagging <Text style={{ color: t.ink, fontFamily: TallyFonts.sansSemi }}>
              {applyTab.name || 'Untitled calculation'}
            </Text>
            {' — tap a tag to add or remove it.'}
          </Text>
        )}

        {catalog.length === 0 && !adding && (
          <Text style={[styles.empty, { color: t.ink3 }]}>No tags yet. Tap + to add one.</Text>
        )}

        {sections.map((sec) => (
          <View key={sec.label ?? 'search'}>
            {sec.label && <Text style={[styles.secLab, { color: t.ink }]}>{sec.label}</Text>}
            {sec.items.length ? (
              <GroupedCard theme={t} style={!sec.label ? styles.addGroup : undefined}>
                {sec.items.map((name, i) => (
                  // In picker mode the whole row is the target — checkmark
                  // included — so filing a calculation is one comfortable tap.
                  // Edit mode hands the row back to its inner controls.
                  <CardRow
                    key={name}
                    theme={t}
                    first={i === 0}
                    disabled={!applyTab || editMode}
                    accessibilityRole={applyTab && !editMode ? 'checkbox' : undefined}
                    accessibilityState={applyTab && !editMode ? { checked: applied.includes(name) } : undefined}
                    onPress={() => toggleOnTab(name)}>
                    {editMode && (
                      <Pressable
                        onPress={() => {
                          Haptic.impact();
                          removeCatalogTag(name);
                        }}
                        hitSlop={8}
                        accessibilityLabel={`Delete ${name}`}>
                        <Icon
                          name="minus.circle.fill"
                          size={IconSize.row + 4}
                          color={DESTRUCTIVE}
                          fallback="−"
                        />
                      </Pressable>
                    )}
                    {editing === name ? (
                      <TextInput
                        ref={renameRef}
                        style={[styles.input, { color: t.ink, borderBottomColor: t.accent }]}
                        value={draft}
                        // clearing the field used to leave an unlabelled box
                        placeholder="Tag name"
                        placeholderTextColor={t.ink3}
                        onChangeText={setDraft}
                        onBlur={commitRename}
                        onSubmitEditing={commitRename}
                        returnKeyType="done"
                        maxLength={22}
                        autoCapitalize="words"
                        autoCorrect={false}
                        spellCheck={false}
                        clearButtonMode="while-editing"
                      />
                    ) : (
                      // Only edit mode listens here — the row above owns the
                      // tap the rest of the time.
                      <Pressable
                        style={styles.namePress}
                        disabled={!editMode}
                        onPress={() => {
                          setEditing(name);
                          setDraft(name);
                        }}>
                        <Text style={[styles.name, { color: t.ink }]} numberOfLines={1}>
                          {name}
                        </Text>
                      </Pressable>
                    )}
                    {editMode && editing !== name && (
                      <Icon name="pencil" size={IconSize.row} color={t.ink3} weight="medium" fallback="✎" />
                    )}
                    {!editMode && applyTab && applied.includes(name) && (
                      <Icon name="checkmark" size={IconSize.row} color={t.accent} fallback="✓" />
                    )}
                  </CardRow>
                ))}
              </GroupedCard>
            ) : (
              query !== '' && <Text style={[styles.empty, { color: t.ink3 }]}>No tags match “{q}”</Text>
            )}
          </View>
        ))}
      </ScrollView>

      {/* Decorative A–Z rail (design TagSheet) — appears once tags span letters.
          The one place left that opts out of Dynamic Type: it's a fixed-height
          rail, and every letter it shows is already a real section header. */}
      {!query && railLetters.length > 1 && (
        <View style={styles.rail} pointerEvents="none">
          {railLetters.map((L) => (
            <Text key={L} style={[styles.railL, { color: t.accentInk }]} allowFontScaling={false}>
              {L}
            </Text>
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  bodyScroll: { flex: 1 },
  // section labels and loose text line up with the *rows'* text, not with the
  // card's edge — ROW_INSET is that x, shared with the list (see grouped-list)
  secLab: {
    fontFamily: TallyFonts.sansSemi,
    fontSize: 19,
    letterSpacing: -0.2,
    paddingTop: 20,
    paddingBottom: 8,
    paddingHorizontal: ROW_INSET,
  },
  addGroup: { marginTop: 16 },
  namePress: { flex: 1 },
  name: { fontFamily: TallyFonts.sans, fontSize: 16.5 },
  input: {
    flex: 1,
    fontFamily: TallyFonts.sans,
    fontSize: 16.5,
    paddingVertical: 0,
    borderBottomWidth: 1.5,
  },
  empty: { fontFamily: TallyFonts.sans, fontSize: 14, textAlign: 'center', paddingVertical: 32 },
  applyLead: {
    fontFamily: TallyFonts.sans,
    fontSize: 13.5,
    lineHeight: 19,
    paddingTop: 12,
    paddingHorizontal: ROW_INSET,
  },
  notice: {
    fontFamily: TallyFonts.sans,
    fontSize: 13,
    lineHeight: 18,
    marginTop: 12,
    marginHorizontal: 20,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 12,
    overflow: 'hidden',
  },

  rail: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    right: 4,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 0,
  },
  railL: { fontFamily: TallyFonts.sansBold, fontSize: 10.5, lineHeight: 13 },
});
