// tag-filter-glass.tsx — the Saved-screen tag filter rendered as native SwiftUI
// liquid-glass capsules (iOS 26 `buttonStyle(.glass)`).
// Single-select: "All" plus one chip per tag actually in use (catalog order,
// with used-but-uncatalogued names appended). Selection lives in React — the
// native buttons just call back. Renders nothing when no tag is in use.
import { Button, Host } from '@expo/ui/swift-ui';
import { buttonStyle, tint } from '@expo/ui/swift-ui/modifiers';
import { StyleSheet, View } from 'react-native';

import { type TallyTheme, type ThemeMode } from '@/constants/tally-theme';
import * as Haptic from '@/lib/haptics';

/** Local copy of the store's tagsOf so this file stays presentational. */
function tagsOfLike(tb: { tags?: string[]; tag?: string }): string[] {
  if (Array.isArray(tb.tags)) return tb.tags;
  if (tb.tag) return [tb.tag];
  return [];
}

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

  const allOn = active == null;
  return (
    // The row wraps in RN rather than scrolling horizontally, and every capsule
    // is its own Host. Both matter: iOS 26 lays a scroll-edge wash over any
    // scroll view holding liquid glass, and on a strip this short that wash
    // covers the whole row — a grey block sitting on the screen colour. @expo/ui
    // exposes no modifier to turn it off, so the strip simply isn't a scroll
    // view; wrapping also keeps every tag reachable as the catalog grows.
    <View style={styles.row}>
      <GlassChip
        label="All"
        on={allOn}
        tintColor={allOn ? t.ink : t.ink2}
        mode={mode}
        onPress={() => onChange(null)}
      />
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
    </View>
  );
}

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
    <Host matchContents colorScheme={mode}>
      <Button
        label={label}
        onPress={() => {
          Haptic.select();
          onPress();
        }}
        modifiers={[on ? buttonStyle('glassProminent') : buttonStyle('glass'), tint(tintColor)]}
      />
    </Host>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
    marginBottom: 6,
  },
});
