import { useState, useEffect } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Session } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

const fnHeaders = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
};

export interface Customer {
  id: string;
  phone: string;
  name: string;
  email?: string;
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
    // Load persisted session on mount
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
      .select('id, phone, name, email')
      .eq('phone', phone)
      .single();

    let loyaltyCard: LoyaltyCardData | null = null;

    if (customer) {
      const { data: card } = await supabase
        .from('loyalty_cards')
        .select('id, qr_code, total_points, pairs_count, tier')
        .eq('customer_id', customer.id)
        .single();

      if (card) {
        const { data: tierData } = await supabase.functions.invoke('calculate-tier', {
          body: { total_points: card.total_points, pairs_count: card.pairs_count },
        });
        loyaltyCard = {
          ...card,
          points_to_next: tierData?.points_to_next ?? null,
          pairs_to_next: tierData?.pairs_to_next ?? null,
        };
      }
    }

    setState({ session, customer: customer ?? null, loyaltyCard, isLoading: false });
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

    // Set session in Supabase client
    await supabase.auth.setSession({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    });

    return { isNewUser: data.isNewUser };
  }

  async function createProfile(phone: string, name: string, email?: string): Promise<{ error?: string }> {
    const { data: customer, error } = await supabase
      .from('customers')
      .insert({ phone, name, email: email ?? null })
      .select('id')
      .single();

    if (error || !customer) return { error: 'Error creando perfil' };

    // Generate QR and loyalty card
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

  return { ...state, sendOTP, verifyOTP, createProfile, signOut };
}
