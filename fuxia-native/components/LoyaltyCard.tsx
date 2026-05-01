import React, { useEffect, useRef, useState } from 'react';
import {
  View, Text, StyleSheet, Dimensions, Image,
  Animated, TouchableOpacity,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { MotiView } from 'moti';
import QRCode from 'react-native-qrcode-svg';

const { width } = Dimensions.get('window');
const CARD_WIDTH  = width - 48;
const CARD_HEIGHT = CARD_WIDTH / 1.585; // ISO credit card ratio

type Tier = 'bronze' | 'silver' | 'gold';

interface LoyaltyCardProps {
  customerName: string;
  qrCode: string;
  tier: Tier;
  totalPoints: number;
  pairsCount: number;
  pointsToNext: number | null;
  pairsToNext: number | null;
}

const TIER_CONFIG: Record<Tier, {
  label: string;
  colors: [string, string, string];
  accent: string;
  shimmer: string;
}> = {
  bronze: {
    label: 'Bronce',
    colors: ['#2A1000', '#7A3B00', '#3D1C00'],
    accent: '#CD7F32',
    shimmer: 'rgba(205,127,50,0.35)',
  },
  silver: {
    label: 'Plata',
    colors: ['#111122', '#2E2E4E', '#1A1A2E'],
    accent: '#C0C0C0',
    shimmer: 'rgba(192,192,192,0.35)',
  },
  gold: {
    label: 'Oro',
    colors: ['#1C0E00', '#5C3800', '#2C1A00'],
    accent: '#FFD700',
    shimmer: 'rgba(255,215,0,0.35)',
  },
};

const LOGO_ICON     = require('../assets/images/logo-icon.png');
const LOGO_WORDMARK = require('../assets/images/logo-wordmark.png');

export const LoyaltyCard = ({
  customerName,
  qrCode,
  tier,
  totalPoints,
  pairsCount,
  pointsToNext,
  pairsToNext,
}: LoyaltyCardProps) => {
  const config = TIER_CONFIG[tier];

  /* ── Flip animation ── */
  const flipAnim  = useRef(new Animated.Value(0)).current;
  const shimmerAnim = useRef(new Animated.Value(-CARD_WIDTH)).current;
  const [showingFront, setShowingFront] = useState(true);

  const flipCard = (toFront?: boolean) => {
    const current = showingFront;
    const goToFront = toFront !== undefined ? toFront : !current;
    const toValue   = goToFront ? 0 : 180;

    Animated.spring(flipAnim, {
      toValue,
      friction: 7,
      tension: 60,
      useNativeDriver: true,
    }).start();
    setShowingFront(goToFront);
  };

  /* Auto-flip every 5 s */
  useEffect(() => {
    const t = setTimeout(() => flipCard(), 5000);
    return () => clearTimeout(t);
  }, [showingFront]);

  /* Shimmer loop — only runs on front face */
  useEffect(() => {
    shimmerAnim.setValue(-CARD_WIDTH * 1.5);
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(shimmerAnim, {
          toValue: CARD_WIDTH * 1.5,
          duration: 2200,
          useNativeDriver: true,
        }),
        Animated.delay(3000),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, []);

  /* Interpolated rotations */
  const frontRotateY = flipAnim.interpolate({
    inputRange: [0, 180],
    outputRange: ['0deg', '180deg'],
  });
  const backRotateY = flipAnim.interpolate({
    inputRange: [0, 180],
    outputRange: ['180deg', '360deg'],
  });

  /* Computed values */
  const progressLabel =
    tier === 'gold'
      ? 'Nivel máximo'
      : pointsToNext && pointsToNext > 0
      ? `${pointsToNext} pts para ${tier === 'bronze' ? 'Plata' : 'Oro'}`
      : 'Lista para subir de nivel';

  const progressPercent =
    tier === 'gold' ? 1
    : tier === 'bronze' ? Math.min(1, totalPoints / 501)
    : Math.min(1, totalPoints / 1201);

  return (
    <MotiView
      from={{ scale: 0.92, opacity: 0 }}
      animate={{ scale: 1, opacity: 1 }}
      transition={{ type: 'spring', damping: 15, delay: 150 }}
      style={{ width: CARD_WIDTH, height: CARD_HEIGHT }}
    >
      <TouchableOpacity
        activeOpacity={1}
        onPress={() => flipCard()}
        style={{ width: CARD_WIDTH, height: CARD_HEIGHT }}
      >

        {/* ────── FRONT FACE ────── */}
        <Animated.View
          style={[
            styles.cardFace,
            { transform: [{ perspective: 1200 }, { rotateY: frontRotateY }] },
          ]}
        >
          <LinearGradient
            colors={config.colors}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={styles.cardInner}
          >
            {/* Subtle dot-pattern overlay */}
            <View style={styles.patternOverlay} pointerEvents="none" />

            {/* Logo icon centrado grande */}
            <View style={styles.frontCenter}>
              <MotiView
                from={{ scale: 0.85, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ type: 'spring', damping: 12, delay: 400 }}
                style={styles.iconWrapper}
              >
                <Image source={LOGO_ICON} style={styles.frontIcon} resizeMode="contain" />
              </MotiView>
              <Image source={LOGO_WORDMARK} style={styles.frontWordmark} resizeMode="contain" />
              <Text style={[styles.frontTier, { color: config.accent }]}>
                {config.label.toUpperCase()} MEMBER
              </Text>
            </View>

            {/* Bottom: name + hint */}
            <View style={styles.frontBottom}>
              <Text style={styles.frontName}>{customerName}</Text>
              <Text style={styles.frontHint}>Toca para ver tus puntos</Text>
            </View>

            {/* ── Shimmer sweep ── */}
            <Animated.View
              pointerEvents="none"
              style={[
                styles.shimmer,
                { transform: [{ translateX: shimmerAnim }, { rotate: '20deg' }] },
              ]}
            >
              <LinearGradient
                colors={[
                  'transparent',
                  config.shimmer,
                  'rgba(255,255,255,0.18)',
                  config.shimmer,
                  'transparent',
                ]}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 0 }}
                style={styles.shimmerGrad}
              />
            </Animated.View>
          </LinearGradient>
        </Animated.View>

        {/* ────── BACK FACE ────── */}
        <Animated.View
          style={[
            styles.cardFace,
            styles.cardFaceBack,
            { transform: [{ perspective: 1200 }, { rotateY: backRotateY }] },
          ]}
        >
          <LinearGradient
            colors={config.colors}
            start={{ x: 1, y: 1 }}
            end={{ x: 0, y: 0 }}
            style={styles.cardInner}
          >
            <View style={styles.patternOverlay} pointerEvents="none" />

            {/* Tier badge arriba derecha */}
            <View style={styles.backHeader}>
              <Text style={styles.customerName}>{customerName}</Text>
              <View style={[styles.tierBadge, { borderColor: config.accent }]}>
                <Text style={[styles.tierLabel, { color: config.accent }]}>
                  {config.label.toUpperCase()}
                </Text>
              </View>
            </View>

            {/* Logo en relieve centrado — watermark grande */}
            <View style={styles.backLogoRelief} pointerEvents="none">
              <Image
                source={LOGO_ICON}
                style={[styles.backLogoReliefIcon, { tintColor: config.accent }]}
                resizeMode="contain"
              />
              <Image
                source={LOGO_WORDMARK}
                style={[styles.backLogoReliefWordmark, { tintColor: config.accent }]}
                resizeMode="contain"
              />
            </View>

            {/* Stats + QR abajo */}
            <View style={styles.body}>
              <View style={styles.statsCol}>
                <View style={styles.statRow}>
                  <View style={styles.stat}>
                    <Text style={[styles.statValue, { color: config.accent }]}>
                      {totalPoints.toLocaleString()}
                    </Text>
                    <Text style={styles.statLabel}>PUNTOS</Text>
                  </View>
                  <View style={styles.statDivider} />
                  <View style={styles.stat}>
                    <Text style={[styles.statValue, { color: config.accent }]}>
                      {pairsCount}
                    </Text>
                    <Text style={styles.statLabel}>PARES</Text>
                  </View>
                </View>
                <View style={styles.progressWrapper}>
                  <View style={styles.progressBg}>
                    <MotiView
                      from={{ width: '0%' }}
                      animate={{ width: `${Math.round(progressPercent * 100)}%` }}
                      transition={{ type: 'timing', duration: 1400, delay: 400 }}
                      style={[styles.progressFill, { backgroundColor: config.accent }]}
                    />
                  </View>
                  <Text style={styles.progressLabel}>{progressLabel}</Text>
                </View>
              </View>

              <View style={styles.qrWrapper}>
                <QRCode
                  value={qrCode}
                  size={82}
                  color="#FFFFFF"
                  backgroundColor="transparent"
                />
              </View>
            </View>

            <Text style={styles.hint}>Muéstrala en tienda para acumular puntos</Text>
          </LinearGradient>
        </Animated.View>

      </TouchableOpacity>
    </MotiView>
  );
};

