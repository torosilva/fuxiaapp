/**
 * /admin/dashboard-today — "Morning check" del negocio.
 *
 * Diseñado para que la admin abra la app y en 5 segundos sepa cómo va el día
 * sin tener que entrar a Reportes o cruzar información de varias pantallas.
 *
 * Métricas:
 *   - Ventas de hoy en $ vs ayer (delta con flecha + color)
 *   - # operaciones hoy vs ayer
 *   - Ventas de esta semana vs semana pasada
 *   - Top 3 canales del día
 *   - Nuevas clientas registradas hoy
 *   - Stock bajo por canal (items con < 3 pares restantes)
 *   - Alertas activas: aprobaciones pendientes, tickets, stock bajo
 */
import React, { useCallback, useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  StatusBar, ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import {
  ArrowLeft, TrendingUp, TrendingDown, Users, Package,
  Store, ShoppingBag, AlertTriangle, ClipboardCheck, LifeBuoy,
} from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

const MXN = new Intl.NumberFormat('es-MX', {
  style: 'currency', currency: 'MXN', maximumFractionDigits: 0,
});

interface Metrics {
  today: { revenue: number; sales: number };
  yesterday: { revenue: number; sales: number };
  thisWeek: number;
  lastWeek: number;
  topChannels: { id: string; name: string; type: 'store' | 'bazar'; revenue: number; sales: number }[];
  newCustomersToday: number;
  lowStock: { id: string; product_name: string; size: string; color: string | null; remaining: number; channel_name: string }[];
  pendingApprovals: number;
  openTickets: number;
}

function startOfDay(d: Date): Date {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

function delta(current: number, previous: number): { pct: number; abs: number; up: boolean | null } {
  const abs = current - previous;
  if (previous === 0) return { pct: 0, abs, up: current > 0 ? true : null };
  const pct = Math.round((abs / previous) * 100);
  return { pct, abs, up: abs > 0 ? true : abs < 0 ? false : null };
}

export default function DashboardTodayScreen() {
  const [m, setM] = useState<Metrics | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const now = new Date();
    const today = startOfDay(now);
    const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1);
    const yesterday = new Date(today); yesterday.setDate(yesterday.getDate() - 1);
    const weekAgo = new Date(today); weekAgo.setDate(weekAgo.getDate() - 7);
    const twoWeeksAgo = new Date(today); twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

    const [
      salesTodayRes,
      salesYesterdayRes,
      salesWeekRes,
      salesLastWeekRes,
      channelsRes,
      newCustomersRes,
      lowStockRes,
      pendingRes,
      ticketsRes,
    ] = await Promise.all([
      supabase.from('offline_sales').select('total, channel_id')
        .not('claimed_at', 'is', null)
        .gte('claimed_at', today.toISOString())
        .lt('claimed_at', tomorrow.toISOString()),
      supabase.from('offline_sales').select('total')
        .not('claimed_at', 'is', null)
        .gte('claimed_at', yesterday.toISOString())
        .lt('claimed_at', today.toISOString()),
      supabase.from('offline_sales').select('total')
        .not('claimed_at', 'is', null)
        .gte('claimed_at', weekAgo.toISOString())
        .lt('claimed_at', tomorrow.toISOString()),
      supabase.from('offline_sales').select('total')
        .not('claimed_at', 'is', null)
        .gte('claimed_at', twoWeeksAgo.toISOString())
        .lt('claimed_at', weekAgo.toISOString()),
      supabase.from('channels').select('id, name, type').eq('active', true),
      supabase.from('customers').select('id', { count: 'exact', head: true })
        .gte('created_at', today.toISOString()),
      supabase.from('channel_inventory')
        .select('id, product_name, size, color, stock, sold, channels(name)')
        .order('product_name'),
      supabase.from('inventory_change_requests').select('id', { count: 'exact', head: true })
        .eq('status', 'pending'),
      supabase.from('support_tickets').select('id', { count: 'exact', head: true })
        .neq('status', 'resolved'),
    ]);

    const salesToday = (salesTodayRes.data ?? []) as { total: number; channel_id: string }[];
    const salesYesterday = (salesYesterdayRes.data ?? []) as { total: number }[];
    const salesWeek = (salesWeekRes.data ?? []) as { total: number }[];
    const salesLastWeek = (salesLastWeekRes.data ?? []) as { total: number }[];
    const channels = ((channelsRes.data ?? []) as { id: string; name: string; type: 'store' | 'bazar' }[]);

    // Top channels hoy
    const chAgg = new Map<string, { revenue: number; sales: number }>();
    for (const s of salesToday) {
      if (!s.channel_id) continue;
      const cur = chAgg.get(s.channel_id) ?? { revenue: 0, sales: 0 };
      cur.revenue += Number(s.total ?? 0);
      cur.sales += 1;
      chAgg.set(s.channel_id, cur);
    }
    const topChannels = Array.from(chAgg.entries())
      .map(([id, v]) => {
        const ch = channels.find((c) => c.id === id);
        return {
          id,
          name: ch?.name ?? 'Canal ?',
          type: (ch?.type ?? 'store') as 'store' | 'bazar',
          revenue: v.revenue,
          sales: v.sales,
        };
      })
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, 3);

    const lowStockRaw = (lowStockRes.data ?? []) as any[];
    const lowStock = lowStockRaw
      .map((r) => ({
        id: r.id as string,
        product_name: r.product_name as string,
        size: r.size as string,
        color: (r.color ?? null) as string | null,
        remaining: (r.stock ?? 0) - (r.sold ?? 0),
        channel_name: r.channels?.name ?? '?',
      }))
      .filter((r) => r.remaining > 0 && r.remaining <= 2)
      .sort((a, b) => a.remaining - b.remaining)
      .slice(0, 12);

    setM({
      today: {
        revenue: salesToday.reduce((s, r) => s + Number(r.total ?? 0), 0),
        sales: salesToday.length,
      },
      yesterday: {
        revenue: salesYesterday.reduce((s, r) => s + Number(r.total ?? 0), 0),
        sales: salesYesterday.length,
      },
      thisWeek: salesWeek.reduce((s, r) => s + Number(r.total ?? 0), 0),
      lastWeek: salesLastWeek.reduce((s, r) => s + Number(r.total ?? 0), 0),
      topChannels,
      newCustomersToday: newCustomersRes.count ?? 0,
      lowStock,
      pendingApprovals: pendingRes.count ?? 0,
      openTickets: ticketsRes.count ?? 0,
    });
    setLoading(false);
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>

        <Text style={styles.eyebrow}>HOY</Text>
        <Text style={styles.title}>
          {new Date().toLocaleDateString('es-MX', { weekday: 'long', day: 'numeric', month: 'long' })}
        </Text>

        {loading || !m ? (
          <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
        ) : (
          <>
            {/* Ventas del día — hero */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} style={styles.heroCard}>
              <Text style={styles.heroLabel}>VENTAS HOY</Text>
              <Text style={styles.heroValue}>{MXN.format(m.today.revenue)}</Text>
              <View style={styles.heroDeltaRow}>
                <DeltaBadge current={m.today.revenue} previous={m.yesterday.revenue} suffix="vs ayer" />
                <Text style={styles.heroCount}>{m.today.sales} {m.today.sales === 1 ? 'operación' : 'operaciones'}</Text>
              </View>
            </MotiView>

            {/* Semana */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 80 }} style={styles.kpiRow}>
              <View style={styles.kpi}>
                <Text style={styles.kpiLabel}>ESTA SEMANA</Text>
                <Text style={styles.kpiValue}>{MXN.format(m.thisWeek)}</Text>
                <DeltaBadge current={m.thisWeek} previous={m.lastWeek} suffix="vs anterior" small />
              </View>
              <View style={styles.kpi}>
                <Text style={styles.kpiLabel}>NUEVAS CLIENTAS</Text>
                <Text style={styles.kpiValue}>{m.newCustomersToday}</Text>
                <Text style={styles.kpiSub}>registradas hoy</Text>
              </View>
            </MotiView>

            {/* Alertas activas */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 140 }}>
              <Text style={styles.sectionTitle}>Requiere tu atención</Text>
              <View style={styles.alertsRow}>
                <AlertPill
                  active={m.pendingApprovals > 0}
                  count={m.pendingApprovals}
                  label="Aprobaciones"
                  icon={ClipboardCheck}
                  color="#FFC107"
                  onPress={() => router.push('/admin/inventory-approvals' as any)}
                />
                <AlertPill
                  active={m.openTickets > 0}
                  count={m.openTickets}
                  label="Tickets"
                  icon={LifeBuoy}
                  color="#E05C7A"
                  onPress={() => router.push('/admin' as any)}
                />
                <AlertPill
                  active={m.lowStock.length > 0}
                  count={m.lowStock.length}
                  label="Stock bajo"
                  icon={AlertTriangle}
                  color="#FF9800"
                  onPress={() => { /* stays on this screen; lowStock ya visible */ }}
                />
              </View>
            </MotiView>

            {/* Top canales del día */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 200 }} style={styles.section}>
              <Text style={styles.sectionTitle}>Top canales de hoy</Text>
              {m.topChannels.length === 0 ? (
                <Text style={styles.emptyLine}>Sin ventas registradas todavía en este día.</Text>
              ) : (
                m.topChannels.map((c, i) => (
                  <TouchableOpacity
                    key={c.id}
                    activeOpacity={0.75}
                    onPress={() => router.push({ pathname: '/admin/channel/[id]' as any, params: { id: c.id } })}
                    style={styles.rankRow}
                  >
                    <Text style={styles.rankPos}>{i + 1}</Text>
                    <View style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                      {c.type === 'bazar'
                        ? <ShoppingBag size={14} color="rgba(255,255,255,0.6)" />
                        : <Store size={14} color="rgba(255,255,255,0.6)" />}
                      <View style={{ flex: 1 }}>
                        <Text style={styles.rankName}>{c.name}</Text>
                        <Text style={styles.rankMeta}>{c.sales} {c.sales === 1 ? 'venta' : 'ventas'}</Text>
                      </View>
                    </View>
                    <Text style={styles.rankAmount}>{MXN.format(c.revenue)}</Text>
                  </TouchableOpacity>
                ))
              )}
            </MotiView>

            {/* Stock bajo */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 260 }} style={styles.section}>
              <View style={styles.sectionHead}>
                <Package size={14} color="#FF9800" />
                <Text style={styles.sectionTitle}>Stock bajo (1-2 pares)</Text>
              </View>
              {m.lowStock.length === 0 ? (
                <Text style={styles.emptyLine}>Todo en orden — nada con stock crítico.</Text>
              ) : (
                m.lowStock.map((s) => (
                  <View key={s.id} style={styles.lowRow}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.lowName}>{s.product_name}</Text>
                      <Text style={styles.lowMeta}>
                        Talla {s.size}{s.color ? ' · ' + s.color : ''} · {s.channel_name}
                      </Text>
                    </View>
                    <View style={[styles.stockPill, { backgroundColor: s.remaining === 1 ? 'rgba(224,92,122,0.18)' : 'rgba(255,152,0,0.18)' }]}>
                      <Text style={[styles.stockPillText, { color: s.remaining === 1 ? '#E05C7A' : '#FF9800' }]}>
                        {s.remaining} {s.remaining === 1 ? 'par' : 'pares'}
                      </Text>
                    </View>
                  </View>
                ))
              )}
            </MotiView>
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function DeltaBadge({ current, previous, suffix, small }: {
  current: number; previous: number; suffix: string; small?: boolean;
}) {
  const d = delta(current, previous);
  const isPositive = d.up === true;
  const isNegative = d.up === false;
  const color = isPositive ? '#4CAF50' : isNegative ? '#E05C7A' : 'rgba(255,255,255,0.4)';
  const Icon = isPositive ? TrendingUp : TrendingDown;
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
      {d.up !== null && <Icon size={small ? 10 : 12} color={color} />}
      <Text style={{ color, fontSize: small ? 10 : 12, fontWeight: '700' }}>
        {d.up === null ? '—' : `${Math.abs(d.pct)}%`} {suffix}
      </Text>
    </View>
  );
}

