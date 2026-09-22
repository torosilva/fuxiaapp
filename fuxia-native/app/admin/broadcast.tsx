/**
 * /admin/broadcast — Marketing directo por push a un segmento.
 *
 * La admin elige a quiénes va, escribe título + cuerpo, ve un preview
 * como se va a ver en el teléfono, y confirma. La edge function
 * `admin-broadcast-push` hace la magia + registra en `broadcasts` para
 * auditoría.
 *
 * Rate limit: 1 broadcast por segmento por 24h (enforced en el server).
 */
import React, { useCallback, useEffect, useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity, TextInput,
  StatusBar, ActivityIndicator, Alert, KeyboardAvoidingView, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useFocusEffect } from 'expo-router';
import { ArrowLeft, Bell, Send } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;

const SEGMENTS = [
  { key: 'all',      label: 'Todas',       hint: 'Todas las clientas registradas' },
  { key: 'bronze',   label: 'Bronce',      hint: 'Nivel Bronce · 0-299 pts' },
  { key: 'silver',   label: 'Silver',      hint: 'Nivel Silver · 300-899 pts' },
  { key: 'gold',     label: 'Gold',        hint: 'Nivel Gold · 900+ pts' },
  { key: 'inactive', label: 'Inactivas',   hint: 'Sin compras en los últimos 30 días' },
];

interface Broadcast {
  id: string;
  segment: string;
  title: string;
  body: string;
  recipients_count: number;
  sent_by_name: string;
  created_at: string;
}

