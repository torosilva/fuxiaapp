import React, { useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Share,
  StatusBar,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MotiView } from 'moti';
import { Share2, ShoppingBag, Sparkles } from 'lucide-react-native';
import { LoyaltyCard } from '@/components/LoyaltyCard';
import { generateQRCode } from '@/lib/utils/qrGenerator';

// Placeholder data — replace with real Supabase data after auth is wired up
const MOCK_CUSTOMER = {
  id: 'a3f8b2c1-1234-5678-abcd-ef0123456789',
  name: 'Ana García',
  tier: 'bronze' as const,
  totalPoints: 320,
  pairsCount: 3,
  pointsToNext: 181,
  pairsToNext: 3,
};

const MOCK_TRANSACTIONS = [
  { id: '1', date: '12 abr 2026', description: 'Ballerinas Nude Satín', points: +70, channel: 'web' },
  { id: '2', date: '28 mar 2026', description: 'Sandalia Tiras Doradas', points: +50, channel: 'store' },
  { id: '3', date: '10 mar 2026', description: 'Bota Chelsea Negra', points: +90, channel: 'web' },
  { id: '4', date: '2 feb 2026',  description: 'Flat Charol Rosa',     points: +60, channel: 'store' },
  { id: '5', date: '15 ene 2026', description: 'Mule Leopardo',         points: +50, channel: 'web' },
];

const qrCode = generateQRCode(MOCK_CUSTOMER.id);

export default function CardScreen() {
  const handleShare = async () => {
    await Share.share({
      message: `Mi tarjeta de lealtad Fuxia Ballerinas — ${MOCK_CUSTOMER.totalPoints} puntos · Nivel ${MOCK_CUSTOMER.tier}`,
    });
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <StatusBar barStyle="light-content" />
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scroll}
      >
        {/* Title */}
        <View style={styles.titleRow}>
          <View>
            <Text style={styles.eyebrow}>MI TARJETA</Text>
            <Text style={styles.title}>Lealtad Fuxia</Text>
          </View>
          <Sparkles size={20} color="#CD7F32" />
        </View>

        {/* Card */}
        <View style={styles.cardWrapper}>
          <LoyaltyCard
            customerName={MOCK_CUSTOMER.name}
            qrCode={qrCode}
            tier={MOCK_CUSTOMER.tier}
            totalPoints={MOCK_CUSTOMER.totalPoints}
            pairsCount={MOCK_CUSTOMER.pairsCount}
            pointsToNext={MOCK_CUSTOMER.pointsToNext}
            pairsToNext={MOCK_CUSTOMER.pairsToNext}
          />
        </View>

        {/* Share button */}
        <TouchableOpacity style={styles.shareBtn} onPress={handleShare} activeOpacity={0.8}>
          <Share2 size={16} color="#CD7F32" />
          <Text style={styles.shareBtnText}>Compartir tarjeta</Text>
        </TouchableOpacity>

        {/* Recent movements */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <ShoppingBag size={16} color="#CD7F32" />
            <Text style={styles.sectionTitle}>Últimos movimientos</Text>
          </View>

          {MOCK_TRANSACTIONS.map((tx, i) => (
            <MotiView
              key={tx.id}
              from={{ opacity: 0, translateY: 10 }}
              animate={{ opacity: 1, translateY: 0 }}
              transition={{ delay: 100 + i * 80, type: 'timing', duration: 300 }}
              style={styles.txRow}
            >
              <View style={styles.txIcon}>
                <Text style={styles.txIconText}>
                  {tx.channel === 'store' ? '🏪' : '🌐'}
                </Text>
              </View>
              <View style={styles.txInfo}>
                <Text style={styles.txDesc}>{tx.description}</Text>
                <Text style={styles.txDate}>{tx.date}</Text>
              </View>
              <Text style={styles.txPoints}>+{tx.points} pts</Text>
            </MotiView>
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
  },
  scroll: {
    paddingBottom: 120,
  },
  titleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingTop: 16,
    marginBottom: 24,
  },
  eyebrow: {
    fontSize: 10,
    color: '#CD7F32',
    fontWeight: '800',
    letterSpacing: 3,
    marginBottom: 4,
  },
  title: {
    fontSize: 28,
    color: '#FFFFFF',
    fontFamily: 'serif',
    fontWeight: '400',
  },
  cardWrapper: {
    paddingHorizontal: 24,
    marginBottom: 20,
  },
  shareBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 30,
    borderWidth: 1,
    borderColor: 'rgba(205, 127, 50, 0.4)',
    backgroundColor: 'rgba(205, 127, 50, 0.07)',
    marginBottom: 36,
  },
  shareBtnText: {
    color: '#CD7F32',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 1,
  },
  section: {
    paddingHorizontal: 24,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 16,
  },
  sectionTitle: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  txRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  txIcon: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  txIconText: {
    fontSize: 16,
  },
  txInfo: {
    flex: 1,
  },
  txDesc: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '500',
  },
  txDate: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 11,
    marginTop: 2,
  },
  txPoints: {
    color: '#CD7F32',
    fontSize: 13,
    fontWeight: '700',
  },
});
