// tags.tsx — the tag catalog as its own pushed screen (design "E · Manage
// tags"). Native large title + header search bar; the header's + starts a new
// tag and the pencil toggles edit mode (inline rename, red delete — both
// cascade through every tab via the store). The list groups Most Used first,
// then A–Z sections with a decorative letter rail, matching the design's
// TagSheet.
import { Button, Host, HStack } from '@expo/ui/swift-ui';
import { labelStyle, tint } from '@expo/ui/swift-ui/modifiers';
import { Stack } from 'expo-router';
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

import { TallyFonts } from '@/constants/tally-theme';
import * as Haptic from '@/lib/haptics';
import { tagsOf, useTally } from '@/lib/tally-store';

const DESTRUCTIVE = '#e0443e';

export default function TagsScreen() {
  const insets = useSafeAreaInsets();
  const { theme: t, themeMode, tabs, catalog, addCatalogTag, removeCatalogTag, renameCatalogTag } =
    useTally();

  const [q, setQ] = useState('');
  const [editMode, setEditMode] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [adding, setAdding] = useState(false);
  const [addDraft, setAddDraft] = useState('');
  const renameRef = useRef<RNTextInput>(null);
  const addRef = useRef<RNTextInput>(null);

  useEffect(() => {
    if (editing) renameRef.current?.focus();
  }, [editing]);
  useEffect(() => {
    if (adding) addRef.current?.focus();
  }, [adding]);

  function commitRename() {
    if (editing && draft.trim()) renameCatalogTag(editing, draft);
    setEditing(null);
    setDraft('');
  }
  function commitAdd() {
    addCatalogTag(addDraft);
    setAdding(false);
    setAddDraft('');
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
    const counts: Record<string, number> = {};
    tabs.forEach((tb) => tagsOf(tb).forEach((n) => (counts[n] = (counts[n] || 0) + 1)));
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
            <Host matchContents>
              <HStack spacing={4}>
                <Button
                  label="Add tag"
                  systemImage="plus"
                  onPress={() => {
                    setAdding(true);
                    setEditMode(false);
                    setEditing(null);
                  }}
                  modifiers={[labelStyle('iconOnly'), tint(t.accent)]}
                />
                <Button
                  label={editMode ? 'Done' : 'Edit tags'}
                  systemImage={editMode ? 'checkmark' : 'pencil'}
                  onPress={() => {
                    Haptic.select();
                    setEditMode((m) => !m);
                    setEditing(null);
                  }}
                  modifiers={[labelStyle('iconOnly'), tint(t.accent)]}
                />
              </HStack>
            </Host>
          ),
        }}
      />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      <ScrollView
        style={styles.bodyScroll}
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={[styles.body, { paddingBottom: insets.bottom + 26 }]}
        keyboardShouldPersistTaps="handled">
        {adding && (
          <View style={[styles.group, styles.addGroup, { backgroundColor: t.card }]}>
            <View style={styles.row}>
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
              />
            </View>
          </View>
        )}

        {catalog.length === 0 && !adding && (
          <Text style={[styles.empty, { color: t.ink3 }]}>No tags yet. Tap + to add one.</Text>
        )}

        {sections.map((sec) => (
          <View key={sec.label ?? 'search'}>
            {sec.label && <Text style={[styles.secLab, { color: t.ink }]}>{sec.label}</Text>}
            {sec.items.length ? (
              <View style={[styles.group, !sec.label && styles.addGroup, { backgroundColor: t.card }]}>
                {sec.items.map((name, i) => (
                  <View
                    key={name}
                    style={[styles.row, i > 0 && { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: t.line }]}>
                    {editMode && (
                      <Pressable
                        onPress={() => {
                          Haptic.impact();
                          removeCatalogTag(name);
                        }}
                        hitSlop={8}
                        accessibilityLabel={`Delete ${name}`}
                        style={styles.minus}>
                        <View style={styles.minusBar} />
                      </Pressable>
                    )}
                    {editing === name ? (
                      <TextInput
                        ref={renameRef}
                        style={[styles.input, { color: t.ink, borderBottomColor: t.accent }]}
                        value={draft}
                        onChangeText={setDraft}
                        onBlur={commitRename}
                        onSubmitEditing={commitRename}
                        returnKeyType="done"
                        maxLength={22}
                        autoCapitalize="words"
                      />
                    ) : (
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
                    {editMode && editing !== name && <PencilGlyph color={t.ink3} />}
                  </View>
                ))}
              </View>
            ) : (
              query !== '' && <Text style={[styles.empty, { color: t.ink3 }]}>No tags match “{q}”</Text>
            )}
          </View>
        ))}
      </ScrollView>

      {/* decorative A–Z rail (design TagSheet) — appears once tags span letters */}
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

/** Minimal monochrome pencil, drawn with views to match the app's glyphs. */
function PencilGlyph({ color }: { color: string }) {
  return (
    <View style={pencil.wrap}>
      <View style={pencil.turn}>
        <View style={[pencil.tip, { borderRightColor: color }]} />
        <View style={[pencil.body, { backgroundColor: color }]} />
      </View>
    </View>
  );
}

const pencil = StyleSheet.create({
  wrap: { width: 16, height: 16, alignItems: 'center', justifyContent: 'center' },
  turn: { flexDirection: 'row', alignItems: 'center', transform: [{ rotate: '-45deg' }] },
  tip: {
    width: 0,
    height: 0,
    borderTopWidth: 2.5,
    borderBottomWidth: 2.5,
    borderRightWidth: 4,
    borderTopColor: 'transparent',
    borderBottomColor: 'transparent',
  },
  body: { width: 9, height: 5, borderRadius: 1, marginLeft: 1 },
});

const styles = StyleSheet.create({
  root: { flex: 1 },
  bodyScroll: { flex: 1 },
  body: { paddingHorizontal: 16 },

  secLab: {
    fontFamily: TallyFonts.sansSemi,
    fontSize: 19,
    letterSpacing: -0.2,
    paddingTop: 20,
    paddingBottom: 9,
    paddingHorizontal: 6,
  },
  group: {
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOpacity: 0.04,
    shadowRadius: 2,
    shadowOffset: { width: 0, height: 1 },
    elevation: 1,
  },
  addGroup: { marginTop: 16 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 13 },
  namePress: { flex: 1 },
  name: { fontFamily: TallyFonts.sans, fontSize: 16.5 },
  input: {
    flex: 1,
    fontFamily: TallyFonts.sans,
    fontSize: 16.5,
    paddingVertical: 1,
    borderBottomWidth: 1.5,
  },
  minus: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: DESTRUCTIVE,
    alignItems: 'center',
    justifyContent: 'center',
  },
  minusBar: { width: 9, height: 2, borderRadius: 1, backgroundColor: '#fff' },
  empty: { fontFamily: TallyFonts.sans, fontSize: 14, textAlign: 'center', paddingVertical: 30 },

  rail: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    right: 4,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 1.5,
  },
  railL: { fontFamily: TallyFonts.sansBold, fontSize: 10.5, lineHeight: 13 },
});
