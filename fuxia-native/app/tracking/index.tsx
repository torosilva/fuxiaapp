import React, { useEffect, useState, useMemo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
  Linking,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Redirect, router, Stack } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Package, Truck, CheckCircle2, Clock, ExternalLink } from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';
import { wcService, WCOrder, WCOrderStatus } from '@/services/WooCommerceService';
import { formatMoney } from '@/lib/CountryService';
import { supabase } from '@/lib/supabase';

interface StoreTx {
  id: string;
  created_at: string;
  points_earned: number;
  first_item: string;
}

interface UnclaimedSale {
  id: string;
  created_at: string;
  code: string;
  first_item: string;
  total: number;
}

const TRACKING_STATUSES: WCOrderStatus[] = ['pending', 'processing', 'on-hold'];

const STATUS_LABEL_ES: Record<WCOrderStatus, string> = {
  pending: 'Pendiente de pago',
  processing: 'Procesando',
  'on-hold': 'En espera',
  completed: 'Entregado',
  cancelled: 'Cancelado',
  refunded: 'Reembolsado',
  failed: 'Falló',
};

const STATUS_STAGE: Record<WCOrderStatus, number> = {
  pending: 0,
  'on-hold': 0,
  processing: 1,
  completed: 3,
  cancelled: -1,
  refunded: -1,
  failed: -1,
};

const STAGES = [
  { key: 'paid', label: 'Pagado', icon: CheckCircle2 },
  { key: 'preparing', label: 'Preparando', icon: Package },
  { key: 'shipped', label: 'En camino', icon: Truck },
  { key: 'delivered', label: 'Entregado', icon: CheckCircle2 },
];

const formatDate = (iso: string) => {
  const d = new Date(iso);
  return d.toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' });
};


interface TrackingMeta {
  trackingNumber: string | null;
  trackingProvider: string | null;
  trackingUrl: string | null;
}

function extractTrackingMeta(order: WCOrder): TrackingMeta {
  const map = new Map(order.meta_data?.map((m) => [m.key.toLowerCase(), m.value]) ?? []);
  const trackingNumber =
    map.get('_tracking_number') ?? map.get('tracking_number') ?? map.get('_aftership_tracking_number') ?? null;
  const trackingProvider =
    map.get('_tracking_provider') ?? map.get('tracking_provider') ?? map.get('_aftership_tracking_provider') ?? null;
  const trackingUrl = map.get('_tracking_url') ?? map.get('tracking_url') ?? null;
  return { trackingNumber, trackingProvider, trackingUrl };
}

