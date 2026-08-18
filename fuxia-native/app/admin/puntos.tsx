import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TextInput, TouchableOpacity, ScrollView,
  ActivityIndicator, StatusBar, Alert, KeyboardAvoidingView, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { ArrowLeft, Search } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;

type Cust = {
  id: string; name: string | null; phone: string; email: string | null;
  total_points: number; tier: string; created_at?: string;
};

const TIER_LABEL: Record<string, string> = { bronze: 'Bronce', silver: 'Plata', gold: 'Oro' };

async function callAdmin(action: string, payload: Record<string, unknown>) {
  const { data: { session } } = await supabase.auth.getSession();
  const res = await fetch(`${SUPABASE_URL}/functions/v1/admin-points`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token}` },
    body: JSON.stringify({ action, ...payload }),
  });
  return res.json();
}

export default function AdminPuntosScreen() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Cust[]>([]);
  const [selected, setSelected] = useState<Cust | null>(null);
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [searched, setSearched] = useState(false);

  const doSearch = async () => {
    if (!query.trim()) return;
    setLoading(true); setSelected(null); setSearched(true);
    const r = await callAdmin('search', { query: query.trim() });
    setResults(Array.isArray(r.customers) ? r.customers : []);
    setLoading(false);
  };

  const adjust = async (sign: 1 | -1) => {
    const n = parseInt(amount, 10);
    if (!selected) return;
    if (!Number.isFinite(n) || n <= 0) { Alert.alert('Ingresa un monto válido'); return; }
    setBusy(true);
    const r = await callAdmin('adjust', { customer_id: selected.id, delta: sign * n, reason: reason.trim() });
    setBusy(false);
    if (r.error) { Alert.alert('Error', r.error); return; }
    const updated = { ...selected, total_points: r.new_total, tier: r.tier };
    setSelected(updated);
    setResults((rs) => rs.map((c) => (c.id === selected.id ? updated : c)));
    setAmount(''); setReason('');
    Alert.alert('Listo ✅', `${sign > 0 ? 'Agregados' : 'Quitados'} ${n} pts.\nNuevo total: ${r.new_total} (${TIER_LABEL[r.tier] ?? r.tier})`);
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
            <ArrowLeft size={22} color="#FFF" />
          </TouchableOpacity>
          <Text style={styles.eyebrow}>ADMIN</Text>
          <Text style={styles.title}>Clientas y puntos</Text>

          {/* Buscador */}
          <View style={styles.searchRow}>
            <TextInput
              style={styles.searchInput}
              value={query}
              onChangeText={setQuery}
              placeholder="Nombre, teléfono o email"
              placeholderTextColor="rgba(255,255,255,0.3)"
              autoCapitalize="none"
              autoCorrect={false}
              onSubmitEditing={doSearch}
              returnKeyType="search"
            />
            <TouchableOpacity style={styles.searchBtn} onPress={doSearch} activeOpacity={0.85}>
              <Search size={20} color="#0D0D0D" />
            </TouchableOpacity>
          </View>

          {loading && <ActivityIndicator color="#B8860B" style={{ marginTop: 20 }} />}

          {!loading && searched && results.length === 0 && (
            <Text style={styles.empty}>No se encontraron clientas.</Text>
          )}

          {/* Resultados */}
          {!loading && results.map((c) => {
            const isSel = selected?.id === c.id;
            return (
              <TouchableOpacity
                key={c.id}
                style={[styles.card, isSel && styles.cardSel]}
                onPress={() => setSelected(isSel ? null : c)}
                activeOpacity={0.85}
              >
                <View style={{ flex: 1 }}>
                  <Text style={styles.cardName}>{c.name ?? 'Sin nombre'}</Text>
                  <Text style={styles.cardMeta}>{c.phone}{c.email ? ` · ${c.email}` : ''}</Text>
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={styles.cardPts}>{c.total_points}</Text>
                  <Text style={styles.cardTier}>{TIER_LABEL[c.tier] ?? c.tier}</Text>
                </View>
              </TouchableOpacity>
            );
          })}

          {/* Panel de ajuste */}
          {selected && (
            <View style={styles.adjustPanel}>
              <Text style={styles.adjustTitle}>Ajustar puntos de {selected.name ?? 'la clienta'}</Text>
              <Text style={styles.adjustCurrent}>Actual: {selected.total_points} pts · {TIER_LABEL[selected.tier] ?? selected.tier}</Text>

              <TextInput
                style={styles.input}
                value={amount}
                onChangeText={(t) => setAmount(t.replace(/[^0-9]/g, ''))}
                placeholder="Cantidad de puntos"
                placeholderTextColor="rgba(255,255,255,0.3)"
                keyboardType="number-pad"
              />
              <TextInput
                style={styles.input}
                value={reason}
                onChangeText={setReason}
                placeholder="Motivo (ej: corrección, regalo, cortesía)"
                placeholderTextColor="rgba(255,255,255,0.3)"
              />

              <View style={styles.btnRow}>
                <TouchableOpacity style={[styles.actionBtn, styles.removeBtn]} onPress={() => adjust(-1)} disabled={busy} activeOpacity={0.85}>
                  <Text style={styles.removeText}>− Quitar</Text>
                </TouchableOpacity>
                <TouchableOpacity style={[styles.actionBtn, styles.addBtn]} onPress={() => adjust(1)} disabled={busy} activeOpacity={0.85}>
                  {busy ? <ActivityIndicator color="#0D0D0D" /> : <Text style={styles.addText}>+ Agregar</Text>}
                </TouchableOpacity>
              </View>
              <Text style={styles.hint}>Al agregar puntos, a la clienta le salta la celebración en su app 🎉</Text>
            </View>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 80 },
  backBtn: { width: 40, height: 40, justifyContent: 'center', marginBottom: 8 },
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 3, marginBottom: 6 },
  title: { fontSize: 32, color: '#FFF', fontFamily: 'serif', marginBottom: 24 },
  searchRow: { flexDirection: 'row', gap: 10 },
  searchInput: {
    flex: 1, backgroundColor: '#1A1A1A', borderRadius: 12, borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)', paddingHorizontal: 16, height: 52, color: '#FFF', fontSize: 15,
  },
  searchBtn: { width: 52, height: 52, borderRadius: 12, backgroundColor: '#B8860B', justifyContent: 'center', alignItems: 'center' },
  empty: { color: 'rgba(255,255,255,0.4)', textAlign: 'center', marginTop: 24 },
  card: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#1A1A1A',
    borderRadius: 14, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', padding: 16, marginTop: 12,
  },
  cardSel: { borderColor: '#B8860B' },
  cardName: { color: '#FFF', fontSize: 16, fontWeight: '600' },
  cardMeta: { color: 'rgba(255,255,255,0.4)', fontSize: 12, marginTop: 3 },
  cardPts: { color: '#B8860B', fontSize: 20, fontWeight: '800' },
  cardTier: { color: 'rgba(255,255,255,0.5)', fontSize: 11, marginTop: 2 },
  adjustPanel: {
    backgroundColor: '#141414', borderRadius: 16, borderWidth: 1,
    borderColor: 'rgba(184,134,11,0.35)', padding: 20, marginTop: 24,
  },
  adjustTitle: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  adjustCurrent: { color: 'rgba(255,255,255,0.5)', fontSize: 13, marginTop: 4, marginBottom: 16 },
  input: {
    backgroundColor: '#1A1A1A', borderRadius: 12, borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
    paddingHorizontal: 16, height: 50, color: '#FFF', fontSize: 15, marginBottom: 12,
  },
  btnRow: { flexDirection: 'row', gap: 12, marginTop: 4 },
  actionBtn: { flex: 1, height: 52, borderRadius: 30, justifyContent: 'center', alignItems: 'center' },
  addBtn: { backgroundColor: '#B8860B' },
  addText: { color: '#0D0D0D', fontSize: 14, fontWeight: '800', letterSpacing: 0.5 },
  removeBtn: { backgroundColor: 'transparent', borderWidth: 1.5, borderColor: 'rgba(224,92,122,0.7)' },
  removeText: { color: '#E05C7A', fontSize: 14, fontWeight: '800', letterSpacing: 0.5 },
  hint: { color: 'rgba(255,255,255,0.35)', fontSize: 11, marginTop: 14, textAlign: 'center' },
});
