import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import { Plus, Store, ShoppingBag, User, TrendingUp, Package } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface Channel {
  id: string;
  name: string;
  type: 'store' | 'bazar';
  location: string | null;
  active: boolean;
}

interface Staff {
  id: string;
  name: string;
  pin: string;
  channel_id: string | null;
  active: boolean;
  channels: { name: string } | null;
}

interface ChannelSummary {
  channel_id: string;
  channel_name: string;
  total_stock: number;
  total_sold: number;
  total_revenue: number;
  sales_count: number;
}

export default function AdminHomeScreen() {
  const [channels, setChannels] = useState<Channel[]>([]);
  const [staff, setStaff] = useState<Staff[]>([]);
  const [summaries, setSummaries] = useState<ChannelSummary[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [channelsRes, staffRes, inventoryRes, salesRes] = await Promise.all([
      supabase.from('channels').select('id, name, type, location, active').order('created_at', { ascending: false }),
      supabase.from('staff').select('id, name, pin, channel_id, active, channels(name)').order('created_at', { ascending: false }),
      supabase.from('channel_inventory').select('channel_id, stock, sold'),
      supabase.from('offline_sales').select('channel_id, total').not('channel_id', 'is', null),
    ]);

    if (channelsRes.data) setChannels(channelsRes.data as Channel[]);
    if (staffRes.data) setStaff(staffRes.data as unknown as Staff[]);

    // Build per-channel summaries client-side
    if (channelsRes.data && inventoryRes.data && salesRes.data) {
      const inv = inventoryRes.data as { channel_id: string; stock: number; sold: number }[];
      const sales = salesRes.data as { channel_id: string; total: number }[];

      const built: ChannelSummary[] = (channelsRes.data as Channel[]).map((ch) => {
        const chInv = inv.filter((i) => i.channel_id === ch.id);
        const chSales = sales.filter((s) => s.channel_id === ch.id);
        return {
          channel_id: ch.id,
          channel_name: ch.name,
          total_stock: chInv.reduce((s, i) => s + (i.stock ?? 0), 0),
          total_sold: chInv.reduce((s, i) => s + (i.sold ?? 0), 0),
          total_revenue: chSales.reduce((s, v) => s + Number(v.total ?? 0), 0),
          sales_count: chSales.length,
        };
      }).filter((s) => s.total_stock > 0 || s.sales_count > 0);

      setSummaries(built);
    }

    setLoading(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      fetchData();
    }, [fetchData]),
  );

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scroll}>
        <MotiView
          from={{ opacity: 0, translateY: 16 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 400 }}
        >
          <Text style={styles.eyebrow}>FUXIA BALLERINAS</Text>
          <Text style={styles.title}>Panel Admin</Text>

          {/* Resumen de ventas */}
          {summaries.length > 0 && (
            <MotiView
              from={{ opacity: 0, translateY: 12 }}
              animate={{ opacity: 1, translateY: 0 }}
              transition={{ type: 'timing', duration: 400 }}
            >
              <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Resumen de Ventas</Text>
                <TrendingUp size={18} color="#B8860B" />
              </View>
              {summaries.map((s) => (
                <View key={s.channel_id} style={styles.summaryCard}>
                  <Text style={styles.summaryName}>{s.channel_name}</Text>
                  <View style={styles.summaryRow}>
                    <View style={styles.summaryItem}>
                      <Text style={styles.summaryValue}>{s.total_sold}</Text>
                      <Text style={styles.summaryLabel}>pares vendidos</Text>
                    </View>
                    <View style={styles.summaryDivider} />
                    <View style={styles.summaryItem}>
                      <Text style={styles.summaryValue}>{s.total_stock - s.total_sold}</Text>
                      <Text style={styles.summaryLabel}>restantes</Text>
                    </View>
                    <View style={styles.summaryDivider} />
                    <View style={styles.summaryItem}>
                      <Text style={[styles.summaryValue, { color: '#B8860B' }]}>
                        ${s.total_revenue.toLocaleString('es-MX', { minimumFractionDigits: 0 })}
                      </Text>
                      <Text style={styles.summaryLabel}>recaudado</Text>
                    </View>
                  </View>
                  <View style={styles.stockBar}>
                    <View
                      style={[
                        styles.stockBarFill,
                        {
                          width: s.total_stock > 0
                            ? `${Math.min(100, (s.total_sold / s.total_stock) * 100)}%`
                            : '0%',
                        },
                      ]}
                    />
                  </View>
                  <Text style={styles.stockBarLabel}>
                    {s.total_stock > 0
                      ? `${Math.round((s.total_sold / s.total_stock) * 100)}% vendido`
                      : 'Sin inventario'}
                  </Text>
                </View>
              ))}
            </MotiView>
          )}

          {/* Canales */}
          <View style={[styles.sectionHeader, summaries.length > 0 && { marginTop: 28 }]}>
            <Text style={styles.sectionTitle}>Canales</Text>
            <TouchableOpacity
              style={styles.addBtn}
              onPress={() => router.push('/admin/channel-new' as any)}
              activeOpacity={0.8}
            >
              <Plus size={16} color="#0D0D0D" />
            </TouchableOpacity>
          </View>

          {loading ? (
            <ActivityIndicator color="#B8860B" style={{ marginVertical: 20 }} />
          ) : channels.length === 0 ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyText}>Sin canales. Crea uno con el botón +</Text>
            </View>
          ) : (
            channels.map((ch, idx) => (
              <MotiView
                key={ch.id}
                from={{ opacity: 0, translateX: -12 }}
                animate={{ opacity: 1, translateX: 0 }}
                transition={{ type: 'timing', duration: 300, delay: idx * 60 }}
              >
                <TouchableOpacity
                  style={styles.card}
                  onPress={() => router.push(`/admin/channel/${ch.id}` as any)}
                  activeOpacity={0.8}
                >
                  <View style={styles.cardIcon}>
                    {ch.type === 'store' ? (
                      <Store size={20} color="#B8860B" />
                    ) : (
                      <ShoppingBag size={20} color="#B8860B" />
                    )}
                  </View>
                  <View style={styles.cardBody}>
                    <Text style={styles.cardTitle}>{ch.name}</Text>
                    {ch.location ? (
                      <Text style={styles.cardSub}>{ch.location}</Text>
                    ) : null}
                  </View>
                  <View style={styles.cardRight}>
                    <View style={[styles.typeBadge, ch.type === 'bazar' && styles.typeBadgeBazar]}>
                      <Text style={styles.typeBadgeText}>
                        {ch.type === 'store' ? 'TIENDA' : 'BAZAR'}
                      </Text>
                    </View>
                    <View style={[styles.statusDot, ch.active ? styles.dotActive : styles.dotInactive]} />
                  </View>
                </TouchableOpacity>
              </MotiView>
            ))
          )}

          {/* Vendedoras */}
          <View style={[styles.sectionHeader, { marginTop: 32 }]}>
            <Text style={styles.sectionTitle}>Vendedoras</Text>
            <TouchableOpacity
              style={styles.addBtn}
              onPress={() => router.push('/admin/staff-new' as any)}
              activeOpacity={0.8}
            >
              <Plus size={16} color="#0D0D0D" />
            </TouchableOpacity>
          </View>

          {loading ? (
            <ActivityIndicator color="#B8860B" style={{ marginVertical: 20 }} />
          ) : staff.length === 0 ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyText}>Sin vendedoras. Agrega una con el botón +</Text>
            </View>
          ) : (
            staff.map((s, idx) => (
              <MotiView
                key={s.id}
                from={{ opacity: 0, translateX: -12 }}
                animate={{ opacity: 1, translateX: 0 }}
                transition={{ type: 'timing', duration: 300, delay: idx * 60 }}
              >
                <View style={styles.card}>
                  <View style={styles.cardIcon}>
                    <User size={20} color="#B8860B" />
                  </View>
                  <View style={styles.cardBody}>
                    <Text style={styles.cardTitle}>{s.name}</Text>
                    <Text style={styles.cardSub}>
                      PIN: ****  ·  {s.channels?.name ?? 'Sin canal'}
                    </Text>
                  </View>
                  <View style={[styles.statusDot, s.active ? styles.dotActive : styles.dotInactive]} />
                </View>
              </MotiView>
            ))
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
  },
  eyebrow: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 3,
    marginBottom: 4,
  },
  title: {
    fontSize: 32,
    color: '#fff',
    fontWeight: '700',
    marginBottom: 32,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 18,
    color: '#fff',
    fontWeight: '600',
  },
  addBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#B8860B',
    justifyContent: 'center',
    alignItems: 'center',
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 16,
    marginBottom: 10,
    gap: 12,
  },
  cardIcon: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  cardBody: {
    flex: 1,
  },
  cardTitle: {
    fontSize: 15,
    color: '#fff',
    fontWeight: '600',
  },
  cardSub: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
  },
  cardRight: {
    alignItems: 'flex-end',
    gap: 6,
  },
  typeBadge: {
    backgroundColor: 'rgba(184,134,11,0.2)',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  typeBadgeBazar: {
    backgroundColor: 'rgba(128,0,128,0.2)',
  },
  typeBadgeText: {
    fontSize: 9,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 1,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  dotActive: {
    backgroundColor: '#4CAF50',
  },
  dotInactive: {
    backgroundColor: 'rgba(255,255,255,0.2)',
  },
  summaryCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 16,
    marginBottom: 10,
  },
  summaryName: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '700',
    marginBottom: 14,
  },
  summaryRow: {
    flexDirection: 'row',
    marginBottom: 14,
  },
  summaryItem: {
    flex: 1,
    alignItems: 'center',
  },
  summaryValue: {
    fontSize: 22,
    color: '#fff',
    fontWeight: '700',
  },
  summaryLabel: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  summaryDivider: {
    width: 1,
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  stockBar: {
    height: 4,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 2,
    overflow: 'hidden',
    marginBottom: 6,
  },
  stockBarFill: {
    height: 4,
    backgroundColor: '#B8860B',
    borderRadius: 2,
  },
  stockBarLabel: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.3)',
    textAlign: 'right',
  },
  emptyCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 24,
    alignItems: 'center',
    marginBottom: 10,
  },
  emptyText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
  },
});
