import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, StatusBar, Dimensions } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView, MotiText } from 'moti';

const { width, height } = Dimensions.get('window');

// Niveles (misma regla que tier_config: plata 300, oro 900).
const TIERS = [
  { min: 900, label: 'ORO', emoji: '🥇', color: '#DAA520', next: null as null | { at: number; label: string } },
  { min: 300, label: 'PLATA', emoji: '🥈', color: '#C0C0C0', next: { at: 900, label: 'ORO' } },
  { min: 0, label: 'BRONCE', emoji: '🥉', color: '#CD7F32', next: { at: 300, label: 'PLATA' } },
];
const tierFor = (pts: number) => TIERS.find((t) => pts >= t.min) ?? TIERS[TIERS.length - 1];

// Confetti liviano (React Native puro, sin librerías).
const CONFETTI_COLORS = ['#CD7F32', '#DAA520', '#E05C7A', '#C0C0C0', '#FFFFFF'];
const CONFETTI = Array.from({ length: 44 }, (_, i) => ({
  id: i,
  left: Math.random() * width,
  color: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
  delay: Math.random() * 900,
  size: 6 + Math.random() * 8,
  rotate: Math.round(Math.random() * 360),
  duration: 2200 + Math.random() * 1200,
}));

/**
 * Pantalla de celebración reutilizable. Se usa cada vez que se agregan puntos a
 * la tarjeta (compra web detectada, retro-crédito al registrarse, etc.).
 * Params:
 *   added  — puntos que se acaban de agregar (número héroe).
 *   total  — nuevo total en la tarjeta.
 *   title  — encabezado (default "PUNTOS AGREGADOS A TU TARJETA").
 *   found  — opcional: nº de compras encontradas (caso retro-crédito).
 */
export default function CelebratePointsScreen() {
  const params = useLocalSearchParams<{ added: string; total: string; title?: string; found?: string }>();
  const added = parseInt(params.added ?? '0', 10) || 0;
  const total = parseInt(params.total ?? '0', 10) || 0;
  const found = params.found ? parseInt(params.found, 10) : 0;
  const title = params.title || 'PUNTOS AGREGADOS A TU TARJETA';

  const tier = tierFor(total);
  const pointsToNext = tier.next ? Math.max(0, tier.next.at - total) : 0;

  // Contador que sube de 0 → added con easeOutCubic.
  const [display, setDisplay] = useState(0);
  useEffect(() => {
    const dur = 1600;
    const start = Date.now();
    const timer = setInterval(() => {
      const t = Math.min(1, (Date.now() - start) / dur);
      const eased = 1 - Math.pow(1 - t, 3);
      setDisplay(Math.round(eased * added));
      if (t >= 1) clearInterval(timer);
    }, 30);
    return () => clearInterval(timer);
  }, [added]);

  const close = () => router.replace('/(tabs)');

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" />

      {/* Confetti cayendo */}
      {CONFETTI.map((c) => (
        <MotiView
          key={c.id}
          from={{ translateY: -50, opacity: 0 }}
          animate={{ translateY: height + 60, opacity: 1 }}
          transition={{ type: 'timing', duration: c.duration, delay: c.delay }}
          style={[styles.confetti, { left: c.left, width: c.size, height: c.size, backgroundColor: c.color, transform: [{ rotate: `${c.rotate}deg` }] }]}
        />
      ))}

      <SafeAreaView style={styles.safe}>
        <View style={styles.center}>
          <MotiText
            from={{ opacity: 0, translateY: 16 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 500 }}
            style={styles.eyebrow}
          >
            {title.toUpperCase()}
          </MotiText>

          {found > 0 && (
            <MotiText
              from={{ opacity: 0, translateY: 16 }}
              animate={{ opacity: 1, translateY: 0 }}
              transition={{ type: 'timing', duration: 500, delay: 150 }}
              style={styles.headline}
            >
              Encontramos {found} {found === 1 ? 'compra tuya' : 'compras tuyas'} 🛍️
            </MotiText>
          )}

          {/* Puntos agregados (héroe) */}
          <MotiView
            from={{ opacity: 0, scale: 0.6 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: 'spring', delay: 350, damping: 12 }}
            style={styles.counterWrap}
          >
            <Text style={styles.counter}>+{display.toLocaleString('es-MX')}</Text>
            <Text style={styles.counterLabel}>Ahora tienes {total.toLocaleString('es-MX')} puntos</Text>
          </MotiView>

          {/* Badge de nivel */}
          <MotiView
            from={{ opacity: 0, scale: 0 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ type: 'spring', delay: 1400, damping: 10 }}
            style={[styles.badge, { borderColor: tier.color }]}
          >
            <Text style={styles.badgeEmoji}>{tier.emoji}</Text>
            <Text style={[styles.badgeText, { color: tier.color }]}>Nivel {tier.label}</Text>
          </MotiView>

          {/* Progreso al siguiente nivel */}
          <MotiText
            from={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ type: 'timing', duration: 500, delay: 1650 }}
            style={styles.progress}
          >
            {tier.next
              ? `Te faltan ${pointsToNext.toLocaleString('es-MX')} puntos para nivel ${tier.next.label}`
              : '¡Llegaste al nivel máximo! 🎉'}
          </MotiText>
        </View>

        <MotiView
          from={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ type: 'timing', duration: 400, delay: 1800 }}
        >
          <TouchableOpacity style={styles.btn} onPress={close} activeOpacity={0.85}>
            <Text style={styles.btnText}>Ver mi tarjeta</Text>
          </TouchableOpacity>
        </MotiView>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  safe: { flex: 1, justifyContent: 'space-between', padding: 24 },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  confetti: { position: 'absolute', top: 0, borderRadius: 2 },
  eyebrow: {
    fontSize: 12, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, textAlign: 'center', marginBottom: 12,
  },
  headline: {
    fontSize: 26, color: '#FFF', fontFamily: 'serif',
    textAlign: 'center', marginBottom: 24, lineHeight: 32,
  },
  counterWrap: { alignItems: 'center', marginBottom: 40 },
  counter: {
    fontSize: 84, color: '#FFF', fontWeight: '800',
    letterSpacing: -2, lineHeight: 92,
  },
  counterLabel: {
    fontSize: 13, color: 'rgba(255,255,255,0.55)',
    fontWeight: '600', letterSpacing: 0.5, marginTop: 6,
  },
  badge: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    borderWidth: 1.5, borderRadius: 30,
    paddingVertical: 10, paddingHorizontal: 20,
    backgroundColor: 'rgba(255,255,255,0.03)', marginBottom: 16,
  },
  badgeEmoji: { fontSize: 22 },
  badgeText: { fontSize: 15, fontWeight: '800', letterSpacing: 1 },
  progress: {
    fontSize: 13, color: 'rgba(255,255,255,0.5)',
    textAlign: 'center', letterSpacing: 0.3,
  },
  btn: {
    backgroundColor: '#CD7F32', borderRadius: 30, height: 54,
    justifyContent: 'center', alignItems: 'center',
  },
  btnText: { color: '#0D0D0D', fontSize: 14, fontWeight: '800', letterSpacing: 1 },
});
