// Fuxia 360 · store sale at a Fuxia 360 store (f360_record_store_sale): the seller picks pairs from HER shift store's
// stock, how the customer paid, and (optionally) scans the customer's card. Price, total, points and stock are the
// server's. Pairs reserved for a Gold customer can only go to her (scan her card). Opened from "Apartados" with
// ?variant=…&para=… the reserved pair is already in the cart and the card scan is requested.
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Alert, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { ArrowLeft, Minus, Plus, QrCode } from 'lucide-react-native';
import QRScanner from '@/components/QRScanner';
import { currentShift } from '@/lib/sellerSession';
import { newSaleKey, recordSale, shiftCatalog, type CatalogItem, type SaleResult } from '@/lib/f360Store';

const PAGOS = [{ k: 'cash', l: 'Efectivo' }, { k: 'card', l: 'Tarjeta' }, { k: 'transfer', l: 'Transferencia' }, { k: 'other', l: 'Otro' }] as const;
const money = (n: number) => `$${n.toLocaleString('es-MX', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;

export default function VentaF360() {
  const { variant, para } = useLocalSearchParams<{ variant?: string; para?: string }>();
  const [items, setItems] = useState<CatalogItem[] | null>(null);
  const [q, setQ] = useState('');
  const [cart, setCart] = useState<Record<string, number>>(variant ? { [variant]: 1 } : {});
  const [pago, setPago] = useState<(typeof PAGOS)[number]['k'] | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<SaleResult | null>(null);
  const key = useRef(newSaleKey());                    // one key per sale: a retry or double tap never sells twice

  useEffect(() => {
    if (!currentShift()) { router.replace('/vendedora' as any); return; }
    shiftCatalog().then((c) => setItems(c.items ?? [])).catch((e) => Alert.alert('No se pudo cargar', e.message));
  }, []);

  const byId = useMemo(() => Object.fromEntries((items ?? []).map((i) => [i.variant_id, i])), [items]);
  const shown = useMemo(() => {
    const t = q.trim().toLowerCase();
    return (items ?? []).filter((i) => !t || `${i.product_name} ${i.color} ${i.size} ${i.sku}`.toLowerCase().includes(t)).slice(0, 80);
  }, [items, q]);
  const lines = Object.entries(cart).filter(([, n]) => n > 0);
  const total = lines.reduce((a, [id, n]) => a + (byId[id]?.price ?? 0) * n, 0);
  const add = (id: string, d: number) => setCart((c) => ({ ...c, [id]: Math.max(0, Math.min((c[id] ?? 0) + d, byId[id]?.available ?? 0)) }));

  const vender = async () => {
    if (!pago) { Alert.alert('Falta el pago', 'Elige cómo pagó la clienta.'); return; }
    setBusy(true);
    try {
      const r = await recordSale(key.current, lines.map(([variant_id, quantity]) => ({ variant_id, quantity })), pago, qr);
      setDone(r);
    } catch (e) {
      Alert.alert('No se registró la venta', (e as Error).message);
    }
    setBusy(false);
  };

  if (done) {
    return (
      <SafeAreaView style={s.container}>
        <View style={s.doneBox}>
          <Text style={s.doneTitle}>Venta registrada</Text>
          <Text style={s.doneTotal}>{money(Number(done.total))}</Text>
          {done.claimed ? <Text style={s.doneSub}>+{done.points} puntos para la clienta</Text>
            : done.code ? <Text style={s.doneSub}>Código para que la clienta sume sus puntos: <Text style={s.code}>{done.code}</Text></Text> : null}
          <TouchableOpacity style={s.cta} onPress={() => router.replace('/vendedora/tienda' as any)}><Text style={s.ctaText}>Listo</Text></TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={s.container}>
      <View style={s.top}>
        <TouchableOpacity onPress={() => router.back()} style={s.back} accessibilityLabel="Regresar"><ArrowLeft size={20} color="#fff" /></TouchableOpacity>
        <Text style={s.title}>Venta · {currentShift()?.location.name}</Text>
      </View>
      {para ? <Text style={s.banner}>Apartado de {para}: escanea su tarjeta para entregarle su par.</Text> : null}
      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
        <TextInput value={q} onChangeText={setQ} placeholder="Buscar modelo, color o talla" placeholderTextColor="rgba(255,255,255,0.35)" style={s.search} />
        {items === null && <ActivityIndicator color="#B8860B" style={{ marginTop: 30 }} />}
        {items?.length === 0 && <Text style={s.empty}>No hay pares en esta tienda.</Text>}
        {shown.map((i) => {
          const n = cart[i.variant_id] ?? 0;
          const libres = Math.max(0, i.available - i.reserved);
          return (
            <View key={i.variant_id} style={[s.item, n > 0 && s.itemOn]}>
              <View style={{ flex: 1 }}>
                <Text style={s.itemName}>{i.product_name}</Text>
                <Text style={s.itemSub}>{i.color} · talla {i.size} · {i.price != null ? money(Number(i.price)) : 'sin precio'}</Text>
                <Text style={s.itemStock}>{libres} libres{i.reserved ? ` · ${i.reserved} apartado${i.reserved > 1 ? 's' : ''} Gold` : ''}</Text>
              </View>
              <View style={s.qty}>
                <TouchableOpacity onPress={() => add(i.variant_id, -1)} style={s.qBtn} accessibilityLabel="Quitar uno"><Minus size={16} color="#fff" /></TouchableOpacity>
                <Text style={s.qN}>{n}</Text>
                <TouchableOpacity onPress={() => add(i.variant_id, 1)} style={s.qBtn} accessibilityLabel="Agregar uno"><Plus size={16} color="#fff" /></TouchableOpacity>
              </View>
            </View>
          );
        })}
      </ScrollView>

      <View style={s.footer}>
        <TouchableOpacity style={[s.scan, qr && s.scanOn]} onPress={() => setScanning(true)}>
          <QrCode size={18} color={qr ? '#0D0D0D' : '#B8860B'} />
          <Text style={[s.scanText, qr && { color: '#0D0D0D' }]}>{qr ? 'Tarjeta de la clienta escaneada' : 'Escanear tarjeta de la clienta (opcional)'}</Text>
        </TouchableOpacity>
        <View style={s.pagos}>
          {PAGOS.map((p) => (
            <TouchableOpacity key={p.k} style={[s.pago, pago === p.k && s.pagoOn]} onPress={() => setPago(p.k)}>
              <Text style={[s.pagoText, pago === p.k && { color: '#0D0D0D' }]}>{p.l}</Text>
            </TouchableOpacity>
          ))}
        </View>
        <TouchableOpacity style={[s.cta, (!lines.length || busy) && { opacity: 0.5 }]} disabled={!lines.length || busy} onPress={vender}>
          <Text style={s.ctaText}>{busy ? 'Registrando…' : `Cobrar ${money(total)} · ${lines.reduce((a, [, n]) => a + n, 0)} par(es)`}</Text>
        </TouchableOpacity>
      </View>
      <QRScanner visible={scanning} onScan={(d) => { setQr(d); setScanning(false); }} onClose={() => setScanning(false)} />
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  top: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 20, paddingBottom: 8 },
  back: { width: 40, height: 40, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.06)', alignItems: 'center', justifyContent: 'center' },
  title: { color: '#fff', fontSize: 20, fontWeight: '700', flexShrink: 1 },
  banner: { marginHorizontal: 20, padding: 12, borderRadius: 12, backgroundColor: 'rgba(184,134,11,0.15)', color: '#E6C36A', fontSize: 13 },
  body: { padding: 20, gap: 10, paddingBottom: 40 },
  search: { backgroundColor: '#1A1A1A', borderRadius: 12, padding: 14, color: '#fff', fontSize: 15 },
  empty: { color: 'rgba(255,255,255,0.6)', textAlign: 'center', marginTop: 30 },
  item: { flexDirection: 'row', alignItems: 'center', backgroundColor: '#1A1A1A', borderRadius: 14, padding: 14, borderWidth: 1, borderColor: 'transparent' },
  itemOn: { borderColor: '#B8860B' },
  itemName: { color: '#fff', fontSize: 15, fontWeight: '700' },
  itemSub: { color: 'rgba(255,255,255,0.7)', fontSize: 13, marginTop: 2 },
  itemStock: { color: 'rgba(255,255,255,0.45)', fontSize: 12, marginTop: 2 },
  qty: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  qBtn: { width: 34, height: 34, borderRadius: 10, backgroundColor: 'rgba(255,255,255,0.08)', alignItems: 'center', justifyContent: 'center' },
  qN: { color: '#fff', fontSize: 16, fontWeight: '700', minWidth: 18, textAlign: 'center' },
  footer: { padding: 16, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.08)', gap: 10 },
  scan: { flexDirection: 'row', alignItems: 'center', gap: 8, padding: 12, borderRadius: 12, borderWidth: 1, borderColor: '#B8860B' },
  scanOn: { backgroundColor: '#B8860B' },
  scanText: { color: '#B8860B', fontSize: 14, fontWeight: '600' },
  pagos: { flexDirection: 'row', gap: 8 },
  pago: { flex: 1, paddingVertical: 10, borderRadius: 10, backgroundColor: 'rgba(255,255,255,0.06)', alignItems: 'center' },
  pagoOn: { backgroundColor: '#fff' },
  pagoText: { color: '#fff', fontSize: 12, fontWeight: '600' },
  cta: { backgroundColor: '#B8860B', borderRadius: 14, paddingVertical: 16, alignItems: 'center' },
  ctaText: { color: '#0D0D0D', fontSize: 16, fontWeight: '800' },
  doneBox: { flex: 1, padding: 28, justifyContent: 'center', alignItems: 'center', gap: 10 },
  doneTitle: { color: '#B8860B', fontSize: 14, fontWeight: '800', letterSpacing: 2, textTransform: 'uppercase' },
  doneTotal: { color: '#fff', fontSize: 48, fontWeight: '700' },
  doneSub: { color: 'rgba(255,255,255,0.75)', fontSize: 15, textAlign: 'center', marginBottom: 20 },
  code: { color: '#fff', fontWeight: '800', letterSpacing: 2 },
});
