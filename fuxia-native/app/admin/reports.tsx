import React, { useCallback, useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  StatusBar, ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, TrendingUp, Users, Store, ShoppingBag, ClipboardList } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface Metrics {
  monthRevenue: number;
  monthSales: number;
  totalCustomers: number;
  totalActiveStaff: number;
  topStaff: { id: string; name: string; sales: number; revenue: number }[];
  topChannels: { id: string; name: string; type: 'store' | 'bazar'; sales: number; revenue: number }[];
  recentAdjustments: {
    id: string;
    created_at: string;
    points: number;
    customer_name: string | null;
    reason: string | null;
  }[];
}

const MXN = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN', maximumFractionDigits: 0 });

function parseNotesReason(notes: string | null): string | null {
  if (!notes) return null;
  const parts = notes.split('|');
  const reasonPart = parts.find((p) => !p.startsWith('by:') && p !== 'ajuste_admin');
  return reasonPart?.trim() || null;
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const min = String(d.getMinutes()).padStart(2, '0');
  return `${dd}/${mm} ${hh}:${min}`;
}

export default function ReportsScreen() {
  const [m, setM] = useState<Metrics | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const startOfMonth = new Date();
    startOfMonth.setDate(1);
    startOfMonth.setHours(0, 0, 0, 0);

    const [salesRes, customersRes, staffRes, channelsRes, adjustRes] = await Promise.all([
      supabase.from('offline_sales')
        .select('id, total, channel_id, staff_id')
        .gte('created_at', startOfMonth.toISOString())
        .not('claimed_at', 'is', null),
      supabase.from('customers').select('id', { count: 'exact', head: true }),
      supabase.from('staff').select('id, name').eq('active', true),
      supabase.from('channels').select('id, name, type').eq('active', true),
      supabase.from('transactions')
        .select('id, created_at, points_earned, notes, loyalty_card_id, loyalty_cards(customer_id, customers(name))')
        .eq('channel', 'manual')
        .order('created_at', { ascending: false })
        .limit(10),
    ]);

    const sales = (salesRes.data ?? []) as { id: string; total: number; channel_id: string; staff_id: string | null }[];
    const staff = (staffRes.data ?? []) as { id: string; name: string }[];
    const channels = (channelsRes.data ?? []) as { id: string; name: string; type: 'store' | 'bazar' }[];

    const staffAgg = new Map<string, { name: string; sales: number; revenue: number }>();
    const chAgg = new Map<string, { name: string; type: 'store' | 'bazar'; sales: number; revenue: number }>();
    let monthRevenue = 0;

    for (const s of sales) {
      const amount = Number(s.total ?? 0);
      monthRevenue += amount;

      if (s.staff_id) {
        const staffRow = staff.find((st) => st.id === s.staff_id);
        const name = staffRow?.name ?? 'Vendedora eliminada';
        const cur = staffAgg.get(s.staff_id) ?? { name, sales: 0, revenue: 0 };
        cur.sales += 1;
        cur.revenue += amount;
        staffAgg.set(s.staff_id, cur);
      }

      if (s.channel_id) {
        const chRow = channels.find((c) => c.id === s.channel_id);
        if (chRow) {
          const cur = chAgg.get(s.channel_id) ?? { name: chRow.name, type: chRow.type, sales: 0, revenue: 0 };
          cur.sales += 1;
          cur.revenue += amount;
          chAgg.set(s.channel_id, cur);
        }
      }
    }

    const topStaff = Array.from(staffAgg.entries())
      .map(([id, v]) => ({ id, ...v }))
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, 5);

    const topChannels = Array.from(chAgg.entries())
      .map(([id, v]) => ({ id, ...v }))
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, 5);

    const recentAdjustments = ((adjustRes.data ?? []) as any[]).map((row) => ({
      id: row.id as string,
      created_at: row.created_at as string,
      points: row.points_earned as number,
      customer_name: row.loyalty_cards?.customers?.name ?? null,
      reason: parseNotesReason(row.notes),
    }));

    setM({
      monthRevenue,
      monthSales: sales.length,
      totalCustomers: customersRes.count ?? 0,
      totalActiveStaff: staff.length,
      topStaff,
      topChannels,
      recentAdjustments,
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

        <Text style={styles.eyebrow}>PANEL ADMIN</Text>
        <Text style={styles.title}>Reportes</Text>

        {loading || !m ? (
          <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
        ) : (
          <>
            {/* KPI cards */}
            <View style={styles.kpiRow}>
              <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 60 }} style={styles.kpi}>
                <TrendingUp size={16} color="#B8860B" />
                <Text style={styles.kpiValue}>{MXN.format(m.monthRevenue)}</Text>
                <Text style={styles.kpiLabel}>Ventas del mes</Text>
                <Text style={styles.kpiSub}>{m.monthSales} operaciones</Text>
              </MotiView>
              <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 120 }} style={styles.kpi}>
                <Users size={16} color="#B8860B" />
                <Text style={styles.kpiValue}>{m.totalCustomers}</Text>
                <Text style={styles.kpiLabel}>Clientas registradas</Text>
                <Text style={styles.kpiSub}>{m.totalActiveStaff} vendedoras activas</Text>
              </MotiView>
            </View>

            {/* Top vendedoras — cada fila lleva al editor de esa vendedora. */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 180 }} style={styles.section}>
              <Text style={styles.sectionTitle}>Top vendedoras del mes</Text>
              {m.topStaff.length === 0 ? (
                <Text style={styles.emptyLine}>Todavía no hay ventas registradas este mes.</Text>
              ) : (
                m.topStaff.map((s, i) => (
                  <TouchableOpacity
                    key={s.id}
                    activeOpacity={0.75}
                    onPress={() => router.push({ pathname: '/admin/staff/[id]' as any, params: { id: s.id } })}
                    style={styles.rankRow}
                  >
                    <Text style={styles.rankPos}>{i + 1}</Text>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.rankName}>{s.name}</Text>
                      <Text style={styles.rankMeta}>{s.sales} {s.sales === 1 ? 'venta' : 'ventas'}</Text>
                    </View>
                    <Text style={styles.rankAmount}>{MXN.format(s.revenue)}</Text>
                  </TouchableOpacity>
                ))
              )}
            </MotiView>

            {/* Top canales — cada fila lleva al editor del canal. */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 240 }} style={styles.section}>
              <Text style={styles.sectionTitle}>Top canales del mes</Text>
              {m.topChannels.length === 0 ? (
                <Text style={styles.emptyLine}>Sin actividad este mes.</Text>
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

            {/* Audit log — cada ajuste abre /admin/puntos con la clienta precargada. */}
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ delay: 300 }} style={styles.section}>
              <View style={styles.sectionHead}>
                <ClipboardList size={14} color="#B8860B" />
                <Text style={styles.sectionTitle}>Últimos ajustes de puntos</Text>
              </View>
              {m.recentAdjustments.length === 0 ? (
                <Text style={styles.emptyLine}>Ningún ajuste manual todavía.</Text>
              ) : (
                m.recentAdjustments.map((a) => (
                  <TouchableOpacity
                    key={a.id}
                    activeOpacity={a.customer_name ? 0.75 : 1}
                    disabled={!a.customer_name}
                    onPress={() =>
                      router.push({ pathname: '/admin/puntos' as any, params: { prefill: a.customer_name ?? '' } })
                    }
                    style={styles.auditRow}
                  >
                    <View style={{ flex: 1 }}>
                      <Text style={styles.auditWho}>{a.customer_name ?? 'Clienta sin nombre'}</Text>
                      <Text style={styles.auditWhen}>{formatDate(a.created_at)}{a.reason ? ` · ${a.reason}` : ''}</Text>
                    </View>
                    <Text style={[styles.auditPoints, a.points < 0 ? styles.auditNeg : styles.auditPos]}>
                      {a.points > 0 ? '+' : ''}{a.points} pts
                    </Text>
                  </TouchableOpacity>
                ))
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
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 3, marginBottom: 6 },
  title: { fontSize: 32, color: '#FFF', fontFamily: 'serif', marginBottom: 24 },
  kpiRow: { flexDirection: 'row', gap: 10, marginBottom: 24 },
  kpi: {
    flex: 1, backgroundColor: '#141414', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    padding: 16, gap: 6,
  },
  kpiValue: { color: '#FFF', fontSize: 22, fontWeight: '800', marginTop: 4 },
  kpiLabel: { color: 'rgba(255,255,255,0.6)', fontSize: 11, fontWeight: '600' },
  kpiSub: { color: 'rgba(255,255,255,0.35)', fontSize: 10 },
  section: {
    backgroundColor: '#141414', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    padding: 18, marginBottom: 16,
  },
  sectionHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 4 },
  sectionTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginBottom: 12 },
  emptyLine: { color: 'rgba(255,255,255,0.35)', fontSize: 12, marginTop: 4 },
  rankRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  rankPos: { color: '#B8860B', fontSize: 13, fontWeight: '800', width: 20 },
  rankName: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  rankMeta: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  rankAmount: { color: '#B8860B', fontSize: 13, fontWeight: '700' },
  auditRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  auditWho: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  auditWhen: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  auditPoints: { fontSize: 13, fontWeight: '800' },
  auditPos: { color: '#4CAF50' },
  auditNeg: { color: '#E05C7A' },
});
