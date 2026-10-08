// Fuxia 360 · seller home for a store whose inventory lives in Fuxia 360 (e.g. Tienda Polanco). The location and the
// person come from the server-side shift (lib/sellerSession); this screen never chooses them.
import React, { useCallback, useEffect, useState } from 'react';
import { StyleSheet, Text, TouchableOpacity, View, StatusBar } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { Bookmark, LogOut, Package, ShoppingCart, Store } from 'lucide-react-native';
import { currentShift, endShift } from '@/lib/sellerSession';
import { onReservations, refreshReservations, startReservationWatch, stopReservationWatch, type ShiftReservation } from '@/lib/f360Store';
import { onNoticeTap } from '@/lib/notifications';

export default function TiendaF360() {
  const shift = currentShift();
  const [list, setList] = useState<ShiftReservation[] | null>(null);

  useEffect(() => {
    if (!shift) { router.replace('/vendedora' as any); return; }
    startReservationWatch();
    const off = onReservations(setList);
    const offTap = onNoticeTap((d) => { if (d.type === 'f360_reservation' && currentShift()) router.push('/vendedora/apartados' as any); });
    return () => { off(); offTap(); };
  }, []);
  useFocusEffect(useCallback(() => { if (currentShift()) refreshReservations().then(setList).catch(() => {}); }, []));

  if (!shift) return null;
  const active = (list ?? []).filter((r) => r.status === 'activa');
  const pending = active.filter((r) => !r.separated_at).length;

  const exit = async () => { stopReservationWatch(); await endShift(); router.replace('/vendedora' as any); };

  return (
    <SafeAreaView style={s.container}>
      <StatusBar barStyle="light-content" />
      <View style={s.content}>
        <View style={s.header}>
          <View>
            <Text style={s.greeting}>Hola, {shift.person || 'Vendedora'}</Text>
            <View style={s.row}><Store size={14} color="#B8860B" /><Text style={s.place}>{shift.location.name}</Text></View>
          </View>
          <TouchableOpacity onPress={exit} style={s.exit} accessibilityLabel="Terminar turno"><LogOut size={18} color="rgba(255,255,255,0.4)" /></TouchableOpacity>
        </View>

        <TouchableOpacity style={[s.card, pending > 0 && s.cardAlert]} onPress={() => router.push('/vendedora/apartados' as any)} activeOpacity={0.85} accessibilityLabel="Apartados">
          <View style={s.row}><Bookmark size={16} color="#B8860B" /><Text style={s.cardLabel}>Apartados Fuxia Gold</Text></View>
          <Text style={s.cardValue}>{list === null ? '…' : active.length}</Text>
          <Text style={s.cardSub}>{pending > 0 ? `${pending} por separar · toca para verlos` : active.length ? 'Todos separados' : 'Ninguno por ahora'}</Text>
        </TouchableOpacity>

        <TouchableOpacity style={s.primary} onPress={() => router.push('/vendedora/venta' as any)} activeOpacity={0.85}>
          <ShoppingCart size={28} color="#0D0D0D" />
          <Text style={s.primaryText}>Registrar venta</Text>
          <Text style={s.primarySub}>Precio e inventario de Fuxia 360</Text>
        </TouchableOpacity>
        <TouchableOpacity style={s.secondary} onPress={() => router.push('/vendedora/inventario-tienda' as any)} activeOpacity={0.85} accessibilityLabel="Inventario de la tienda">
          <Package size={20} color="#B8860B" />
          <Text style={s.secondaryText}>Inventario de la tienda</Text>
        </TouchableOpacity>
        <Text style={s.note}>Te avisamos aquí cuando una clienta Gold aparte un par en esta tienda.</Text>
      </View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  content: { flex: 1, padding: 24 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 28 },
  greeting: { fontSize: 28, color: '#fff', fontWeight: '700', marginBottom: 6 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  place: { fontSize: 13, color: '#B8860B', fontWeight: '600' },
  exit: { width: 40, height: 40, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.06)', justifyContent: 'center', alignItems: 'center' },
  card: { backgroundColor: '#1A1A1A', borderRadius: 20, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', padding: 24, alignItems: 'center', marginBottom: 20 },
  cardAlert: { borderColor: '#B8860B', borderWidth: 2 },
  cardLabel: { fontSize: 11, color: '#B8860B', fontWeight: '800', letterSpacing: 2, textTransform: 'uppercase' },
  cardValue: { fontSize: 56, color: '#fff', fontWeight: '700', marginVertical: 4 },
  cardSub: { fontSize: 13, color: 'rgba(255,255,255,0.6)' },
  primary: { backgroundColor: '#B8860B', borderRadius: 20, padding: 24, alignItems: 'center', gap: 6 },
  primaryText: { fontSize: 20, fontWeight: '800', color: '#0D0D0D' },
  primarySub: { fontSize: 12, color: 'rgba(13,13,13,0.7)' },
  secondary: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 10, marginTop: 14, padding: 18, borderRadius: 20, borderWidth: 1, borderColor: '#B8860B' },
  secondaryText: { fontSize: 16, fontWeight: '700', color: '#B8860B' },
  note: { marginTop: 20, fontSize: 12, color: 'rgba(255,255,255,0.4)', textAlign: 'center' },
});
