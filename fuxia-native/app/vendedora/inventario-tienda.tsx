// Fuxia 360 · the shift store's stock, read-only (same server catalog the sale uses: f360_shift_catalog). The seller
// sees what her store has, by model, colour and size; changes happen only through sales, transfers and Carolina's
// adjustments in the admin.
import React, { useCallback, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, RefreshControl, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { ArrowLeft } from 'lucide-react-native';
import { currentShift } from '@/lib/sellerSession';
import { shiftCatalog, type CatalogItem } from '@/lib/f360Store';

export default function InventarioTienda() {
  const [items, setItems] = useState<CatalogItem[] | null>(null);
  const [q, setQ] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    if (!currentShift()) { router.replace('/vendedora' as any); return; }
    try { setItems((await shiftCatalog()).items ?? []); } catch (e) { Alert.alert('No se pudo cargar', (e as Error).message); }
  }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  const groups = useMemo(() => {
    const t = q.trim().toLowerCase();
    const map = new Map<string, CatalogItem[]>();
    for (const i of items ?? []) {
      if (i.available <= 0) continue;
      if (t && !`${i.product_name} ${i.color} ${i.size} ${i.sku}`.toLowerCase().includes(t)) continue;
      const k = `${i.product_name} · ${i.color}`;
      map.set(k, [...(map.get(k) ?? []), i]);
    }
    return [...map.entries()].sort(([a], [b]) => a.localeCompare(b, 'es'));
  }, [items, q]);
  const pares = (items ?? []).reduce((a, i) => a + Math.max(0, i.available), 0);

  return (
    <SafeAreaView style={s.container}>
      <View style={s.top}>
        <TouchableOpacity onPress={() => router.back()} style={s.back} accessibilityLabel="Regresar"><ArrowLeft size={20} color="#fff" /></TouchableOpacity>
        <View style={{ flexShrink: 1 }}>
          <Text style={s.title}>Inventario · {currentShift()?.location.name}</Text>
          {items && <Text style={s.sub}>{pares} pares en la tienda</Text>}
        </View>
      </View>
      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled"
        refreshControl={<RefreshControl refreshing={refreshing} tintColor="#B8860B" onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}>
        <TextInput value={q} onChangeText={setQ} placeholder="Buscar modelo, color o talla" placeholderTextColor="rgba(255,255,255,0.35)" style={s.search} />
        {items === null && <ActivityIndicator color="#B8860B" style={{ marginTop: 30 }} />}
        {items && groups.length === 0 && <Text style={s.empty}>{q ? 'No hay pares con esa búsqueda.' : 'No hay pares en esta tienda.'}</Text>}
        {groups.map(([name, list]) => (
          <View key={name} style={s.card}>
            <Text style={s.cardName}>{name}</Text>
            <View style={s.sizes}>
              {list.sort((a, b) => a.size.localeCompare(b.size, 'es', { numeric: true })).map((i) => (
                <View key={i.variant_id} style={s.size}>
                  <Text style={s.sizeLabel}>{i.size}</Text>
                  <Text style={s.sizeN}>{i.available}{i.reserved ? ` (${i.reserved} apart.)` : ''}</Text>
                </View>
              ))}
            </View>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  top: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 20, paddingBottom: 8 },
  back: { width: 40, height: 40, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.06)', alignItems: 'center', justifyContent: 'center' },
  title: { color: '#fff', fontSize: 20, fontWeight: '700' },
  sub: { color: '#B8860B', fontSize: 13, fontWeight: '600', marginTop: 2 },
  body: { padding: 20, gap: 10, paddingBottom: 40 },
  search: { backgroundColor: '#1A1A1A', borderRadius: 12, padding: 14, color: '#fff', fontSize: 15 },
  empty: { color: 'rgba(255,255,255,0.6)', textAlign: 'center', marginTop: 30 },
  card: { backgroundColor: '#1A1A1A', borderRadius: 14, padding: 14 },
  cardName: { color: '#fff', fontSize: 15, fontWeight: '700', marginBottom: 10 },
  sizes: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  size: { backgroundColor: 'rgba(255,255,255,0.06)', borderRadius: 10, paddingVertical: 6, paddingHorizontal: 10, alignItems: 'center', minWidth: 52 },
  sizeLabel: { color: 'rgba(255,255,255,0.6)', fontSize: 11 },
  sizeN: { color: '#fff', fontSize: 15, fontWeight: '700' },
});
