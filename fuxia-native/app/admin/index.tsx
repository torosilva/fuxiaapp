import React, { useState, useCallback } from 'react';
import {
  View, Text, StyleSheet, ScrollView,
  TouchableOpacity, StatusBar, ActivityIndicator, Linking,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import { Plus, Store, ShoppingBag, User, TrendingUp, LifeBuoy, Check, ArrowLeft } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface ChannelRow {
  id: string;
  name: string;
  type: 'store' | 'bazar';
  location: string | null;
  active: boolean;
  total_stock: number;
  total_sold: number;
  total_revenue: number;
  sales_count: number;
}

interface Staff {
  id: string;
  name: string;
  channel_id: string | null;
  active: boolean;
  channels: { name: string } | null;
}

interface SupportTicket {
  id: string;
  customer_name: string | null;
  customer_phone: string | null;
  topic: string | null;
  created_at: string;
  status: 'open' | 'in_progress' | 'resolved';
}

/** wa.me link with a pre-written, editable message so the staff doesn't lose
 *  the ticket context when they open the chat with the customer. */
function buildWhatsAppUrl(t: SupportTicket): string {
  const phone = (t.customer_phone ?? '').replace(/[^\d]/g, '');
  const firstName = t.customer_name?.split(' ')[0];
  const greeting = `Hola${firstName ? ' ' + firstName : ''}, te escribimos de Fuxia Ballerinas 👠`;
  const context = t.topic ? `\n\nVimos tu mensaje: "${t.topic}".` : '';
  const closing = `\n\n¿Cómo podemos ayudarte a resolverlo?`;
  const text = encodeURIComponent(`${greeting}${context}${closing}`);
  return `https://wa.me/${phone}?text=${text}`;
}

export default function AdminHomeScreen() {
  const [channels, setChannels] = useState<ChannelRow[]>([]);
  const [staff, setStaff] = useState<Staff[]>([]);
  const [tickets, setTickets] = useState<SupportTicket[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [chRes, staffRes, invRes, salesRes, ticketsRes] = await Promise.all([
      supabase.from('channels').select('id, name, type, location, active').order('created_at', { ascending: false }),
      supabase.from('staff').select('id, name, channel_id, active, channels(name)').order('created_at', { ascending: false }),
      supabase.from('channel_inventory').select('channel_id, stock, sold'),
      supabase.from('offline_sales').select('channel_id, total').not('channel_id', 'is', null),
      supabase.from('support_tickets').select('id, customer_name, customer_phone, topic, created_at, status').neq('status', 'resolved').order('created_at', { ascending: false }).limit(20),
    ]);

    const rawChannels = (chRes.data ?? []) as { id: string; name: string; type: 'store' | 'bazar'; location: string | null; active: boolean }[];
    const inv = (invRes.data ?? []) as { channel_id: string; stock: number; sold: number }[];
    const sales = (salesRes.data ?? []) as { channel_id: string; total: number }[];

    const merged: ChannelRow[] = rawChannels.map((ch) => {
      const chInv = inv.filter((i) => i.channel_id === ch.id);
      const chSales = sales.filter((s) => s.channel_id === ch.id);
      return {
        ...ch,
        total_stock: chInv.reduce((s, i) => s + (i.stock ?? 0), 0),
        total_sold: chInv.reduce((s, i) => s + (i.sold ?? 0), 0),
        total_revenue: chSales.reduce((s, v) => s + Number(v.total ?? 0), 0),
        sales_count: chSales.length,
      };
    });

    setChannels(merged);
    if (staffRes.data) setStaff(staffRes.data as unknown as Staff[]);
    if (ticketsRes.data) setTickets(ticketsRes.data as SupportTicket[]);
    setLoading(false);
  }, []);

  const resolveTicket = useCallback(async (id: string) => {
    setTickets((prev) => prev.filter((t) => t.id !== id));
    await supabase
      .from('support_tickets')
      .update({ status: 'resolved', resolved_at: new Date().toISOString() })
      .eq('id', id);
  }, []);

  useFocusEffect(useCallback(() => { fetchData(); }, [fetchData]));

  const totalRevenue = channels.reduce((s, ch) => s + ch.total_revenue, 0);
  const totalSold = channels.reduce((s, ch) => s + ch.total_sold, 0);
  const totalSales = channels.reduce((s, ch) => s + ch.sales_count, 0);

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scroll}>
        <MotiView from={{ opacity: 0, translateY: 16 }} animate={{ opacity: 1, translateY: 0 }} transition={{ type: 'timing', duration: 400 }}>
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
            <ArrowLeft size={22} color="#FFF" />
          </TouchableOpacity>
          <Text style={styles.eyebrow}>FUXIA BALLERINAS</Text>
          <Text style={styles.title}>Panel Admin</Text>

          {/* Global summary */}
          {!loading && channels.length > 0 && (
            <MotiView from={{ opacity: 0, translateY: 8 }} animate={{ opacity: 1, translateY: 0 }} transition={{ type: 'timing', duration: 350 }}>
              <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Resumen Total</Text>
                <TrendingUp size={18} color="#B8860B" />
              </View>
              <View style={styles.globalCard}>
                <View style={styles.globalItem}>
                  <Text style={styles.globalValue}>{totalSales}</Text>
                  <Text style={styles.globalLabel}>ventas</Text>
                </View>
                <View style={styles.globalDivider} />
                <View style={styles.globalItem}>
                  <Text style={styles.globalValue}>{totalSold}</Text>
                  <Text style={styles.globalLabel}>pares</Text>
                </View>
                <View style={styles.globalDivider} />
                <View style={styles.globalItem}>
                  <Text style={[styles.globalValue, { color: '#B8860B' }]}>
                    ${totalRevenue.toLocaleString('es-MX', { maximumFractionDigits: 0 })}
                  </Text>
                  <Text style={styles.globalLabel}>recaudado</Text>
                </View>
              </View>
            </MotiView>
          )}

          {/* Tickets de soporte pendientes (de Hilo chat) */}
          {tickets.length > 0 && (
            <>
              <View style={[styles.sectionHeader, { marginTop: 28 }]}>
                <View style={styles.ticketsHeaderLeft}>
                  <LifeBuoy size={16} color="#E05C7A" />
                  <Text style={styles.sectionTitle}>Tickets pendientes</Text>
                  <View style={styles.ticketCount}>
                    <Text style={styles.ticketCountText}>{tickets.length}</Text>
                  </View>
                </View>
              </View>
              {tickets.map((t) => (
                <View key={t.id} style={styles.ticketCard}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.ticketName}>
                      {t.customer_name ?? 'Cliente'}
                      {t.customer_phone ? ` · ${t.customer_phone}` : ''}
                    </Text>
                    {t.topic && <Text style={styles.ticketTopic} numberOfLines={2}>{t.topic}</Text>}
                    <Text style={styles.ticketDate}>{new Date(t.created_at).toLocaleString('es-MX', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</Text>
                  </View>
                  <View style={styles.ticketActions}>
                    {t.customer_phone && (
                      <TouchableOpacity
                        onPress={() => Linking.openURL(buildWhatsAppUrl(t))}
                        style={styles.ticketWaBtn}
                        activeOpacity={0.85}
                      >
                        <Text style={styles.ticketWaText}>WhatsApp</Text>
                      </TouchableOpacity>
                    )}
                    <TouchableOpacity onPress={() => resolveTicket(t.id)} style={styles.ticketResolveBtn} activeOpacity={0.85}>
                      <Check size={14} color="#0D0D0D" strokeWidth={3} />
                    </TouchableOpacity>
                  </View>
                </View>
              ))}
            </>
          )}

          {/* Canales con stats */}
          <View style={[styles.sectionHeader, { marginTop: 28 }]}>
            <Text style={styles.sectionTitle}>Canales</Text>
            <TouchableOpacity style={styles.addBtn} onPress={() => router.push('/admin/channel-new' as any)} activeOpacity={0.8}>
              <Plus size={16} color="#0D0D0D" />
            </TouchableOpacity>
          </View>

          {loading ? (
            <ActivityIndicator color="#B8860B" style={{ marginVertical: 20 }} />
          ) : channels.length === 0 ? (
            <View style={styles.emptyCard}><Text style={styles.emptyText}>Sin canales. Crea uno con el botón +</Text></View>
          ) : (
            channels.map((ch, idx) => (
              <MotiView key={ch.id} from={{ opacity: 0, translateX: -12 }} animate={{ opacity: 1, translateX: 0 }} transition={{ type: 'timing', duration: 300, delay: idx * 60 }}>
                <TouchableOpacity style={styles.channelCard} onPress={() => router.push(`/admin/channel/${ch.id}` as any)} activeOpacity={0.8}>
                  <View style={styles.channelTop}>
                    <View style={styles.cardIcon}>
                      {ch.type === 'store' ? <Store size={20} color="#B8860B" /> : <ShoppingBag size={20} color="#B8860B" />}
                    </View>
                    <View style={styles.cardBody}>
                      <Text style={styles.cardTitle}>{ch.name}</Text>
                      {ch.location ? <Text style={styles.cardSub}>{ch.location}</Text> : null}
                    </View>
                    <View style={styles.cardRight}>
                      <View style={[styles.typeBadge, ch.type === 'bazar' && styles.typeBadgeBazar]}>
                        <Text style={styles.typeBadgeText}>{ch.type === 'store' ? 'TIENDA' : 'BAZAR'}</Text>
                      </View>
                      <View style={[styles.statusDot, ch.active ? styles.dotActive : styles.dotInactive]} />
                    </View>
                  </View>
                  {/* Stats inline */}
                  <View style={styles.channelStats}>
                    <Text style={styles.statItem}>{ch.total_sold} pares</Text>
                    <Text style={styles.statDot}>·</Text>
                    <Text style={styles.statItem}>{ch.total_stock - ch.total_sold} restantes</Text>
                    <Text style={styles.statDot}>·</Text>
                    <Text style={[styles.statItem, { color: '#B8860B' }]}>
                      ${ch.total_revenue.toLocaleString('es-MX', { maximumFractionDigits: 0 })}
                    </Text>
                  </View>
                  {ch.total_stock > 0 && (
                    <View style={styles.stockBar}>
                      <View style={[styles.stockBarFill, { width: `${Math.min(100, (ch.total_sold / ch.total_stock) * 100)}%` }]} />
                    </View>
                  )}
                </TouchableOpacity>
              </MotiView>
            ))
          )}

          {/* Vendedoras */}
          <View style={[styles.sectionHeader, { marginTop: 32 }]}>
            <Text style={styles.sectionTitle}>Vendedoras</Text>
            <TouchableOpacity style={styles.addBtn} onPress={() => router.push('/admin/staff-new' as any)} activeOpacity={0.8}>
              <Plus size={16} color="#0D0D0D" />
            </TouchableOpacity>
          </View>

          {loading ? (
            <ActivityIndicator color="#B8860B" style={{ marginVertical: 20 }} />
          ) : staff.length === 0 ? (
            <View style={styles.emptyCard}><Text style={styles.emptyText}>Sin vendedoras. Agrega una con el botón +</Text></View>
          ) : (
            staff.map((s, idx) => (
              <MotiView key={s.id} from={{ opacity: 0, translateX: -12 }} animate={{ opacity: 1, translateX: 0 }} transition={{ type: 'timing', duration: 300, delay: idx * 60 }}>
                <View style={styles.card}>
                  <View style={styles.cardIcon}><User size={20} color="#B8860B" /></View>
                  <View style={styles.cardBody}>
                    <Text style={styles.cardTitle}>{s.name}</Text>
                    <Text style={styles.cardSub}>PIN: ****  ·  {s.channels?.name ?? 'Sin canal'}</Text>
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
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24 },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
    marginBottom: 16,
  },
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 3, marginBottom: 4 },
  title: { fontSize: 32, color: '#fff', fontWeight: '700', marginBottom: 32 },
  sectionHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 },
  sectionTitle: { fontSize: 18, color: '#fff', fontWeight: '600' },
  addBtn: { width: 32, height: 32, borderRadius: 16, backgroundColor: '#B8860B', justifyContent: 'center', alignItems: 'center' },
  globalCard: {
    flexDirection: 'row', backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(184,134,11,0.25)', padding: 20, marginBottom: 4,
  },
  globalItem: { flex: 1, alignItems: 'center' },
  globalValue: { fontSize: 26, color: '#fff', fontWeight: '700' },
  globalLabel: { fontSize: 10, color: 'rgba(255,255,255,0.4)', marginTop: 2, textTransform: 'uppercase', letterSpacing: 0.5 },
  globalDivider: { width: 1, backgroundColor: 'rgba(255,255,255,0.08)' },
  channelCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16, borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)', padding: 16, marginBottom: 10,
  },
  channelTop: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: 12 },
  channelStats: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 8 },
  statItem: { fontSize: 12, color: 'rgba(255,255,255,0.5)', fontWeight: '500' },
  statDot: { fontSize: 12, color: 'rgba(255,255,255,0.2)' },
  stockBar: { height: 3, backgroundColor: 'rgba(255,255,255,0.08)', borderRadius: 2, overflow: 'hidden' },
  stockBarFill: { height: 3, backgroundColor: '#B8860B', borderRadius: 2 },
  card: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#1A1A1A',
    borderRadius: 16, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: 16, marginBottom: 10, gap: 12,
  },
  cardIcon: { width: 40, height: 40, borderRadius: 12, backgroundColor: 'rgba(184,134,11,0.12)', justifyContent: 'center', alignItems: 'center' },
  cardBody: { flex: 1 },
  cardTitle: { fontSize: 15, color: '#fff', fontWeight: '600' },
  cardSub: { fontSize: 12, color: 'rgba(255,255,255,0.4)', marginTop: 2 },
  cardRight: { alignItems: 'flex-end', gap: 6 },
  typeBadge: { backgroundColor: 'rgba(184,134,11,0.2)', paddingHorizontal: 8, paddingVertical: 3, borderRadius: 6 },
  typeBadgeBazar: { backgroundColor: 'rgba(128,0,128,0.2)' },
  typeBadgeText: { fontSize: 9, color: '#B8860B', fontWeight: '800', letterSpacing: 1 },
  statusDot: { width: 8, height: 8, borderRadius: 4 },
  dotActive: { backgroundColor: '#4CAF50' },
  dotInactive: { backgroundColor: 'rgba(255,255,255,0.2)' },
  emptyCard: { backgroundColor: '#1A1A1A', borderRadius: 16, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', padding: 24, alignItems: 'center', marginBottom: 10 },
  emptyText: { color: 'rgba(255,255,255,0.4)', fontSize: 13, textAlign: 'center' },
  ticketsHeaderLeft: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  ticketCount: {
    backgroundColor: '#E05C7A',
    minWidth: 22, height: 22, borderRadius: 11,
    paddingHorizontal: 6,
    justifyContent: 'center', alignItems: 'center',
  },
  ticketCountText: { color: '#FFF', fontSize: 11, fontWeight: '800' },
  ticketCard: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: '#1A1A1A',
    borderRadius: 14,
    padding: 14, marginBottom: 8,
    borderWidth: 1, borderColor: 'rgba(224,92,122,0.25)',
  },
  ticketName: { color: '#FFF', fontSize: 13, fontWeight: '700', marginBottom: 2 },
  ticketTopic: { color: 'rgba(255,255,255,0.65)', fontSize: 12, marginBottom: 4, lineHeight: 16 },
  ticketDate: { color: 'rgba(255,255,255,0.35)', fontSize: 10 },
  ticketActions: { flexDirection: 'row', alignItems: 'center', gap: 8, marginLeft: 10 },
  ticketWaBtn: {
    backgroundColor: '#25D366',
    paddingHorizontal: 10, paddingVertical: 7, borderRadius: 14,
  },
  ticketWaText: { color: '#FFF', fontSize: 11, fontWeight: '700' },
  ticketResolveBtn: {
    width: 30, height: 30, borderRadius: 15,
    backgroundColor: '#CD7F32',
    justifyContent: 'center', alignItems: 'center',
  },
});
