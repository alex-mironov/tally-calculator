// settings.tsx — preferences for the tab: accent, theme, and which pieces of
// the running tab to show. Presented as a modal over the calculator.
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ACCENTS, TallyFonts, type ThemeMode } from '@/constants/tally-theme';
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
  } = useTally();

  return (
    <View style={[styles.root, { backgroundColor: t.screen, paddingTop: insets.top }]}>
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />

      {/* top bar */}
      <View style={styles.bar}>
        <Pressable style={styles.back} onPress={() => router.back()} hitSlop={8}>
          <Text style={[styles.backChevron, { color: t.ink2 }]}>‹</Text>
          <Text style={[styles.backText, { color: t.ink2 }]}>TAB</Text>
        </Pressable>
        <Pressable style={[styles.done, { backgroundColor: t.deep }]} onPress={() => router.back()}>
          <Text style={[styles.doneText, { color: t.deepInk }]}>Done</Text>
        </Pressable>
      </View>

      <View style={styles.header}>
        <Text style={[styles.eyebrow, { color: t.ink3 }]}>PREFERENCES</Text>
        <Text style={[styles.hTitle, { color: t.ink }]}>Settings</Text>
      </View>

      <ScrollView contentContainerStyle={{ paddingBottom: insets.bottom + 24 }}>
        <SecLab theme={t}>Appearance</SecLab>

        {/* accent swatches */}
        <View style={[styles.swatchRow, { borderTopColor: t.line }]}>
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

        {/* theme segmented control */}
        <View style={[styles.row, { borderTopColor: t.line }]}>
          <Text style={[styles.rowLab, { color: t.ink }]}>Theme</Text>
          <View style={styles.seg}>
            {(['light', 'dark'] as ThemeMode[]).map((m) => {
              const on = themeMode === m;
              return (
                <Pressable
                  key={m}
                  onPress={() => setThemeMode(m)}
                  style={[
                    styles.segBtn,
                    { borderColor: on ? 'transparent' : t.line, backgroundColor: on ? t.deep : 'transparent' },
                  ]}>
                  <Text style={[styles.segText, { color: on ? t.deepInk : t.ink2 }]}>
                    {m === 'light' ? 'Light' : 'Dark'}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </View>

        <SecLab theme={t}>The tab</SecLab>

        <View style={[styles.row, { borderTopColor: t.line }]}>
          <View style={styles.rowTextWrap}>
            <Text style={[styles.rowLab, { color: t.ink }]}>Show running total</Text>
            <Text style={[styles.rowSub, { color: t.ink3 }]}>the live sum above the keypad</Text>
          </View>
          <Switch
            value={showTotal}
            onValueChange={setShowTotal}
            trackColor={{ true: t.accent, false: t.ink3 }}
            thumbColor="#ffffff"
            ios_backgroundColor={t.ink3}
          />
        </View>

        <View style={[styles.row, { borderTopColor: t.line }]}>
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

        <Text style={[styles.about, { color: t.ink3 }]}>
          TALLY · CONCEPT PROTOTYPE · v0.1{'\n'}SETTINGS SAVED FOR THIS SESSION
        </Text>
      </ScrollView>
    </View>
  );
}

function SecLab({ theme, children }: { theme: ReturnType<typeof useTally>['theme']; children: string }) {
  return (
    <View style={styles.secLab}>
      <Text style={[styles.secMark, { color: theme.accent }]}>►</Text>
      <Text style={[styles.secLabText, { color: theme.accentInk }]}>{children}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  bar: {
    height: 46,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  back: { flexDirection: 'row', alignItems: 'center', gap: 7, padding: 6 },
  backChevron: { fontSize: 22, lineHeight: 22, fontWeight: '500' },
  backText: { fontFamily: TallyFonts.monoSemi, fontSize: 10.5, letterSpacing: 1.4 },
  done: { paddingVertical: 7, paddingHorizontal: 16, borderRadius: 999 },
  doneText: { fontFamily: TallyFonts.sansSemi, fontSize: 12.5 },

  header: { paddingHorizontal: 22, paddingTop: 6, paddingBottom: 16 },
  eyebrow: { fontFamily: TallyFonts.mono, fontSize: 10, letterSpacing: 2.2, marginBottom: 9 },
  hTitle: { fontFamily: TallyFonts.serif, fontSize: 42, lineHeight: 42 },

  secLab: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 22, paddingTop: 24, paddingBottom: 4 },
  secMark: { fontSize: 9 },
  secLabText: { fontFamily: TallyFonts.mono, fontSize: 10, letterSpacing: 2, textTransform: 'uppercase' },

  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingHorizontal: 22,
    paddingVertical: 15,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  rowTextWrap: { flex: 1 },
  rowLab: { fontFamily: TallyFonts.sansMedium, fontSize: 14.5 },
  rowSub: { fontFamily: TallyFonts.mono, fontSize: 10.5, marginTop: 4, letterSpacing: 0.3 },

  swatchRow: { paddingHorizontal: 22, paddingVertical: 15, borderTopWidth: StyleSheet.hairlineWidth },
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

  seg: { flexDirection: 'row', gap: 6 },
  segBtn: { paddingVertical: 7, paddingHorizontal: 16, borderRadius: 999, borderWidth: 1 },
  segText: { fontFamily: TallyFonts.sansSemi, fontSize: 12.5 },

  about: {
    paddingHorizontal: 22,
    paddingTop: 26,
    fontFamily: TallyFonts.mono,
    fontSize: 10,
    lineHeight: 19,
    letterSpacing: 0.6,
  },
});
