import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

import { TallyProvider } from '@/lib/tally-store';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts({
    'Geist-Regular': require('@/assets/fonts/Geist-Regular.ttf'),
    'Geist-Medium': require('@/assets/fonts/Geist-Medium.ttf'),
    'Geist-SemiBold': require('@/assets/fonts/Geist-SemiBold.ttf'),
    'Geist-Bold': require('@/assets/fonts/Geist-Bold.ttf'),
    'GeistMono-Regular': require('@/assets/fonts/GeistMono-Regular.ttf'),
    'GeistMono-Medium': require('@/assets/fonts/GeistMono-Medium.ttf'),
    'GeistMono-SemiBold': require('@/assets/fonts/GeistMono-SemiBold.ttf'),
  });

  useEffect(() => {
    if (fontsLoaded || fontError) SplashScreen.hideAsync();
  }, [fontsLoaded, fontError]);

  // Hold the splash until the fonts are ready (or fail) so we never flash
  // the wrong typeface.
  if (!fontsLoaded && !fontError) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <TallyProvider>
        {/* Saved & Settings are pushed (not modal) so they get the real iOS
            nav bar: a native large title and the system back chevron. */}
        <Stack screenOptions={{ headerShown: false }}>
          <Stack.Screen name="index" />
          <Stack.Screen name="saved" />
          <Stack.Screen name="settings" />
        </Stack>
      </TallyProvider>
    </GestureHandlerRootView>
  );
}
