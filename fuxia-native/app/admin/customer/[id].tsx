/**
 * /admin/customer/[id] — Vista 360° de una clienta.
 *
 * Todo lo que la admin necesita saber en una sola pantalla:
 *  - Identidad + contacto + WhatsApp de un tap
 *  - Tarjeta de lealtad: puntos, tier, progreso al siguiente
 *  - Compras (online + tienda) unificadas y ordenadas
 *  - Referidas que trajo
 *  - Cumpleaños próximo (si aplica)
 *  - Botón "Ajustar puntos" que lleva a /admin/puntos preseleccionada
 *
 * Uso tipico: la admin toca a una clienta en 'Ultimas clientas' o en
 * el buscador y ve el perfil completo para decidir atencion personalizada.
 */
import React, { useCallback, useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  StatusBar, ActivityIndicator, Linking, Image,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import {
  ArrowLeft, MessageCircle, Cake, ShoppingBag, Store, Gift,
  Award, TrendingUp, User as UserIcon, Users, Mail, Phone,
} from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

const TIER_LABEL: Record<string, string> = { bronze: 'Bronce', silver: 'Plata', gold: 'Oro' };
const TIER_COLOR: Record<string, string> = { bronze: '#CD7F32', silver: '#C0C0C0', gold: '#FFD700' };

interface Detail {
  id: string;
  name: string | null;
  phone: string;
  email: string | null;
  avatar_url: string | null;
  country: string | null;
  birthday: string | null;
  shoe_size: string | null;
  role: string | null;
  created_at: string;
  referral_code: string | null;
  wc_customer_id: number | null;
  total_points: number;
  pairs_count: number;
  tier: string;
  transactions: {
    id: string; amount: number; currency: string; points_earned: number;
    pairs_in_order: number; channel: string; created_at: string; wc_order_id: number | null;
    notes: string | null;
  }[];
  referred_customers: { id: string; name: string | null; created_at: string }[];
  open_tickets: number;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' });
}
function formatDateShort(iso: string): string {
  return new Date(iso).toLocaleDateString('es-MX', { day: '2-digit', month: 'short' });
}
function daysUntilBirthday(iso: string): number | null {
  if (!iso) return null;
  const [, month, day] = iso.split('-').map(Number);
  if (!month || !day) return null;
  const now = new Date();
  const thisYear = new Date(now.getFullYear(), month - 1, day);
  if (thisYear >= now) return Math.round((thisYear.getTime() - now.getTime()) / 86400000);
  const nextYear = new Date(now.getFullYear() + 1, month - 1, day);
  return Math.round((nextYear.getTime() - now.getTime()) / 86400000);
}

// Cumples guardados con año centinela 1900 = solo día/mes conocidos.
function birthdayLabel(iso: string): string {
  const [year, month, day] = iso.split('-').map(Number);
  if (!month || !day) return iso;
  const monthName = new Date(2000, month - 1, 1).toLocaleDateString('es-MX', { month: 'long' });
  if (year === 1900) return `${day} de ${monthName}`;
  return `${day} de ${monthName}, ${year}`;
}

const MXN = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN', maximumFractionDigits: 0 });

export default function CustomerDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [d, setD] = useState<Detail | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    const [custRes, cardRes, txRes, refsRes, ticketsRes] = await Promise.all([
      supabase.from('customers')
        .select('id, name, phone, email, avatar_url, country, birthday, shoe_size, role, created_at, referral_code, wc_customer_id')
        .eq('id', id).single(),
      supabase.from('loyalty_cards')
        .select('id, total_points, pairs_count, tier')
        .eq('customer_id', id).maybeSingle(),
      // Trae las transacciones de esa clienta a traves de su loyalty_card
      supabase.from('transactions')
        .select('id, amount, currency, points_earned, pairs_in_order, channel, created_at, wc_order_id, notes, loyalty_cards!inner(customer_id)')
        .eq('loyalty_cards.customer_id', id)
        .order('created_at', { ascending: false })
        .limit(30),
      supabase.from('customers')
        .select('id, name, created_at')
        .eq('referred_by', id)
        .order('created_at', { ascending: false }),
      supabase.from('support_tickets').select('id', { count: 'exact', head: true })
        .eq('customer_id', id).neq('status', 'resolved'),
    ]);

    if (!custRes.data) { setLoading(false); return; }
    const c = custRes.data as any;
    const card = (cardRes.data ?? { total_points: 0, pairs_count: 0, tier: 'bronze' }) as any;

    setD({
      id: c.id,
      name: c.name,
      phone: c.phone,
      email: c.email,
      avatar_url: c.avatar_url,
      country: c.country,
      birthday: c.birthday,
      shoe_size: c.shoe_size,
      role: c.role,
      created_at: c.created_at,
      referral_code: c.referral_code,
      wc_customer_id: c.wc_customer_id,
      total_points: card.total_points ?? 0,
      pairs_count: card.pairs_count ?? 0,
      tier: card.tier ?? 'bronze',
      transactions: (txRes.data ?? []) as any[],
      referred_customers: (refsRes.data ?? []) as any[],
      open_tickets: ticketsRes.count ?? 0,
    });
    setLoading(false);
  }, [id]);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const openWhatsApp = () => {
    if (!d?.phone) return;
    const phone = d.phone.replace(/\D/g, '');
    const first = d.name?.split(' ')[0];
    const msg = encodeURIComponent(`Hola${first ? ' ' + first : ''}, te escribimos de Fuxia Ballerinas 👠`);
    Linking.openURL(`https://wa.me/${phone}?text=${msg}`);
  };

  const daysToBday = d?.birthday ? daysUntilBirthday(d.birthday) : null;
  const birthdayNear = daysToBday !== null && daysToBday <= 14;

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>

        {loading || !d ? (
          <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
        ) : (
          <>
            {/* Identidad hero */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} style={styles.identity}>
              <View style={styles.avatarWrap}>
                {d.avatar_url
                  ? <Image source={{ uri: d.avatar_url }} style={styles.avatar} />
                  : <UserIcon size={32} color="#B8860B" />}
              </View>
              <Text style={styles.name}>{d.name ?? 'Sin nombre'}</Text>
              <View style={styles.contactRow}>
                <Phone size={12} color="rgba(255,255,255,0.5)" />
                <Text style={styles.contactText}>{d.phone}</Text>
              </View>
              {d.email && (
                <View style={styles.contactRow}>
                  <Mail size={12} color="rgba(255,255,255,0.5)" />
                  <Text style={styles.contactText}>{d.email}</Text>
                </View>
              )}
              <Text style={styles.metaLine}>
                Cliente desde {formatDate(d.created_at)}
                {d.country ? ' · ' + d.country : ''}
                {d.shoe_size ? ' · Talla ' + d.shoe_size : ''}
                {d.role && d.role !== 'customer' ? ` · ${d.role.toUpperCase()}` : ''}
              </Text>

              {/* WhatsApp CTA */}
              <TouchableOpacity style={styles.waBtn} onPress={openWhatsApp} activeOpacity={0.85}>
                <MessageCircle size={16} color="#0D0D0D" />
                <Text style={styles.waBtnText}>Escribir por WhatsApp</Text>
              </TouchableOpacity>
            </MotiView>

            {/* Tarjeta de lealtad */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 80 }} style={styles.loyaltyCard}>
              <View style={styles.tierBadge}>
                <Award size={14} color={TIER_COLOR[d.tier] ?? '#B8860B'} />
                <Text style={[styles.tierText, { color: TIER_COLOR[d.tier] ?? '#B8860B' }]}>
                  {TIER_LABEL[d.tier] ?? d.tier.toUpperCase()}
                </Text>
              </View>
              <Text style={styles.pointsValue}>{d.total_points}</Text>
              <Text style={styles.pointsLabel}>puntos · {d.pairs_count} {d.pairs_count === 1 ? 'par' : 'pares'} acumulados</Text>
              <TouchableOpacity
                style={styles.adjustBtn}
                onPress={() => router.push({ pathname: '/admin/puntos' as any, params: { prefill: d.phone } })}
                activeOpacity={0.85}
              >
                <TrendingUp size={14} color="#B8860B" />
                <Text style={styles.adjustBtnText}>Ajustar puntos</Text>
              </TouchableOpacity>
            </MotiView>

            {/* Cumpleaños si viene pronto */}
            {birthdayNear && d.birthday && (
              <View style={styles.bdayCard}>
                <Cake size={18} color="#FFC107" />
                <View style={{ flex: 1 }}>
                  <Text style={styles.bdayTitle}>
                    Cumple en {daysToBday === 0 ? 'hoy 🎉' : `${daysToBday} día${daysToBday === 1 ? '' : 's'}`}
                  </Text>
                  <Text style={styles.bdaySub}>{birthdayLabel(d.birthday)}</Text>
                </View>
              </View>
            )}

            {/* Referidas */}
            {d.referred_customers.length > 0 && (
              <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 140 }} style={styles.section}>
                <View style={styles.sectionHead}>
                  <Users size={14} color="#B8860B" />
                  <Text style={styles.sectionTitle}>Trajo {d.referred_customers.length} {d.referred_customers.length === 1 ? 'amiga' : 'amigas'}</Text>
                </View>
                {d.referred_customers.slice(0, 5).map((r) => (
                  <TouchableOpacity
                    key={r.id}
                    onPress={() => router.replace({ pathname: '/admin/customer/[id]' as any, params: { id: r.id } })}
                    style={styles.refRow}
                    activeOpacity={0.75}
                  >
                    <Text style={styles.refName}>{r.name ?? 'Sin nombre'}</Text>
                    <Text style={styles.refDate}>{formatDateShort(r.created_at)}</Text>
                  </TouchableOpacity>
                ))}
              </MotiView>
            )}

            {/* Historial de compras */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 200 }} style={styles.section}>
              <View style={styles.sectionHead}>
                <Gift size={14} color="#B8860B" />
                <Text style={styles.sectionTitle}>Historial ({d.transactions.length})</Text>
              </View>
              {d.transactions.length === 0 ? (
                <Text style={styles.emptyLine}>Sin transacciones registradas.</Text>
              ) : (
                d.transactions.map((tx) => {
                  const isManual = tx.channel === 'manual';
                  const isWeb = tx.channel === 'web';
                  const label = isManual ? 'Ajuste manual' : isWeb ? `Orden web #${tx.wc_order_id ?? '?'}` : 'Venta en tienda';
                  return (
                    <View key={tx.id} style={styles.txRow}>
                      <View style={styles.txIcon}>
                        {isWeb ? <ShoppingBag size={14} color="#B8860B" /> : <Store size={14} color="#B8860B" />}
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.txLabel}>{label}</Text>
                        <Text style={styles.txMeta}>
                          {formatDateShort(tx.created_at)}
                          {tx.amount > 0 ? ` · ${MXN.format(Number(tx.amount))}` : ''}
                          {tx.pairs_in_order > 0 ? ` · ${tx.pairs_in_order} ${tx.pairs_in_order === 1 ? 'par' : 'pares'}` : ''}
                        </Text>
                      </View>
                      <Text style={[styles.txPoints, tx.points_earned < 0 ? styles.txPointsNeg : styles.txPointsPos]}>
                        {tx.points_earned > 0 ? '+' : ''}{tx.points_earned} pts
                      </Text>
                    </View>
                  );
                })
              )}
            </MotiView>
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 80 },
  backBtn: { width: 40, height: 40, justifyContent: 'center', marginBottom: 8 },
  identity: {
    backgroundColor: '#141414', borderRadius: 16, padding: 20,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    alignItems: 'center', marginBottom: 14,
  },
  avatarWrap: {
    width: 72, height: 72, borderRadius: 36,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center', alignItems: 'center', marginBottom: 12,
    overflow: 'hidden',
  },
  avatar: { width: 72, height: 72 },
  name: { color: '#FFF', fontSize: 22, fontWeight: '700', marginBottom: 8 },
  contactRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 4 },
  contactText: { color: 'rgba(255,255,255,0.7)', fontSize: 13 },
  metaLine: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 6, textAlign: 'center' },
  waBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: '#25D366', paddingHorizontal: 18, paddingVertical: 10, borderRadius: 24, marginTop: 14,
  },
  waBtnText: { color: '#0D0D0D', fontSize: 13, fontWeight: '800' },
  loyaltyCard: {
    backgroundColor: '#141414', borderRadius: 16, padding: 20,
    borderWidth: 1, borderColor: 'rgba(184,134,11,0.35)',
    marginBottom: 14, alignItems: 'center',
  },
  tierBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 10, paddingVertical: 4, borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.05)', marginBottom: 8,
  },
  tierText: { fontSize: 11, fontWeight: '800', letterSpacing: 1.5 },
  pointsValue: { color: '#FFF', fontSize: 48, fontWeight: '800', lineHeight: 52 },
  pointsLabel: { color: 'rgba(255,255,255,0.5)', fontSize: 12, marginTop: 2 },
  adjustBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20,
    borderWidth: 1, borderColor: 'rgba(184,134,11,0.5)', marginTop: 12,
  },
  adjustBtnText: { color: '#B8860B', fontSize: 12, fontWeight: '800' },
  bdayCard: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: 'rgba(255,193,7,0.1)', borderWidth: 1, borderColor: 'rgba(255,193,7,0.4)',
    borderRadius: 14, padding: 14, marginBottom: 14,
  },
  bdayTitle: { color: '#FFC107', fontSize: 13, fontWeight: '800' },
  bdaySub: { color: 'rgba(255,193,7,0.75)', fontSize: 11, marginTop: 2 },
  section: {
    backgroundColor: '#141414', borderRadius: 16, borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)', padding: 18, marginBottom: 14,
  },
  sectionHead: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 4 },
  sectionTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginBottom: 12 },
  emptyLine: { color: 'rgba(255,255,255,0.35)', fontSize: 12 },
  refRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  refName: { color: '#FFF', fontSize: 13 },
  refDate: { color: 'rgba(255,255,255,0.4)', fontSize: 11 },
  txRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  txIcon: {
    width: 30, height: 30, borderRadius: 15,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center', alignItems: 'center',
  },
  txLabel: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  txMeta: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  txPoints: { fontSize: 13, fontWeight: '800' },
  txPointsPos: { color: '#4CAF50' },
  txPointsNeg: { color: '#E05C7A' },
});
