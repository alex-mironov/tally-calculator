// icon.tsx — the app's single interface-icon vocabulary, on SF Symbols.
//
// HIG "Icons": "all interface icons in your app need to use a consistent size,
// level of detail, stroke thickness (or weight), and perspective" and "in
// general, match the weights of interface icons and adjacent text".
//
// Before this, icons were a mix of Unicode characters (⌫ ✎ ↵ ✓ ✕) and shapes
// hand-drawn out of bordered Views. The Unicode route was the worse of the two:
// Geist has no glyph for ⌫/✎/↵, so iOS substituted a *different* fallback font
// per character — which is why they rendered at visibly different weights.
//
// SF Symbols solve that by construction: at a given point size and weight every
// symbol is drawn to the same optical metrics. So the rule here is one Size
// token + one Weight per context, and colour — never size — carries emphasis.
//
// `resizeMode="center"` matters: it draws the symbol at its natural size for the
// requested point size instead of stretching it to the box, so a wide symbol
// (minus, delete.left) keeps the same stroke weight as a square one (plus).
import { SymbolView, type SFSymbol, type SymbolWeight } from 'expo-symbols';
import { StyleSheet, Text, type ColorValue, type StyleProp, type ViewStyle } from 'react-native';

export type { SFSymbol };

/** Point sizes, one per context. Anything drawn in that context uses its size. */
export const IconSize = {
  /** keypad keys — sits with the 21pt Geist Medium digits */
  key: 20,
  /** swipe actions and other standalone controls */
  action: 19,
  /** list-row affordances — chevrons, edit pencils, next to 15–16.5pt labels */
  row: 16,
  /** inside a tag chip, alongside 11–12pt monospaced text */
  chip: 10,
} as const;

type Props = {
  name: SFSymbol;
  size: number;
  color: ColorValue;
  /** Defaults to semibold — the weight the keypad and chips read best at. */
  weight?: SymbolWeight;
  /** Rendered on platforms without SF Symbols (Android, web). */
  fallback?: string;
  style?: StyleProp<ViewStyle>;
};

export function Icon({ name, size, color, weight = 'semibold', fallback, style }: Props) {
  // Generous square box so nothing clips; `center` keeps the glyph unscaled, so
  // every symbol shares one stroke weight regardless of its aspect ratio.
  const box = Math.round(size * 1.6);
  return (
    <SymbolView
      name={name}
      size={size}
      weight={weight}
      tintColor={color}
      resizeMode="center"
      style={[{ width: box, height: box }, styles.center, style]}
      fallback={
        fallback ? (
          <Text style={{ color: color as string, fontSize: size }} maxFontSizeMultiplier={1.3}>
            {fallback}
          </Text>
        ) : undefined
      }
    />
  );
}

const styles = StyleSheet.create({
  center: { alignItems: 'center', justifyContent: 'center' },
});
