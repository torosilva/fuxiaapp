import React, { useMemo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Redirect, router, Stack } from 'expo-router';
import { MotiView } from 'moti';
import {
  ArrowLeft,
  Award,
  Gift,
  Truck,
  Sparkles,
  Crown,
  Cake,
  Users,
  Check,
} from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';

type Tier = 'bronze' | 'silver' | 'gold';

interface TierSpec {
  key: Tier;
  name: string;
  minPoints: number;
  minPairs: number;
  color: string;
  perks: { icon: any; label: string }[];
}

const TIERS: TierSpec[] = [
  {
    key: 'bronze',
    name: 'Bronze',
    minPoints: 0,
    minPairs: 0,
    color: '#CD7F32',
    perks: [
      { icon: Sparkles, label: 'Acumulación de puntos en todas tus compras' },
      { icon: Gift, label: 'Acceso a la tarjeta de lealtad digital' },
      { icon: Users, label: 'Programa de referidos 2× activo' },
    ],
  },
  {
    key: 'silver',
    name: 'Silver',
    minPoints: 300,
    minPairs: 3,
    color: '#C0C0C0',
    perks: [
      { icon: Sparkles, label: 'Todo lo de Bronze' },
      { icon: Gift, label: '5% de descuento permanente en tienda y web' },
      { icon: Truck, label: 'Envío gratis en pedidos mayores a $1,500 MXN' },
      { icon: Cake, label: 'Regalo de cumpleaños · 50 puntos extra' },
    ],
  },
  {
    key: 'gold',
    name: 'Gold',
    minPoints: 900,
    minPairs: 9,
    color: '#FFD700',
    perks: [
      { icon: Sparkles, label: 'Todo lo de Silver' },
      { icon: Gift, label: '10% de descuento permanente' },
      { icon: Truck, label: 'Envío gratis en TODAS tus compras' },
      { icon: Crown, label: 'Acceso anticipado a nuevas colecciones (48 h antes)' },
      { icon: Cake, label: 'Regalo de cumpleaños · 100 puntos + sorpresa física' },
      { icon: Award, label: 'Atención personalizada vía Hilo prioritario' },
    ],
  },
];