const styles = StyleSheet.create({
  cardFace: {
    position: 'absolute',
    width: CARD_WIDTH,
    height: CARD_HEIGHT,
    backfaceVisibility: 'hidden',
    borderRadius: 20,
    overflow: 'hidden',
    elevation: 14,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.55,
    shadowRadius: 18,
  },
  cardFaceBack: {
    // back face starts at 180deg via animation — no extra transform here
  },
  cardInner: {
    flex: 1,
    padding: 20,
    borderRadius: 20,
    justifyContent: 'space-between',
    overflow: 'hidden',
  },

  /* Subtle texture overlay */
  patternOverlay: {
    ...StyleSheet.absoluteFillObject,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
  },

  /* ── FRONT ── */
  frontCenter: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 10,
  },
  iconWrapper: {
    shadowColor: '#CD7F32',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 24,
  },
  frontIcon: {
    width: 90,
    height: 90,
  },
  frontWordmark: {
    width: CARD_WIDTH * 0.55,
    height: 32,
    marginTop: 4,
  },
  frontTier: {
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 4,
    marginTop: 6,
    opacity: 0.9,
  },
  frontBottom: {
    alignItems: 'center',
    gap: 3,
  },
  frontName: {
    color: 'rgba(255,255,255,0.85)',
    fontSize: 13,
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  frontHint: {
    color: 'rgba(255,255,255,0.28)',
    fontSize: 9,
    letterSpacing: 1,
  },

  /* Shimmer */
  shimmer: {
    ...StyleSheet.absoluteFillObject,
    overflow: 'hidden',
  },
  shimmerGrad: {
    width: CARD_WIDTH * 0.55,
    height: CARD_HEIGHT * 2.5,
    marginTop: -CARD_HEIGHT * 0.75,
  },

  /* ── BACK ── */
  backHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  backLogoRelief: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
    opacity: 0.18,
  },
  backLogoReliefIcon: {
    width: CARD_WIDTH * 0.22,
    height: CARD_WIDTH * 0.22,
  },
  backLogoReliefWordmark: {
    width: CARD_WIDTH * 0.48,
    height: 22,
  },
  tierBadge: {
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  tierLabel: {
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 2,
  },
  body: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    flex: 1,
    marginTop: 8,
  },
  statsCol: {
    flex: 1,
    justifyContent: 'flex-end',
    paddingRight: 12,
  },
  customerName: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '600',
    letterSpacing: 0.5,
    marginBottom: 10,
  },
  statRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  stat: { alignItems: 'flex-start' },
  statValue: {
    fontSize: 22,
    fontWeight: '300',
    letterSpacing: 1,
  },
  statLabel: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 2,
    marginTop: 1,
  },
  statDivider: {
    width: 1,
    height: 28,
    backgroundColor: 'rgba(255,255,255,0.15)',
    marginHorizontal: 14,
  },
  progressWrapper: { gap: 5 },
  progressBg: {
    height: 3,
    backgroundColor: 'rgba(255,255,255,0.12)',
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 2,
  },
  progressLabel: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 9,
    letterSpacing: 0.5,
  },
  qrWrapper: {
    padding: 8,
    backgroundColor: 'rgba(0,0,0,0.35)',
    borderRadius: 10,
  },
  hint: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 9,
    textAlign: 'center',
    letterSpacing: 1,
    marginTop: 4,
  },
});
