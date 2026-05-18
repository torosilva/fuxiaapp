import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Package } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface InventoryItem {
  id: string;
  product_name: string;
  size: string;
  color: string | null;
  price: number;
  stock: number;
  sold: number;
}

export default function VendedoraInventoryScreen() {
  const { channelId, channelName } = useLocalSearchParams<{
    channelId: string;
    channelName: string;
  }>();

  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchInventory = useCallback(async () => {
    if (!channelId) return;
    setLoading(true);
    const { data } = await supabase
      .from('channel_inventory')
      .select('id, product_name, size, color, price, stock, sold')
      .eq('channel_id', channelId)
      .order('product_name');
    if (data) setInventory(data as InventoryItem[]);
    setLoading(false);
  }, [channelId]);

  useEffect(() => {
    fetchInventory();
  }, [fetchInventory]);

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

          <Text style={styles.eyebrow}>{channelName ?? 'CANAL'}</Text>
          <Text style={styles.title}>Mi Inventario</Text>

          {loading ? (
            <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
          ) : inventory.length === 0 ? (
            <View style={styles.emptyCard}>
              <Package size={32} color="rgba(255,255,255,0.2)" />
              <Text style={styles.emptyText}>Sin productos en inventario.</Text>
            </View>
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
                    <View style={styles.itemBody}>
                      <Text style={styles.itemName}>{item.product_name}</Text>
                      <Text style={styles.itemMeta}>
                        Talla {item.size}{item.color ? ` · ${item.color}` : ''}
                      </Text>
                      <Text style={styles.itemPrice}>${item.price.toFixed(2)} MXN</Text>
                    </View>
                    <View style={[styles.stockBadge, getStockStyle(remaining)]}>
                      <Text style={[styles.stockNumber, { color: getStockTextColor(remaining) }]}>
                        {remaining}
                      </Text>
                      <Text style={[styles.stockLabel, { color: getStockTextColor(remaining) }]}>
                        {remaining === 1 ? 'par' : 'pares'}
                      </Text>
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
    padding: 16,
    marginBottom: 10,
    gap: 14,
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
});
