import React, { useCallback } from 'react';
import {
  View, Text, StyleSheet, ScrollView,
  TouchableOpacity, StatusBar, ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, QrCode, Hash, CheckCircle2, Clock } from 'lucide-react-native';
import { useState } from 'react';
import { supabase } from '@/lib/supabase';

interface SaleItem {
  product_name: string;
  size: string;
  color?: string;
  quantity: number;
  unit_price: number;
}

interface Sale {
  id: string;
  code: string;
  customer_phone: string | null;
  items: SaleItem[];
  total: number;
  points_earned: number;
  claimed_at: string | null;
  created_at: string;
}

export default function SalesTodayScreen() {
  const { channelId, channelName } = useLocalSearchParams<{
    channelId: string;
    channelName: string;
  }>();

  const [sales, setSales] = useState<Sale[]>([]);
  const [loading, setLoading] = useState(true);

  useFocusEffect(
    useCallback(() => {
      if (!channelId) return;
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      setLoading(true);
      supabase
        .from('offline_sales')
        .select('id, code, customer_phone, items, total, points_earned, claimed_at, created_at')
        .eq('channel_id', channelId)
        .gte('created_at', today.toISOString())
        .order('created_at', { ascending: false })
        .then(({ data }) => {
          setSales((data ?? []) as Sale[]);
          setLoading(false);
        });
    }, [channelId]),
  );

  const totalRevenue = sales.reduce((s, v) => s + Number(v.total), 0);
  const totalPairs = sales.reduce((s, v) =>
    s + v.items.reduce((a, i) => a + (i.quantity ?? 1), 0), 0);

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <View style={styles.topBar}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.7}>
          <ArrowLeft size={20} color="#B8860B" />
        </TouchableOpacity>
        <Text style={styles.title}>Ventas de hoy</Text>
        <View style={{ width: 40 }} />
      </View>

      {loading ? (
        <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
      ) : (
        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scroll}>
          {/* Summary bar */}
          <MotiView
            from={{ opacity: 0, translateY: 10 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 350 }}
            style={styles.summaryBar}
          >
            <View style={styles.summaryItem}>
              <Text style={styles.summaryValue}>{sales.length}</Text>
              <Text style={styles.summaryLabel}>ventas</Text>
            </View>
            <View style={styles.summaryDivider} />
            <View style={styles.summaryItem}>
              <Text style={styles.summaryValue}>{totalPairs}</Text>
              <Text style={styles.summaryLabel}>pares</Text>
            </View>
            <View style={styles.summaryDivider} />
            <View style={styles.summaryItem}>
              <Text style={[styles.summaryValue, { color: '#B8860B' }]}>
                ${totalRevenue.toLocaleString('es-MX', { minimumFractionDigits: 0 })}
              </Text>
              <Text style={styles.summaryLabel}>total</Text>
            </View>
          </MotiView>

          {sales.length === 0 ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyText}>No hay ventas registradas hoy.</Text>
            </View>
          ) : (
            sales.map((sale, idx) => {
              const isQR = sale.code.startsWith('QR-');
              const isClaimed = !!sale.claimed_at;
              const time = new Date(sale.created_at).toLocaleTimeString('es-MX', {
                hour: '2-digit', minute: '2-digit',
              });

              return (
                <MotiView
                  key={sale.id}
                  from={{ opacity: 0, translateX: -10 }}
                  animate={{ opacity: 1, translateX: 0 }}
                  transition={{ type: 'timing', duration: 280, delay: idx * 50 }}
                >
                  <View style={styles.saleCard}>
                    <View style={styles.saleHeader}>
                      <View style={styles.saleCodeRow}>
                        {isQR
                          ? <QrCode size={14} color="#B8860B" />
                          : <Hash size={14} color="#B8860B" />
                        }
                        <Text style={styles.saleCode}>{sale.code}</Text>
                      </View>
                      <View style={styles.saleRight}>
                        <Text style={styles.saleTime}>{time}</Text>
                        {isClaimed
                          ? <CheckCircle2 size={16} color="#4CAF50" />
                          : <Clock size={16} color="rgba(255,255,255,0.3)" />
                        }
                      </View>
                    </View>

                    {sale.customer_phone && (
                      <Text style={styles.salePhone}>{sale.customer_phone}</Text>
                    )}

                    <View style={styles.itemsList}>
                      {sale.items.map((item, i) => (
                        <View key={i} style={styles.itemRow}>
                          <Text style={styles.itemName} numberOfLines={1}>
                            {item.product_name} · T{item.size}
                            {item.color ? ` · ${item.color}` : ''}
                            {item.quantity > 1 ? ` x${item.quantity}` : ''}
                          </Text>
                          <Text style={styles.itemPrice}>
                            ${(item.unit_price * item.quantity).toFixed(0)}
                          </Text>
                        </View>
                      ))}
                    </View>

                    <View style={styles.saleTotalRow}>
                      <Text style={styles.saleTotalLabel}>
                        {isClaimed ? '✓ Puntos acreditados' : 'Pendiente de reclamar'}
                      </Text>
                      <Text style={styles.saleTotalValue}>
                        ${Number(sale.total).toLocaleString('es-MX', { minimumFractionDigits: 0 })}
                      </Text>
                    </View>
                  </View>
                </MotiView>
              );
            })
          )}

          <View style={{ height: 40 }} />
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center', alignItems: 'center',
  },
  title: { fontSize: 18, color: '#fff', fontWeight: '700' },
  scroll: { padding: 20 },
  summaryBar: {
    flexDirection: 'row',
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 20,
    marginBottom: 20,
  },
  summaryItem: { flex: 1, alignItems: 'center' },
  summaryValue: { fontSize: 24, color: '#fff', fontWeight: '700' },
  summaryLabel: { fontSize: 10, color: 'rgba(255,255,255,0.4)', marginTop: 2, textTransform: 'uppercase', letterSpacing: 0.5 },
  summaryDivider: { width: 1, backgroundColor: 'rgba(255,255,255,0.08)' },
  emptyCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: 32, alignItems: 'center',
  },
  emptyText: { color: 'rgba(255,255,255,0.4)', fontSize: 13, textAlign: 'center' },
  saleCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: 16, marginBottom: 10,
  },
  saleHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 },
  saleCodeRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  saleCode: { fontSize: 14, color: '#B8860B', fontWeight: '800', letterSpacing: 1 },
  saleRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  saleTime: { fontSize: 12, color: 'rgba(255,255,255,0.4)' },
  salePhone: { fontSize: 12, color: 'rgba(255,255,255,0.35)', marginBottom: 10 },
  itemsList: { borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.06)', paddingTop: 10, marginTop: 4, gap: 6 },
  itemRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  itemName: { fontSize: 13, color: 'rgba(255,255,255,0.7)', flex: 1, marginRight: 8 },
  itemPrice: { fontSize: 13, color: '#fff', fontWeight: '600' },
  saleTotalRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.06)',
    marginTop: 10, paddingTop: 10,
  },
  saleTotalLabel: { fontSize: 11, color: 'rgba(255,255,255,0.3)' },
  saleTotalValue: { fontSize: 16, color: '#fff', fontWeight: '700' },
});
