// screen-bg.tsx — the signature accent "bloom" background shared by every
// screen. The design layers two radial-gradient accent washes over the flat
// screen colour: one off the top-right corner, one off the bottom-left. React
// Native has no native radial gradient, so we approximate each bloom with a
// corner-anchored LinearGradient that fades to the same colour at zero alpha
// (fading to `transparent` would tint toward black and dirty the wash).
import { LinearGradient } from 'expo-linear-gradient';
import { StyleSheet, View } from 'react-native';

import { type TallyTheme, type ThemeMode } from '@/constants/tally-theme';

export function ScreenBackground({ theme: t, mode }: { theme: TallyTheme; mode: ThemeMode }) {
  // Wash strength: ~0.4 alpha in light, ~0.22 in dark (design `tintHex`).
  const bloom = t.accent2 + (mode === 'dark' ? '38' : '66');
  const fade = t.accent2 + '00';
  return (
    <View style={[StyleSheet.absoluteFill, { backgroundColor: t.screen }]} pointerEvents="none">
      {/* top-right bloom */}
      <LinearGradient
        colors={[bloom, fade]}
        locations={[0, 0.55]}
        start={{ x: 0.92, y: -0.05 }}
        end={{ x: 0.12, y: 0.72 }}
        style={StyleSheet.absoluteFill}
      />
      {/* bottom-left bloom */}
      <LinearGradient
        colors={[bloom, fade]}
        locations={[0, 0.5]}
        start={{ x: 0.04, y: 1.05 }}
        end={{ x: 0.72, y: 0.34 }}
        style={StyleSheet.absoluteFill}
      />
    </View>
  );
}
