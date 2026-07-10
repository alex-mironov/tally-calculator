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
                      onPress={() => {
                        Haptic.select();
                        setAccent(a.accent);
                      }}
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
        <View style={[styles.group, { backgroundColor: t.card, borderColor: t.line }]}>
          {/* disclosure row → the dedicated Tags screen (count + chevron) */}
          <Pressable
            onPress={() => router.push('/tags')}
            accessibilityRole="button"
            accessibilityLabel={`Tags, ${catalog.length}`}
            style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}>
            <Text style={[styles.rowLab, { color: t.ink }]}>Tags</Text>
            <View style={styles.rowTrail}>
              <Text style={[styles.rowValue, { color: t.ink3 }]}>{catalog.length}</Text>
              <Chevron color={t.ink3} />
            </View>
          </Pressable>
        </View>

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

/** Small disclosure chevron drawn with borders (no icon dependency). */
function Chevron({ color }: { color: string }) {
  return <View style={[styles.chev, { borderColor: color }]} />;
}

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
  rowPressed: { opacity: 0.8, transform: [{ scale: 0.98 }] },
  rowTextWrap: { flex: 1 },
  rowLab: { fontFamily: TallyFonts.sansMedium, fontSize: 15 },
  rowSub: { fontFamily: TallyFonts.sans, fontSize: 12.5, marginTop: 3 },
  rowTrail: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  rowValue: { fontFamily: TallyFonts.sans, fontSize: 14.5 },
  chev: {
    width: 9,
    height: 9,
    borderTopWidth: 2,
    borderRightWidth: 2,
    borderTopRightRadius: 1,
    transform: [{ rotate: '45deg' }],
    marginRight: 2,
  },

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