export default function BroadcastScreen() {
  const [segment, setSegment] = useState<string>('all');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);
  const [history, setHistory] = useState<Broadcast[]>([]);

  const loadHistory = useCallback(async () => {
    const { data } = await supabase.from('broadcasts')
      .select('id, segment, title, body, recipients_count, sent_by_name, created_at')
      .order('created_at', { ascending: false })
      .limit(10);
    setHistory((data ?? []) as Broadcast[]);
  }, []);

  useFocusEffect(useCallback(() => { loadHistory(); }, [loadHistory]));

  const canSend = title.trim().length > 0 && body.trim().length > 0 && !sending;

  const handleSend = async () => {
    if (!canSend) return;
    Alert.alert(
      '¿Enviar broadcast?',
      `Vas a mandar un push a "${SEGMENTS.find(s => s.key === segment)?.label}". No se puede deshacer.`,
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Enviar', style: 'default',
          onPress: async () => {
            setSending(true);
            const { data: { session } } = await supabase.auth.getSession();
            const res = await fetch(`${SUPABASE_URL}/functions/v1/admin-broadcast-push`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${session?.access_token}`,
              },
              body: JSON.stringify({ segment, title: title.trim(), body: body.trim() }),
            });
            const j = await res.json();
            setSending(false);
            if (j.error) { Alert.alert('Error', j.error); return; }
            Alert.alert(
              '¡Enviado!',
              `Push enviado a ${j.sent_count} ${j.sent_count === 1 ? 'clienta' : 'clientas'}.`,
              [{ text: 'OK', onPress: () => { setTitle(''); setBody(''); loadHistory(); } }],
            );
          },
        },
      ],
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
            <ArrowLeft size={22} color="#FFF" />
          </TouchableOpacity>

          <Text style={styles.eyebrow}>MARKETING</Text>
          <Text style={styles.title}>Push a un segmento</Text>
          <Text style={styles.subtitle}>
            Manda una notificación a un grupo de clientas. Máximo 1 broadcast por segmento cada 24 h.
          </Text>

          {/* Segmento */}
          <Text style={styles.label}>Para</Text>
          <View style={styles.chipRow}>
            {SEGMENTS.map((s) => {
              const on = segment === s.key;
              return (
                <TouchableOpacity
                  key={s.key}
                  style={[styles.chip, on && styles.chipOn]}
                  onPress={() => setSegment(s.key)}
                  activeOpacity={0.75}
                >
                  <Text style={[styles.chipText, on && styles.chipTextOn]}>{s.label}</Text>
                </TouchableOpacity>
              );
            })}
          </View>
          <Text style={styles.hint}>{SEGMENTS.find(s => s.key === segment)?.hint}</Text>

          {/* Título */}
          <Text style={[styles.label, { marginTop: 20 }]}>Título · {title.length}/60</Text>
          <TextInput
            style={styles.input}
            value={title}
            onChangeText={(t) => setTitle(t.slice(0, 60))}
            placeholder="Ej: Nueva colección Fuxia 🌸"
            placeholderTextColor="rgba(255,255,255,0.25)"
            maxLength={60}
          />

          {/* Cuerpo */}
          <Text style={[styles.label, { marginTop: 20 }]}>Mensaje · {body.length}/140</Text>
          <TextInput
            style={[styles.input, { height: 88, textAlignVertical: 'top' }]}
            value={body}
            onChangeText={(t) => setBody(t.slice(0, 140))}
            placeholder="Descubre los nuevos modelos exclusivos con envío gratis esta semana."
            placeholderTextColor="rgba(255,255,255,0.25)"
            multiline
            maxLength={140}
          />

          {/* Preview */}
          <Text style={[styles.label, { marginTop: 20 }]}>Preview</Text>
          <View style={styles.preview}>
            <View style={styles.previewIcon}>
              <Bell size={16} color="#0D0D0D" />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={styles.previewApp}>FUXIA BALLERINAS · ahora</Text>
              <Text style={styles.previewTitle}>{title || 'Título del mensaje'}</Text>
              <Text style={styles.previewBody}>{body || 'Cuerpo del mensaje que verá la clienta'}</Text>
            </View>
          </View>

          <TouchableOpacity
            style={[styles.sendBtn, !canSend && { opacity: 0.5 }]}
            onPress={handleSend}
            disabled={!canSend}
            activeOpacity={0.85}
          >
            {sending
              ? <ActivityIndicator color="#0D0D0D" />
              : <>
                  <Send size={16} color="#0D0D0D" />
                  <Text style={styles.sendBtnText}>Enviar broadcast</Text>
                </>}
          </TouchableOpacity>

          {/* Historial */}
          {history.length > 0 && (
            <View style={{ marginTop: 32 }}>
              <Text style={styles.sectionTitle}>Últimos envíos</Text>
              {history.map((h) => (
                <View key={h.id} style={styles.historyRow}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.historyTitle}>{h.title}</Text>
                    <Text style={styles.historyBody} numberOfLines={2}>{h.body}</Text>
                    <Text style={styles.historyMeta}>
                      {SEGMENTS.find(s => s.key === h.segment)?.label ?? h.segment} · {h.recipients_count} envíos
                      · {new Date(h.created_at).toLocaleDateString('es-MX', { day: '2-digit', month: 'short' })}
                    </Text>
                  </View>
                </View>
              ))}
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
  title: { fontSize: 28, color: '#FFF', fontFamily: 'serif', marginBottom: 6 },
  subtitle: { fontSize: 13, color: 'rgba(255,255,255,0.5)', marginBottom: 24, lineHeight: 18 },
  label: {
    fontSize: 11, color: 'rgba(255,255,255,0.6)', fontWeight: '700',
    letterSpacing: 1, textTransform: 'uppercase', marginBottom: 8,
  },
  hint: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 6 },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    paddingHorizontal: 14, paddingVertical: 9, borderRadius: 20,
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
  },
  chipOn: { backgroundColor: '#B8860B', borderColor: '#B8860B' },
  chipText: { color: 'rgba(255,255,255,0.75)', fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: '#0D0D0D', fontWeight: '800' },
  input: {
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12, paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: '#FFF',
  },
  preview: {
    flexDirection: 'row', gap: 12, padding: 14, borderRadius: 14,
    backgroundColor: 'rgba(255,255,255,0.06)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
  },
  previewIcon: {
    width: 34, height: 34, borderRadius: 8, backgroundColor: '#B8860B',
    justifyContent: 'center', alignItems: 'center',
  },
  previewApp: { color: 'rgba(255,255,255,0.5)', fontSize: 10, fontWeight: '800', letterSpacing: 0.5, marginBottom: 3 },
  previewTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginBottom: 2 },
  previewBody: { color: 'rgba(255,255,255,0.75)', fontSize: 13, lineHeight: 17 },
  sendBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    backgroundColor: '#B8860B', paddingVertical: 16, borderRadius: 28, marginTop: 24,
  },
  sendBtnText: { color: '#0D0D0D', fontSize: 15, fontWeight: '800', letterSpacing: 0.5 },
  sectionTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginBottom: 12 },
  historyRow: {
    backgroundColor: '#141414', borderRadius: 12, padding: 14, marginBottom: 8,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
  },
  historyTitle: { color: '#FFF', fontSize: 13, fontWeight: '700' },
  historyBody: { color: 'rgba(255,255,255,0.65)', fontSize: 12, marginTop: 4, lineHeight: 16 },
  historyMeta: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 6 },
});
