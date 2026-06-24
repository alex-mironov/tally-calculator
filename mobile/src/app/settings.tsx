// settings.tsx — preferences for the tab (2026 refresh): accent, theme, and
// which pieces of the running tab to show. Grouped cards, sentence-case labels.
// Presented as a modal over the calculator.
import { Host, Switch as NativeSwitch } from '@expo/ui';
import { tint } from '@expo/ui/swift-ui/modifiers';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
  type TextInput as RNTextInput,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ACCENTS, TallyFonts, type TallyTheme } from '@/constants/tally-theme';
import { useTally } from '@/lib/tally-store';

export default function SettingsScreen() {
  const insets = useSafeAreaInsets();
  const {
    theme: t,
    themeMode,
    setThemeMode,
    accent,
    setAccent,
    showExpr,
    setShowExpr,
    showTotal,
    setShowTotal,
    catalog,
    addCatalogTag,
    removeCatalogTag,
    renameCatalogTag,
  } = useTally();

  return (
    <View style={[styles.root, { backgroundColor: t.screen }]}>
      {/* Native navigation header → real iOS back chevron, screen-coloured & flat */}
      <Stack.Screen
        options={{
          headerShown: true,
          headerStyle: { backgroundColor: t.screen },
          headerShadowVisible: false,
          headerTitle: '',
          headerBackButtonDisplayMode: 'minimal',
          headerTintColor: t.accentInk,
        }}
      />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      <View style={styles.header}>
        <Text style={[styles.hTitle, { color: t.ink }]}>Settings</Text>
        <Text style={[styles.hSub, { color: t.ink2 }]}>Appearance and what shows on the tab.</Text>
      </View>

      <ScrollView contentContainerStyle={[styles.body, { paddingBottom: insets.bottom + 24 }]}>
        <Text style={[styles.secLab, { color: t.ink3 }]}>Appearance</Text>
        <View style={[styles.group, { backgroundColor: t.card, borderColor: t.line }]}>
          {/* accent swatches */}
          <View style={styles.swatchRow}>
            <Text style={[styles.rowLab, { color: t.ink }]}>Accent colour</Text>
            <View style={styles.swatches}>
              {ACCENTS.map((a) => {
                const on = a.accent === accent;
                return (
                  <Pressable
                    key={a.accent}
                    onPress={() => setAccent(a.accent)}
                    accessibilityLabel={a.name}
                    style={[
                      styles.swatch,
                      { backgroundColor: a.accent },
                      on && { borderColor: t.screen, shadowColor: a.accent },
                      on && styles.swatchOn,
                    ]}>
                    {on && <Text style={styles.swatchCheck}>✓</Text>}
                  </Pressable>
                );
              })}
            </View>
          </View>

          {/* theme — native SwiftUI switch (on = dark) */}
          <View style={[styles.row, { borderTopColor: t.line, borderTopWidth: StyleSheet.hairlineWidth }]}>
            <View style={styles.rowTextWrap}>
              <Text style={[styles.rowLab, { color: t.ink }]}>Dark mode</Text>
              <Text style={[styles.rowSub, { color: t.ink3 }]}>Switch to a dark palette</Text>
            </View>
            <Host matchContents>
              <NativeSwitch
                value={themeMode === 'dark'}
                onValueChange={(on) => setThemeMode(on ? 'dark' : 'light')}
                modifiers={[tint(t.accent)]}
              />
            </Host>
          </View>
        </View>

        <Text style={[styles.secLab, { color: t.ink3 }]}>Tags</Text>
        <TagManager
          theme={t}
          catalog={catalog}
          onAdd={addCatalogTag}
          onRemove={removeCatalogTag}
          onRename={renameCatalogTag}
        />

        <Text style={[styles.secLab, { color: t.ink3 }]}>The tab</Text>
        <View style={[styles.group, { backgroundColor: t.card, borderColor: t.line }]}>
          <View style={styles.row}>
            <View style={styles.rowTextWrap}>
              <Text style={[styles.rowLab, { color: t.ink }]}>Show running total</Text>
              <Text style={[styles.rowSub, { color: t.ink3 }]}>The live sum above the keypad</Text>
            </View>
            <Switch
              value={showTotal}
              onValueChange={setShowTotal}
              trackColor={{ true: t.accent, false: t.ink3 }}
              thumbColor="#ffffff"
              ios_backgroundColor={t.ink3}
            />
          </View>

          <View style={[styles.row, { borderTopColor: t.line, borderTopWidth: StyleSheet.hairlineWidth }]}>
            <View style={styles.rowTextWrap}>
              <Text style={[styles.rowLab, { color: t.ink }]}>Show the maths under each line</Text>
              <Text style={[styles.rowSub, { color: t.ink3 }]}>e.g. 60 ÷ 4 beneath a split</Text>
            </View>
            <Switch
              value={showExpr}
              onValueChange={setShowExpr}
              trackColor={{ true: t.accent, false: t.ink3 }}
              thumbColor="#ffffff"
              ios_backgroundColor={t.ink3}
            />
          </View>
        </View>

        <Text style={[styles.about, { color: t.ink3 }]}>
          Tally · concept prototype · v0.1{'\n'}Settings saved on this device
        </Text>
      </ScrollView>
    </View>
  );
}

/**
 * Manage the shared tag catalog: every tag shows a uniform accent dot, its
 * name (tap to rename — cascades to tabs), and a delete (cascades the removal).
 * Plus an "Add tag" row.
 */
