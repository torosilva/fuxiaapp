import React, { useCallback, useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  StatusBar, ActivityIndicator, TextInput, Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Plus, Search, Store, ShoppingBag, User } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface StaffRow {
  id: string;
  name: string;
  pin: string;
  active: boolean;
  channel_id: string | null;
  channels: { name: string; type: 'store' | 'bazar' } | null;
}

export default function StaffListScreen() {
  const [staff, setStaff] = useState<StaffRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);

  const fetchStaff = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('staff')
      .select('id, name, pin, active, channel_id, channels(name, type)')
      .order('active', { ascending: false })
      .order('name');
    if (error) Alert.alert('Error', error.message);
    setStaff((data ?? []) as unknown as StaffRow[]);
    setLoading(false);
  }, []);

  useFocusEffect(useCallback(() => { fetchStaff(); }, [fetchStaff]));

  const toggleActive = async (row: StaffRow) => {
    setBusyId(row.id);
    const { error } = await supabase
      .from('staff')
      .update({ active: !row.active })
      .eq('id', row.id);
    setBusyId(null);
    if (error) { Alert.alert('Error', error.message); return; }
    setStaff((s) => s.map((v) => v.id === row.id ? { ...v, active: !v.active } : v));
  };

  const filtered = query.trim()
    ? staff.filter((v) => (v.name ?? '').toLowerCase().includes(query.trim().toLowerCase()))
    : staff;

  const activeCount = staff.filter((s) => s.active).length;

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>

        <View style={styles.headerRow}>
          <View>
            <Text style={styles.eyebrow}>PANEL ADMIN</Text>
            <Text style={styles.title}>Vendedoras</Text>
            <Text style={styles.subtitle}>{activeCount} activas · {staff.length} en total</Text>
          </View>
          <TouchableOpacity
            style={styles.addBtn}
            onPress={() => router.push('/admin/staff-new' as any)}
            activeOpacity={0.85}
          >
            <Plus size={18} color="#0D0D0D" strokeWidth={3} />
          </TouchableOpacity>
        </View>

        <View style={styles.searchRow}>
          <Search size={16} color="rgba(255,255,255,0.4)" />
          <TextInput
            style={styles.searchInput}
            value={query}
            onChangeText={setQuery}
            placeholder="Buscar por nombre"
            placeholderTextColor="rgba(255,255,255,0.3)"
            autoCapitalize="none"
            autoCorrect={false}
          />
        </View>

        {loading ? (
          <ActivityIndicator color="#B8860B" style={{ marginTop: 32 }} />
        ) : filtered.length === 0 ? (
          <Text style={styles.empty}>
            {query ? 'Ninguna vendedora coincide con la búsqueda.' : 'Todavía no hay vendedoras dadas de alta.'}
          </Text>
        ) : (
          filtered.map((row, i) => (
            <MotiView
              key={row.id}
              from={{ opacity: 0, translateY: 8 }}
              animate={{ opacity: 1, translateY: 0 }}
              transition={{ type: 'timing', duration: 280, delay: i * 40 }}
              style={[styles.card, !row.active && styles.cardInactive]}
            >
              <TouchableOpacity
                style={styles.cardMain}
                onPress={() => router.push({ pathname: '/admin/staff/[id]' as any, params: { id: row.id } })}
                activeOpacity={0.85}
              >
                <View style={styles.avatar}>
                  <User size={20} color="#B8860B" />
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.name}>{row.name}</Text>
                  <View style={styles.metaRow}>
                    {row.channels ? (
                      <>
                        {row.channels.type === 'bazar'
                          ? <ShoppingBag size={11} color="rgba(255,255,255,0.5)" />
                          : <Store size={11} color="rgba(255,255,255,0.5)" />}
                        <Text style={styles.metaText}>{row.channels.name}</Text>
                      </>
                    ) : (
                      <Text style={styles.metaText}>Sin canal asignado</Text>
                    )}
                    <Text style={styles.metaSep}>·</Text>
                    <Text style={styles.pin}>PIN {row.pin}</Text>
                  </View>
                </View>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.toggle, row.active ? styles.toggleOn : styles.toggleOff]}
                onPress={() => toggleActive(row)}
                disabled={busyId === row.id}
                activeOpacity={0.75}
              >
                {busyId === row.id ? (
                  <ActivityIndicator size="small" color={row.active ? '#0D0D0D' : '#B8860B'} />
                ) : (
                  <Text style={[styles.toggleText, row.active ? styles.toggleTextOn : styles.toggleTextOff]}>
                    {row.active ? 'Activa' : 'Inactiva'}
                  </Text>
                )}
              </TouchableOpacity>
            </MotiView>
          ))
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 60 },
  backBtn: { width: 40, height: 40, justifyContent: 'center', marginBottom: 8 },
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 24 },
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 3, marginBottom: 4 },
  title: { fontSize: 32, color: '#FFF', fontFamily: 'serif', marginBottom: 4 },
  subtitle: { fontSize: 12, color: 'rgba(255,255,255,0.4)' },
  addBtn: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: '#B8860B',
    justifyContent: 'center', alignItems: 'center',
  },
  searchRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#1A1A1A',
    borderRadius: 12, paddingHorizontal: 16, height: 46, marginBottom: 12,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
  },
  searchInput: { flex: 1, color: '#FFF', fontSize: 14 },
  empty: { color: 'rgba(255,255,255,0.4)', textAlign: 'center', marginTop: 40, fontSize: 13, lineHeight: 20 },
  card: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#141414',
    borderRadius: 14, borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    padding: 12, marginTop: 10, gap: 8,
  },
  cardInactive: { opacity: 0.55 },
  cardMain: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12 },
  avatar: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center', alignItems: 'center',
  },
  name: { color: '#FFF', fontSize: 15, fontWeight: '600' },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 3 },
  metaText: { color: 'rgba(255,255,255,0.5)', fontSize: 11 },
  metaSep: { color: 'rgba(255,255,255,0.25)', fontSize: 11 },
  pin: { color: 'rgba(184,134,11,0.75)', fontSize: 11, fontWeight: '700' },
  toggle: {
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: 20,
    minWidth: 78, alignItems: 'center', justifyContent: 'center',
  },
  toggleOn: { backgroundColor: '#B8860B' },
  toggleOff: { backgroundColor: 'transparent', borderWidth: 1, borderColor: 'rgba(184,134,11,0.4)' },
  toggleText: { fontSize: 11, fontWeight: '800', letterSpacing: 0.5 },
  toggleTextOn: { color: '#0D0D0D' },
  toggleTextOff: { color: '#B8860B' },
});
