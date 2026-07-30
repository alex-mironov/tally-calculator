// tag-glass.tsx — tag capsules on real Liquid Glass (iOS 26): the calculator's
// "tags on this tab" row and the Saved screen's filter strip, so both read as
// one control in two moods. Labels stay in the app's mono face, matching the
// drawn chips on the Saved cards and in the native sheets.
//
// The glass is expo-glass-effect's GlassView rather than SwiftUI's
// `buttonStyle(.glass)`: hosted SwiftUI glass inside a scroll view makes iOS
// draw a grey backdrop across the whole group, which on a strip this short is a
// dirty block sitting on the screen colour. GlassView has no such problem, and
// it keeps the chip's type and metrics ours.
//
// Below iOS 26 there is no glass at all, so each strip falls back to its drawn
// React Native twin in tags.tsx.
import { GlassView, isLiquidGlassAvailable } from 'expo-glass-effect';
import { useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, type TextInput as RNTextInput } from 'react-native';

import { TagFilterBar, TagToggleGrid } from '@/components/tally/tags';
import { TallyFonts, type TallyTheme, type ThemeMode } from '@/constants/tally-theme';
import * as Haptic from '@/lib/haptics';

// Resolved once at module load, same as the calculator's entry card.
const LIQUID = isLiquidGlassAvailable();

/** Local copy of the store's tagsOf so this file stays presentational. */
function tagsOfLike(tb: { tags?: string[]; tag?: string }): string[] {
  if (Array.isArray(tb.tags)) return tb.tags;
  if (tb.tag) return [tb.tag];
  return [];
}

/**
 * Single-select filter (Saved): "All" plus one capsule per tag actually in use,
 * in catalog order with used-but-uncatalogued names appended. Renders nothing
 * when no tag is in use.
 */
export function TagFilterBarGlass({
  theme: t,
  mode,
  tabs,
  catalog,
  active,
  onChange,
}: {
  theme: TallyTheme;
  mode: ThemeMode;
  tabs: { tags?: string[]; tag?: string }[];
  catalog: string[];
  active: string | null;
  onChange: (next: string | null) => void;
}) {
  const counts: Record<string, number> = {};
  tabs.forEach((tb) => tagsOfLike(tb).forEach((n) => (counts[n] = (counts[n] || 0) + 1)));
  const used = catalog.filter((n) => counts[n]);
  Object.keys(counts).forEach((n) => {
    if (!used.includes(n)) used.push(n);
  });

  if (!used.length) return null;
  if (!LIQUID) return <TagFilterBar theme={t} tabs={tabs} catalog={catalog} active={active} onChange={onChange} />;

  const allOn = active == null;
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      style={[styles.scroll, styles.filterRow]}
      contentContainerStyle={styles.row}>
      <GlassChip label="All" on={allOn} tintColor={allOn ? t.ink : t.ink2} mode={mode} onPress={() => onChange(null)} />
      {used.map((n) => {
        const on = active === n;
        return (
          <GlassChip
            key={n}
            label={n}
            on={on}
            tintColor={on ? t.accent : t.accentInk}
            mode={mode}
            onPress={() => onChange(on ? null : n)}
          />
        );
      })}
    </ScrollView>
  );
}

/**
 * Multi-select toggle (the calculator's live tab tags): every catalog tag is a
 * capsule, prominent while selected, with a trailing "+ New" that swaps into an
 * inline field and creates-then-selects the tag it commits.
 */
