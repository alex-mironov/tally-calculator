// share/[id].tsx — landing route for share links (tally://share/<id>).
// Fetches the snapshot from the tally-share Worker, files it as a new saved
// tab (fresh local ids, so references keep working), opens it and drops the
// user on the calculator. Stays on screen only long enough to show a spinner —
// or the error, when the link has expired.
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';

import { TallyFonts } from '@/constants/tally-theme';
import * as Haptic from '@/lib/haptics';
import { fetchShare, remapEntries } from '@/lib/share-link';
import { useTally } from '@/lib/tally-store';

export default function ShareImportScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { importTab, theme: t, themeMode } = useTally();
  const [error, setError] = useState<string | null>(null);
  // one import per mount — an effect re-run (fast refresh, strict mode) must
  // not file the same snapshot twice
  const started = useRef(false);

  useEffect(() => {
    if (started.current || !id) return;
    started.current = true;
    let cancelled = false;
    (async () => {
      try {
        const share = await fetchShare(String(id));
        if (cancelled) return;
        importTab(share.name, share.tags, remapEntries(share.entries));
        Haptic.impact();
        router.replace('/');
      } catch (e) {
        if (cancelled) return;
        setError(
          e instanceof Error && e.message === 'not-found'
            ? 'This share link has expired — or it never existed.'
            : 'Couldn’t load the shared calculation. Check your connection and try again.',
        );
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  return (
    <View style={[styles.root, { backgroundColor: t.screen }]}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />
      {error ? (
        <>
          <Text style={[styles.title, { color: t.ink2 }]}>{error}</Text>
          <Text style={[styles.sub, { color: t.accentInk }]} onPress={() => router.replace('/')}>
            Back to the calculator
          </Text>
        </>
      ) : (
        <>
          <ActivityIndicator color={t.accentInk} />
          <Text style={[styles.sub, { color: t.ink3 }]}>Opening shared calculation…</Text>
        </>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, padding: 32 },
  title: { fontFamily: TallyFonts.serif, fontSize: 20, lineHeight: 26, textAlign: 'center', maxWidth: 280 },
  sub: { fontFamily: TallyFonts.sans, fontSize: 14, textAlign: 'center' },
});
