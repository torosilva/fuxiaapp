/**
 * Country selection for multi-currency.
 *
 * The WooCommerce store at fuxiaballerinas.com runs the "WooCommerce Price
 * Based on Country" plugin (Oscar Gare). It expects the country code via the
 * `wcpbc-manual-country` query param. The web auto-detects via Cloudflare's
 * `CF-IPCountry` header, but native fetch from React Native does not always
 * trigger that path, so we pass the country explicitly on every API call.
 *
 * Resolution order on first read:
 *   1. AsyncStorage (last user choice / synced from profile)
 *   2. Device locale (expo-localization) if it maps to a supported country
 *   3. 'MX' (the store default)
 *
 * After first read the value is cached in memory and broadcast to subscribers.
 */
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Localization from 'expo-localization';
import { supabase } from '@/lib/supabase';

export const SUPPORTED_COUNTRIES = [
  { code: 'MX', name: 'México',         flag: '🇲🇽', currency: 'MXN' },
  { code: 'CO', name: 'Colombia',       flag: '🇨🇴', currency: 'COP' },
  { code: 'US', name: 'Estados Unidos', flag: '🇺🇸', currency: 'USD' },
  { code: 'CA', name: 'Canadá',         flag: '🇨🇦', currency: 'USD' },
  { code: 'GT', name: 'Guatemala',      flag: '🇬🇹', currency: 'USD' },
  { code: 'SV', name: 'El Salvador',    flag: '🇸🇻', currency: 'USD' },
  { code: 'CL', name: 'Chile',          flag: '🇨🇱', currency: 'USD' },
  { code: 'AR', name: 'Argentina',      flag: '🇦🇷', currency: 'USD' },
  { code: 'PA', name: 'Panamá',         flag: '🇵🇦', currency: 'USD' },
  { code: 'CR', name: 'Costa Rica',     flag: '🇨🇷', currency: 'USD' },
  { code: 'PE', name: 'Perú',           flag: '🇵🇪', currency: 'USD' },
] as const;

export type CountryCode = typeof SUPPORTED_COUNTRIES[number]['code'];

const STORAGE_KEY = '@fuxia/country';
const DEFAULT_COUNTRY: CountryCode = 'MX';

export function isSupported(code: string | null | undefined): code is CountryCode {
  return !!code && SUPPORTED_COUNTRIES.some((c) => c.code === code);
}

export function detectDeviceCountry(): CountryCode {
  try {
    const region = Localization.getLocales()[0]?.regionCode?.toUpperCase();
    if (isSupported(region)) return region;
  } catch {
    // expo-localization can throw on non-iOS dev hosts; fall through to default
  }
  return DEFAULT_COUNTRY;
}

let _cached: CountryCode | null = null;
const _listeners = new Set<(c: CountryCode) => void>();

/** Resolves the country to use for API/UI; safe to call repeatedly (cached). */
export async function getCountry(): Promise<CountryCode> {
  if (_cached) return _cached;
  try {
    const stored = await AsyncStorage.getItem(STORAGE_KEY);
    if (isSupported(stored)) {
      _cached = stored;
      return stored;
    }
  } catch {
    // AsyncStorage failures should not block product loading
  }
  const detected = detectDeviceCountry();
  _cached = detected;
  return detected;
}

/** Last known country without async — only safe after at least one getCountry() call. */
export function getCountrySync(): CountryCode {
  return _cached ?? detectDeviceCountry();
}

/** User-driven change (selector in profile). Persists to AsyncStorage and Supabase. */
export async function setCountry(code: CountryCode, customerId?: string): Promise<void> {
  _cached = code;
  await AsyncStorage.setItem(STORAGE_KEY, code);
  if (customerId) {
    await supabase.from('customers').update({ country: code }).eq('id', customerId);
  }
  for (const fn of _listeners) fn(code);
}

/** Called from useAuth after loading the customer row, to align local cache. */
export async function syncFromCustomer(country: string | null | undefined) {
  if (!isSupported(country)) return;
  if (_cached === country) return;
  _cached = country;
  await AsyncStorage.setItem(STORAGE_KEY, country);
  for (const fn of _listeners) fn(country);
}

export function subscribeCountry(fn: (c: CountryCode) => void): () => void {
  _listeners.add(fn);
  return () => {
    _listeners.delete(fn);
  };
}

export function getCountryMeta(code: CountryCode) {
  return SUPPORTED_COUNTRIES.find((c) => c.code === code) ?? SUPPORTED_COUNTRIES[0];
}

/**
 * Formats `1234.5` as `$1,235 MXN`. Uses thousand separators based on currency
 * (es-MX → comma, es-CO → period, etc). Currency code is appended so the user
 * can tell MXN $2,700 from USD $160 (both use the `$` glyph).
 */
export function formatMoney(
  amount: number | string,
  currency: string,
  symbol: string = '$',
): string {
  const n = typeof amount === 'string' ? Number(amount) : amount;
  if (!Number.isFinite(n)) return `${symbol}— ${currency}`;
  const locale = currency === 'COP' ? 'es-CO' : currency === 'USD' ? 'en-US' : 'es-MX';
  const decimals = currency === 'COP' ? 0 : 0;
  const formatted = n.toLocaleString(locale, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
  return `${symbol}${formatted} ${currency}`;
}
