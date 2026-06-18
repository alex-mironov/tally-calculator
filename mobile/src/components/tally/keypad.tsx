// keypad.tsx — the 4×5 calculator pad. The tinted ✎ opens the note field and
// ↵ commits the current entry to the running tab.
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { TallyFonts, type TallyTheme } from '@/constants/tally-theme';

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

type Props = {
  theme: TallyTheme;
  onPress: (k: Key) => void;
  /** extra padding so the bottom row clears the home indicator */
  bottomInset: number;
};

export function Keypad({ theme, onPress, bottomInset }: Props) {
  return (
    <View
      style={[
        styles.pad,
        { backgroundColor: theme.screen, borderTopColor: theme.line, paddingBottom: bottomInset + 16 },
      ]}>
      {KEYS.map((row, r) => (
        <View key={r} style={styles.row}>
          {row.map((k) => (
            <KeyButton key={k} k={k} theme={theme} onPress={onPress} />
          ))}
        </View>
      ))}
    </View>
  );
}

function KeyButton({ k, theme, onPress }: { k: Key; theme: TallyTheme } & Pick<Props, 'onPress'>) {
  const isOp = OPS.indexOf(k) >= 0;
  const isDim = k === 'AC' || k === '%' || k === '⌫';
  const isNote = k === '✎';
  const isEnter = k === '↵';

  const keyStyle = [
    styles.key,
    { backgroundColor: 'transparent', borderColor: theme.line },
    isNote && { backgroundColor: theme.accent2, borderColor: 'transparent' },
    isEnter && {
      backgroundColor: theme.deep,
      borderColor: 'transparent',
      shadowColor: theme.deep,
      shadowOpacity: 0.4,
      shadowRadius: 16,
      shadowOffset: { width: 0, height: 6 },
      elevation: 4,
    },
  ];

  const textStyle = [
    styles.keyText,
    { color: theme.ink },
    isOp && { color: theme.accent, fontSize: 23 },
    isDim && { color: theme.ink3, fontSize: 16, fontFamily: TallyFonts.sansSemi },
    isNote && { color: theme.accentInk, fontSize: 18 },
    isEnter && { color: theme.deepInk, fontSize: 18, fontFamily: TallyFonts.sansSemi },
  ];

  return (
    <Pressable
      style={({ pressed }) => [styles.keyWrap, keyStyle, pressed && styles.pressed]}
      onPress={() => onPress(k)}
      android_ripple={{ color: theme.keyLine, borderless: false }}
      accessibilityRole="button"
      accessibilityLabel={k}>
      <Text style={textStyle} allowFontScaling={false}>
        {k}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  pad: {
    flex: 0,
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 16,
    paddingTop: 12,
    gap: 9,
  },
  row: {
    flexDirection: 'row',
    gap: 9,
  },
  keyWrap: {
    flex: 1,
  },
  key: {
    height: 48,
    borderRadius: 12,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pressed: {
    opacity: 0.55,
  },
  keyText: {
    fontFamily: TallyFonts.sansMedium,
    fontSize: 20,
  },
});
