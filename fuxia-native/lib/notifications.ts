import * as Device from 'expo-device';
import { Platform } from 'react-native';
import Constants from 'expo-constants';
import { supabase } from '@/lib/supabase';

// expo-notifications remote push was removed from Expo Go in SDK 53.
// Skip the require entirely in Expo Go to avoid the error overlay.
const isExpoGo = Constants.appOwnership === 'expo';
let Notifications: typeof import('expo-notifications') | null = null;

if (!isExpoGo) {
  try {
    Notifications = require('expo-notifications');
    Notifications!.setNotificationHandler({
      handleNotification: async () => ({
        shouldShowBanner: true,
        shouldShowList: true,
        shouldPlaySound: true,
        shouldSetBadge: true,
      }),
    });
  } catch {
    // dev build without notifications configured
  }
}

export async function registerPushToken(customerId: string): Promise<string | null> {
  if (!Notifications) return null;
  if (!Device.isDevice) return null;

  const { status: existing } = await Notifications.getPermissionsAsync();
  let status = existing;
  if (status !== 'granted') {
    const req = await Notifications.requestPermissionsAsync();
    status = req.status;
  }
  if (status !== 'granted') return null;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'default',
      importance: Notifications.AndroidImportance.DEFAULT,
      vibrationPattern: [0, 250, 250, 250],
    });
    await ensureApartadosChannel();
  }

  const projectId =
    Constants.expoConfig?.extra?.eas?.projectId ??
    (Constants as any).easConfig?.projectId;

  if (!projectId) return null;

  try {
    const tokenResult = await Notifications.getExpoPushTokenAsync({ projectId });
    const expoToken = tokenResult.data;

    const { error } = await supabase
      .from('push_tokens')
      .upsert(
        {
          customer_id: customerId,
          expo_token: expoToken,
          platform: Platform.OS === 'ios' ? 'ios' : 'android',
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'expo_token' },
      );

    if (error) return null;
    return expoToken;
  } catch {
    return null;
  }
}

// Fuxia 360 · Apartado Gold: a loud channel for "separa este par" notices (server push and in-app alerts use it).
async function ensureApartadosChannel() {
  if (!Notifications || Platform.OS !== 'android') return;
  await Notifications.setNotificationChannelAsync('apartados', {
    name: 'Apartados Fuxia Gold',
    importance: Notifications.AndroidImportance.MAX,
    vibrationPattern: [0, 400, 200, 400],
    sound: 'default',
  });
}

/** Local alert while the seller has the app open (works without server push / Firebase). */
export async function alertNow(title: string, body: string, data: Record<string, unknown> = {}) {
  if (!Notifications) return;
  try {
    const { status } = await Notifications.getPermissionsAsync();
    if (status !== 'granted' && (await Notifications.requestPermissionsAsync()).status !== 'granted') return;
    await ensureApartadosChannel();
    await Notifications.scheduleNotificationAsync({
      content: { title, body, data, sound: 'default' },
      trigger: Platform.OS === 'android' ? { channelId: 'apartados' } as any : null,
    });
  } catch {
    // alerts are best-effort; the list on screen is the source of truth
  }
}

/** Tap on a notice → callback with its data (e.g. open "Apartados"). Returns the unsubscribe function. */
export function onNoticeTap(cb: (data: Record<string, unknown>) => void): () => void {
  if (!Notifications) return () => {};
  const sub = Notifications.addNotificationResponseReceivedListener((r) => cb((r.notification.request.content.data ?? {}) as Record<string, unknown>));
  return () => sub.remove();
}