export default function TrackingScreen() {
  const { session, customer, loyaltyCard, isLoading } = useAuth();
  const [orders, setOrders] = useState<WCOrder[]>([]);
  const [storeTxs, setStoreTxs] = useState<StoreTx[]>([]);
  const [unclaimedSales, setUnclaimedSales] = useState<UnclaimedSale[]>([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState<Set<number>>(new Set());

  useEffect(() => {
    if (!customer) return;
    (async () => {
      setLoading(true);
      const [wcData, txRes, unclaimedRes] = await Promise.all([
        wcService.getOrdersByCustomer({
          customerId: (customer as any).wc_customer_id ?? undefined,
          email: customer.email ?? undefined,
          statuses: TRACKING_STATUSES,
          limit: 30,
        }),
        loyaltyCard?.id
          ? supabase
              .from('transactions')
              .select('id, created_at, points_earned, purchase_items(product_name)')
              .eq('loyalty_card_id', loyaltyCard.id)
              .eq('channel', 'store')
              .order('created_at', { ascending: false })
              .limit(10)
          : Promise.resolve({ data: [] }),
        customer.phone
          ? supabase
              .from('offline_sales')
              .select('id, created_at, code, items, total')
              .eq('customer_phone', customer.phone)
              .is('claimed_at', null)
              .order('created_at', { ascending: false })
          : Promise.resolve({ data: [] }),
      ]);

      setOrders(wcData);

      setStoreTxs(
        ((txRes as any).data ?? []).map((r: any) => ({
          id: r.id,
          created_at: r.created_at,
          points_earned: r.points_earned,
          first_item: r.purchase_items?.[0]?.product_name ?? 'Compra en tienda',
        }))
      );

      setUnclaimedSales(
        ((unclaimedRes as any).data ?? []).map((r: any) => ({
          id: r.id,
          created_at: r.created_at,
          code: r.code,
          first_item: r.items?.[0]?.product_name ?? 'Compra en tienda',
          total: r.total ?? 0,
        }))
      );

      setLoading(false);
    })();
  }, [customer?.id, loyaltyCard?.id]);

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator color="#CD7F32" />
      </SafeAreaView>
    );
  }

  if (!session || !customer) return <Redirect href="/onboarding" />;

  const toggle = (id: number) => {
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
          <Text style={styles.eyebrow}>EN CAMINO</Text>
          <Text style={styles.title}>Seguimiento</Text>
        </View>
        <View style={{ width: 40 }} />
      </View>

      {loading ? (
        <View style={styles.center}>
          <ActivityIndicator color="#CD7F32" />
        </View>
      ) : (
        <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>

          {/* ── Pedidos web (WooCommerce) ── */}
          {orders.length > 0 && (
            <>
              <Text style={styles.sectionLabel}>PEDIDOS EN LÍNEA</Text>
              {orders.map((o, i) => {
            const stage = STATUS_STAGE[o.status] ?? 0;
            const isOpen = expanded.has(o.id);
            const tracking = extractTrackingMeta(o);

            return (
              <MotiView
                key={o.id}
                from={{ opacity: 0, translateY: 12 }}
                animate={{ opacity: 1, translateY: 0 }}
                transition={{ type: 'timing', duration: 350, delay: i * 70 }}
                style={styles.orderCard}
              >
                <TouchableOpacity onPress={() => toggle(o.id)} activeOpacity={0.85}>
                  <View style={styles.orderHeader}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.orderTitle}>Pedido #{o.number}</Text>
                      <Text style={styles.orderDate}>{formatDate(o.date_created)}</Text>
                    </View>
                    <View style={styles.statusBadge}>
                      <Clock size={11} color="#CD7F32" />
                      <Text style={styles.statusText}>{STATUS_LABEL_ES[o.status]}</Text>
                    </View>
                  </View>

                  {/* Stage timeline */}
                  <View style={styles.timeline}>
                    {STAGES.map((s, idx) => {
                      const reached = idx <= stage;
                      const Icon = s.icon;
                      return (
                        <React.Fragment key={s.key}>
                          <View style={styles.stageWrapper}>
                            <View
                              style={[
                                styles.stageDot,
                                reached && styles.stageDotActive,
                              ]}
                            >
                              <Icon
                                size={12}
                                color={reached ? '#0D0D0D' : 'rgba(255,255,255,0.3)'}
                              />
                            </View>
                            <Text
                              style={[
                                styles.stageLabel,
                                reached && styles.stageLabelActive,
                              ]}
                            >
                              {s.label}
                            </Text>
                          </View>
                          {idx < STAGES.length - 1 && (
                            <View
                              style={[
                                styles.stageLine,
                                idx < stage && styles.stageLineActive,
                              ]}
                            />
                          )}
                        </React.Fragment>
                      );
                    })}
                  </View>

                  {isOpen && (
                    <View style={styles.detailSection}>
                      <View style={styles.row}>
                        <Text style={styles.rowLabel}>Total</Text>
                        <Text style={styles.rowValue}>
                          {formatMoney(parseFloat(o.total), o.currency)}
                        </Text>
                      </View>
                      <View style={styles.row}>
                        <Text style={styles.rowLabel}>Pago</Text>
                        <Text style={styles.rowValue}>{o.payment_method_title || 'No especificado'}</Text>
                      </View>
                      {o.shipping?.address_1 ? (
                        <View style={styles.row}>
                          <Text style={styles.rowLabel}>Envío a</Text>
                          <Text style={[styles.rowValue, { flex: 1, textAlign: 'right' }]} numberOfLines={2}>
                            {[o.shipping.address_1, o.shipping.city, o.shipping.country].filter(Boolean).join(', ')}
                          </Text>
                        </View>
                      ) : null}

                      {tracking.trackingNumber && (
                        <View style={styles.trackingBox}>
                          <Truck size={14} color="#CD7F32" />
                          <View style={{ flex: 1 }}>
                            <Text style={styles.trackingLabel}>
                              {tracking.trackingProvider ?? 'Paquete'}
                            </Text>
                            <Text style={styles.trackingNumber}>{tracking.trackingNumber}</Text>
                          </View>
                          {tracking.trackingUrl && (
                            <TouchableOpacity onPress={() => Linking.openURL(tracking.trackingUrl!)}>
                              <ExternalLink size={16} color="#CD7F32" />
                            </TouchableOpacity>
                          )}
                        </View>
                      )}

                      <View style={styles.itemsList}>
                        {o.line_items.map((it) => (
                          <View key={it.id} style={styles.itemRow}>
                            <Text style={styles.itemName}>{it.name}</Text>
                            <Text style={styles.itemQty}>x{it.quantity}</Text>
                          </View>
                        ))}
                      </View>
                    </View>
                  )}
                </TouchableOpacity>
              </MotiView>
            );
            })}
            </>
          )}

          {/* ── Puntos pendientes de reclamar ── */}
          {unclaimedSales.length > 0 && (
            <>
              <Text style={[styles.sectionLabel, { marginTop: orders.length > 0 ? 24 : 0 }]}>
                PUNTOS PENDIENTES
              </Text>
              {unclaimedSales.map((sale, i) => (
                <MotiView
                  key={sale.id}
                  from={{ opacity: 0, translateY: 10 }}
                  animate={{ opacity: 1, translateY: 0 }}
                  transition={{ type: 'timing', duration: 300, delay: i * 60 }}
                  style={[styles.orderCard, styles.pendingCard]}
                >
                  <View style={styles.orderHeader}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.orderTitle}>{sale.first_item}</Text>
                      <Text style={styles.orderDate}>{formatDate(sale.created_at)}</Text>
                    </View>
                    <View style={[styles.statusBadge, styles.pendingBadge]}>
                      <Clock size={11} color="#FFC107" />
                      <Text style={[styles.statusText, { color: '#FFC107' }]}>Puntos pendientes</Text>
                    </View>
                  </View>
                  <Text style={styles.pendingHint}>
                    Tienes una compra sin reclamar. Ingresa el código que te dio la vendedora para acumular tus puntos.
                  </Text>
                  <TouchableOpacity
                    style={styles.claimBtn}
                    onPress={() => router.push('/claim' as any)}
                    activeOpacity={0.85}
                  >
                    <Text style={styles.claimBtnText}>Reclamar puntos ahora →</Text>
                  </TouchableOpacity>
                </MotiView>
              ))}
            </>
          )}

          {/* ── Compras en tienda ya reclamadas ── */}
          {storeTxs.length > 0 && (
            <>
              <Text style={[styles.sectionLabel, { marginTop: 24 }]}>COMPRAS EN TIENDA</Text>
              {storeTxs.map((tx, i) => (
                <MotiView
                  key={tx.id}
                  from={{ opacity: 0, translateY: 10 }}
                  animate={{ opacity: 1, translateY: 0 }}
                  transition={{ type: 'timing', duration: 300, delay: i * 50 }}
                  style={styles.orderCard}
                >
                  <View style={styles.orderHeader}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.orderTitle}>{tx.first_item}</Text>
                      <Text style={styles.orderDate}>{formatDate(tx.created_at)}</Text>
                    </View>
                    <View style={[styles.statusBadge, styles.deliveredBadge]}>
                      <CheckCircle2 size={11} color="#4CAF50" />
                      <Text style={[styles.statusText, { color: '#4CAF50' }]}>Entregado</Text>
                    </View>
                  </View>
                  <View style={styles.pointsRow}>
                    <Text style={styles.pointsRowText}>Puntos acumulados</Text>
                    <Text style={styles.pointsRowValue}>+{tx.points_earned} pts</Text>
                  </View>
                </MotiView>
              ))}
            </>
          )}

          {/* Empty state when nothing at all */}
          {orders.length === 0 && storeTxs.length === 0 && unclaimedSales.length === 0 && (
            <View style={styles.emptyState}>
              <Package size={36} color="rgba(205,127,50,0.4)" />
              <Text style={styles.emptyTitle}>Sin pedidos aún</Text>
              <Text style={styles.emptySubtitle}>
                Tus pedidos en línea y compras en tienda aparecerán aquí.
              </Text>
            </View>
          )}

          <View style={{ height: 60 }} />
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
  },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 2, textAlign: 'center',
  },
  title: { fontSize: 20, color: '#FFFFFF', fontFamily: 'serif', textAlign: 'center' },
  scroll: { padding: 20, paddingBottom: 140 },
  emptyState: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 40,
    gap: 12,
  },
  emptyTitle: { color: '#FFF', fontSize: 18, fontFamily: 'serif', textAlign: 'center' },
  emptySubtitle: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
    lineHeight: 20,
  },
  orderCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 18,
    padding: 16,
    marginBottom: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  orderHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  orderTitle: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  orderDate: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },
  statusBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: 'rgba(205,127,50,0.12)',
    borderRadius: 12, paddingHorizontal: 10, paddingVertical: 4,
  },
  statusText: { color: '#CD7F32', fontSize: 11, fontWeight: '600' },
  timeline: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
  },
  stageWrapper: { alignItems: 'center', width: 64 },
  stageDot: {
    width: 28, height: 28, borderRadius: 14,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
  },
  stageDotActive: {
    backgroundColor: '#CD7F32',
    borderColor: '#CD7F32',
  },
  stageLabel: {
    color: 'rgba(255,255,255,0.3)', fontSize: 9,
    marginTop: 6, textAlign: 'center',
  },
  stageLabelActive: { color: '#CD7F32', fontWeight: '700' },
  stageLine: {
    flex: 1, height: 2, marginTop: 13,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  stageLineActive: { backgroundColor: '#CD7F32' },
  detailSection: {
    marginTop: 16,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.05)',
    gap: 8,
  },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' },
  rowLabel: { color: 'rgba(255,255,255,0.5)', fontSize: 12 },
  rowValue: { color: '#FFF', fontSize: 12, fontWeight: '500' },
  trackingBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginTop: 8,
    padding: 12,
    borderRadius: 12,
    backgroundColor: 'rgba(205,127,50,0.08)',
    borderWidth: 1,
    borderColor: 'rgba(205,127,50,0.2)',
  },
  trackingLabel: { color: 'rgba(205,127,50,0.7)', fontSize: 10, fontWeight: '600', letterSpacing: 1 },
  trackingNumber: { color: '#FFF', fontSize: 13, fontWeight: '600', marginTop: 2 },
  itemsList: { marginTop: 8 },
  itemRow: {
    flexDirection: 'row', justifyContent: 'space-between',
    paddingVertical: 6,
  },
  itemName: { color: 'rgba(255,255,255,0.7)', fontSize: 12, flex: 1 },
  itemQty: { color: '#CD7F32', fontSize: 12, fontWeight: '600' },
  sectionLabel: {
    fontSize: 10, color: 'rgba(255,255,255,0.3)',
    fontWeight: '800', letterSpacing: 2, marginBottom: 12,
  },
  pendingCard: {
    borderColor: 'rgba(255,193,7,0.2)',
    backgroundColor: 'rgba(255,193,7,0.04)',
  },
  pendingBadge: { backgroundColor: 'rgba(255,193,7,0.12)' },
  deliveredBadge: { backgroundColor: 'rgba(76,175,80,0.12)' },
  pendingHint: {
    fontSize: 12, color: 'rgba(255,255,255,0.4)',
    lineHeight: 18, marginBottom: 12,
  },
  claimBtn: {
    backgroundColor: 'rgba(255,193,7,0.15)',
    borderWidth: 1, borderColor: 'rgba(255,193,7,0.3)',
    borderRadius: 10, paddingVertical: 10, alignItems: 'center',
  },
  claimBtnText: { color: '#FFC107', fontSize: 13, fontWeight: '700' },
  pointsRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    marginTop: 10, paddingTop: 10,
    borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.05)',
  },
  pointsRowText: { fontSize: 12, color: 'rgba(255,255,255,0.4)' },
  pointsRowValue: { fontSize: 13, color: '#CD7F32', fontWeight: '700' },
});
