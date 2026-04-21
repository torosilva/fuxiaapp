import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, TextInput,
  StatusBar, ActivityIndicator, KeyboardAvoidingView, Platform, ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { useAuth } from '@/lib/hooks/useAuth';

export default function CompleteProfileScreen() {
  const { phone } = useLocalSearchParams<{ phone: string }>();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const { createProfile } = useAuth();

  const handleSave = async () => {
    if (name.trim().length < 2) {
      setError('Ingresa tu nombre completo');
      return;
    }
    setError('');
    setLoading(true);
    const result = await createProfile(phone, name.trim(), email.trim() || undefined);
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
        <ScrollView contentContainerStyle={styles.scroll}>
          <MotiView
            from={{ opacity: 0, translateY: 20 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 500 }}
          >
            <Text style={styles.eyebrow}>ÚLTIMO PASO</Text>
            <Text style={styles.title}>Cuéntanos{'\n'}tu nombre</Text>
            <Text style={styles.subtitle}>
              Así personalizamos tu experiencia Fuxia
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
              <Text style={styles.label}>EMAIL (opcional)</Text>
              <TextInput
                style={styles.input}
                value={email}
                onChangeText={setEmail}
                placeholder="ana@ejemplo.com"
                placeholderTextColor="rgba(255,255,255,0.2)"
                keyboardType="email-address"
                autoCapitalize="none"
              />
              <Text style={styles.fieldHint}>Para recibir facturas y confirmaciones de compra</Text>
            </View>

            {error ? <Text style={styles.error}>{error}</Text> : null}

            <TouchableOpacity
              style={[styles.btn, (loading || name.length < 2) && styles.btnDisabled]}
              onPress={handleSave}
              disabled={loading || name.length < 2}
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
