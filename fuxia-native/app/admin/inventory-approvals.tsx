/**
 * /admin/inventory-approvals
 *
 * La admin ve las solicitudes de cambio de inventario que hicieron las
 * vendedoras y decide aprobar o rechazar cada una. La aplicación real del
 * cambio la hace la edge function `inventory-approve` con service_role.
 *
 * Muestra pendientes primero, y abajo un historial de las últimas resueltas
 * para tener contexto y detectar patrones raros ("esta vendedora pide bajar
 * stock todos los días").
 */
import React, { useCallback, useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  StatusBar, ActivityIndicator, Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Check, X, Package, Minus, Plus, Trash2 } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;

interface Request {
  id: string;
  channel_id: string;
  channels: { name: string } | null;
  requested_by_staff_id: string | null;
  requested_by_name: string;
  action: 'bulk_add' | 'adjust_stock' | 'delete';
  payload: any;
  status: 'pending' | 'approved' | 'rejected';
  created_at: string;
  reviewed_at: string | null;
  rejection_reason: string | null;
}

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'hace un momento';
  if (mins < 60) return `hace ${mins} min`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `hace ${hrs} h`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `hace ${days} d`;
  return new Date(iso).toLocaleDateString('es-MX', { day: '2-digit', month: 'short' });
}

function summarize(r: Request): { title: string; sub: string; icon: any; color: string } {
  if (r.action === 'bulk_add') {
    const p = r.payload || {};
    const combos = (p.colors?.length || 1) * (p.sizes?.length || 0);
    return {
      icon: Package,
      color: '#4CAF50',
      title: `Agregar "${p.product_name ?? '¿?'}"`,
      sub: `${combos} combinaciones · ${p.stock_per_combo ?? 0} par c/u · $${Number(p.price ?? 0).toLocaleString('es-MX')}`,
    };
  }
  if (r.action === 'adjust_stock') {
    const p = r.payload || {};
    const delta = (p.target_stock ?? 0) - (p.current_stock ?? 0);
    const up = delta > 0;
    return {
      icon: up ? Plus : Minus,
      color: up ? '#4CAF50' : '#E05C7A',
      title: `${up ? '+' : ''}${delta} pares de "${p.product_name ?? '¿?'}"`,
      sub: `Talla ${p.size}${p.color ? ' · ' + p.color : ''} · Actual ${p.current_stock} → Nuevo ${p.target_stock}`,
    };
  }
  if (r.action === 'delete') {
    const p = r.payload || {};
    return {
      icon: Trash2,
      color: '#E05C7A',
      title: `Eliminar "${p.product_name ?? '¿?'}"`,
      sub: `Talla ${p.size}${p.color ? ' · ' + p.color : ''} · quedan ${p.remaining ?? '?'} par(es)`,
    };
  }
  return { icon: Package, color: '#B8860B', title: 'Cambio desconocido', sub: '' };
}