function TagManager({
  theme: t,
  catalog,
  onAdd,
  onRemove,
  onRename,
}: {
  theme: TallyTheme;
  catalog: string[];
  onAdd: (raw: string) => string | null;
  onRemove: (name: string) => void;
  onRename: (name: string, next: string) => void;
}) {
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

  function startRename(name: string) {
    setEditing(name);
    setDraft(name);
  }
  function commitRename() {
    if (editing) onRename(editing, draft);
    setEditing(null);
    setDraft('');
  }
  function commitAdd() {
    onAdd(addDraft);
    setAdding(false);
    setAddDraft('');
  }

  return (
    <View style={[tm.group, { backgroundColor: t.card, borderColor: t.line }]}>
      {catalog.map((name, i) => (
        <View
          key={name}
          style={[tm.row, i > 0 && { borderTopColor: t.line, borderTopWidth: StyleSheet.hairlineWidth }]}>
          <View style={[tm.dot, { backgroundColor: t.accent }]} />
          {editing === name ? (
            <TextInput
              ref={renameRef}
              style={[tm.nameInput, { color: t.ink, borderBottomColor: t.accent }]}
              value={draft}
              onChangeText={setDraft}
              onBlur={commitRename}
              onSubmitEditing={commitRename}
              returnKeyType="done"
              maxLength={22}
              autoCapitalize="words"
            />
          ) : (
            <Pressable style={tm.namePress} onPress={() => startRename(name)} hitSlop={6}>
              <Text style={[tm.name, { color: t.ink }]} numberOfLines={1}>
                {name}
              </Text>
            </Pressable>
          )}
          <Pressable onPress={() => onRemove(name)} hitSlop={8} accessibilityLabel={`Delete ${name}`} style={tm.del}>
            <TrashGlyph color={t.ink3} />
          </Pressable>
        </View>
      ))}

      <View style={[tm.row, catalog.length > 0 && { borderTopColor: t.line, borderTopWidth: StyleSheet.hairlineWidth }]}>
        {adding ? (
          <>
            <View style={[tm.dot, { backgroundColor: t.accent }]} />
            <TextInput
              ref={addRef}
              style={[tm.nameInput, { color: t.ink, borderBottomColor: t.accent }]}
              value={addDraft}
              placeholder="tag name…"
              placeholderTextColor={t.ink3}
              onChangeText={setAddDraft}
              onBlur={commitAdd}
              onSubmitEditing={commitAdd}
              returnKeyType="done"
              maxLength={22}
              autoCapitalize="words"
            />
          </>
        ) : (
          <Pressable style={tm.addBtn} onPress={() => setAdding(true)}>
            <Text style={[tm.addText, { color: t.accentInk }]}>+ Add tag</Text>
          </Pressable>
        )}
      </View>
    </View>
  );
}

/** Minimal monochrome trash can, drawn with views to match the Saved screen. */
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
  wrap: { width: 15, height: 16, alignItems: 'center' },
  handle: {
    width: 6,
    height: 3,
    borderWidth: 1.4,
    borderBottomWidth: 0,
    borderTopLeftRadius: 1.5,
    borderTopRightRadius: 1.5,
  },
  lid: { width: 13, height: 1.6, borderRadius: 1, marginTop: 0.5 },
  body: {
    width: 10,
    height: 9,
    borderWidth: 1.4,
    borderTopWidth: 0,
    borderBottomLeftRadius: 2.5,
    borderBottomRightRadius: 2.5,
    marginTop: 0.5,
  },
});

const tm = StyleSheet.create({
  group: { borderRadius: 18, borderWidth: 1, overflow: 'hidden' },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 13 },
  dot: { width: 9, height: 9, borderRadius: 4.5, marginLeft: 2 },
  namePress: { flex: 1 },
  name: { fontFamily: TallyFonts.mono, fontSize: 14, letterSpacing: 0.12 },
  nameInput: {
    flex: 1,
    fontFamily: TallyFonts.mono,
    fontSize: 14,
    letterSpacing: 0.12,
    paddingVertical: 2,
    borderBottomWidth: 1.5,
  },
  del: { padding: 4, marginRight: -2 },
  addBtn: { paddingVertical: 2 },
  addText: { fontFamily: TallyFonts.sansSemi, fontSize: 15 },
});

const styles = StyleSheet.create({
  root: { flex: 1 },

  header: { paddingHorizontal: 22, paddingTop: 2, paddingBottom: 10 },
  hTitle: { fontFamily: TallyFonts.serif, fontSize: 30, lineHeight: 32, letterSpacing: -0.4 },
  hSub: { fontFamily: TallyFonts.sans, fontSize: 13.5, marginTop: 4 },

  body: { paddingHorizontal: 14 },
  secLab: { fontFamily: TallyFonts.sansSemi, fontSize: 13, paddingTop: 22, paddingBottom: 8, paddingHorizontal: 10 },
  group: { borderRadius: 18, borderWidth: 1, overflow: 'hidden' },

  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  rowTextWrap: { flex: 1 },
  rowLab: { fontFamily: TallyFonts.sansMedium, fontSize: 15 },
  rowSub: { fontFamily: TallyFonts.sans, fontSize: 12.5, marginTop: 3 },

  swatchRow: { paddingHorizontal: 16, paddingVertical: 14 },
  swatches: { flexDirection: 'row', gap: 14, paddingTop: 16, flexWrap: 'wrap' },
  swatch: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  swatchOn: {
    borderWidth: 2.5,
    shadowOpacity: 1,
    shadowRadius: 0,
    shadowOffset: { width: 0, height: 0 },
    elevation: 2,
  },
  swatchCheck: { color: '#ffffff', fontSize: 15, fontWeight: '700' },

  about: {
    paddingHorizontal: 10,
    paddingTop: 22,
    fontFamily: TallyFonts.sans,
    fontSize: 12,
    lineHeight: 20,
  },
});
