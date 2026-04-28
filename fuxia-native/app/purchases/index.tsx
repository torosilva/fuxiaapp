import React, { useEffect, useMemo, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
  Image,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Redirect, router, Stack } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, ChevronDown, ChevronUp } from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import type { Channel } from '@/lib/database.types';

interface PurchaseItem {
  id: string;
  sku: string;
  product_name: string;
  size: string | null;
  color: string | null;
  quantity: number;
  unit_price: number | null;
}

interface Purchase {
  id: string;
  wc_order_id: number | null;
  created_at: string;
  points_earned: number;
  channel: Channel;
  items: PurchaseItem[];
}

const MONTHS_ES = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

function monthKey(iso: string) {
  const d = new Date(iso);
  return `${MONTHS_ES[d.getMonth()]} ${d.getFullYear()}`;
}

function formatDay(iso: string) {
  const d = new Date(iso);
  return `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}`;
}

export default function PurchaseHistoryScreen() {
  const { session, loyaltyCard, isLoading } = useAuth();
  const [purchases, setPurchases] = useState<Purchase[]>([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!loyaltyCard) return;
    loadPurchases(loyaltyCard.id);
  }, [loyaltyCard?.id]);

  async function loadPurchases(cardId: string) {
    setLoading(true);
    const { data } = await supabase
      .from('transactions')
      .select('id, wc_order_id, created_at, points_earned, channel, purchase_items(id, sku, product_name, size, color, quantity, unit_price)')
      .eq('loyalty_card_id', cardId)
      .order('created_at', { ascending: false });

    const mapped: Purchase[] = (data ?? []).map((row: any) => ({
      id: row.id,
      wc_order_id: row.wc_order_id,
      created_at: row.created_at,
      points_earned: row.points_earned,
      channel: row.channel,
      items: row.purchase_items ?? [],
    }));
    setPurchases(mapped);
    setLoading(false);
  }

  const grouped = useMemo(() => {
    const map = new Map<string, Purchase[]>();
    for (const p of purchases) {
      const key = monthKey(p.created_at);
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(p);
    }
    return Array.from(map.entries());
  }, [purchases]);

  const totalPairs = useMemo(
    () => purchases.reduce((sum, p) => sum + p.items.reduce((s, i) => s + i.quantity, 0), 0),
    [purchases],
  );

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator color="#CD7F32" />
      </SafeAreaView>
    );
  }

  if (!session || !loyaltyCard) {
    return <Redirect href="/onboarding" />;
  }

  const toggle = (id: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>
        <View>
          <Text style={styles.eyebrow}>MIS ZAPATOS</Text>
          <Text style={styles.title}>{totalPairs} {totalPairs === 1 ? 'par' : 'pares'}</Text>
        </View>
        <View style={{ width: 40 }} />
      </View>

      {loading ? (
        <View style={styles.center}>
          <ActivityIndicator color="#CD7F32" />
        </View>
      ) : purchases.length === 0 ? (
        <View style={styles.emptyState}>
          <Text style={styles.emptyTitle}>Tus compras aparecerán aquí</Text>
          <Text style={styles.emptySubtitle}>
            Cada par que compres sumará puntos a tu tarjeta de lealtad.
          </Text>
        </View>
      ) : (
        <ScrollView
          contentContainerStyle={styles.scroll}
          showsVerticalScrollIndicator={false}
        >
          {grouped.map(([month, list]) => (
            <View key={month} style={styles.monthSection}>
              <Text style={styles.monthLabel}>{month.toUpperCase()}</Text>
              {list.map((p, i) => (
                <MotiView
                  key={p.id}
                  from={{ opacity: 0, translateY: 10 }}
                  animate={{ opacity: 1, translateY: 0 }}
                  transition={{ delay: 50 + i * 60, type: 'timing', duration: 300 }}
                >
                  <TouchableOpacity
                    style={styles.card}
                    onPress={() => toggle(p.id)}
                    activeOpacity={0.85}
                  >
                    <View style={styles.cardHeader}>
                      <View style={styles.channelBadge}>
                        <Text style={styles.channelEmoji}>
                          {p.channel === 'store' ? '🏪' : '🌐'}
                        </Text>
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.cardTitle}>
                          {p.items[0]?.product_name ?? 'Compra'}
                          {p.items.length > 1 ? ` +${p.items.length - 1}` : ''}
                        </Text>
                        <Text style={styles.cardDate}>
                          {formatDay(p.created_at)}{p.wc_order_id ? ` · #${p.wc_order_id}` : ''}
                        </Text>
                      </View>
                      <View style={styles.ptsBadge}>
                        <Text style={styles.ptsText}>+{p.points_earned} pts</Text>
                      </View>
                      {expanded.has(p.id)
                        ? <ChevronUp size={16} color="rgba(255,255,255,0.4)" style={{ marginLeft: 8 }} />
                        : <ChevronDown size={16} color="rgba(255,255,255,0.4)" style={{ marginLeft: 8 }} />}
                    </View>

                    {expanded.has(p.id) && (
                      <View style={styles.itemsList}>
                        {p.items.map((item) => (
                          <View key={item.id} style={styles.itemRow}>
                            <View style={styles.itemThumb}>
                              <Text style={styles.itemThumbText}>👟</Text>
                            </View>
                            <View style={{ flex: 1 }}>
                              <Text style={styles.itemName}>{item.product_name}</Text>
                              <View style={styles.chipsRow}>
                                {item.size ? <Text style={styles.chip}>Talla {item.size}</Text> : null}
                                {item.color ? <Text style={styles.chip}>{item.color}</Text> : null}
                                <Text style={styles.chip}>x{item.quantity}</Text>
                              </View>
                            </View>
                            {item.unit_price ? (
                              <Text style={styles.itemPrice}>
                                ${item.unit_price.toLocaleString('es-MX')}
                              </Text>
                            ) : null}
                          </View>
                        ))}
                      </View>
                    )}
                  </TouchableOpacity>
                </MotiView>
              ))}
            </View>
          ))}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
  },
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  eyebrow: {
    fontSize: 10,
    color: '#CD7F32',
    fontWeight: '800',
    letterSpacing: 3,
    marginBottom: 2,
    textAlign: 'center',
  },
  title: {
    fontSize: 20,
    color: '#FFFFFF',
    fontFamily: 'serif',
    textAlign: 'center',
  },
  scroll: {
    padding: 20,
    paddingBottom: 140,
  },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 40,
  },
  emptyTitle: {
    color: '#FFFFFF',
    fontSize: 18,
    fontFamily: 'serif',
    marginBottom: 8,
    textAlign: 'center',
  },
  emptySubtitle: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
    lineHeight: 20,
  },
  monthSection: {
    marginBottom: 24,
  },
  monthLabel: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 2,
    marginBottom: 10,
  },
  card: {
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    padding: 14,
    marginBottom: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  channelBadge: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  channelEmoji: {
    fontSize: 16,
  },
  cardTitle: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '600',
  },
  cardDate: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 11,
    marginTop: 2,
  },
  ptsBadge: {
    backgroundColor: 'rgba(205,127,50,0.15)',
    borderRadius: 12,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  ptsText: {
    color: '#CD7F32',
    fontSize: 11,
    fontWeight: '700',
  },
  itemsList: {
    marginTop: 12,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.05)',
    gap: 10,
  },
  itemRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  itemThumb: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  itemThumbText: {
    fontSize: 18,
  },
  itemName: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '500',
  },
  chipsRow: {
    flexDirection: 'row',
    gap: 6,
    marginTop: 4,
    flexWrap: 'wrap',
  },
  chip: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 10,
    backgroundColor: 'rgba(255,255,255,0.05)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
  },
  itemPrice: {
    color: '#CD7F32',
    fontSize: 12,
    fontWeight: '600',
  },
});
