import React from 'react';
import { View, Text, StyleSheet, Dimensions, Image } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { MotiView } from 'moti';
import QRCode from 'react-native-qrcode-svg';

const { width } = Dimensions.get('window');
const CARD_WIDTH = width - 48;
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

const TIER_CONFIG: Record<Tier, { label: string; colors: [string, string]; text: string }> = {
  bronze: { label: 'Bronce', colors: ['#3D1C00', '#7A3B00'], text: '#CD7F32' },
  silver: { label: 'Plata',  colors: ['#1A1A2E', '#2E2E4E'], text: '#C0C0C0' },
  gold:   { label: 'Oro',    colors: ['#2C1A00', '#5C3800'], text: '#FFD700' },
};

const LOGO = require('../assets/images/logo.png');

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

  const progressLabel =
    tier === 'gold'
      ? 'Nivel máximo alcanzado'
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
    >
      <LinearGradient
        colors={config.colors}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={styles.card}
      >
        {/* Header */}
        <View style={styles.header}>
          <Image source={LOGO} style={styles.logo} resizeMode="contain" />
          <View style={[styles.tierBadge, { borderColor: config.text }]}>
            <Text style={[styles.tierLabel, { color: config.text }]}>
              {config.label.toUpperCase()}
            </Text>
          </View>
        </View>

        {/* Body: stats + QR */}
        <View style={styles.body}>
          <View style={styles.statsCol}>
            <Text style={styles.customerName}>{customerName}</Text>

            <View style={styles.statRow}>
              <View style={styles.stat}>
                <Text style={[styles.statValue, { color: config.text }]}>
                  {totalPoints.toLocaleString()}
                </Text>
                <Text style={styles.statLabel}>PUNTOS</Text>
              </View>
              <View style={styles.statDivider} />
              <View style={styles.stat}>
                <Text style={[styles.statValue, { color: config.text }]}>
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
                  style={[styles.progressFill, { backgroundColor: config.text }]}
                />
              </View>
              <Text style={styles.progressLabel}>{progressLabel}</Text>
            </View>
          </View>

          <View style={styles.qrWrapper}>
            <QRCode
              value={qrCode}
              size={88}
              color="#FFFFFF"
              backgroundColor="transparent"
            />
          </View>
        </View>

        <Text style={styles.hint}>Muéstrala en tienda para acumular puntos</Text>
      </LinearGradient>
    </MotiView>
  );
};

const styles = StyleSheet.create({
  card: {
    width: CARD_WIDTH,
    height: CARD_HEIGHT,
    borderRadius: 20,
    padding: 20,
    justifyContent: 'space-between',
    overflow: 'hidden',
    elevation: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.5,
    shadowRadius: 16,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  logo: {
    width: 100,
    height: 28,
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
  stat: {
    alignItems: 'flex-start',
  },
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
  progressWrapper: {
    gap: 5,
  },
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
