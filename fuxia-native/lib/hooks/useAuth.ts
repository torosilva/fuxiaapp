import { useState, useEffect } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Session } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import type { Tier } from '@/lib/database.types';
import { registerPushToken } from '@/lib/notifications';
import { detectDeviceCountry, syncFromCustomer } from '@/lib/CountryService';
import { wcService } from '@/services/WooCommerceService';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

const fnHeaders = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
};

const TIER_THRESHOLDS: { tier: Tier; min_points: number; min_pairs: number }[] = [
  { tier: 'silver', min_points: 300, min_pairs: 3 },
  { tier: 'gold',   min_points: 900, min_pairs: 9 },
];

function computeTierProgress(tier: Tier, total_points: number, pairs_count: number) {
  const next = tier === 'bronze' ? TIER_THRESHOLDS[0] : tier === 'silver' ? TIER_THRESHOLDS[1] : null;
  if (!next) return { points_to_next: null as number | null, pairs_to_next: null as number | null };
  return {
    points_to_next: Math.max(0, next.min_points - total_points),
    pairs_to_next: Math.max(0, next.min_pairs - pairs_count),
  };
}

export interface Customer {
  id: string;
  phone: string;
  name: string;
  email?: string;
  avatar_url?: string | null;
  country?: string | null;
  birthday?: string | null;
  wc_customer_id?: number | null;
}

export interface LoyaltyCardData {
  id: string;
  qr_code: string;
  total_points: number;
  pairs_count: number;
  tier: 'bronze' | 'silver' | 'gold';
  points_to_next: number | null;
  pairs_to_next: number | null;
}

interface AuthState {
  session: Session | null;
  customer: Customer | null;
  loyaltyCard: LoyaltyCardData | null;
  isLoading: boolean;
}

export function useAuth() {
  const [state, setState] = useState<AuthState>({
    session: null,
    customer: null,
    loyaltyCard: null,
    isLoading: true,
  });

  useEffect(() => {
    loadSession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) {
        loadCustomerData(session);
      } else {
        setState({ session: null, customer: null, loyaltyCard: null, isLoading: false });
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  async function loadSession() {
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
      await loadCustomerData(session);
    } else {
      setState(s => ({ ...s, isLoading: false }));
    }
  }

  async function loadCustomerData(session: Session) {
    const phone = session.user.user_metadata?.phone;
    if (!phone) {
      setState({ session, customer: null, loyaltyCard: null, isLoading: false });
      return;
    }

    const { data: customer } = await supabase
      .from('customers')
      .select('id, phone, name, email, avatar_url, country')
      .eq('phone', phone)
      .single();

    if (customer?.country) {
      await syncFromCustomer(customer.country);
    }

    // Auto-link WC account in background if not yet linked and email is available.
    if (customer && !customer.wc_customer_id && customer.email) {
      wcService
        .findOrCreateWCCustomer(customer.email, customer.name, customer.phone)
        .then((wcId) => {
          if (wcId) {
            supabase
              .from('customers')
              .update({ wc_customer_id: wcId })
              .eq('id', customer.id)
              .then(() => {});
          }
        })
        .catch(() => {});
    }

    let loyaltyCard: LoyaltyCardData | null = null;

    if (customer) {
      const { data: card } = await supabase
        .from('loyalty_cards')
        .select('id, qr_code, total_points, pairs_count, tier')
        .eq('customer_id', customer.id)
        .single();

      if (card) {
        const progress = computeTierProgress(card.tier, card.total_points, card.pairs_count);
        loyaltyCard = {
          ...card,
          points_to_next: progress.points_to_next,
          pairs_to_next: progress.pairs_to_next,
        };
      }
    }

    setState({ session, customer: customer ?? null, loyaltyCard, isLoading: false });

    if (customer?.id) {
      registerPushToken(customer.id).catch(() => {});
    }
  }

  async function checkPhone(phone: string): Promise<{ exists: boolean; error?: string }> {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-otp`, {
      method: 'POST',
      headers: fnHeaders,
      body: JSON.stringify({ action: 'check_phone', phone }),
    });
    const data = await res.json();
    if (!res.ok) return { exists: false, error: data.error };
    return { exists: !!data.exists };
  }

  async function sendOTP(phone: string): Promise<{ error?: string }> {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-otp`, {
      method: 'POST',
      headers: fnHeaders,
      body: JSON.stringify({ action: 'send', phone }),
    });
    const data = await res.json();
    return res.ok ? {} : { error: data.error };
  }

  async function verifyOTP(phone: string, code: string): Promise<{ isNewUser?: boolean; error?: string }> {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-otp`, {
      method: 'POST',
      headers: fnHeaders,
      body: JSON.stringify({ action: 'verify', phone, code }),
    });
    const data = await res.json();
    if (!res.ok) return { error: data.error };

    await supabase.auth.setSession({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    });

    return { isNewUser: data.isNewUser };
  }

  async function createProfile(
    phone: string,
    name: string,
    email: string,
    birthday?: string,
  ): Promise<{ error?: string }> {
    const country = detectDeviceCountry();

    // Find or create the WooCommerce customer account.
    let wc_customer_id: number | null = null;
    try {
      wc_customer_id = await wcService.findOrCreateWCCustomer(email, name, phone);
    } catch {
      // Non-fatal — user can still use the app without WC linking.
    }

    const { data: customer, error } = await supabase
      .from('customers')
      .insert({
        phone,
        name,
        email,
        country,
        birthday: birthday ?? null,
        wc_customer_id,
      })
      .select('id')
      .single();

    if (error || !customer) return { error: 'Error creando perfil' };

    const shortId = phone.replace('+', '').slice(-8).padStart(8, '0');
    const qrCode = `FX-${shortId}-${Date.now().toString(36)}-00`;

    await supabase.from('loyalty_cards').insert({
      customer_id: customer.id,
      qr_code: qrCode,
      total_points: 0,
      pairs_count: 0,
      tier: 'bronze',
    });

    await loadSession();
    return {};
  }

  async function signOut() {
    await supabase.auth.signOut();
    await AsyncStorage.removeItem('supabase.auth.token');
  }

  return { ...state, checkPhone, sendOTP, verifyOTP, createProfile, signOut, refresh: loadSession };
}
