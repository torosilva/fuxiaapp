import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Star } from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

const CODE_LENGTH = 6;
const SAFE_CODE_REGEX = /^[A-Z2-9]$/;

type ClaimState = 'idle' | 'loading' | 'success' | 'error';

export default function ClaimScreen() {
  const { customer, loyaltyCard } = useAuth();
  const [digits, setDigits] = useState<string[]>(Array(CODE_LENGTH).fill(''));
  const [claimState, setClaimState] = useState<ClaimState>('idle');
  const [errorMsg, setErrorMsg] = useState('');
  const [result, setResult] = useState<{
    points_earned: number;
    new_total_points: number;
    tier: string;
  } | null>(null);
  const inputRefs = useRef<TextInput[]>([]);

  const code = digits.join('');
  const isComplete = digits.every((d) => d !== '');

  const handleDigit = (text: string, index: number) => {
    const cleaned = text.toUpperCase().replace(/[^A-Z2-9]/g, '').slice(-1);
    const next = [...digits];
    next[index] = cleaned;
    setDigits(next);
    setClaimState('idle');
    setErrorMsg('');
    if (cleaned && index < CODE_LENGTH - 1) {
      inputRefs.current[index + 1]?.focus();
    }
  };

  const handleKeyPress = (key: string, index: number) => {
    if (key === 'Backspace') {
      if (!digits[index] && index > 0) {
        const next = [...digits];
        next[index - 1] = '';
        setDigits(next);
        inputRefs.current[index - 1]?.focus();
      } else {
        const next = [...digits];
        next[index] = '';
        setDigits(next);
      }
    }
  };

  const handleClaim = async () => {
    if (!isComplete) return;
    if (!customer?.phone) {
      setClaimState('error');
      setErrorMsg('No se encontró tu número. Por favor inicia sesión de nuevo.');
      return;
    }

    setClaimState('loading');
    setErrorMsg('');

    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/claim-sale`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        },
        body: JSON.stringify({ code, phone: customer.phone }),
      });
      const data = await res.json();

      if (!res.ok) {
        setClaimState('error');
        setErrorMsg(data.error ?? 'Error al reclamar. Intenta de nuevo.');
        return;
      }

      setResult(data);
      setClaimState('success');
    } catch {
      setClaimState('error');
      setErrorMsg('Sin conexión. Intenta de nuevo.');
    }
  };

  const handleReset = () => {
    setDigits(Array(CODE_LENGTH).fill(''));
    setClaimState('idle');
    setErrorMsg('');
    setResult(null);
    setTimeout(() => inputRefs.current[0]?.focus(), 100);
  };

  const TIER_LABEL: Record<string, string> = {
    bronze: 'Bronce',
    silver: 'Plata',
    gold: 'Oro',
  };

  // ─── Success view ───────────────────────────────────────────────────────────
  if (claimState === 'success' && result) {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" />
        <MotiView
          from={{ opacity: 0, scale: 0.88 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: 'spring', stiffness: 200, damping: 22 }}
          style={styles.successContainer}
        >
          <MotiView
            from={{ rotate: '0deg' }}
            animate={{ rotate: '360deg' }}
            transition={{ type: 'timing', duration: 800, loop: false }}
          >
            <Star size={60} color="#B8860B" fill="#B8860B" />
          </MotiView>

          <Text style={styles.successTitle}>¡Puntos reclamados!</Text>

          <View style={styles.pointsCard}>
            <View style={styles.pointsRow}>
              <View style={styles.pointsItem}>
                <Text style={styles.pointsItemLabel}>Ganaste</Text>
                <Text style={styles.pointsItemValue}>+{result.points_earned}</Text>
                <Text style={styles.pointsItemUnit}>puntos</Text>
              </View>
              <View style={styles.pointsDivider} />
              <View style={styles.pointsItem}>
                <Text style={styles.pointsItemLabel}>Total</Text>
                <Text style={styles.pointsItemValue}>{result.new_total_points}</Text>
                <Text style={styles.pointsItemUnit}>puntos</Text>
              </View>
            </View>
            <View style={styles.tierRow}>
              <Text style={styles.tierLabel}>Nivel actual: </Text>
              <Text style={styles.tierValue}>{TIER_LABEL[result.tier] ?? result.tier}</Text>
            </View>
          </View>

          <TouchableOpacity style={styles.doneBtn} onPress={() => router.back()} activeOpacity={0.85}>
            <Text style={styles.doneBtnText}>Volver al perfil</Text>
          </TouchableOpacity>

          <TouchableOpacity style={styles.claimAnotherBtn} onPress={handleReset} activeOpacity={0.7}>
            <Text style={styles.claimAnotherText}>Reclamar otro código</Text>
          </TouchableOpacity>
        </MotiView>
      </SafeAreaView>
    );
  }

  // ─── Main view ──────────────────────────────────────────────────────────────
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />

      <MotiView
        from={{ opacity: 0, translateY: 20 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 450 }}
        style={styles.content}
      >
        <TouchableOpacity
          style={styles.backBtn}
          onPress={() => router.back()}
          activeOpacity={0.7}
        >
          <ArrowLeft size={20} color="#B8860B" />
        </TouchableOpacity>

        <Text style={styles.eyebrow}>CLUB FUXIA</Text>
        <Text style={styles.title}>Reclamar puntos{'\n'}de tienda</Text>
        <Text style={styles.subtitle}>
          Ingresa el código de 6 caracteres que te dio tu vendedora.
        </Text>

        {/* Code input boxes */}
        <View style={styles.codeRow}>
          {digits.map((d, i) => (
            <TextInput
              key={i}
              ref={(r) => { if (r) inputRefs.current[i] = r; }}
              style={[
                styles.digitInput,
                d && styles.digitFilled,
                claimState === 'error' && styles.digitError,
              ]}
              value={d}
              onChangeText={(t) => handleDigit(t, i)}
              onKeyPress={({ nativeEvent }) => handleKeyPress(nativeEvent.key, i)}
              keyboardType="default"
              autoCapitalize="characters"
              maxLength={1}
              autoFocus={i === 0}
              selectTextOnFocus
              editable={claimState !== 'loading'}
            />
          ))}
        </View>

        {claimState === 'loading' && (
          <View style={styles.loadingRow}>
            <ActivityIndicator color="#B8860B" size="small" />
            <Text style={styles.loadingText}>Verificando código...</Text>
          </View>
        )}

        {claimState === 'error' && errorMsg ? (
          <Text style={styles.errorText}>{errorMsg}</Text>
        ) : null}

        <TouchableOpacity
          style={[
            styles.claimBtn,
            (!isComplete || claimState === 'loading') && styles.claimBtnDisabled,
          ]}
          onPress={handleClaim}
          activeOpacity={0.85}
          disabled={!isComplete || claimState === 'loading'}
        >
          <Text style={styles.claimBtnText}>Reclamar</Text>
        </TouchableOpacity>

        <Text style={styles.hint}>
          El código son 6 letras y números mayúsculas.{'\n'}
          Ejemplo: AB3X7K
        </Text>
      </MotiView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
  },
  content: {
    flex: 1,
    padding: 24,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 28,
  },
  eyebrow: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 3,
    marginBottom: 4,
  },
  title: {
    fontSize: 34,
    color: '#fff',
    fontWeight: '700',
    lineHeight: 40,
    marginBottom: 12,
  },
  subtitle: {
    fontSize: 14,
    color: 'rgba(255,255,255,0.4)',
    lineHeight: 22,
    marginBottom: 40,
  },
  codeRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 8,
    marginBottom: 24,
  },
  digitInput: {
    width: 46,
    height: 60,
    borderRadius: 14,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    textAlign: 'center',
    fontSize: 22,
    fontWeight: '700',
    color: '#fff',
    letterSpacing: 0,
  },
  digitFilled: {
    borderColor: '#B8860B',
    backgroundColor: 'rgba(184,134,11,0.08)',
  },
  digitError: {
    borderColor: '#FF6B6B',
    backgroundColor: 'rgba(255,107,107,0.08)',
  },
  loadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginBottom: 12,
  },
  loadingText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
  },
  errorText: {
    color: '#FF6B6B',
    fontSize: 13,
    textAlign: 'center',
    marginBottom: 16,
  },
  claimBtn: {
    backgroundColor: '#B8860B',
    borderRadius: 30,
    paddingVertical: 16,
    alignItems: 'center',
    marginBottom: 20,
  },
  claimBtnDisabled: {
    opacity: 0.4,
  },
  claimBtnText: {
    color: '#0D0D0D',
    fontSize: 16,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  hint: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.25)',
    textAlign: 'center',
    lineHeight: 20,
  },
  // Success
  successContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
  },
  successTitle: {
    fontSize: 28,
    color: '#fff',
    fontWeight: '700',
    marginTop: 20,
    marginBottom: 28,
  },
  pointsCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(184,134,11,0.3)',
    width: '100%',
    overflow: 'hidden',
    marginBottom: 32,
  },
  pointsRow: {
    flexDirection: 'row',
  },
  pointsItem: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 24,
  },
  pointsDivider: {
    width: 1,
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  pointsItemLabel: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 2,
    textTransform: 'uppercase',
    marginBottom: 6,
  },
  pointsItemValue: {
    fontSize: 40,
    color: '#fff',
    fontWeight: '700',
  },
  pointsItemUnit: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
  },
  tierRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.06)',
    paddingVertical: 14,
  },
  tierLabel: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.4)',
  },
  tierValue: {
    fontSize: 13,
    color: '#B8860B',
    fontWeight: '700',
  },
  doneBtn: {
    backgroundColor: '#B8860B',
    borderRadius: 30,
    paddingHorizontal: 40,
    paddingVertical: 16,
    marginBottom: 14,
    width: '100%',
    alignItems: 'center',
  },
  doneBtnText: {
    color: '#0D0D0D',
    fontSize: 15,
    fontWeight: '800',
  },
  claimAnotherBtn: {
    paddingVertical: 12,
  },
  claimAnotherText: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 14,
    fontWeight: '600',
  },
});
