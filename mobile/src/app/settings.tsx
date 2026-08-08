// settings.tsx — preferences for the tab (2026 refresh): accent, theme, and
// which pieces of the running tab to show. Grouped cards, sentence-case labels.
// The Tags row pushes the dedicated Tags screen. Presented as a push over the
// calculator, on the flat screen colour (the bloom stays on the keypad screen).
import { Host, Picker, Text as UIText } from '@expo/ui/swift-ui';
import { pickerStyle, tag, tint } from '@expo/ui/swift-ui/modifiers';
import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CardRow, GroupedCard, ROW_INSET } from '@/components/tally/grouped-list';
import { Icon, IconSize } from '@/components/tally/icon';
import { ACCENTS, TallyFonts, type ThemeMode } from '@/constants/tally-theme';
import * as Haptic from '@/lib/haptics';
import { useTally } from '@/lib/tally-store';

export default function SettingsScreen() {
  const router = useRouter();
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
  } = useTally();

  return (
    <View style={[styles.root, { backgroundColor: t.screen }]}>
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
        contentContainerStyle={{ paddingBottom: insets.bottom + 24 }}>
        <Text style={[styles.hSub, { color: t.ink2 }]}>Appearance and what shows on the tab.</Text>

        <Text style={[styles.secLab, { color: t.ink3 }]}>Appearance</Text>
        <GroupedCard theme={t}>
          {/* accent swatches */}
          <CardRow theme={t} first style={styles.swatchRow}>
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
                      onPress={() => {
                        Haptic.select();
                        setAccent(a.accent);
                      }}
                      accessibilityLabel={a.name}
                      style={[styles.swatch, { backgroundColor: a.accent }]}>
                      {on && <Icon name="checkmark" size={IconSize.chip + 3} color="#ffffff" weight="bold" fallback="✓" />}
                    </Pressable>
                  </View>
                );
              })}
            </View>
          </CardRow>

          {/* theme — native SwiftUI segmented control */}
          <CardRow theme={t}>
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
          </CardRow>
        </GroupedCard>

        <Text style={[styles.secLab, { color: t.ink3 }]}>Tags</Text>
        <GroupedCard theme={t}>
          {/* disclosure row → the dedicated Tags screen (count + chevron) */}
          <CardRow
            theme={t}
            first
            onPress={() => router.push('/tags')}
            accessibilityRole="button"
            accessibilityLabel={`Tags, ${catalog.length}`}>
            <Text style={[styles.rowLab, { color: t.ink }]}>Tags</Text>
            <View style={styles.rowTrail}>
              <Text style={[styles.rowValue, { color: t.ink3 }]}>{catalog.length}</Text>
              <Icon name="chevron.right" size={IconSize.row - 3} color={t.ink3} weight="semibold" fallback="›" />
            </View>
          </CardRow>
        </GroupedCard>

        <Text style={[styles.secLab, { color: t.ink3 }]}>The tab</Text>
        <GroupedCard theme={t}>
          <CardRow theme={t} first>
            <View style={styles.rowTextWrap}>
              <Text style={[styles.rowLab, { color: t.ink }]}>Show running total</Text>
              <Text style={[styles.rowSub, { color: t.ink3 }]}>The live sum above the keypad</Text>
            </View>
            {/* HIG "Toggles": only the *on* tint may be themed. The off track and
                the thumb stay system-drawn — the stock light-grey off state is
                what gives the accent enough contrast to read at a glance. */}
            <Switch
              value={showTotal}
              onValueChange={setShowTotal}
              trackColor={{ true: t.accent }}
              accessibilityLabel="Show running total"
            />
          </CardRow>

          <CardRow theme={t}>
            <View style={styles.rowTextWrap}>
              <Text style={[styles.rowLab, { color: t.ink }]}>Show the maths under each line</Text>
              <Text style={[styles.rowSub, { color: t.ink3 }]}>e.g. 60 ÷ 4 beneath a split</Text>
            </View>
            <Switch
              value={showExpr}
              onValueChange={setShowExpr}
              trackColor={{ true: t.accent }}
              accessibilityLabel="Show the maths under each line"
            />
          </CardRow>
        </GroupedCard>

        <Text style={[styles.about, { color: t.ink3 }]}>
          Tally · concept prototype · v0.1{'\n'}Settings saved on this device
        </Text>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },

  // section labels and loose text line up with the *rows'* text, not with the
  // card's edge — ROW_INSET is that x, shared with the list (see grouped-list)
  hSub: { fontFamily: TallyFonts.sans, fontSize: 13.5, paddingTop: 4, paddingBottom: 4, paddingHorizontal: ROW_INSET },
  secLab: {
    fontFamily: TallyFonts.sansSemi,
    fontSize: 13,
    paddingTop: 24,
    paddingBottom: 8,
    paddingHorizontal: ROW_INSET,
  },

  rowTextWrap: { flex: 1 },
  rowLab: { fontFamily: TallyFonts.sansMedium, fontSize: 15 },
  rowSub: { fontFamily: TallyFonts.sans, fontSize: 12.5, marginTop: 4 },
  rowTrail: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  rowValue: { fontFamily: TallyFonts.sans, fontSize: 14.5 },

  // Light/Dark native segmented control
  segHost: { width: 160, height: 32 },

  // the swatches wrap onto their own line, so this row stacks instead of
  // sitting side by side like the others
  swatchRow: { flexDirection: 'column', alignItems: 'stretch', gap: 16 },
  swatches: { flexDirection: 'row', gap: 16, flexWrap: 'wrap' },
  swatchWrap: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  swatch: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center' },
  swatchRing: {
    // the ring sits 4pt outside the 40pt swatch, so its radius is the
    // swatch's 20 plus that 4 — derived from the shape, not chosen
    position: 'absolute',
    top: -4,
    left: -4,
    right: -4,
    bottom: -4,
    borderRadius: 24,
    borderWidth: 2,
  },

  about: {
    paddingHorizontal: ROW_INSET,
    paddingTop: 24,
    fontFamily: TallyFonts.sans,
    fontSize: 12,
    lineHeight: 20,
  },
});