export function TagToggleGlass({
  theme: t,
  mode,
  catalog,
  value,
  onChange,
  onCreate,
  allowCreate = true,
}: {
  theme: TallyTheme;
  mode: ThemeMode;
  catalog: string[];
  value: string[];
  onChange: (next: string[]) => void;
  onCreate: (raw: string) => string | null;
  allowCreate?: boolean;
}) {
  const [adding, setAdding] = useState(false);
  const [draft, setDraft] = useState('');
  const inputRef = useRef<RNTextInput>(null);

  useEffect(() => {
    if (adding) inputRef.current?.focus();
  }, [adding]);

  if (!LIQUID) {
    return (
      <TagToggleGrid
        theme={t}
        catalog={catalog}
        value={value}
        onChange={onChange}
        onCreate={onCreate}
        allowCreate={allowCreate}
      />
    );
  }

  const toggle = (n: string) => onChange(value.includes(n) ? value.filter((x) => x !== n) : [...value, n]);

  function commit() {
    const name = onCreate(draft);
    setAdding(false);
    setDraft('');
    if (name && !value.includes(name)) onChange([...value, name]);
  }

  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      keyboardShouldPersistTaps="handled"
      style={styles.scroll}
      contentContainerStyle={styles.row}>
      {catalog.map((n) => {
        const on = value.includes(n);
        return (
          <GlassChip
            key={n}
            label={n}
            on={on}
            tintColor={on ? t.accent : t.accentInk}
            mode={mode}
            onPress={() => toggle(n)}
          />
        );
      })}
      {allowCreate &&
        (adding ? (
          <TextInput
            ref={inputRef}
            style={[styles.newInput, { color: t.ink, borderColor: t.accent, backgroundColor: t.card }]}
            value={draft}
            placeholder="new tag…"
            placeholderTextColor={t.ink3}
            onChangeText={setDraft}
            onBlur={commit}
            onSubmitEditing={commit}
            returnKeyType="done"
            maxLength={22}
            autoCapitalize="words"
            // Tag names are proper nouns as often as not ("Bali", "Kyiv") —
            // autocorrect would silently rewrite them.
            autoCorrect={false}
            spellCheck={false}
            clearButtonMode="while-editing"
            maxFontSizeMultiplier={1.4}
          />
        ) : (
          // Drawn rather than glass: it creates a tag instead of being one, and
          // the dashed outline is the same "add" affordance the Saved cards use.
          <Pressable
            style={[styles.newBtn, { borderColor: t.ink3 }]}
            accessibilityLabel="New tag"
            onPress={() => {
              Haptic.tap();
              setAdding(true);
            }}>
            <Text style={[styles.newBtnText, { color: t.ink2 }]} maxFontSizeMultiplier={1.4}>
              + New
            </Text>
          </Pressable>
        ))}
    </ScrollView>
  );
}

/** One capsule: clear glass when off, accent-tinted with white type when on. */
function GlassChip({
  label,
  on,
  tintColor,
  mode,
  onPress,
}: {
  label: string;
  on: boolean;
  tintColor: string;
  mode: ThemeMode;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={() => {
        Haptic.select();
        onPress();
      }}>
      <GlassView
        glassEffectStyle="regular"
        colorScheme={mode}
        isInteractive
        tintColor={on ? tintColor : undefined}
        style={styles.chip}>
        <Text style={[styles.chipText, { color: on ? '#ffffff' : tintColor }]} maxFontSizeMultiplier={1.4}>
          {label}
        </Text>
      </GlassView>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  scroll: { flexGrow: 0 },
  chip: {
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 999,
    overflow: 'hidden',
  },
  chipText: { fontFamily: TallyFonts.mono, fontSize: 13, letterSpacing: 0.12 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
  },
  // the calculator's row is spaced by its own wrapper; the Saved strip isn't
  filterRow: { marginBottom: 6 },
  newBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 7,
    paddingHorizontal: 14,
    borderRadius: 999,
    borderWidth: 1,
    borderStyle: 'dashed',
  },
  // "+ New" stays in the UI (sans) font — it's an action, not a tag label.
  newBtnText: { fontFamily: TallyFonts.sansSemi, fontSize: 13 },
  newInput: {
    // a touch wider than the "+ New" pill it replaces, so the trailing clear
    // button doesn't crowd the text
    minWidth: 132,
    paddingVertical: 7,
    paddingHorizontal: 14,
    borderRadius: 999,
    borderWidth: 1,
    fontFamily: TallyFonts.sansSemi,
    fontSize: 13,
  },
});
