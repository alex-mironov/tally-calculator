// tag-filter-glass.tsx — the Saved-screen tag filter rendered as a native
// SwiftUI strip of liquid-glass capsules (iOS 26 `buttonStyle(.glass)`).
// Single-select: "All" plus one chip per tag actually in use (catalog order,
// with used-but-uncatalogued names appended). Selection lives in React — the
// native buttons just call back. Renders nothing when no tag is in use.
import { Button, Host, HStack, ScrollView } from '@expo/ui/swift-ui';
import { buttonStyle, padding, tint } from '@expo/ui/swift-ui/modifiers';
import { StyleSheet } from 'react-native';

import { type TallyTheme, type ThemeMode } from '@/constants/tally-theme';

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
    <Host style={styles.host} colorScheme={mode}>
      <ScrollView axes="horizontal" showsIndicators={false}>
        <HStack spacing={8} modifiers={[padding({ leading: 16, trailing: 16 })]}>
          <Button
            label="All"
            onPress={() => onChange(null)}
            modifiers={[allOn ? buttonStyle('glassProminent') : buttonStyle('glass'), tint(allOn ? t.ink : t.ink2)]}
          />
          {used.map((n) => {
            const on = active === n;
            return (
              <Button
                key={n}
                label={n}
                onPress={() => onChange(on ? null : n)}
                modifiers={[on ? buttonStyle('glassProminent') : buttonStyle('glass'), tint(on ? t.accent : t.accentInk)]}
              />
            );
          })}
        </HStack>
      </ScrollView>
    </Host>
  );
}

const styles = StyleSheet.create({
  host: { height: 46, marginBottom: 6 },
});
