import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, TextInput,
  StatusBar, ActivityIndicator, KeyboardAvoidingView, Platform, ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { useAuth } from '@/lib/hooks/useAuth';

function formatBirthday(raw: string): string {
  const digits = raw.replace(/\D/g, '').slice(0, 8);
  if (digits.length <= 2) return digits;
  if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`;
  return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`;
}

function parseBirthdayToISO(formatted: string): string | undefined {
  const parts = formatted.split('/');
  if (parts.length !== 3 || parts[2].length !== 4) return undefined;
  const [dd, mm, yyyy] = parts;
  const d = parseInt(dd, 10), m = parseInt(mm, 10), y = parseInt(yyyy, 10);
  if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1900 || y > new Date().getFullYear()) return undefined;
  return `${yyyy}-${mm.padStart(2, '0')}-${dd.padStart(2, '0')}`;
}

export default function CompleteProfileScreen() {
  const { phone } = useLocalSearchParams<{ phone: string }>();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [birthday, setBirthday] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const { createProfile } = useAuth();

  const emailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
  const birthdayIso = parseBirthdayToISO(birthday);
  const birthdayValid = birthday.length === 0 || !!birthdayIso;
  const canSubmit = name.trim().length >= 2 && emailValid && !loading;

  const handleSave = async () => {
    if (!canSubmit) return;
    if (!emailValid) { setError('Ingresa un email válido'); return; }
    setError('');
    setLoading(true);
    const result = await createProfile(phone, name.trim(), email.trim(), birthdayIso);
    setLoading(false);
    if (result.error) {
      setError(result.error);
    } else {
      router.replace('/(tabs)');
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <MotiView
            from={{ opacity: 0, translateY: 20 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 500 }}
          >
            <Text style={styles.eyebrow}>ÚLTIMO PASO</Text>
            <Text style={styles.title}>Crea tu{'\n'}perfil Fuxia</Text>
            <Text style={styles.subtitle}>
              Tu email vincula tus compras del sitio web con tu tarjeta de puntos
            </Text>

            <View style={styles.field}>
              <Text style={styles.label}>NOMBRE COMPLETO</Text>
              <TextInput
                style={styles.input}
                value={name}
                onChangeText={setName}
                placeholder="Ana García"
                placeholderTextColor="rgba(255,255,255,0.2)"
                autoCapitalize="words"
                autoFocus
              />
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>EMAIL <Text style={styles.required}>*</Text></Text>
              <TextInput
                style={[styles.input, email.length > 0 && !emailValid && styles.inputError]}
                value={email}
                onChangeText={setEmail}
                placeholder="ana@ejemplo.com"
                placeholderTextColor="rgba(255,255,255,0.2)"
                keyboardType="email-address"
                autoCapitalize="none"
                autoCorrect={false}
              />
              <Text style={styles.fieldHint}>
                Necesario para vincular tus compras en fuxiaballerinas.com
              </Text>
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>FECHA DE CUMPLEAÑOS <Text style={styles.optional}>(opcional)</Text></Text>
              <TextInput
                style={[styles.input, birthday.length > 0 && !birthdayValid && styles.inputError]}
                value={birthday}
                onChangeText={(t) => setBirthday(formatBirthday(t))}
                placeholder="DD/MM/AAAA"
                placeholderTextColor="rgba(255,255,255,0.2)"
                keyboardType="numeric"
                maxLength={10}
              />
              <Text style={styles.fieldHint}>Para mandarte una sorpresa en tu día 🎂</Text>
            </View>

            {error ? <Text style={styles.error}>{error}</Text> : null}

            <TouchableOpacity
              style={[styles.btn, !canSubmit && styles.btnDisabled]}
              onPress={handleSave}
              disabled={!canSubmit}
              activeOpacity={0.8}
            >
              {loading
                ? <ActivityIndicator color="#0D0D0D" />
                : <Text style={styles.btnText}>Crear mi tarjeta de lealtad</Text>
              }
            </TouchableOpacity>
          </MotiView>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 60 },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 8, marginTop: 20,
  },
  title: {
    fontSize: 38, color: '#FFF', fontFamily: 'serif',
    fontWeight: '400', lineHeight: 44, marginBottom: 8,
  },
  subtitle: {
    fontSize: 14, color: 'rgba(255,255,255,0.4)',
    marginBottom: 40, lineHeight: 20,
  },
  field: { marginBottom: 24 },
  label: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 2, marginBottom: 8,
  },
  required: { color: '#FF6B6B' },
  optional: { color: 'rgba(205,127,50,0.5)', fontWeight: '400', letterSpacing: 0 },
  input: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 12,
    paddingHorizontal: 16,
    height: 54,
    color: '#FFF',
    fontSize: 16,
  },
  inputError: {
    borderColor: 'rgba(255,107,107,0.5)',
  },
  fieldHint: {
    color: 'rgba(255,255,255,0.25)',
    fontSize: 11,
    marginTop: 6,
  },
  error: { color: '#FF6B6B', fontSize: 13, marginBottom: 16 },
  btn: {
    backgroundColor: '#CD7F32',
    borderRadius: 30,
    height: 54,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 8,
  },
  btnDisabled: { opacity: 0.4 },
  btnText: { color: '#0D0D0D', fontSize: 14, fontWeight: '800', letterSpacing: 1 },
});