async function callEdge(action: 'approve' | 'reject', requestId: string, reason?: string) {
  const { data: { session } } = await supabase.auth.getSession();
  const res = await fetch(`${SUPABASE_URL}/functions/v1/inventory-approve`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session?.access_token}`,
    },
    body: JSON.stringify({ action, request_id: requestId, reason }),
  });
  return res.json();
}

export default function InventoryApprovalsScreen() {
  const [pending, setPending] = useState<Request[]>([]);
  const [recent, setRecent] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [pRes, rRes] = await Promise.all([
      supabase
        .from('inventory_change_requests')
        .select('id, channel_id, requested_by_staff_id, requested_by_name, action, payload, status, created_at, reviewed_at, rejection_reason, channels(name)')
        .eq('status', 'pending')
        .order('created_at', { ascending: false })
        .limit(50),
      supabase
        .from('inventory_change_requests')
        .select('id, channel_id, requested_by_staff_id, requested_by_name, action, payload, status, created_at, reviewed_at, rejection_reason, channels(name)')
        .neq('status', 'pending')
        .order('reviewed_at', { ascending: false })
        .limit(15),
    ]);
    setPending((pRes.data ?? []) as unknown as Request[]);
    setRecent((rRes.data ?? []) as unknown as Request[]);
    setLoading(false);
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const handleApprove = async (r: Request) => {
    setBusyId(r.id);
    const res = await callEdge('approve', r.id);
    setBusyId(null);
    if (res.error) { Alert.alert('Error', res.error); return; }
    load();
  };

  const handleReject = (r: Request) => {
    Alert.prompt?.(
      'Rechazar solicitud',
      '¿Por qué la rechazas? (opcional, para el historial)',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Rechazar', style: 'destructive',
          onPress: async (reason?: string) => {
            setBusyId(r.id);
            const res = await callEdge('reject', r.id, reason);
            setBusyId(null);
            if (res.error) { Alert.alert('Error', res.error); return; }
            load();
          },
        },
      ],
    ) ?? // Android no tiene Alert.prompt — fallback simple sin motivo
    (async () => {
      setBusyId(r.id);
      const res = await callEdge('reject', r.id);
      setBusyId(null);
      if (res.error) { Alert.alert('Error', res.error); return; }
      load();
    })();
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>

        <Text style={styles.eyebrow}>PANEL ADMIN</Text>
        <Text style={styles.title}>Aprobar cambios{'\n'}de inventario</Text>

        {loading ? (
          <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
        ) : (
          <>
            <Text style={styles.sectionTitle}>Pendientes ({pending.length})</Text>
            {pending.length === 0 ? (
              <View style={styles.emptyCard}>
                <Check size={28} color="rgba(76,175,80,0.4)" />
                <Text style={styles.emptyText}>No hay solicitudes esperando.</Text>
              </View>
            ) : (
              pending.map((r, i) => {
                const s = summarize(r);
                const Icon = s.icon;
                const isBusy = busyId === r.id;
                return (
                  <MotiView
                    key={r.id}
                    from={{ opacity: 0, translateY: 8 }}
                    animate={{ opacity: 1, translateY: 0 }}
                    transition={{ delay: i * 50 }}
                    style={styles.card}
                  >
                    <View style={styles.cardHead}>
                      <View style={[styles.iconWrap, { backgroundColor: s.color + '22' }]}>
                        <Icon size={16} color={s.color} />
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.cardTitle}>{s.title}</Text>
                        <Text style={styles.cardSub}>{s.sub}</Text>
                      </View>
                    </View>
                    <Text style={styles.cardMeta}>
                      {r.requested_by_name} · {r.channels?.name ?? 'canal ?'} · {timeAgo(r.created_at)}
                    </Text>
                    <View style={styles.actions}>
                      <TouchableOpacity
                        style={[styles.rejectBtn, isBusy && { opacity: 0.5 }]}
                        onPress={() => handleReject(r)}
                        disabled={isBusy}
                      >
                        <X size={14} color="#E05C7A" />
                        <Text style={styles.rejectText}>Rechazar</Text>
                      </TouchableOpacity>
                      <TouchableOpacity
                        style={[styles.approveBtn, isBusy && { opacity: 0.5 }]}
                        onPress={() => handleApprove(r)}
                        disabled={isBusy}
                      >
                        {isBusy
                          ? <ActivityIndicator color="#0D0D0D" size="small" />
                          : <>
                              <Check size={14} color="#0D0D0D" strokeWidth={3} />
                              <Text style={styles.approveText}>Aprobar</Text>
                            </>}
                      </TouchableOpacity>
                    </View>
                  </MotiView>
                );
              })
            )}

            {recent.length > 0 && (
              <>
                <Text style={[styles.sectionTitle, { marginTop: 28 }]}>Historial reciente</Text>
                {recent.map((r) => {
                  const s = summarize(r);
                  const Icon = s.icon;
                  const isApproved = r.status === 'approved';
                  return (
                    <View key={r.id} style={styles.historyRow}>
                      <View style={[styles.iconWrap, { backgroundColor: s.color + '15' }]}>
                        <Icon size={14} color={s.color} />
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.historyTitle}>{s.title}</Text>
                        <Text style={styles.historySub}>
                          {r.requested_by_name} · {timeAgo(r.reviewed_at ?? r.created_at)}
                          {r.rejection_reason ? ` · "${r.rejection_reason}"` : ''}
                        </Text>
                      </View>
                      <Text style={[styles.historyStatus, { color: isApproved ? '#4CAF50' : '#E05C7A' }]}>
                        {isApproved ? 'Aprobada' : 'Rechazada'}
                      </Text>
                    </View>
                  );
                })}
              </>
            )}
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
  title: { fontSize: 30, color: '#FFF', fontFamily: 'serif', lineHeight: 36, marginBottom: 24 },
  sectionTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginBottom: 12 },
  emptyCard: {
    backgroundColor: '#141414', borderRadius: 16, borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)', padding: 32, alignItems: 'center', gap: 10,
  },
  emptyText: { color: 'rgba(255,255,255,0.4)', fontSize: 13 },
  card: {
    backgroundColor: '#141414', borderRadius: 14, borderWidth: 1,
    borderColor: 'rgba(255,193,7,0.35)', padding: 14, marginBottom: 10,
  },
  cardHead: { flexDirection: 'row', alignItems: 'flex-start', gap: 10 },
  iconWrap: {
    width: 32, height: 32, borderRadius: 16,
    justifyContent: 'center', alignItems: 'center',
  },
  cardTitle: { color: '#FFF', fontSize: 14, fontWeight: '700' },
  cardSub: { color: 'rgba(255,255,255,0.55)', fontSize: 12, marginTop: 2 },
  cardMeta: {
    color: 'rgba(255,255,255,0.4)', fontSize: 11,
    marginTop: 8, marginLeft: 42,
  },
  actions: { flexDirection: 'row', gap: 10, marginTop: 12 },
  rejectBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 6, paddingVertical: 10, borderRadius: 24,
    backgroundColor: 'transparent', borderWidth: 1.5, borderColor: 'rgba(224,92,122,0.6)',
  },
  rejectText: { color: '#E05C7A', fontSize: 13, fontWeight: '800' },
  approveBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 6, paddingVertical: 10, borderRadius: 24, backgroundColor: '#B8860B',
  },
  approveText: { color: '#0D0D0D', fontSize: 13, fontWeight: '800' },
  historyRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  historyTitle: { color: 'rgba(255,255,255,0.85)', fontSize: 13, fontWeight: '600' },
  historySub: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  historyStatus: { fontSize: 11, fontWeight: '800' },
});
