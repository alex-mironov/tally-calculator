// tags.tsx — the reusable multi-tag UI shared by the keypad screen, the Save
// sheet, the Saved archive and Settings. Tags share one colour: the live theme
// accent. Labels are monospaced, regular weight, slightly tracked. We ship the
// "Soft" style (accent-tint background, accent ink); the selected state in any
// chooser flips to solid accent + a white check so it stays legible.
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

import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';

type ChipSize = 'sm' | 'md';

/**
 * A single tag chip. Soft by default; `selected` flips it to the solid accent
 * with a white check. `onRemove` adds a trailing ✕ that deletes without
 * triggering the chip's own press.
 */
export function TagChip({
  name,
  theme: t,
  size = 'md',
  selected = false,
  onPress,
  onRemove,
}: {
  name: string;
  theme: TallyTheme;
  size?: ChipSize;
  selected?: boolean;
  onPress?: () => void;
  onRemove?: () => void;
}) {
  const sm = size === 'sm';
  const chipStyle = [
    styles.chip,
    sm ? styles.chipSm : styles.chipMd,
    selected
      ? { backgroundColor: t.accent }
      : { backgroundColor: t.accent2 },
  ];
  const textStyle = [
    sm ? styles.chipTextSm : styles.chipTextMd,
    { color: selected ? '#fff' : t.accentInk },
  ];

  const inner = (
    <>
      {selected && <Text style={[textStyle, styles.check]} allowFontScaling={false}>✓</Text>}
      <Text style={textStyle} numberOfLines={1} allowFontScaling={false}>
        {name}
      </Text>
      {onRemove && (
        <Pressable onPress={onRemove} hitSlop={8} style={styles.remove}>
          <Text style={[textStyle, styles.removeText]} allowFontScaling={false}>✕</Text>
        </Pressable>
      )}
    </>
  );

  if (!onPress) return <View style={chipStyle}>{inner}</View>;
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [chipStyle, pressed && styles.pressed]}>
      {inner}
    </Pressable>
  );
}

/**
 * Pick / create tags. Catalog chips toggle selected; the inline "New" field
 * creates a catalog tag and selects it. Used in the Save sheet and the Saved
 * card editor.
 */
export function TagToggleGrid({
  theme: t,
  catalog,
  value,
  onChange,
  onCreate,
  allowCreate = true,
}: {
  theme: TallyTheme;
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

  const toggle = (n: string) => onChange(value.includes(n) ? value.filter((x) => x !== n) : [...value, n]);

  function commit() {
    const name = onCreate(draft);
    setAdding(false);
    setDraft('');
    if (name && !value.includes(name)) onChange([...value, name]);
  }

  return (
    <View style={styles.grid}>
      {catalog.map((name) => (
        <TagChip
          key={name}
          name={name}
          theme={t}
          selected={value.includes(name)}
          onPress={() => toggle(name)}
        />
      ))}
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
          />
        ) : (
          <Pressable
            style={[styles.newBtn, { borderColor: t.ink3 }]}
            onPress={() => setAdding(true)}>
            <Text style={[styles.newBtnText, { color: t.ink2 }]}>+ New</Text>
          </Pressable>
        ))}
    </View>
  );
}

/**
 * Horizontal single-select filter: "All" plus one chip per tag actually in use
 * (catalog order, with used-but-uncatalogued names appended). Tapping a chip
 * filters; tapping it again or "All" clears. Renders nothing when no tag is in
 * use.
 */
export function TagFilterBar({
  theme: t,
  tabs,
  catalog,
  active,
  onChange,
}: {
  theme: TallyTheme;
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

  const allOn = active == null;
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      style={styles.filterScroll}
      contentContainerStyle={styles.filterBar}>
      <Pressable
        onPress={() => onChange(null)}
        style={[
          styles.allChip,
          allOn ? { backgroundColor: t.ink, borderColor: 'transparent' } : { borderColor: t.line },
        ]}>
        <Text style={[styles.allChipText, { color: allOn ? t.screen : t.ink2 }]} allowFontScaling={false}>
          All
        </Text>
      </Pressable>
      {used.map((n) => (
        <TagChip
          key={n}
          name={n}
          theme={t}
          selected={active === n}
          onPress={() => onChange(active === n ? null : n)}
        />
      ))}
    </ScrollView>
  );
}

/** Local copy of the store's tagsOf so this file stays presentational. */
function tagsOfLike(tb: { tags?: string[]; tag?: string }): string[] {
  if (Array.isArray(tb.tags)) return tb.tags;
  if (tb.tag) return [tb.tag];
  return [];
}

const styles = StyleSheet.create({
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 999,
    flexShrink: 0,
  },
  chipSm: { paddingVertical: 3, paddingHorizontal: 9, gap: 5 },
  chipMd: { paddingVertical: 5, paddingHorizontal: 11, gap: 5 },
  chipTextSm: { fontFamily: TallyFonts.mono, fontSize: 11, letterSpacing: 0.1 },
  chipTextMd: { fontFamily: TallyFonts.mono, fontSize: 12, letterSpacing: 0.12 },
  check: { marginRight: -2 },
  remove: { marginLeft: 1, marginRight: -3 },
  removeText: { opacity: 0.8, fontSize: 10 },
  pressed: { opacity: 0.6 },

  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  newBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 5,
    paddingHorizontal: 12,
    borderRadius: 999,
    borderWidth: 1,
    borderStyle: 'dashed',
  },
  newBtnText: { fontFamily: TallyFonts.sansSemi, fontSize: 12.5 },
  newInput: {
    minWidth: 110,
    paddingVertical: 5,
    paddingHorizontal: 12,
    borderRadius: 999,
    borderWidth: 1,
    fontFamily: TallyFonts.mono,
    fontSize: 12,
  },

  filterScroll: { flexGrow: 0 },
  filterBar: { alignItems: 'center', gap: 8, paddingHorizontal: 16, paddingVertical: 2 },
  allChip: {
    flexShrink: 0,
    paddingVertical: 5,
    paddingHorizontal: 13,
    borderRadius: 999,
    borderWidth: 1,
  },
  allChipText: { fontFamily: TallyFonts.mono, fontSize: 12, letterSpacing: 0.12 },
});
