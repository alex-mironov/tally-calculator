// nav.tsx — shared navigation chrome for the Saved/Settings screens. The back
// button and large title now come from the native nav bar; this just supplies
// the small pill action for the header's trailing slot (headerRight).
import { Pressable, StyleSheet, Text } from 'react-native';

import { TallyFonts } from '@/constants/tally-theme';

/** Trailing pill action (e.g. "+ New tab") for the header's right slot. */
export function HeaderAction({
  label,
  color,
  background,
  onPress,
}: {
  label: string;
  color: string;
  background: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.action, { backgroundColor: background }, pressed && styles.pressed]}>
      <Text style={[styles.actionText, { color }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  pressed: { opacity: 0.45 },
  action: { paddingVertical: 7, paddingHorizontal: 14, borderRadius: 999 },
  actionText: { fontFamily: TallyFonts.sansSemi, fontSize: 14 },
});
