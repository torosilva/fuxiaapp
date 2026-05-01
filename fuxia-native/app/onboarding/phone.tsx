import React, { useState, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, TextInput,
  StatusBar, ActivityIndicator, KeyboardAvoidingView, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { useAuth } from '@/lib/hooks/useAuth';

export default function PhoneScreen() {
  const { countryCode } = useLocalSearchParams<{ countryCode: string }>();
  const [number, setNumber] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const { sendOTP } = useAuth();

  const fullPhone = `${countryCode}${number.replace(/\s/g, '')}`;

  const handleSend = async () => {
    if (number.replace(/\D/g, '').length < 8) {
      setError('Ingresa un número válido');
      return;
    }
    setError('');
    setLoading(true);
    const result = await sendOTP(fullPhone);
    setLoading(false);
    if (result.error) {
      setError(result.error);
    } else {
      router.push({ pathname: '/onboarding/verify' as any, params: { phone: fullPhone } });
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.kav}
      >
        <MotiView
          from={{ opacity: 0, translateY: 20 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 500 }}
          style={styles.content}
        >
          <Text style={styles.eyebrow}>PASO 2 DE 3</Text>
          <Text style={styles.title}>Tu número{'\n'}de WhatsApp</Text>
          <Text style={styles.subtitle}>
            Te enviaremos un código de verificación por WhatsApp
          </Text>

          <View style={styles.inputRow}>
            <View style={styles.codeBox}>
              <Text style={styles.codeText}>{countryCode}</Text>
            </View>
            <TextInput
              style={styles.input}
              value={number}
              onChangeText={setNumber}
              placeholder="55 1234 5678"
              placeholderTextColor="rgba(255,255,255,0.2)"
              keyboardType="phone-pad"
              autoFocus
              maxLength={15}
            />
          </View>

          {error ? <Text style={styles.error}>{error}</Text> : null}

          <TouchableOpacity
            style={[styles.btn, (loading || number.length < 8) && styles.btnDisabled]}
            onPress={handleSend}
            disabled={loading || number.length < 8}
            activeOpacity={0.8}
          >
            {loading
              ? <ActivityIndicator color="#0D0D0D" />
              : <Text style={styles.btnText}>Enviar código por WhatsApp</Text>
            }
          </TouchableOpacity>

          <Text style={styles.hint}>
            Al continuar aceptas recibir mensajes de WhatsApp de Fuxia Ballerinas
          </Text>
        </MotiView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  kav: { flex: 1 },
  content: { flex: 1, padding: 24, justifyContent: 'center' },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 8,
  },
  title: {
    fontSize: 38, color: '#FFF', fontFamily: 'serif',
    fontWeight: '400', lineHeight: 44, marginBottom: 8,
  },
  subtitle: {
    fontSize: 14, color: 'rgba(255,255,255,0.4)',
    marginBottom: 36, lineHeight: 20,
  },
  inputRow: {
    flexDirection: 'row',
    gap: 10,
    marginBottom: 12,
  },
  codeBox: {
    backgroundColor: 'rgba(255,255,255,0.07)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    borderRadius: 14,
    paddingHorizontal: 16,
    justifyContent: 'center',
  },
  codeText: { color: '#FFF', fontSize: 16, fontWeight: '600' },
  input: {
    flex: 1,
    backgroundColor: 'rgba(255,255,255,0.07)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    borderRadius: 14,
    paddingHorizontal: 16,
    height: 54,
    color: '#FFF',
    fontSize: 18,
    letterSpacing: 1,
  },
  error: { color: '#FF6B6B', fontSize: 13, marginBottom: 12 },
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
  hint: {
    color: 'rgba(255,255,255,0.2)',
    fontSize: 11,
    textAlign: 'center',
    marginTop: 16,
    lineHeight: 16,
  },
});
