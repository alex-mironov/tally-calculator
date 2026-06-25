// keypad.tsx — the 4×5 calculator pad. The tinted ✎ opens the note field and
// ↵ commits the current entry to the running tab.
//
// On iOS 26+ the keys render as native Liquid Glass (expo-glass-effect); on
// older iOS / Android they fall back to the opaque "refresh" keys. The ↵ key is
// always the solid deep-ink CTA — glass is for the neutral surface keys.
import { GlassView, isLiquidGlassAvailable } from 'expo-glass-effect';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { TallyFonts, type TallyTheme, type ThemeMode } from '@/constants/tally-theme';
import { Elevation } from '@/constants/tokens';

export type Key =
  | 'AC' | '%' | '⌫' | '÷'
  | '7' | '8' | '9' | '×'
  | '4' | '5' | '6' | '−'
  | '1' | '2' | '3' | '+'
  | '✎' | '0' | '.' | '↵';

const KEYS: Key[][] = [
  ['AC', '%', '⌫', '÷'],
  ['7', '8', '9', '×'],
  ['4', '5', '6', '−'],
  ['1', '2', '3', '+'],
  ['✎', '0', '.', '↵'],
];

const OPS = '+−×÷';

// Resolved once: true only on builds where iOS Liquid Glass is available.
const LIQUID = isLiquidGlassAvailable();

type Props = {
  theme: TallyTheme;
  /** drives the glass appearance so keys follow the app theme, not the system */
  themeMode: ThemeMode;
  onPress: (k: Key) => void;
  /** extra padding so the bottom row clears the home indicator */
  bottomInset: number;
};

export function Keypad({ theme, themeMode, onPress, bottomInset }: Props) {
  return (
    <View
      style={[
        styles.pad,
        { backgroundColor: theme.screen, borderTopColor: theme.line, paddingBottom: bottomInset + 16 },
      ]}>
      {KEYS.map((row, r) => (
        <View key={r} style={styles.row}>
          {row.map((k) => (
            <KeyButton key={k} k={k} theme={theme} themeMode={themeMode} onPress={onPress} />
          ))}
        </View>
      ))}
    </View>
  );
}

function KeyButton({
  k,
  theme,
  themeMode,
  onPress,
}: { k: Key; theme: TallyTheme } & Pick<Props, 'themeMode' | 'onPress'>) {
  const isOp = OPS.indexOf(k) >= 0;
  const isDim = k === 'AC' || k === '%' || k === '⌫';
  const isNote = k === '✎';
  const isEnter = k === '↵';

  // Enter is always the solid CTA; the rest become glass when available.
  const glass = LIQUID && !isEnter;

  const textStyle = [
    styles.keyText,
    { color: theme.ink },
    isOp && { color: theme.accent, fontSize: 24 },
    isDim && { color: theme.ink3, fontSize: 16, fontFamily: TallyFonts.sansSemi },
    isNote && { color: theme.accentInk, fontSize: 18 },
    isEnter && { color: theme.deepInk, fontSize: 18, fontFamily: TallyFonts.sansSemi },
  ];

  const opaqueStyle = [
    styles.key,
    styles.keyOpaque,
    { backgroundColor: theme.key, borderColor: theme.keyLine },
    isNote && { backgroundColor: theme.accent2, borderColor: 'transparent' },
    isEnter && {
      backgroundColor: theme.deep,
      borderColor: 'transparent',
      // tinted CTA press lift (shadow-cta); the deep ink supplies the colour
      shadowColor: theme.deep,
      ...Elevation.cta,
    },
  ];

  const renderSurface = (pressed: boolean) => {
    const label = (
      <Text style={textStyle} allowFontScaling={false}>
        {k}
      </Text>
    );
    if (glass) {
      return (
        <GlassView
          glassEffectStyle="regular"
          tintColor={isNote ? theme.accent2 : undefined}
          colorScheme={themeMode}
          style={[styles.key, styles.keyGlass, pressed && styles.pressed]}>
          {label}
        </GlassView>
      );
    }
    return <View style={[opaqueStyle, pressed && styles.pressed]}>{label}</View>;
  };

  return (
    <Pressable
      style={styles.keyWrap}
      onPress={() => onPress(k)}
      android_ripple={{ color: theme.keyLine, borderless: false }}
      accessibilityRole="button"
      accessibilityLabel={k}>
      {({ pressed }) => renderSurface(pressed)}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  pad: {
    flex: 0,
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 16,
    paddingTop: 15,
    gap: 10,
  },
  row: {
    flexDirection: 'row',
    gap: 10,
  },
  keyWrap: {
    flex: 1,
  },
  // Shared key geometry — the surface (glass or opaque) fills the wrap width.
  key: {
    height: 52,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  keyOpaque: {
    borderWidth: 1,
    // soft lift on the opaque keys (refresh look)
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowRadius: 2,
    shadowOffset: { width: 0, height: 1 },
    elevation: 1,
  },
  keyGlass: {
    overflow: 'hidden',
  },
  pressed: {
    opacity: 0.55,
  },
  keyText: {
    fontFamily: TallyFonts.sansMedium,
    fontSize: 21,
  },
});
