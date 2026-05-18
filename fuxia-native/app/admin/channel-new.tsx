import React, { useState } from 'react';
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
import { ArrowLeft, Store, ShoppingBag } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

type ChannelType = 'store' | 'bazar';

export default function ChannelNewScreen() {
  const [name, setName] = useState('');
  const [type, setType] = useState<ChannelType>('store');
  const [location, setLocation] = useState('');
  const [eventDate, setEventDate] = useState('');
  const [loading, setLoading] = useState(false);

  const handleCreate = async () => {
    if (!name.trim()) {
      Alert.alert('Campo requerido', 'El nombre del canal es obligatorio.');
      return;
    }
    if (type === 'bazar' && eventDate.trim()) {
      const parts = eventDate.trim().split('/');
      if (parts.length !== 3 || parts.some((p) => isNaN(Number(p)))) {
        Alert.alert('Formato incorrecto', 'La fecha debe ser DD/MM/YYYY.');
        return;
      }
    }

    setLoading(true);
    try {
      let formattedDate: string | null = null;
      if (type === 'bazar' && eventDate.trim()) {
        const [dd, mm, yyyy] = eventDate.trim().split('/');
        formattedDate = `${yyyy}-${mm.padStart(2, '0')}-${dd.padStart(2, '0')}`;
      }

      const { error } = await supabase.from('channels').insert({
        name: name.trim(),
        type,
        location: location.trim() || null,
        event_date: formattedDate,
        active: true,
      });

      if (error) throw error;
      router.back();
    } catch (err: any) {
      Alert.alert('Error', err?.message ?? 'No se pudo crear el canal.');
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
            <Text style={styles.title}>Nuevo Canal</Text>

            <View style={styles.field}>
              <Text style={styles.label}>Nombre del canal</Text>
              <TextInput
                style={styles.input}
                value={name}
                onChangeText={setName}
                placeholder="Ej. Tienda Roma Norte"
                placeholderTextColor="rgba(255,255,255,0.25)"
                autoCapitalize="words"
              />
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>Tipo</Text>
              <View style={styles.typeRow}>
                <TouchableOpacity
                  style={[styles.typeBtn, type === 'store' && styles.typeBtnActive]}
                  onPress={() => setType('store')}
                  activeOpacity={0.8}
                >
                  <Store size={18} color={type === 'store' ? '#0D0D0D' : '#B8860B'} />
                  <Text style={[styles.typeBtnText, type === 'store' && styles.typeBtnTextActive]}>
                    Tienda Física
                  </Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={[styles.typeBtn, type === 'bazar' && styles.typeBtnActive]}
                  onPress={() => setType('bazar')}
                  activeOpacity={0.8}
                >
                  <ShoppingBag size={18} color={type === 'bazar' ? '#0D0D0D' : '#B8860B'} />
                  <Text style={[styles.typeBtnText, type === 'bazar' && styles.typeBtnTextActive]}>
                    Bazar
                  </Text>
                </TouchableOpacity>
              </View>
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>Ubicación <Text style={styles.optional}>(opcional)</Text></Text>
              <TextInput
                style={styles.input}
                value={location}
                onChangeText={setLocation}
                placeholder="Ej. Av. Álvaro Obregón 45, CDMX"
                placeholderTextColor="rgba(255,255,255,0.25)"
                autoCapitalize="sentences"
              />
            </View>

            {type === 'bazar' && (
              <MotiView
                from={{ opacity: 0, translateY: -8 }}
                animate={{ opacity: 1, translateY: 0 }}
                transition={{ type: 'timing', duration: 250 }}
              >
                <View style={styles.field}>
                  <Text style={styles.label}>Fecha del evento</Text>
                  <TextInput
                    style={styles.input}
                    value={eventDate}
                    onChangeText={(text) => {
                      // Strip non-digits then auto-insert slashes
                      const digits = text.replace(/\D/g, '');
                      let formatted = digits;
                      if (digits.length > 2) formatted = digits.slice(0, 2) + '/' + digits.slice(2);
                      if (digits.length > 4) formatted = formatted.slice(0, 5) + '/' + digits.slice(4, 8);
                      setEventDate(formatted);
                    }}
                    placeholder="DD/MM/YYYY"
                    placeholderTextColor="rgba(255,255,255,0.25)"
                    keyboardType="number-pad"
                    maxLength={10}
                  />
                </View>
              </MotiView>
            )}

            <TouchableOpacity
              style={[styles.createBtn, loading && styles.createBtnDisabled]}
              onPress={handleCreate}
              activeOpacity={0.85}
              disabled={loading}
            >
              {loading ? (
                <ActivityIndicator color="#0D0D0D" size="small" />
              ) : (
                <Text style={styles.createBtnText}>Crear Canal</Text>
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
  typeRow: {
    flexDirection: 'row',
    gap: 12,
  },
  typeBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(184,134,11,0.3)',
    backgroundColor: '#1A1A1A',
  },
  typeBtnActive: {
    backgroundColor: '#B8860B',
    borderColor: '#B8860B',
  },
  typeBtnText: {
    fontSize: 14,
    color: '#B8860B',
    fontWeight: '700',
  },
  typeBtnTextActive: {
    color: '#0D0D0D',
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
