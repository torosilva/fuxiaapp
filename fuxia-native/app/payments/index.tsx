import React, { useEffect, useMemo, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Redirect, router, Stack } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, TrendingUp, Wallet, Calendar } from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import type { Channel } from '@/lib/database.types';
import { formatMoney } from '@/lib/CountryService';

interface Tx {
  id: string;
  created_at: string;
  amount: number;
  currency: string;
  channel: Channel;
  wc_order_id: number | null;
}

const MONTHS_ES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];


const monthKey = (iso: string) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};

const monthLabel = (key: string) => {
  const [y, m] = key.split('-');
  return `${MONTHS_ES[Number(m) - 1]} ${y}`;
};

export default function PaymentsScreen() {
  const { session, customer, isLoading } = useAuth();
  const [txs, setTxs] = useState<Tx[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!customer) return;
    (async () => {
      setLoading(true);
      const { data: card } = await supabase
        .from('loyalty_cards')
        .select('id')
        .eq('customer_id', customer.id)
        .single();
      if (!card) {
        setLoading(false);
        return;
      }
      const { data } = await supabase
        .from('transactions')
        .select('id, created_at, amount, currency, channel, wc_order_id')
        .eq('loyalty_card_id', card.id)
        .order('created_at', { ascending: false });
      setTxs(data ?? []);
      setLoading(false);
    })();
  }, [customer?.id]);

  const stats = useMemo(() => {
    const total = txs.reduce((sum, t) => sum + Number(t.amount), 0);
    const orders = txs.length;
    const avg = orders > 0 ? total / orders : 0;

    const now = new Date();
    const thisKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const lastDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const lastKey = `${lastDate.getFullYear()}-${String(lastDate.getMonth() + 1).padStart(2, '0')}`;

    const thisMonth = txs.filter((t) => monthKey(t.created_at) === thisKey).reduce((s, t) => s + Number(t.amount), 0);
    const lastMonth = txs.filter((t) => monthKey(t.created_at) === lastKey).reduce((s, t) => s + Number(t.amount), 0);

    const byMonth = new Map<string, number>();
    for (const t of txs) {
      const k = monthKey(t.created_at);
      byMonth.set(k, (byMonth.get(k) ?? 0) + Number(t.amount));
    }
    const monthly = Array.from(byMonth.entries())
      .sort((a, b) => (a[0] < b[0] ? 1 : -1))
      .slice(0, 6);

    return { total, orders, avg, thisMonth, lastMonth, monthly, currency: txs[0]?.currency ?? 'MXN' };
  }, [txs]);

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator color="#CD7F32" />
      </SafeAreaView>
    );
  }

  if (!session || !customer) return <Redirect href="/onboarding" />;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>
        <View>
          <Text style={styles.eyebrow}>RESUMEN</Text>
          <Text style={styles.title}>Pagos</Text>
        </View>
        <View style={{ width: 40 }} />
      </View>

      {loading ? (
        <View style={styles.center}><ActivityIndicator color="#CD7F32" /></View>
      ) : txs.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyTitle}>Sin movimientos todavía</Text>
          <Text style={styles.emptySubtitle}>
            Cada compra que hagas en fuxiaballerinas.com aparecerá acá.
          </Text>
        </View>
      ) : (
        <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
          {/* Hero card: total spent */}
          <MotiView
            from={{ opacity: 0, translateY: 12 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 400 }}
            style={styles.heroCard}
          >
            <Text style={styles.heroLabel}>TOTAL EN FUXIA</Text>
            <Text style={styles.heroAmount}>
              {formatMoney(stats.total, stats.currency)}
            </Text>
            <Text style={styles.heroMeta}>
              {stats.orders} {stats.orders === 1 ? 'compra' : 'compras'} · ticket promedio {formatMoney(stats.avg, stats.currency)}
            </Text>
          </MotiView>

          {/* This month vs last month */}
          <View style={styles.statsRow}>
            <MotiView
              from={{ opacity: 0, translateY: 12 }}
              animate={{ opacity: 1, translateY: 0 }}
              transition={{ type: 'timing', duration: 400, delay: 100 }}
              style={styles.statCard}
            >
              <Calendar size={16} color="#CD7F32" />
              <Text style={styles.statLabel}>Este mes</Text>
              <Text style={styles.statValue}>{formatMoney(stats.thisMonth, stats.currency)}</Text>
            </MotiView>
            <MotiView
              from={{ opacity: 0, translateY: 12 }}
              animate={{ opacity: 1, translateY: 0 }}
              transition={{ type: 'timing', duration: 400, delay: 150 }}
              style={styles.statCard}
            >
              <TrendingUp size={16} color="#CD7F32" />
              <Text style={styles.statLabel}>Mes pasado</Text>
              <Text style={styles.statValue}>{formatMoney(stats.lastMonth, stats.currency)}</Text>
            </MotiView>
          </View>

          {/* Monthly breakdown */}
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <Wallet size={16} color="#CD7F32" />
              <Text style={styles.sectionTitle}>Por mes</Text>
            </View>
            {stats.monthly.map(([key, amount], i) => {
              const max = Math.max(...stats.monthly.map(([, a]) => a));
              const widthPct = max > 0 ? (amount / max) * 100 : 0;
              return (
                <MotiView
                  key={key}
                  from={{ opacity: 0, translateX: -10 }}
                  animate={{ opacity: 1, translateX: 0 }}
                  transition={{ type: 'timing', duration: 350, delay: 200 + i * 60 }}
                  style={styles.monthRow}
                >
                  <Text style={styles.monthLabel}>{monthLabel(key)}</Text>
                  <View style={styles.monthBarTrack}>
                    <View style={[styles.monthBarFill, { width: `${widthPct}%` }]} />
                  </View>
                  <Text style={styles.monthAmount}>{formatMoney(amount, stats.currency)}</Text>
                </MotiView>
              );
            })}
          </View>

          {/* Recent transactions */}
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <Wallet size={16} color="#CD7F32" />
              <Text style={styles.sectionTitle}>Últimos movimientos</Text>
            </View>
            {txs.slice(0, 8).map((t, i) => (
              <MotiView
                key={t.id}
                from={{ opacity: 0, translateY: 8 }}
                animate={{ opacity: 1, translateY: 0 }}
                transition={{ type: 'timing', duration: 300, delay: 100 + i * 40 }}
                style={styles.txRow}
              >
                <View style={styles.txIcon}>
                  <Text style={styles.txIconText}>
                    {t.channel === 'store' ? '🏪' : '🌐'}
                  </Text>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.txTitle}>
                    {t.wc_order_id ? `Pedido #${t.wc_order_id}` : 'Compra en tienda'}
                  </Text>
                  <Text style={styles.txDate}>{new Date(t.created_at).toLocaleDateString('es-MX')}</Text>
                </View>
                <Text style={styles.txAmount}>{formatMoney(Number(t.amount), t.currency)}</Text>
              </MotiView>
            ))}
          </View>
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
  },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 2, textAlign: 'center',
  },
  title: { fontSize: 20, color: '#FFFFFF', fontFamily: 'serif', textAlign: 'center' },
  scroll: { padding: 20, paddingBottom: 140 },
  emptyState: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 40 },
  emptyTitle: { color: '#FFF', fontSize: 18, fontFamily: 'serif', marginBottom: 8, textAlign: 'center' },
  emptySubtitle: { color: 'rgba(255,255,255,0.4)', fontSize: 13, textAlign: 'center', lineHeight: 20 },
  heroCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 24,
    padding: 24,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: 'rgba(205,127,50,0.2)',
  },
  heroLabel: {
    color: '#CD7F32', fontSize: 10, fontWeight: '800',
    letterSpacing: 3, marginBottom: 8,
  },
  heroAmount: {
    color: '#FFF', fontSize: 36, fontFamily: 'serif', fontWeight: '400', marginBottom: 8,
  },
  heroMeta: { color: 'rgba(255,255,255,0.5)', fontSize: 12 },
  statsRow: { flexDirection: 'row', gap: 12, marginBottom: 24 },
  statCard: {
    flex: 1,
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    padding: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    gap: 6,
  },
  statLabel: { color: 'rgba(255,255,255,0.5)', fontSize: 11, fontWeight: '600', letterSpacing: 1 },
  statValue: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  section: { marginBottom: 24 },
  sectionHeader: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 12 },
  sectionTitle: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  monthRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: 10 },
  monthLabel: { color: 'rgba(255,255,255,0.6)', fontSize: 11, width: 95 },
  monthBarTrack: {
    flex: 1, height: 8, backgroundColor: 'rgba(255,255,255,0.05)', borderRadius: 4, overflow: 'hidden',
  },
  monthBarFill: { height: '100%', backgroundColor: '#CD7F32', borderRadius: 4 },
  monthAmount: { color: '#FFF', fontSize: 11, fontWeight: '700', minWidth: 90, textAlign: 'right' },
  txRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  txIcon: {
    width: 34, height: 34, borderRadius: 17,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center', marginRight: 12,
  },
  txIconText: { fontSize: 14 },
  txTitle: { color: '#FFF', fontSize: 13, fontWeight: '500' },
  txDate: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  txAmount: { color: '#CD7F32', fontSize: 13, fontWeight: '700' },
});
