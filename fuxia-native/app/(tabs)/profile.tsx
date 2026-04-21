import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView } from 'react-native';
import { Text, View } from '@/components/Themed';
import { User as UserIcon, Package, MapPin, Gift, CreditCard, ChevronRight, CheckCircle2 } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { MotiView } from 'moti';

const SANDALS_IMAGE = require('../../assets/images/sandals.png');

import { LoyaltyCard } from '@/components/LoyaltyCard';

export default function ProfileScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];

  return (
    <ScrollView style={[styles.container, { backgroundColor: theme.background }]} showsVerticalScrollIndicator={false}>
      <RNView style={styles.header}>
        <RNView style={[styles.avatarContainer, { borderColor: theme.accent, backgroundColor: theme.soft }]}>
          <UserIcon size={40} color={theme.accent} />
        </RNView>
        <Text style={styles.userName}>Maria Garcia</Text>
        <Text style={[styles.userEmail, { color: theme.muted }]}>maria.garcia@example.com</Text>
      </RNView>

      {/* Loyalty Card */}
      <RNView style={styles.cardContainer}>
        <LoyaltyCard
          customerName="Ana García"
          qrCode="FX-a3f8b2c1-preview-00"
          tier="gold"
          totalPoints={1250}
          pairsCount={14}
          pointsToNext={null}
          pairsToNext={null}
        />
      </RNView>

      {/* Quick Actions Grid */}
      <RNView style={styles.grid}>
        {[
          { icon: Package, label: 'Mis Compras' },
          { icon: MapPin, label: 'Seguimiento' },
          { icon: Gift, label: 'Regalar' },
          { icon: CreditCard, label: 'Pagos' },
        ].map((item, idx) => (
          <TouchableOpacity 
            key={idx} 
            style={[styles.gridItem, { backgroundColor: theme.background, borderColor: theme.border }]}
          >
            <item.icon size={24} color={theme.text} />
            <Text style={styles.gridLabel}>{item.label}</Text>
          </TouchableOpacity>
        ))}
      </RNView>

      {/* Latest Order Section */}
      <RNView style={styles.section}>
        <Text style={styles.sectionTitle}>Último Pedido</Text>
        <RNView style={[styles.orderCard, { backgroundColor: theme.soft }]}>
          <Image source={SANDALS_IMAGE} style={styles.orderImage} />
          <RNView style={styles.orderInfo}>
            <RNView style={styles.orderHeader}>
              <Text style={styles.orderStatus}>En Camino</Text>
              <Text style={[styles.orderId, { color: theme.muted }]}>#FX-4921</Text>
            </RNView>
            <Text style={[styles.deliveryText, { color: theme.muted }]}>Llega mañana, 14:00 - 18:00</Text>
            
            <RNView style={styles.trackerContainer}>
              <CheckCircle2 size={14} color="#4CAF50" />
              <RNView style={[styles.trackLine, { backgroundColor: theme.border }]}>
                 <RNView style={[styles.trackFill, { backgroundColor: '#4CAF50', width: '60%' }]} />
              </RNView>
            </RNView>
          </RNView>
        </RNView>
      </RNView>

      <RNView style={{ height: 100 }} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    alignItems: 'center',
    paddingVertical: 40,
    marginTop: 40,
  },
  avatarContainer: {
    width: 80,
    height: 80,
    borderRadius: 40,
    borderWidth: 2,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
  },
  userName: {
    fontSize: 24,
    fontWeight: '700',
  },
  userEmail: {
    fontSize: 14,
    marginTop: 4,
  },
  cardContainer: {
    paddingHorizontal: 20,
    marginBottom: 30,
  },
  loyaltyCard: {
    borderRadius: 20,
    padding: 24,
  },
  loyaltyHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  loyaltyLabel: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 12,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  loyaltyPoints: {
    color: '#fff',
    fontSize: 32,
    fontWeight: '700',
    marginTop: 4,
  },
  pointsUnit: {
    fontSize: 14,
    opacity: 0.8,
  },
  levelBadge: {
    paddingVertical: 4,
    paddingHorizontal: 12,
    borderRadius: 12,
  },
  levelBadgeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  progressSection: {
    marginTop: 20,
  },
  progressBar: {
    height: 6,
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 3,
  },
  progressText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 11,
    marginTop: 8,
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 20,
    gap: 15,
    marginBottom: 30,
  },
  gridItem: {
    width: '47.5%',
    padding: 20,
    borderRadius: 16,
    borderWidth: 1,
    alignItems: 'center',
    gap: 10,
  },
  gridLabel: {
    fontSize: 13,
    fontWeight: '600',
  },
  section: {
    paddingHorizontal: 20,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 16,
  },
  orderCard: {
    borderRadius: 20,
    padding: 16,
    flexDirection: 'row',
    gap: 16,
  },
  orderImage: {
    width: 60,
    height: 60,
    borderRadius: 12,
  },
  orderInfo: {
    flex: 1,
  },
  orderHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  orderStatus: {
    fontSize: 14,
    fontWeight: '600',
  },
  orderId: {
    fontSize: 12,
  },
  deliveryText: {
    fontSize: 12,
    marginTop: 4,
  },
  trackerContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 12,
  },
  trackLine: {
    flex: 1,
    height: 2,
    position: 'relative',
  },
  trackFill: {
    height: '100%',
  }
});
