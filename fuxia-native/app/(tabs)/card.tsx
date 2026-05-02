import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Share,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MotiView } from 'moti';
import { Redirect } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { Share2, ShoppingBag, Sparkles } from 'lucide-react-native';
import { LoyaltyCard } from '@/components/LoyaltyCard';
import { useAuth } from '@/lib/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import type { Channel } from '@/lib/database.types';

interface RecentTx {
  id: string;
  date: string;
  description: string;
  points: number;
  channel: Channel;
}

const MONTHS_ES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

function formatDate(iso: string): string {
  const d = new Date(iso);
  return `${d.getDate()} ${MONTHS_ES[d.getMonth()]} ${d.getFullYear()}`;
}

export default function CardScreen() {
  const { session, customer, loyaltyCard, isLoading, refresh } = useAuth();
  const [transactions, setTransactions] = useState<RecentTx[]>([]);
  const [txLoading, setTxLoading] = useState(true);

  // Refresh loyalty card data every time the tab gets focus
  useFocusEffect(
    React.useCallback(() => {
      refresh();
    }, [])
  );

  useEffect(() => {
    if (!loyaltyCard) {
      setTxLoading(false);
      return;
    }
    loadRecentTransactions(loyaltyCard.id);
  }, [loyaltyCard?.id]);

  async function loadRecentTransactions(loyaltyCardId: string) {
    setTxLoading(true);
    const { data } = await supabase
      .from('transactions')
      .select('id, created_at, points_earned, channel, purchase_items(product_name)')
      .eq('loyalty_card_id', loyaltyCardId)
      .order('created_at', { ascending: false })
      .limit(5);

    const mapped: RecentTx[] = (data ?? []).map((row: any) => {
      const firstItem = row.purchase_items?.[0];
      const extra = row.purchase_items?.length > 1 ? ` +${row.purchase_items.length - 1} más` : '';
      return {
        id: row.id,
        date: formatDate(row.created_at),
        description: firstItem ? `${firstItem.product_name}${extra}` : 'Compra',
        points: row.points_earned,
        channel: row.channel as Channel,
      };
    });
    setTransactions(mapped);
    setTxLoading(false);
  }

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator color="#CD7F32" />
      </SafeAreaView>
    );
  }

  if (!session || !customer || !loyaltyCard) {
    return <Redirect href="/onboarding" />;
  }

  const handleShare = async () => {
    await Share.share({
      message: `Mi tarjeta de lealtad Fuxia Ballerinas — ${loyaltyCard.total_points} puntos · Nivel ${loyaltyCard.tier}`,
    });
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <StatusBar barStyle="light-content" />
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scroll}
      >
        <View style={styles.titleRow}>
          <View>
            <Text style={styles.eyebrow}>MI TARJETA</Text>
            <Text style={styles.title}>Lealtad Fuxia</Text>
          </View>
          <Sparkles size={20} color="#CD7F32" />
        </View>

        <View style={styles.cardWrapper}>
          <LoyaltyCard
            customerName={customer.name}
            qrCode={loyaltyCard.qr_code}
            tier={loyaltyCard.tier}
            totalPoints={loyaltyCard.total_points}
            pairsCount={loyaltyCard.pairs_count}
            pointsToNext={loyaltyCard.points_to_next}
            pairsToNext={loyaltyCard.pairs_to_next}
          />
        </View>

        <TouchableOpacity style={styles.shareBtn} onPress={handleShare} activeOpacity={0.8}>
          <Share2 size={16} color="#CD7F32" />
          <Text style={styles.shareBtnText}>Compartir tarjeta</Text>
        </TouchableOpacity>

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <ShoppingBag size={16} color="#CD7F32" />
            <Text style={styles.sectionTitle}>Últimos movimientos</Text>
          </View>

          {txLoading ? (
            <ActivityIndicator color="#CD7F32" style={{ marginTop: 16 }} />
          ) : transactions.length === 0 ? (
            <Text style={styles.emptyText}>
              Tus compras aparecerán aquí cuando acumules tu primer par.
            </Text>
          ) : (
            transactions.map((tx, i) => (
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
            ))
          )}
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
  center: {
    justifyContent: 'center',
    alignItems: 'center',
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
  emptyText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
    marginTop: 16,
    lineHeight: 20,
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
