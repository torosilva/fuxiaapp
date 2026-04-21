import React, { useState, useRef, useEffect } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, TextInput,
  StatusBar, ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { useAuth } from '@/lib/hooks/useAuth';

const CODE_LENGTH = 6;

export default function VerifyScreen() {
  const { phone } = useLocalSearchParams<{ phone: string }>();
  const [digits, setDigits] = useState<string[]>(Array(CODE_LENGTH).fill(''));
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [countdown, setCountdown] = useState(60);
  const inputRefs = useRef<TextInput[]>([]);
  const { verifyOTP, sendOTP } = useAuth();

  useEffect(() => {
    const timer = setInterval(() => {
      setCountdown(c => (c > 0 ? c - 1 : 0));
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  const handleDigit = (text: string, index: number) => {
    const cleaned = text.replace(/\D/g, '').slice(-1);
    const next = [...digits];
    next[index] = cleaned;
    setDigits(next);
    if (cleaned && index < CODE_LENGTH - 1) {
      inputRefs.current[index + 1]?.focus();
    }
    if (next.every(d => d !== '') && cleaned) {
      handleVerify(next.join(''));
    }
  };

  const handleKeyPress = (key: string, index: number) => {
    if (key === 'Backspace' && !digits[index] && index > 0) {
      inputRefs.current[index - 1]?.focus();
    }
  };

  const handleVerify = async (code: string) => {
    setError('');
    setLoading(true);
    const result = await verifyOTP(phone, code);
    setLoading(false);
    if (result.error) {
      setError(result.error);
      setDigits(Array(CODE_LENGTH).fill(''));
      inputRefs.current[0]?.focus();
    } else if (result.isNewUser) {
      router.replace({ pathname: '/onboarding/complete-profile' as any, params: { phone } });
    } else {
      router.replace('/(tabs)');
    }
  };

  const handleResend = async () => {
    if (countdown > 0) return;
    setCountdown(60);
    setError('');
    await sendOTP(phone);
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <MotiView
        from={{ opacity: 0, translateY: 20 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 500 }}
        style={styles.content}
      >
        <Text style={styles.eyebrow}>PASO 3 DE 3</Text>
        <Text style={styles.title}>Ingresa{'\n'}tu código</Text>
        <Text style={styles.subtitle}>
          Enviamos un código de 6 dígitos a{'\n'}
          <Text style={{ color: '#CD7F32' }}>{phone}</Text>
          {'\n'}por WhatsApp
        </Text>

        <View style={styles.codeRow}>
          {digits.map((d, i) => (
            <TextInput
              key={i}
              ref={r => { if (r) inputRefs.current[i] = r; }}
              style={[styles.digitInput, d && styles.digitFilled]}
              value={d}
              onChangeText={t => handleDigit(t, i)}
              onKeyPress={({ nativeEvent }) => handleKeyPress(nativeEvent.key, i)}
              keyboardType="number-pad"
              maxLength={1}
              autoFocus={i === 0}
              selectTextOnFocus
            />
          ))}
        </View>

        {loading && (
          <View style={styles.loadingRow}>
            <ActivityIndicator color="#CD7F32" size="small" />
            <Text style={styles.loadingText}>Verificando...</Text>
          </View>
        )}

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <TouchableOpacity onPress={handleResend} disabled={countdown > 0}>
          <Text style={[styles.resend, countdown > 0 && styles.resendDisabled]}>
            {countdown > 0
              ? `Reenviar código en ${countdown}s`
              : 'Reenviar código'}
          </Text>
        </TouchableOpacity>
      </MotiView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
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
    marginBottom: 40, lineHeight: 22,
  },
  codeRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 10,
    marginBottom: 24,
  },
  digitInput: {
    width: 46,
    height: 58,
    borderRadius: 12,
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    textAlign: 'center',
    fontSize: 24,
    fontWeight: '700',
    color: '#FFF',
  },
  digitFilled: { borderColor: '#CD7F32' },
  loadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginBottom: 12,
  },
  loadingText: { color: 'rgba(255,255,255,0.5)', fontSize: 13 },
  error: {
    color: '#FF6B6B', fontSize: 13,
    textAlign: 'center', marginBottom: 16,
  },
  resend: {
    color: '#CD7F32', fontSize: 13,
    textAlign: 'center', fontWeight: '600',
  },
  resendDisabled: { color: 'rgba(255,255,255,0.25)' },
});
