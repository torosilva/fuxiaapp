import React, { useEffect, useState, useCallback } from 'react';
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
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { Plus, Store, ShoppingBag, User } from 'lucide-react-native';
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

export default function AdminHomeScreen() {
  const [channels, setChannels] = useState<Channel[]>([]);
  const [staff, setStaff] = useState<Staff[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const [channelsRes, staffRes] = await Promise.all([
      supabase.from('channels').select('id, name, type, location, active').order('created_at', { ascending: false }),
      supabase.from('staff').select('id, name, pin, channel_id, active, channels(name)').order('created_at', { ascending: false }),
    ]);
    if (channelsRes.data) setChannels(channelsRes.data as Channel[]);
    if (staffRes.data) setStaff(staffRes.data as unknown as Staff[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

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

          {/* Canales */}
          <View style={styles.sectionHeader}>
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