export default function BeneficiosScreen() {
  const { session, customer, loyaltyCard, isLoading } = useAuth();

  const currentTier: Tier = loyaltyCard?.tier ?? 'bronze';
  const totalPoints = loyaltyCard?.total_points ?? 0;
  const pairsCount = loyaltyCard?.pairs_count ?? 0;

  const { current, next, progress } = useMemo(() => {
    const idx = TIERS.findIndex((t) => t.key === currentTier);
    const cur = TIERS[idx];
    const nxt = idx < TIERS.length - 1 ? TIERS[idx + 1] : null;
    if (!nxt) return { current: cur, next: null, progress: 1 };

    const pointsProgress = Math.min(1, totalPoints / nxt.minPoints);
    const pairsProgress = Math.min(1, pairsCount / nxt.minPairs);
    const best = Math.max(pointsProgress, pairsProgress);
    return { current: cur, next: nxt, progress: best };
  }, [currentTier, totalPoints, pairsCount]);

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator color="#CD7F32" />
      </SafeAreaView>
    );
  }

  if (!session || !customer) return <Redirect href="/onboarding" />;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>
        <View>
          <Text style={styles.eyebrow}>TU PROGRAMA DE LEALTAD</Text>
          <Text style={styles.title}>Beneficios</Text>
        </View>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        {/* Current tier hero */}
        <MotiView
          from={{ opacity: 0, translateY: 12 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 400 }}
          style={[styles.heroCard, { borderColor: current.color + '55' }]}
        >
          <View style={[styles.tierBadge, { backgroundColor: current.color + '22', borderColor: current.color }]}>
            <Crown size={14} color={current.color} />
            <Text style={[styles.tierBadgeText, { color: current.color }]}>NIVEL {current.name.toUpperCase()}</Text>
          </View>
          <Text style={styles.heroSubtitle}>Hola, {customer.name?.split(' ')[0] ?? 'tú'}</Text>
          <Text style={styles.heroPoints}>
            {totalPoints} <Text style={styles.heroPointsLabel}>puntos · {pairsCount} {pairsCount === 1 ? 'par' : 'pares'}</Text>
          </Text>

          {next && (
            <View style={styles.progressWrap}>
              <View style={styles.progressTrack}>
                <View
                  style={[styles.progressFill, { width: `${progress * 100}%`, backgroundColor: next.color }]}
                />
              </View>
              <Text style={styles.progressText}>
                {Math.max(0, next.minPoints - totalPoints)} puntos o {Math.max(0, next.minPairs - pairsCount)}{' '}
                {next.minPairs - pairsCount === 1 ? 'par' : 'pares'} para{' '}
                <Text style={{ color: next.color, fontWeight: '800' }}>{next.name}</Text>
              </Text>
            </View>
          )}

          {!next && (
            <View style={styles.maxTierBox}>
              <Sparkles size={14} color="#FFD700" />
              <Text style={styles.maxTierText}>Llegaste al nivel más alto. Gracias por ser parte de Fuxia.</Text>
            </View>
          )}
        </MotiView>

        {/* All tiers list with perks */}
        {TIERS.map((tier, i) => {
          const reached = TIERS.findIndex((t) => t.key === currentTier) >= i;
          const isCurrent = tier.key === currentTier;
          return (
            <MotiView
              key={tier.key}
              from={{ opacity: 0, translateY: 12 }}
              animate={{ opacity: 1, translateY: 0 }}
              transition={{ type: 'timing', duration: 400, delay: 100 + i * 80 }}
              style={[styles.tierCard, isCurrent && { borderColor: tier.color, borderWidth: 1.5 }]}
            >
              <View style={styles.tierHeader}>
                <View style={[styles.tierDot, { backgroundColor: tier.color }]} />
                <Text style={[styles.tierName, { color: tier.color }]}>{tier.name}</Text>
                {isCurrent && (
                  <View style={styles.currentChip}>
                    <Text style={styles.currentChipText}>TU NIVEL</Text>
                  </View>
                )}
                {!isCurrent && reached && (
                  <View style={styles.reachedChip}>
                    <Check size={10} color="#0D0D0D" strokeWidth={3} />
                  </View>
                )}
              </View>
              <Text style={styles.tierReq}>
                Desde {tier.minPoints} puntos o {tier.minPairs} {tier.minPairs === 1 ? 'par' : 'pares'}
              </Text>
              <View style={styles.perks}>
                {tier.perks.map((p, idx) => {
                  const Icon = p.icon;
                  return (
                    <View key={idx} style={styles.perkRow}>
                      <Icon size={14} color={tier.color} />
                      <Text style={styles.perkText}>{p.label}</Text>
                    </View>
                  );
                })}
              </View>
            </MotiView>
          );
        })}

        {/* Referral mini-block */}
        <MotiView
          from={{ opacity: 0, translateY: 12 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 400, delay: 400 }}
          style={styles.referralCard}
        >
          <Users size={20} color="#CD7F32" />
          <View style={{ flex: 1, marginLeft: 12 }}>
            <Text style={styles.referralTitle}>Bonus por referidas</Text>
            <Text style={styles.referralSubtitle}>
              Cuando una amiga compra usando tu código, recibís 2× sus puntos como bonus.
            </Text>
          </View>
          <TouchableOpacity style={styles.referralBtn} onPress={() => router.push('/referral' as any)}>
            <Text style={styles.referralBtnText}>Ver</Text>
          </TouchableOpacity>
        </MotiView>

        <Text style={styles.disclaimer}>
          Los beneficios pueden actualizarse. Términos completos en fuxiaballerinas.com/lealtad.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
  },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 2, textAlign: 'center',
  },
  title: { fontSize: 20, color: '#FFFFFF', fontFamily: 'serif', textAlign: 'center' },
  scroll: { padding: 20, paddingBottom: 140 },

  // Hero
  heroCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 24,
    padding: 22,
    marginBottom: 20,
    borderWidth: 1,
  },
  tierBadge: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    alignSelf: 'flex-start',
    paddingHorizontal: 10, paddingVertical: 5,
    borderRadius: 20, borderWidth: 1, marginBottom: 12,
  },
  tierBadgeText: { fontSize: 10, fontWeight: '800', letterSpacing: 2 },
  heroSubtitle: { color: 'rgba(255,255,255,0.6)', fontSize: 13, marginBottom: 4 },
  heroPoints: { color: '#FFF', fontSize: 32, fontFamily: 'serif', fontWeight: '400', marginBottom: 16 },
  heroPointsLabel: { color: 'rgba(255,255,255,0.45)', fontSize: 14 },
  progressWrap: { marginTop: 4 },
  progressTrack: {
    height: 6, backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 3, overflow: 'hidden', marginBottom: 8,
  },
  progressFill: { height: '100%', borderRadius: 3 },
  progressText: { color: 'rgba(255,255,255,0.6)', fontSize: 12, lineHeight: 18 },
  maxTierBox: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: 'rgba(255,215,0,0.08)',
    borderRadius: 12, padding: 12, marginTop: 8,
  },
  maxTierText: { color: 'rgba(255,255,255,0.75)', fontSize: 12, flex: 1, lineHeight: 16 },

  // Tier cards
  tierCard: {
    backgroundColor: '#161616',
    borderRadius: 18,
    padding: 18,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  tierHeader: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: 6,
  },
  tierDot: { width: 10, height: 10, borderRadius: 5 },
  tierName: { fontSize: 16, fontWeight: '700', flex: 1 },
  currentChip: {
    backgroundColor: '#CD7F32',
    paddingHorizontal: 8, paddingVertical: 3, borderRadius: 10,
  },
  currentChipText: { color: '#0D0D0D', fontSize: 9, fontWeight: '800', letterSpacing: 1 },
  reachedChip: {
    width: 20, height: 20, borderRadius: 10,
    backgroundColor: '#CD7F32',
    justifyContent: 'center', alignItems: 'center',
  },
  tierReq: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginBottom: 12, letterSpacing: 0.5 },
  perks: { gap: 10 },
  perkRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10 },
  perkText: { color: 'rgba(255,255,255,0.82)', fontSize: 13, flex: 1, lineHeight: 19 },

  // Referral block
  referralCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 18,
    padding: 16,
    marginTop: 8,
    marginBottom: 20,
    borderWidth: 1,
    borderColor: 'rgba(205,127,50,0.2)',
    flexDirection: 'row', alignItems: 'center',
  },
  referralTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginBottom: 2 },
  referralSubtitle: { color: 'rgba(255,255,255,0.5)', fontSize: 12, lineHeight: 16 },
  referralBtn: {
    backgroundColor: '#CD7F32', borderRadius: 18,
    paddingHorizontal: 14, paddingVertical: 8,
  },
  referralBtnText: { color: '#0D0D0D', fontSize: 12, fontWeight: '800' },

  disclaimer: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 11, textAlign: 'center', lineHeight: 16, marginTop: 4,
  },
});
