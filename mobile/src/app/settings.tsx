// settings.tsx — preferences for the tab (2026 refresh): accent, theme, and
// which pieces of the running tab to show. Grouped cards, sentence-case labels.
// Presented as a modal over the calculator.
import { Host, Picker, Text as UIText } from '@expo/ui/swift-ui';
import { pickerStyle, tag, tint } from '@expo/ui/swift-ui/modifiers';
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

import { ScreenBackground } from '@/components/tally/screen-bg';
import { ACCENTS, TallyFonts, type TallyTheme, type ThemeMode } from '@/constants/tally-theme';
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
    <View style={styles.root}>
      <ScreenBackground theme={t} mode={themeMode} />
      {/* Real iOS nav bar: native large title + system back chevron (the screen
          is pushed, so the back button is supplied automatically). */}
      <Stack.Screen
        options={{
          headerShown: true,
          headerLargeTitle: true,
          title: 'Settings',
          headerStyle: { backgroundColor: t.screen },
          headerShadowVisible: false,
          headerLargeTitleShadowVisible: false,
          headerTintColor: t.accent,
          headerLargeTitleStyle: { color: t.ink, fontFamily: TallyFonts.serif },
          headerTitleStyle: { color: t.ink, fontFamily: TallyFonts.sansSemi },
          headerBackButtonDisplayMode: 'minimal',
        }}
      />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={[styles.body, { paddingBottom: insets.bottom + 24 }]}>
        <Text style={[styles.hSub, { color: t.ink2 }]}>Appearance and what shows on the tab.</Text>

        <Text style={[styles.secLab, { color: t.ink3 }]}>Appearance</Text>
        <View style={[styles.group, { backgroundColor: t.card, borderColor: t.line }]}>
          {/* accent swatches */}
          <View style={styles.swatchRow}>
            <Text style={[styles.rowLab, { color: t.ink }]}>Accent colour</Text>
            <View style={styles.swatches}>
              {ACCENTS.map((a) => {
                const on = a.accent === accent;
                return (
                  <View key={a.accent} style={styles.swatchWrap}>
                    {/* selected ring: a screen-coloured gap then an accent ring,
                        floating outside the swatch (matches the prototype) */}
                    {on && (
                      <View
                        pointerEvents="none"
                        style={[styles.swatchRing, { borderColor: a.accent }]}
                      />
                    )}
                    <Pressable
                      onPress={() => setAccent(a.accent)}
                      accessibilityLabel={a.name}
                      style={[styles.swatch, { backgroundColor: a.accent }]}>
                      {on && <Text style={styles.swatchCheck}>✓</Text>}
                    </Pressable>
                  </View>
                );
              })}
            </View>
          </View>

          {/* theme — native SwiftUI segmented control */}
          <View style={[styles.row, { borderTopColor: t.line, borderTopWidth: StyleSheet.hairlineWidth }]}>
            <Text style={[styles.rowLab, { color: t.ink }]}>Theme</Text>
            <Host matchContents colorScheme={themeMode} style={styles.segHost}>
              <Picker
                selection={themeMode}
                onSelectionChange={(mode) => setThemeMode(mode as ThemeMode)}
                modifiers={[pickerStyle('segmented'), tint(t.accent)]}>
                <UIText modifiers={[tag('light')]}>Light</UIText>
                <UIText modifiers={[tag('dark')]}>Dark</UIText>
              </Picker>
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
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 14, paddingVertical: 12 },
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

  hSub: { fontFamily: TallyFonts.sans, fontSize: 13.5, paddingHorizontal: 10, paddingTop: 4, paddingBottom: 2 },

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

  // Light/Dark native segmented control
  segHost: { width: 160, height: 32 },

  swatchRow: { paddingHorizontal: 16, paddingVertical: 14 },
  swatches: { flexDirection: 'row', gap: 14, paddingTop: 16, flexWrap: 'wrap' },
  swatchWrap: { width: 34, height: 34, alignItems: 'center', justifyContent: 'center' },
  swatch: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  swatchRing: {
    position: 'absolute',
    top: -4.5,
    left: -4.5,
    right: -4.5,
    bottom: -4.5,
    borderRadius: 21.5,
    borderWidth: 2,
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
