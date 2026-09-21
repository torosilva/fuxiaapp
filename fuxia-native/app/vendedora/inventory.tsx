import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
  ScrollView,
  Image,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Package, Plus, Minus } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface InventoryItem {
  id: string;
  product_name: string;
  size: string;
  color: string | null;
  price: number;
  stock: number;
  sold: number;
  image_url: string | null;
}

export default function VendedoraInventoryScreen() {
  const { channelId, channelName } = useLocalSearchParams<{
    channelId: string;
    channelName: string;
  }>();

  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const fetchInventory = useCallback(async () => {
    if (!channelId) return;
    setLoading(true);
    const { data } = await supabase
      .from('channel_inventory')
      .select('id, product_name, size, color, price, stock, sold, image_url')
      .eq('channel_id', channelId)
      .order('product_name');
    if (data) setInventory(data as InventoryItem[]);
    setLoading(false);
  }, [channelId]);

  // Refrescar al volver de bulk-add o de la venta que descontó stock.
  useFocusEffect(useCallback(() => { fetchInventory(); }, [fetchInventory]));

  // Ajusta el stock físico (no las ventas). Sirve para corregir cuando llega
  // más mercadería del taller o se hace un ajuste por rotura/mermas.
  const adjustStock = async (item: InventoryItem, delta: number) => {
    const newStock = Math.max(item.sold, item.stock + delta); // no permite bajar de lo vendido
    if (newStock === item.stock) return;
    setBusyId(item.id);
    const { error } = await supabase
      .from('channel_inventory')
      .update({ stock: newStock })
      .eq('id', item.id);
    setBusyId(null);
    if (error) { Alert.alert('Error', error.message); return; }
    setInventory((inv) => inv.map((r) => (r.id === item.id ? { ...r, stock: newStock } : r)));
  };

  const getStockStyle = (remaining: number) => {
    if (remaining > 3) return styles.stockGreen;
    if (remaining > 0) return styles.stockYellow;
    return styles.stockRed;
  };

  const getStockTextColor = (remaining: number) => {
    if (remaining > 3) return '#4CAF50';
    if (remaining > 0) return '#FFC107';
    return '#FF6B6B';
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scroll}>
        <MotiView
          from={{ opacity: 0, translateY: 16 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 400 }}
        >
          <TouchableOpacity
            style={styles.backBtn}
            onPress={() => router.back()}
            activeOpacity={0.7}
          >
            <ArrowLeft size={20} color="#B8860B" />
          </TouchableOpacity>

          <View style={styles.headerRow}>
            <View style={{ flex: 1 }}>
              <Text style={styles.eyebrow}>{channelName ?? 'CANAL'}</Text>
              <Text style={styles.title}>Mi Inventario</Text>
            </View>
            <TouchableOpacity
              style={styles.addBtn}
              onPress={() =>
                router.push({
                  pathname: '/inventory/bulk-add' as any,
                  params: { channelId, channelName },
                })
              }
              activeOpacity={0.85}
            >
              <Plus size={18} color="#0D0D0D" strokeWidth={3} />
              <Text style={styles.addBtnText}>Agregar</Text>
            </TouchableOpacity>
          </View>

          {loading ? (
            <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
          ) : inventory.length === 0 ? (
            <TouchableOpacity
              style={styles.emptyCard}
              activeOpacity={0.85}
              onPress={() =>
                router.push({
                  pathname: '/inventory/bulk-add' as any,
                  params: { channelId, channelName },
                })
              }
            >
              <Package size={32} color="rgba(255,255,255,0.2)" />
              <Text style={styles.emptyText}>Sin productos en inventario.</Text>
              <Text style={[styles.emptyText, { color: '#B8860B', marginTop: 8 }]}>
                Toca para agregar el primer modelo
              </Text>
            </TouchableOpacity>
          ) : (
            inventory.map((item, idx) => {
              const remaining = item.stock - item.sold;
              return (
                <MotiView
                  key={item.id}
                  from={{ opacity: 0, translateX: -12 }}
                  animate={{ opacity: 1, translateX: 0 }}
                  transition={{ type: 'timing', duration: 300, delay: idx * 50 }}
                >
                  <View style={styles.itemCard}>
                    {item.image_url
                      ? <Image source={{ uri: item.image_url }} style={styles.itemImage} />
                      : <View style={styles.itemImagePlaceholder}>
                          <Image source={require('../../assets/images/logo-icon.png')} style={{ width: 28, height: 28, opacity: 0.3 }} resizeMode="contain" />
                        </View>}
                    <View style={styles.itemBody}>
                      <Text style={styles.itemName}>{item.product_name}</Text>
                      <Text style={styles.itemMeta}>
                        Talla {item.size}{item.color ? ` · ${item.color}` : ''}
                      </Text>
                      <Text style={styles.itemPrice}>${item.price.toFixed(2)} MXN</Text>
                    </View>

                    {/* Ajuste rápido de stock: sirve para reponer o corregir
                        mermas sin volver al admin. Nunca deja bajar de lo ya
                        vendido, para no romper la trazabilidad. */}
                    <View style={styles.stockCol}>
                      <View style={[styles.stockBadge, getStockStyle(remaining)]}>
                        {busyId === item.id ? (
                          <ActivityIndicator size="small" color={getStockTextColor(remaining)} />
                        ) : (
                          <>
                            <Text style={[styles.stockNumber, { color: getStockTextColor(remaining) }]}>
                              {remaining}
                            </Text>
                            <Text style={[styles.stockLabel, { color: getStockTextColor(remaining) }]}>
                              {remaining === 1 ? 'par' : 'pares'}
                            </Text>
                          </>
                        )}
                      </View>
                      <View style={styles.stockAdjustRow}>
                        <TouchableOpacity
                          style={styles.stockAdjustBtn}
                          onPress={() => adjustStock(item, -1)}
                          disabled={busyId !== null || remaining === 0}
                          activeOpacity={0.7}
                        >
                          <Minus size={12} color="rgba(255,255,255,0.7)" />
                        </TouchableOpacity>
                        <TouchableOpacity
                          style={styles.stockAdjustBtn}
                          onPress={() => adjustStock(item, +1)}
                          disabled={busyId !== null}
                          activeOpacity={0.7}
                        >
                          <Plus size={12} color="rgba(255,255,255,0.7)" />
                        </TouchableOpacity>
                      </View>
                    </View>
                  </View>
                </MotiView>
              );
            })
          )}

          <View style={{ height: 60 }} />
        </MotiView>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
  },
  scroll: {
    padding: 24,
    paddingBottom: 60,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  eyebrow: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 3,
    textTransform: 'uppercase',
    marginBottom: 4,
  },
  title: {
    fontSize: 32,
    color: '#fff',
    fontWeight: '700',
    marginBottom: 24,
  },
  emptyCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 40,
    alignItems: 'center',
    gap: 14,
  },
  emptyText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
  },
  itemCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 12,
    marginBottom: 10,
    gap: 12,
  },
  itemImage: {
    width: 52,
    height: 52,
    borderRadius: 10,
  },
  itemImagePlaceholder: {
    width: 52,
    height: 52,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  itemBody: {
    flex: 1,
  },
  itemName: {
    fontSize: 15,
    color: '#fff',
    fontWeight: '600',
  },
  itemMeta: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
  },
  itemPrice: {
    fontSize: 13,
    color: '#B8860B',
    fontWeight: '700',
    marginTop: 4,
  },
  stockBadge: {
    width: 56,
    height: 56,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stockGreen: { backgroundColor: 'rgba(76,175,80,0.15)' },
  stockYellow: { backgroundColor: 'rgba(255,193,7,0.15)' },
  stockRed: { backgroundColor: 'rgba(255,107,107,0.15)' },
  stockNumber: {
    fontSize: 20,
    fontWeight: '700',
  },
  stockLabel: {
    fontSize: 9,
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginBottom: 20,
  },
  addBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: '#B8860B',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 24,
  },
  addBtnText: { color: '#0D0D0D', fontSize: 13, fontWeight: '800' },
  stockCol: {
    alignItems: 'center',
    gap: 6,
  },
  stockAdjustRow: {
    flexDirection: 'row',
    gap: 6,
  },
  stockAdjustBtn: {
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: 'rgba(255,255,255,0.06)',
    justifyContent: 'center',
    alignItems: 'center',
  },
});
