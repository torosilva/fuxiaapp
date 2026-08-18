import FontAwesome from '@expo/vector-icons/FontAwesome';
import { DarkTheme, DefaultTheme, ThemeProvider } from '@react-navigation/native';
import { useFonts } from 'expo-font';
import { Stack, router } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';
import 'react-native-reanimated';

import AsyncStorage from '@react-native-async-storage/async-storage';

import { useColorScheme } from '@/components/useColorScheme';
import { useAuth } from '@/lib/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import { WishlistProvider } from '@/lib/WishlistContext';

export {
  ErrorBoundary,
} from 'expo-router';

export const unstable_settings = {
  initialRouteName: '(tabs)',
};

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [loaded, error] = useFonts({
    SpaceMono: require('../assets/fonts/SpaceMono-Regular.ttf'),
    ...FontAwesome.font,
  });

  useEffect(() => {
    if (error) throw error;
  }, [error]);

  useEffect(() => {
    if (loaded) SplashScreen.hideAsync();
  }, [loaded]);

  if (!loaded) return null;

  return <RootLayoutNav />;
}

function RootLayoutNav() {
  const colorScheme = useColorScheme();
  const { session, isLoading, customer, loyaltyCard, refresh } = useAuth();

  useEffect(() => {
    if (isLoading) return;
    if (!session) {
      router.replace('/onboarding' as any);
    }
  }, [session, isLoading]);

  // Celebración de puntos: cada vez que el total de la tarjeta SUBE respecto a la
  // última vez que la clienta lo vió (compra web acreditada, etc.), mostramos la
  // animación. Guardamos el último total visto por clienta en AsyncStorage. En el
  // primer load no hay valor previo → no dispara (evita falsos positivos).
  useEffect(() => {
    if (isLoading || !customer || !loyaltyCard) return;
    const key = `lastSeenPoints:${customer.id}`;
    (async () => {
      try {
        const prev = await AsyncStorage.getItem(key);
        const prevPts = prev != null ? parseInt(prev, 10) : null;
        if (prevPts != null && loyaltyCard.total_points > prevPts) {
          router.push({
            pathname: '/celebrate-points' as any,
            params: {
              added: String(loyaltyCard.total_points - prevPts),
              total: String(loyaltyCard.total_points),
            },
          });
        }
        await AsyncStorage.setItem(key, String(loyaltyCard.total_points));
      } catch { /* noop */ }
    })();
  }, [loyaltyCard?.total_points, customer?.id, isLoading]);

  // Realtime: si los puntos de SU tarjeta cambian en el servidor (compra web
  // acreditada, ajuste, etc.) mientras la app está abierta, refrescamos. El
  // efecto de arriba detecta el aumento y dispara la celebración al instante.
  useEffect(() => {
    if (!customer?.id) return;
    const channel = supabase
      .channel(`loyalty-${customer.id}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'loyalty_cards', filter: `customer_id=eq.${customer.id}` },
        () => { refresh(); },
      )
      .subscribe();
    return () => { supabase.removeChannel(channel); };
    // refresh se omite a propósito de las deps: loadSession siempre trae datos
    // frescos, y no queremos re-suscribir en cada render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [customer?.id]);

  // Don't render tabs at all until auth is resolved — prevents hero.png flash
  if (isLoading) return null;

  return (
    <WishlistProvider>
    <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="onboarding" options={{ headerShown: false }} />
        <Stack.Screen name="modal" options={{ presentation: 'modal' }} />
        <Stack.Screen name="hilo" options={{ headerShown: false, presentation: 'fullScreenModal', animation: 'slide_from_bottom' }} />
        <Stack.Screen name="admin" options={{ headerShown: false }} />
        <Stack.Screen name="vendedora" options={{ headerShown: false }} />
        <Stack.Screen name="claim" options={{ headerShown: false }} />
        <Stack.Screen name="celebrate-points" options={{ headerShown: false, presentation: 'fullScreenModal', animation: 'fade' }} />
      </Stack>
    </ThemeProvider>
    </WishlistProvider>
  );
}
