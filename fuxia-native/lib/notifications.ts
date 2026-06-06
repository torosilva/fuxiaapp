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
