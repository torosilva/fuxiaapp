import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  StatusBar,
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, ChevronDown } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface Channel {
  id: string;
  name: string;
  type: 'store' | 'bazar';
}

export default function StaffNewScreen() {
  const [name, setName] = useState('');
  const [pin, setPin] = useState('');
  const [channels, setChannels] = useState<Channel[]>([]);
  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [channelPickerOpen, setChannelPickerOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [loadingChannels, setLoadingChannels] = useState(true);

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from('channels')
        .select('id, name, type')
        .eq('active', true)
        .order('name');
      if (data) setChannels(data as Channel[]);
      setLoadingChannels(false);
    })();
  }, []);

  const handleCreate = async () => {
    if (!name.trim()) {
      Alert.alert('Campo requerido', 'El nombre es obligatorio.');
      return;
    }
    if (pin.length !== 4 || !/^\d{4}$/.test(pin)) {
      Alert.alert('PIN inválido', 'El PIN debe ser exactamente 4 dígitos.');
      return;
    }

    setLoading(true);
    try {
      const { error } = await supabase.from('staff').insert({
        name: name.trim(),
        pin,
        channel_id: selectedChannel?.id ?? null,
        active: true,
      });
      if (error) throw error;
      router.back();
    } catch (err: any) {
      Alert.alert('Error', err?.message ?? 'No se pudo crear la vendedora.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={styles.scroll}
          keyboardShouldPersistTaps="handled"
        >
          <MotiView
            from={{ opacity: 0, translateY: 16 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 400 }}
          >
            <TouchableOpacity
              style={styles.backBtn}
              onPress={() => router.back()}
              activeOpacity={0.7}
            >
              <ArrowLeft size={20} color="#B8860B" />
            </TouchableOpacity>

            <Text style={styles.eyebrow}>PANEL ADMIN</Text>
            <Text style={styles.title}>Nueva Vendedora</Text>

            <View style={styles.field}>
              <Text style={styles.label}>Nombre</Text>
              <TextInput
                style={styles.input}
                value={name}
                onChangeText={setName}
                placeholder="Nombre completo"
                placeholderTextColor="rgba(255,255,255,0.25)"
                autoCapitalize="words"
              />
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>PIN (4 dígitos)</Text>
              <TextInput
                style={styles.input}
                value={pin}
                onChangeText={(t) => setPin(t.replace(/\D/g, '').slice(0, 4))}
                placeholder="····"
                placeholderTextColor="rgba(255,255,255,0.25)"
                keyboardType="number-pad"
                secureTextEntry
                maxLength={4}
              />
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>Asignar Canal <Text style={styles.optional}>(opcional)</Text></Text>
              {loadingChannels ? (
                <ActivityIndicator color="#B8860B" style={{ marginTop: 8 }} />
              ) : (
                <>
                  <TouchableOpacity
                    style={styles.picker}
                    onPress={() => setChannelPickerOpen((v) => !v)}
                    activeOpacity={0.8}
                  >
                    <Text style={[styles.pickerText, !selectedChannel && styles.pickerPlaceholder]}>
                      {selectedChannel ? selectedChannel.name : 'Selecciona un canal'}
                    </Text>
                    <ChevronDown size={18} color="rgba(255,255,255,0.4)" />
                  </TouchableOpacity>

                  {channelPickerOpen && (
                    <MotiView
                      from={{ opacity: 0, translateY: -8 }}
                      animate={{ opacity: 1, translateY: 0 }}
                      transition={{ type: 'timing', duration: 200 }}
                      style={styles.dropdownList}
                    >
                      <TouchableOpacity
                        style={styles.dropdownItem}
                        onPress={() => { setSelectedChannel(null); setChannelPickerOpen(false); }}
                      >
                        <Text style={[styles.dropdownItemText, styles.dropdownNone]}>Sin canal</Text>
                      </TouchableOpacity>
                      {channels.map((ch) => (
                        <TouchableOpacity
                          key={ch.id}
                          style={[
                            styles.dropdownItem,
                            selectedChannel?.id === ch.id && styles.dropdownItemSelected,
                          ]}
                          onPress={() => { setSelectedChannel(ch); setChannelPickerOpen(false); }}
                        >
                          <Text style={styles.dropdownItemText}>{ch.name}</Text>
                          <Text style={styles.dropdownItemBadge}>
                            {ch.type === 'store' ? 'TIENDA' : 'BAZAR'}
                          </Text>
                        </TouchableOpacity>
                      ))}
                    </MotiView>
                  )}
                </>
              )}
            </View>

            <TouchableOpacity
              style={[styles.createBtn, loading && styles.createBtnDisabled]}
              onPress={handleCreate}
              activeOpacity={0.85}
              disabled={loading}
            >
              {loading ? (
                <ActivityIndicator color="#0D0D0D" size="small" />
              ) : (
                <Text style={styles.createBtnText}>Crear Vendedora</Text>
              )}
            </TouchableOpacity>
          </MotiView>
        </ScrollView>
      </KeyboardAvoidingView>
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
    paddingBottom: 60,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
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
  field: {
    marginBottom: 20,
  },
  label: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.5)',
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  optional: {
    fontWeight: '400',
    textTransform: 'none',
    letterSpacing: 0,
  },
  input: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 14,
    paddingHorizontal: 16,
    paddingVertical: 14,
    fontSize: 15,
    color: '#fff',
  },
  picker: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 14,
    paddingHorizontal: 16,
    paddingVertical: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  pickerText: {
    fontSize: 15,
    color: '#fff',
  },
  pickerPlaceholder: {
    color: 'rgba(255,255,255,0.25)',
  },
  dropdownList: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 14,
    marginTop: 4,
    overflow: 'hidden',
  },
  dropdownItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  dropdownItemSelected: {
    backgroundColor: 'rgba(184,134,11,0.1)',
  },
  dropdownItemText: {
    fontSize: 14,
    color: '#fff',
  },
  dropdownNone: {
    color: 'rgba(255,255,255,0.4)',
  },
  dropdownItemBadge: {
    fontSize: 9,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 1,
  },
  createBtn: {
    backgroundColor: '#B8860B',
    borderRadius: 30,
    paddingVertical: 16,
    alignItems: 'center',
    marginTop: 16,
  },
  createBtnDisabled: {
    opacity: 0.6,
  },
  createBtnText: {
    color: '#0D0D0D',
    fontSize: 15,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
});
