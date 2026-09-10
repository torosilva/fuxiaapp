import React, { useEffect, useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, TextInput,
  StatusBar, ActivityIndicator, Alert, KeyboardAvoidingView,
  Platform, ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { ArrowLeft, ChevronDown, Trash2 } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface Channel { id: string; name: string; type: 'store' | 'bazar' }

export default function StaffEditScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [name, setName] = useState('');
  const [pin, setPin] = useState('');
  const [active, setActive] = useState(true);
  const [channels, setChannels] = useState<Channel[]>([]);
  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [channelPickerOpen, setChannelPickerOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    (async () => {
      const [staffRes, chRes] = await Promise.all([
        supabase.from('staff').select('id, name, pin, channel_id, active').eq('id', id).single(),
        supabase.from('channels').select('id, name, type').eq('active', true).order('name'),
      ]);
      if (staffRes.data) {
        setName(staffRes.data.name);
        setPin(staffRes.data.pin);
        setActive(staffRes.data.active);
        if (chRes.data && staffRes.data.channel_id) {
          const found = (chRes.data as Channel[]).find((c) => c.id === staffRes.data.channel_id);
          if (found) setSelectedChannel(found);
        }
      }
      if (chRes.data) setChannels(chRes.data as Channel[]);
      setLoading(false);
    })();
  }, [id]);

  const handleSave = async () => {
    if (!name.trim()) { Alert.alert('Campo requerido', 'El nombre es obligatorio.'); return; }
    if (pin.length !== 4 || !/^\d{4}$/.test(pin)) {
      Alert.alert('PIN inválido', 'El PIN debe ser exactamente 4 dígitos.');
      return;
    }
    setSaving(true);
    const { error } = await supabase.from('staff').update({
      name: name.trim(),
      pin,
      channel_id: selectedChannel?.id ?? null,
      active,
    }).eq('id', id);
    setSaving(false);
    if (error) { Alert.alert('Error', error.message); return; }
    router.back();
  };

  const handleDelete = () => {
    Alert.alert(
      'Eliminar vendedora',
      `¿Seguro que quieres eliminar a ${name}? Esta acción no se puede deshacer.`,
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Eliminar', style: 'destructive',
          onPress: async () => {
            setDeleting(true);
            const { error } = await supabase.from('staff').delete().eq('id', id);
            setDeleting(false);
            if (error) { Alert.alert('Error', error.message); return; }
            router.back();
          },
        },
      ],
    );
  };

  if (loading) {
    return (
      <SafeAreaView style={[styles.container, { justifyContent: 'center', alignItems: 'center' }]}>
        <ActivityIndicator color="#B8860B" />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
            <ArrowLeft size={22} color="#FFF" />
          </TouchableOpacity>

          <Text style={styles.eyebrow}>PANEL ADMIN</Text>
          <Text style={styles.title}>Editar vendedora</Text>

          <View style={styles.field}>
            <Text style={styles.label}>Nombre</Text>
            <TextInput
              style={styles.input}
              value={name}
              onChangeText={setName}
              placeholder="Nombre completo"
              placeholderTextColor="rgba(255,255,255,0.25)"
            />
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>PIN (4 dígitos)</Text>
            <TextInput
              style={styles.input}
              value={pin}
              onChangeText={(t) => setPin(t.replace(/[^0-9]/g, '').slice(0, 4))}
              keyboardType="number-pad"
              maxLength={4}
              secureTextEntry
            />
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>Canal asignado <Text style={styles.optional}>(opcional)</Text></Text>
            <TouchableOpacity
              style={styles.picker}
              onPress={() => setChannelPickerOpen((o) => !o)}
              activeOpacity={0.8}
            >
              <Text style={[styles.pickerText, !selectedChannel && styles.pickerPlaceholder]}>
                {selectedChannel?.name ?? 'Sin asignar'}
              </Text>
              <ChevronDown size={18} color="rgba(255,255,255,0.4)" />
            </TouchableOpacity>
            {channelPickerOpen && (
              <View style={styles.dropdownList}>
                <TouchableOpacity
                  style={styles.dropdownItem}
                  onPress={() => { setSelectedChannel(null); setChannelPickerOpen(false); }}
                >
                  <Text style={[styles.dropdownItemText, styles.dropdownNone]}>Sin asignar</Text>
                </TouchableOpacity>
                {channels.map((ch) => (
                  <TouchableOpacity
                    key={ch.id}
                    style={[styles.dropdownItem, selectedChannel?.id === ch.id && styles.dropdownItemSelected]}
                    onPress={() => { setSelectedChannel(ch); setChannelPickerOpen(false); }}
                  >
                    <Text style={styles.dropdownItemText}>{ch.name}</Text>
                    <Text style={styles.dropdownItemBadge}>{ch.type === 'bazar' ? 'BAZAR' : 'TIENDA'}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            )}
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>Estado</Text>
            <View style={styles.toggleRow}>
              <TouchableOpacity
                style={[styles.toggleOpt, active && styles.toggleOptOn]}
                onPress={() => setActive(true)}
              >
                <Text style={[styles.toggleOptText, active && styles.toggleOptTextOn]}>Activa</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.toggleOpt, !active && styles.toggleOptOff]}
                onPress={() => setActive(false)}
              >
                <Text style={[styles.toggleOptText, !active && styles.toggleOptTextOff]}>Inactiva</Text>
              </TouchableOpacity>
            </View>
          </View>

          <TouchableOpacity
            style={[styles.saveBtn, saving && { opacity: 0.6 }]}
            onPress={handleSave}
            disabled={saving}
            activeOpacity={0.85}
          >
            {saving ? <ActivityIndicator color="#0D0D0D" /> : <Text style={styles.saveBtnText}>Guardar cambios</Text>}
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.deleteBtn}
            onPress={handleDelete}
            disabled={deleting}
            activeOpacity={0.75}
          >
            <Trash2 size={16} color="#E05C7A" />
            <Text style={styles.deleteBtnText}>{deleting ? 'Eliminando…' : 'Eliminar vendedora'}</Text>
          </TouchableOpacity>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 60 },
  backBtn: { width: 40, height: 40, justifyContent: 'center', marginBottom: 8 },
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 3, marginBottom: 6 },
  title: { fontSize: 30, color: '#FFF', fontFamily: 'serif', marginBottom: 28 },
  field: { marginBottom: 20 },
  label: {
    fontSize: 12, color: 'rgba(255,255,255,0.5)', fontWeight: '700',
    letterSpacing: 1, textTransform: 'uppercase', marginBottom: 8,
  },
  optional: { fontWeight: '400', textTransform: 'none', letterSpacing: 0 },
  input: {
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 14, paddingHorizontal: 16, paddingVertical: 14, fontSize: 15, color: '#FFF',
  },
  picker: {
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 14, paddingHorizontal: 16, paddingVertical: 14,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
  },
  pickerText: { fontSize: 15, color: '#FFF' },
  pickerPlaceholder: { color: 'rgba(255,255,255,0.4)' },
  dropdownList: {
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 14, marginTop: 4, overflow: 'hidden',
  },
  dropdownItem: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 14,
    borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  dropdownItemSelected: { backgroundColor: 'rgba(184,134,11,0.1)' },
  dropdownItemText: { fontSize: 14, color: '#FFF' },
  dropdownNone: { color: 'rgba(255,255,255,0.5)' },
  dropdownItemBadge: { fontSize: 9, color: '#B8860B', fontWeight: '800', letterSpacing: 1 },
  toggleRow: { flexDirection: 'row', gap: 10 },
  toggleOpt: {
    flex: 1, paddingVertical: 14, borderRadius: 14, alignItems: 'center',
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
  },
  toggleOptOn: { backgroundColor: 'rgba(184,134,11,0.2)', borderColor: '#B8860B' },
  toggleOptOff: { backgroundColor: 'rgba(224,92,122,0.12)', borderColor: 'rgba(224,92,122,0.5)' },
  toggleOptText: { fontSize: 13, color: 'rgba(255,255,255,0.6)', fontWeight: '700' },
  toggleOptTextOn: { color: '#B8860B' },
  toggleOptTextOff: { color: '#E05C7A' },
  saveBtn: {
    backgroundColor: '#B8860B', borderRadius: 30, paddingVertical: 16,
    alignItems: 'center', marginTop: 16,
  },
  saveBtnText: { color: '#0D0D0D', fontSize: 15, fontWeight: '800', letterSpacing: 0.5 },
  deleteBtn: {
    flexDirection: 'row', gap: 8, alignItems: 'center', justifyContent: 'center',
    paddingVertical: 16, marginTop: 12,
  },
  deleteBtnText: { color: '#E05C7A', fontSize: 13, fontWeight: '700' },
});
