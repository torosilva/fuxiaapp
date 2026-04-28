import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, TextInput,
  StatusBar, ActivityIndicator, KeyboardAvoidingView, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft } from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';

// Default to MX since it's the main market; user can edit the prefix manually if needed.
const DEFAULT_COUNTRY_CODE = '+52';

export default function LoginScreen() {
  const [number, setNumber] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const { checkPhone, sendOTP } = useAuth();

  const fullPhone = `${DEFAULT_COUNTRY_CODE}${number.replace(/\D/g, '')}`;

  const handleLogin = async () => {
    if (number.replace(/\D/g, '').length < 8) {
      setError('Ingresa un número válido');
      return;
    }
    setError('');
    setLoading(true);

    const check = await checkPhone(fullPhone);
    if (check.error) {
      setError(check.error);
      setLoading(false);
      return;
    }
    if (!check.exists) {
      setError('No encontramos una cuenta con ese número. ¿Eres nueva? Toca "Crear cuenta" en la pantalla anterior.');
      setLoading(false);
      return;
    }

    const send = await sendOTP(fullPhone);
    setLoading(false);
    if (send.error) {
      setError(send.error);
    } else {
      router.push({ pathname: '/onboarding/verify' as any, params: { phone: fullPhone } });
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        <TouchableOpacity style={styles.back} onPress={() => router.back()}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>

        <MotiView
          from={{ opacity: 0, translateY: 20 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 500 }}
          style={styles.content}
        >
          <Text style={styles.eyebrow}>INICIAR SESIÓN</Text>
          <Text style={styles.title}>Bienvenida{'\n'}de vuelta</Text>
          <Text style={styles.subtitle}>
            Ingresa tu número de WhatsApp y te enviamos el código.
          </Text>

          <View style={styles.inputRow}>
            <View style={styles.codeBox}>
              <Text style={styles.codeText}>{DEFAULT_COUNTRY_CODE}</Text>
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
            onPress={handleLogin}
            disabled={loading || number.length < 8}
            activeOpacity={0.8}
          >
            {loading
              ? <ActivityIndicator color="#0D0D0D" />
              : <Text style={styles.btnText}>Enviar código</Text>
            }
          </TouchableOpacity>

          <TouchableOpacity
            onPress={() => router.replace('/onboarding/country' as any)}
            style={styles.signupLink}
          >
            <Text style={styles.signupText}>
              ¿No tienes cuenta? <Text style={styles.signupTextBold}>Crear cuenta</Text>
            </Text>
          </TouchableOpacity>
        </MotiView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  back: {
    position: 'absolute', top: 20, left: 20, zIndex: 10,
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
  },
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
  inputRow: { flexDirection: 'row', gap: 10, marginBottom: 12 },
  codeBox: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 12,
    paddingHorizontal: 16,
    justifyContent: 'center',
  },
  codeText: { color: '#FFF', fontSize: 16, fontWeight: '600' },
  input: {
    flex: 1,
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 12,
    paddingHorizontal: 16,
    height: 54,
    color: '#FFF',
    fontSize: 18,
    letterSpacing: 1,
  },
  error: { color: '#FF6B6B', fontSize: 13, marginBottom: 12, lineHeight: 18 },
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
  signupLink: {
    marginTop: 24,
    alignItems: 'center',
  },
  signupText: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 13,
  },
  signupTextBold: {
    color: '#CD7F32',
    fontWeight: '700',
  },
});
