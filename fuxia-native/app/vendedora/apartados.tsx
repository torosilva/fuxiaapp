// Fuxia 360 · Apartados Fuxia Gold of the seller's shift store: what to separate, for whom, until when; "Ya lo separé";
// "Vender a <clienta>" opens the sale with that pair (scanning her card closes the reservation as sold).
import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { ArrowLeft, Check } from 'lucide-react-native';
import { currentShift } from '@/lib/sellerSession';
import { faltan, hora, markSeparated, onReservations, refreshReservations, type ShiftReservation } from '@/lib/f360Store';

const ESTADO: Record<string, string> = { vendida: 'Vendido', vencida: 'Venció', cancelada: 'Cancelado' };

export default function Apartados() {
  const [list, setList] = useState<ShiftReservation[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [, tick] = useState(0);
  const load = useCallback(() => refreshReservations().then(setList).catch((e) => Alert.alert('No se pudo cargar', e.message)), []);

  useEffect(() => {
    if (!currentShift()) { router.replace('/vendedora' as any); return; }
    const off = onReservations(setList);
    const t = setInterval(() => tick((n) => n + 1), 30000);     // keeps "faltan X min" fresh
    return () => { off(); clearInterval(t); };
  }, []);
  useFocusEffect(useCallback(() => { if (currentShift()) load(); }, [load]));

  const separar = async (r: ShiftReservation) => {
    setBusy(r.id);
    try { await markSeparated(r.id); await load(); } catch (e) { Alert.alert('No se pudo', (e as Error).message); }
    setBusy(null);
  };

  const now = Date.now();
  const active = (list ?? []).filter((r) => r.status === 'activa' && new Date(r.expires_at).getTime() > now);
  const closed = (list ?? []).filter((r) => !active.includes(r));

  return (
    <SafeAreaView style={s.container}>
      <View style={s.top}>
        <TouchableOpacity onPress={() => router.back()} style={s.back} accessibilityLabel="Regresar"><ArrowLeft size={20} color="#fff" /></TouchableOpacity>
        <Text style={s.title}>Apartados Fuxia Gold</Text>
      </View>
      <ScrollView contentContainerStyle={s.body} refreshControl={<RefreshControl refreshing={false} onRefresh={load} tintColor="#B8860B" />}>
        {list === null && <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />}
        {list !== null && active.length === 0 && <Text style={s.empty}>No hay apartados activos en {currentShift()?.location.name}.</Text>}
        {active.map((r) => (
          <View key={r.id} style={[s.card, !r.separated_at && s.cardTodo]}>
            <View style={s.line}>
              {r.color_hex ? <View style={[s.swatch, { backgroundColor: r.color_hex }]} /> : null}
              <Text style={s.product}>{r.product}</Text>
            </View>
            <Text style={s.detail}>{r.color} · talla <Text style={s.size}>{r.size}</Text></Text>
            <Text style={s.who}>Para {r.customer}{r.phone_last4 ? ` · tel. ···${r.phone_last4}` : ''} · {r.channel === 'web' ? 'desde la web' : 'desde la app'}</Text>
            <Text style={s.until}>Hasta las {hora(r.expires_at)} · faltan {faltan(r.expires_at, now)}</Text>
            {r.separated_at ? (
              <View style={s.done}><Check size={16} color="#3f9b5f" /><Text style={s.doneText}>Separado por {r.separated_by} a las {hora(r.separated_at)}</Text></View>
            ) : (
              <TouchableOpacity style={s.btn} onPress={() => separar(r)} disabled={busy === r.id} accessibilityLabel="Ya lo separé">
                <Text style={s.btnText}>{busy === r.id ? 'Guardando…' : 'Ya lo separé'}</Text>
              </TouchableOpacity>
            )}
            <TouchableOpacity style={s.btnGhost} onPress={() => router.push({ pathname: '/vendedora/venta' as any, params: { variant: r.variant_id, para: r.customer } })}>
              <Text style={s.btnGhostText}>Llegó: vender a {r.customer}</Text>
            </TouchableOpacity>
          </View>
        ))}
        {closed.length > 0 && <Text style={s.section}>Hoy</Text>}
        {closed.map((r) => (
          <View key={r.id} style={s.closed}>
            <Text style={s.closedText}>{r.product} {r.color} {r.size} · {r.customer}</Text>
            <Text style={s.closedState}>{ESTADO[r.status] ?? 'Venció'}</Text>
          </View>
        ))}
        <Text style={s.help}>El par apartado no se puede vender a otra persona ni mandar a otra tienda. Si la clienta no llega en 2 horas, se libera solo.</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  top: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 20, paddingBottom: 8 },
  back: { width: 40, height: 40, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.06)', alignItems: 'center', justifyContent: 'center' },
  title: { color: '#fff', fontSize: 22, fontWeight: '700' },
  body: { padding: 20, paddingTop: 8, gap: 12 },
  empty: { color: 'rgba(255,255,255,0.6)', textAlign: 'center', marginTop: 40, fontSize: 15 },
  card: { backgroundColor: '#1A1A1A', borderRadius: 18, padding: 18, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  cardTodo: { borderColor: '#B8860B', borderWidth: 2 },
  line: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  swatch: { width: 16, height: 16, borderRadius: 8, borderWidth: 1, borderColor: 'rgba(255,255,255,0.3)' },
  product: { color: '#fff', fontSize: 18, fontWeight: '700', flexShrink: 1 },
  detail: { color: 'rgba(255,255,255,0.8)', fontSize: 15, marginTop: 4 },
  size: { fontWeight: '800', color: '#fff', fontSize: 17 },
  who: { color: 'rgba(255,255,255,0.7)', fontSize: 13, marginTop: 8 },
  until: { color: '#B8860B', fontSize: 13, marginTop: 2, fontWeight: '600' },
  btn: { marginTop: 14, backgroundColor: '#B8860B', borderRadius: 14, paddingVertical: 14, alignItems: 'center' },
  btnText: { color: '#0D0D0D', fontWeight: '800', fontSize: 16 },
  btnGhost: { marginTop: 8, borderRadius: 14, paddingVertical: 12, alignItems: 'center', borderWidth: 1, borderColor: 'rgba(255,255,255,0.15)' },
  btnGhostText: { color: '#fff', fontSize: 14 },
  done: { marginTop: 14, flexDirection: 'row', alignItems: 'center', gap: 6 },
  doneText: { color: '#3f9b5f', fontSize: 14 },
  section: { color: 'rgba(255,255,255,0.5)', fontSize: 12, letterSpacing: 2, textTransform: 'uppercase', marginTop: 12 },
  closed: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.06)' },
  closedText: { color: 'rgba(255,255,255,0.6)', fontSize: 13, flexShrink: 1 },
  closedState: { color: 'rgba(255,255,255,0.4)', fontSize: 13 },
  help: { color: 'rgba(255,255,255,0.4)', fontSize: 12, marginTop: 16, textAlign: 'center' },
});
