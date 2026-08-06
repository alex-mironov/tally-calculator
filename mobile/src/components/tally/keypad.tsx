// keypad.tsx — the 4×5 calculator pad. The tinted ✎ opens the note field and
// ↵ commits the current entry to the running tab.
//
// On iOS 26+ the keys render as native Liquid Glass (expo-glass-effect); on
// older iOS / Android they fall back to the opaque "refresh" keys. The ↵ key is
// always the solid deep-ink CTA — glass is for the neutral surface keys.
import { GlassView, isLiquidGlassAvailable } from 'expo-glass-effect';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { playKeyClick } from '../../../modules/key-click';
import { Icon, IconSize, type SFSymbol } from '@/components/tally/icon';
import * as Haptic from '@/lib/haptics';

import { TallyFonts, type TallyTheme, type ThemeMode } from '@/constants/tally-theme';
import { Elevation } from '@/constants/tokens';

export type Key =
  | '⌫' | 'AC' | '%' | '÷'
  | '7' | '8' | '9' | '×'
  | '4' | '5' | '6' | '−'
  | '1' | '2' | '3' | '+'
  | '✎' | '0' | '.' | '↵';

// Top row follows the iOS Calculator's order (⌫ · AC · % · ÷) so muscle
// memory from the system app transfers.
const KEYS: Key[][] = [
  ['⌫', 'AC', '%', '÷'],
  ['7', '8', '9', '×'],
  ['4', '5', '6', '−'],
  ['1', '2', '3', '+'],
  ['✎', '0', '.', '↵'],
];

const OPS = '+−×÷';

// Every non-numeric key is an SF Symbol at one size and weight (see icon.tsx).
// `label` is the VoiceOver text — HIG "Icons": provide alternative text labels,
// which matters most here because the old labels were the raw glyphs and read
// as gibberish. `fallback` is the character used off-iOS.
const KEY_ICON: Partial<Record<Key, { name: SFSymbol; label: string; fallback: string }>> = {
  '%': { name: 'percent', label: 'Percent', fallback: '%' },
  '⌫': { name: 'delete.left', label: 'Delete', fallback: '⌫' },
  '÷': { name: 'divide', label: 'Divide', fallback: '÷' },
  '×': { name: 'multiply', label: 'Multiply', fallback: '×' },
  '−': { name: 'minus', label: 'Minus', fallback: '−' },
  '+': { name: 'plus', label: 'Plus', fallback: '+' },
  '✎': { name: 'square.and.pencil', label: 'Add a note', fallback: '✎' },
  '↵': { name: 'return', label: 'Add to tab', fallback: '↵' },
};

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
        { backgroundColor: theme.screen, borderTopColor: theme.line, paddingBottom: bottomInset + 8 },
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

  const icon = KEY_ICON[k];

  // One ink per role, shared by the text keys and the symbol keys. Emphasis is
  // carried by colour alone — every symbol keeps the same size and weight.
  const ink = isOp
    ? theme.accent
    : isDim
      ? theme.ink3
      : isNote
        ? theme.accentInk
        : isEnter
          ? theme.deepInk
          : theme.ink;

  const textStyle = [
    styles.keyText,
    { color: ink },
    // "AC" is a word, not an icon; nudged up a point so its cap height sits
    // level with the 20pt symbols sharing its row.
    isDim && { fontSize: 17, fontFamily: TallyFonts.sansSemi },
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
    const label = icon ? (
      <Icon name={icon.name} size={IconSize.key} color={ink} fallback={icon.fallback} />
    ) : (
      <Text style={textStyle} maxFontSizeMultiplier={1.3}>
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
      onPress={() => {
        // HIG asks a custom input view to sound like the system keyboard, so
        // every key gets the standard click (silent if the user has keyboard
        // sounds off). Light tactile tick alongside it; ↵ is left to commit()'s
        // success notification so the commit doesn't double up.
        playKeyClick();
        if (!isEnter) Haptic.tap();
        onPress(k);
      }}
      android_ripple={{ color: theme.keyLine, borderless: false }}
      accessibilityRole="button"
      accessibilityLabel={icon ? icon.label : k}>
      {({ pressed }) => renderSurface(pressed)}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  pad: {
    flex: 0,
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 16,
    paddingTop: 12,
    gap: 8,
  },
  row: {
    flexDirection: 'row',
    gap: 8,
  },
  keyWrap: {
    flex: 1,
  },
  // Shared key geometry — the surface (glass or opaque) fills the wrap width.
  // 48pt keys: above the 44pt HIG minimum, and the shave (plus tighter gaps)
  // hands the list back roughly a full row of height.
  key: {
    height: 48,
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
  // design `.tally-key:active` — keys squish down rather than fade
  pressed: {
    transform: [{ scale: 0.94 }],
    opacity: 0.9,
  },
  keyText: {
    fontFamily: TallyFonts.sansMedium,
    fontSize: 21,
  },
});
