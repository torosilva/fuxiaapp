// The app's cover photo (welcome screen + Home hero), resolved in this order — none of it needs an app build:
//   1. the photo chosen in Fuxia 360 (Más → Foto de la app), read with the anonymous f360_app_welcome_photo();
//      a database without Fuxia 360 yet simply errors and we move on;
//   2. the WooCommerce product marked "Destacado";
//   3. the newest WooCommerce product.
// The last result is remembered so the next launch shows it instantly.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { wcService, WCProduct } from '@/services/WooCommerceService';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const CACHE_KEY = 'appCoverUri';

export type AppCover = { uri: string | null; product: WCProduct | null; fromF360: boolean };

async function f360Photo(): Promise<string | null> {
  try {
    const { data, error } = await supabase.rpc('f360_app_welcome_photo');
    const path = !error && data && typeof data === 'object' ? (data as { path?: string | null }).path : null;
    return path ? `${SUPABASE_URL}/storage/v1/object/public/product-images/${path}` : null;
  } catch { return null; }
}

async function storeProduct(): Promise<WCProduct | null> {
  try {
    const featured = await wcService.getProducts({ featured: 'true', per_page: 1 });
    if (featured[0]) return featured[0];
    const newest = await wcService.getProducts({ orderby: 'date', order: 'desc', per_page: 1 });
    return newest[0] ?? null;
  } catch { return null; }
}

export function useAppCover(): AppCover {
  const [cover, setCover] = useState<AppCover>({ uri: null, product: null, fromF360: false });
  useEffect(() => {
    let alive = true;
    AsyncStorage.getItem(CACHE_KEY)
      .then((cached) => { if (alive && cached) setCover((c) => (c.uri ? c : { ...c, uri: cached })); })
      .catch(() => {});
    (async () => {
      const [photo, product] = await Promise.all([f360Photo(), storeProduct()]);
      const uri = photo ?? product?.images?.[0]?.src ?? null;
      if (!alive) return;
      setCover((c) => ({ uri: uri ?? c.uri, product, fromF360: !!photo }));
      if (uri) AsyncStorage.setItem(CACHE_KEY, uri).catch(() => {});
    })();
    return () => { alive = false; };
  }, []);
  return cover;
}