function AlertPill({ active, count, label, icon: Icon, color, onPress }: {
  active: boolean; count: number; label: string; icon: any; color: string; onPress?: () => void;
}) {
  return (
    <TouchableOpacity
      onPress={onPress}
      activeOpacity={active ? 0.75 : 1}
      disabled={!active}
      style={[styles.alertPill, active && { borderColor: color, backgroundColor: color + '18' }]}
    >
      <Icon size={16} color={active ? color : 'rgba(255,255,255,0.4)'} />
      <Text style={[styles.alertLabel, { color: active ? color : 'rgba(255,255,255,0.5)' }]}>{label}</Text>
      <Text style={[styles.alertCount, { color: active ? color : 'rgba(255,255,255,0.4)' }]}>{count}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 80 },
  backBtn: { width: 40, height: 40, justifyContent: 'center', marginBottom: 8 },
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 3, marginBottom: 6 },
  title: { fontSize: 24, color: '#FFF', fontFamily: 'serif', marginBottom: 24, textTransform: 'capitalize' },
  heroCard: {
    backgroundColor: '#141414', borderRadius: 20, padding: 22, marginBottom: 14,
    borderWidth: 1, borderColor: 'rgba(184,134,11,0.35)',
  },
  heroLabel: { color: '#B8860B', fontSize: 10, fontWeight: '800', letterSpacing: 3, marginBottom: 6 },
  heroValue: { color: '#FFF', fontSize: 40, fontWeight: '800', lineHeight: 44 },
  heroDeltaRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 10 },
  heroCount: { color: 'rgba(255,255,255,0.55)', fontSize: 12 },
  kpiRow: { flexDirection: 'row', gap: 10, marginBottom: 14 },
  kpi: {
    flex: 1, backgroundColor: '#141414', borderRadius: 14, padding: 14,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
  },
  kpiLabel: { color: 'rgba(255,255,255,0.55)', fontSize: 9, fontWeight: '800', letterSpacing: 2 },
  kpiValue: { color: '#FFF', fontSize: 20, fontWeight: '800', marginTop: 4 },
  kpiSub: { color: 'rgba(255,255,255,0.4)', fontSize: 10, marginTop: 4 },
  section: {
    backgroundColor: '#141414', borderRadius: 16, borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)', padding: 18, marginTop: 14,
  },
  sectionHead: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 4 },
  sectionTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginBottom: 12 },
  alertsRow: { flexDirection: 'row', gap: 8, marginBottom: 4 },
  alertPill: {
    flex: 1, flexDirection: 'column', alignItems: 'center', gap: 4,
    padding: 12, borderRadius: 14,
    backgroundColor: '#141414', borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
  },
  alertLabel: { fontSize: 10, fontWeight: '700', letterSpacing: 0.5 },
  alertCount: { fontSize: 18, fontWeight: '800' },
  emptyLine: { color: 'rgba(255,255,255,0.35)', fontSize: 12 },
  rankRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  rankPos: { color: '#B8860B', fontSize: 13, fontWeight: '800', width: 20 },
  rankName: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  rankMeta: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  rankAmount: { color: '#B8860B', fontSize: 13, fontWeight: '700' },
  lowRow: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  lowName: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  lowMeta: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  stockPill: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 12 },
  stockPillText: { fontSize: 11, fontWeight: '800' },
});
