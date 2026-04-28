import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import { Platform } from 'react-native';
import Constants from 'expo-constants';
import { supabase } from '@/lib/supabase';

// Foreground: show banner + play sound so the señora notices even if the app is open.
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

/**
 * Register the device for push notifications and upsert the Expo token
 * against the given customer so the server can push them updates.
 *
 * Idempotent — safe to call on every login or app resume.
 */
export async function registerPushToken(customerId: string): Promise<string | null> {
  // Physical device only — push tokens don't work on simulators/emulators.
  if (!Device.isDevice) return null;

  const { status: existing } = await Notifications.getPermissionsAsync();
  let status = existing;
  if (status !== 'granted') {
    const req = await Notifications.requestPermissionsAsync();
    status = req.status;
  }
  if (status !== 'granted') {
    console.log('[push] permission not granted');
    return null;
  }

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'default',
      importance: Notifications.AndroidImportance.DEFAULT,
      vibrationPattern: [0, 250, 250, 250],
    });
  }

  const projectId =
    Constants.expoConfig?.extra?.eas?.projectId ??
    (Constants as any).easConfig?.projectId;

  if (!projectId) {
    console.warn('[push] no eas projectId configured; skipping');
    return null;
  }

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

    if (error) {
      console.error('[push] save token failed', error.message);
      return null;
    }

    return expoToken;
  } catch (err) {
    console.warn('[push] getExpoPushTokenAsync failed:', err);
    return null;
  }
}
