import { useEffect, useState } from 'react';
import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView, ActivityIndicator } from 'react-native';
import { Text, View } from '@/components/Themed';
import { User as UserIcon, Package, MapPin, Gift, CreditCard, ChevronRight, CheckCircle2, LogOut, Camera, Globe } from 'lucide-react-native';
import { Alert } from 'react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { MotiView } from 'moti';
import { Redirect, router } from 'expo-router';
import { useAuth } from '@/lib/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import * as ImagePicker from 'expo-image-picker';
import { CountryPicker } from '@/components/CountryPicker';
import {
  getCountry,
  getCountryMeta,
  setCountry,
  subscribeCountry,
  type CountryCode,
} from '@/lib/CountryService';

const SANDALS_IMAGE = require('../../assets/images/sandals.png');

import { LoyaltyCard } from '@/components/LoyaltyCard';

interface LatestOrder {
  id: string;
  wc_order_id: number | null;
  created_at: string;
  first_item: string;
  points_earned: number;
}

const MONTHS_ES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const formatDate = (iso: string) => {
  const d = new Date(iso);
  return `${d.getDate()} ${MONTHS_ES[d.getMonth()]} ${d.getFullYear()}`;
};

export default function ProfileScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  const { session, customer, loyaltyCard, isLoading, signOut, refresh } = useAuth();
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [avatarVersion, setAvatarVersion] = useState(0);
  const [country, setCountryState] = useState<CountryCode>('MX');
  const [pickerOpen, setPickerOpen] = useState(false);
  const countryMeta = getCountryMeta(country);

  useEffect(() => {
    let mounted = true;
    getCountry().then((c) => mounted && setCountryState(c));
    const unsub = subscribeCountry((c) => mounted && setCountryState(c));
    return () => {
      mounted = false;
      unsub();
    };
  }, []);

  const handleSelectCountry = async (code: CountryCode) => {
    setPickerOpen(false);
    if (code === country) return;
    await setCountry(code, customer?.id);
  };

  const handlePickAvatar = async () => {
    if (!customer || !session) return;
    const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) {
      Alert.alert('Permiso requerido', 'Necesitamos acceso a tus fotos para cambiar tu avatar.');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.6,
      base64: true,
    });
    if (result.canceled || !result.assets?.[0]?.base64) return;

    setUploadingAvatar(true);
    try {
      const asset = result.assets[0];
      const ext = asset.uri.split('.').pop()?.toLowerCase() || 'jpg';
      const contentType = ext === 'png' ? 'image/png' : 'image/jpeg';
      const path = `${session.user.id}/avatar.${ext}`;

      const bytes = Uint8Array.from(atob(asset.base64!), (c) => c.charCodeAt(0));

      const { error: uploadErr } = await supabase.storage
        .from('avatars')
        .upload(path, bytes, { contentType, upsert: true });
      if (uploadErr) throw uploadErr;

      const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
      const publicUrl = `${pub.publicUrl}?v=${Date.now()}`;

      const { error: updateErr } = await supabase
        .from('customers')
        .update({ avatar_url: publicUrl })
        .eq('id', customer.id);
      if (updateErr) throw updateErr;

      await refresh();
      setAvatarVersion(v => v + 1); // force Image re-render
    } catch (err: any) {
      Alert.alert('Error', err?.message ?? 'No se pudo subir la foto.');
    } finally {
      setUploadingAvatar(false);
    }
  };

  const handleSignOut = () => {
    Alert.alert(
      'Cerrar sesión',
      '¿Seguro que quieres salir de tu cuenta?',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Cerrar sesión',
          style: 'destructive',
          onPress: async () => {
            await signOut();
            router.replace('/onboarding');
          },
        },
      ],
    );
  };
  const [latestOrder, setLatestOrder] = useState<LatestOrder | null>(null);

  useEffect(() => {
    if (!loyaltyCard) return;
    (async () => {
      const { data } = await supabase
        .from('transactions')
        .select('id, wc_order_id, created_at, points_earned, purchase_items(product_name)')
        .eq('loyalty_card_id', loyaltyCard.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (data) {
        const firstName = (data as any).purchase_items?.[0]?.product_name ?? 'Compra';
        setLatestOrder({
          id: data.id,
          wc_order_id: data.wc_order_id,
          created_at: data.created_at,
          first_item: firstName,
          points_earned: data.points_earned,
        });
      }
    })();
  }, [loyaltyCard?.id]);

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: theme.background, justifyContent: 'center', alignItems: 'center' }]}>
        <ActivityIndicator color={theme.accent} />
      </View>
    );
  }

  if (!session || !customer || !loyaltyCard) {
    return <Redirect href="/onboarding" />;
  }

  return (
    <ScrollView style={[styles.container, { backgroundColor: theme.background }]} showsVerticalScrollIndicator={false}>
      <RNView style={styles.header}>
        <TouchableOpacity
          onPress={handlePickAvatar}
          disabled={uploadingAvatar}
          activeOpacity={0.8}
          style={[styles.avatarContainer, { borderColor: theme.accent, backgroundColor: theme.soft }]}
        >
          {customer.avatar_url ? (
            <Image
              key={avatarVersion}
              source={{ uri: customer.avatar_url }}
              style={styles.avatarImage}
            />
          ) : (
            <Text style={[styles.avatarInitials, { color: theme.accent }]}>
              {customer.name
                .split(' ')
                .map((p) => p[0])
                .filter(Boolean)
                .slice(0, 2)
                .join('')
                .toUpperCase()}
            </Text>
          )}
          <RNView style={[styles.avatarBadge, { backgroundColor: theme.accent }]}>
            {uploadingAvatar
              ? <ActivityIndicator size="small" color={theme.background} />
              : <Camera size={14} color={theme.background} />}
          </RNView>
        </TouchableOpacity>
        <Text style={styles.userName}>{customer.name}</Text>
        <Text style={[styles.userEmail, { color: theme.muted }]}>{customer.email ?? customer.phone}</Text>
      </RNView>

      {/* Loyalty Card */}
      <RNView style={styles.cardContainer}>
        <LoyaltyCard
          customerName={customer.name}
          qrCode={loyaltyCard.qr_code}
          tier={loyaltyCard.tier}
          totalPoints={loyaltyCard.total_points}
          pairsCount={loyaltyCard.pairs_count}
          pointsToNext={loyaltyCard.points_to_next}
          pairsToNext={loyaltyCard.pairs_to_next}
        />
      </RNView>

      {/* Quick Actions Grid */}
      <RNView style={styles.grid}>
        {[
          { icon: Package, label: 'Mis Compras', onPress: () => router.push('/purchases' as any) },
          { icon: MapPin, label: 'Seguimiento', onPress: () => router.push('/tracking' as any) },
          { icon: Gift, label: 'Regalar', onPress: undefined },
          { icon: CreditCard, label: 'Pagos', onPress: () => router.push('/payments' as any) },
        ].map((item, idx) => (
          <TouchableOpacity
            key={idx}
            style={[styles.gridItem, { backgroundColor: theme.background, borderColor: theme.border }]}
            onPress={item.onPress}
            disabled={!item.onPress}
            activeOpacity={item.onPress ? 0.7 : 1}
          >
            <item.icon size={24} color={theme.text} />
            <Text style={styles.gridLabel}>{item.label}</Text>
          </TouchableOpacity>
        ))}
      </RNView>

      {/* Latest Order Section */}
      <RNView style={styles.section}>
        <Text style={styles.sectionTitle}>Último Pedido</Text>
        {latestOrder ? (
          <RNView style={[styles.orderCard, { backgroundColor: theme.soft }]}>
            <Image source={SANDALS_IMAGE} style={styles.orderImage} />
            <RNView style={styles.orderInfo}>
              <RNView style={styles.orderHeader}>
                <Text style={styles.orderStatus}>{latestOrder.first_item}</Text>
                <Text style={[styles.orderId, { color: theme.muted }]}>
                  {latestOrder.wc_order_id ? `#${latestOrder.wc_order_id}` : ''}
                </Text>
              </RNView>
              <Text style={[styles.deliveryText, { color: theme.muted }]}>
                {formatDate(latestOrder.created_at)} · +{latestOrder.points_earned} pts
              </Text>
            </RNView>
          </RNView>
        ) : (
          <RNView style={[styles.orderCard, { backgroundColor: theme.soft, justifyContent: 'center' }]}>
            <Text style={[styles.deliveryText, { color: theme.muted, textAlign: 'center', flex: 1 }]}>
              Aún no tienes pedidos. Tus compras aparecerán aquí.
            </Text>
          </RNView>
        )}
      </RNView>

      <RNView style={styles.section}>
        <Text style={styles.sectionTitle}>Preferencias</Text>
        <TouchableOpacity
          activeOpacity={0.7}
          onPress={() => setPickerOpen(true)}
          style={[styles.prefRow, { backgroundColor: theme.soft }]}
        >
          <Globe size={20} color={theme.text} />
          <RNView style={{ flex: 1 }}>
            <Text style={styles.prefLabel}>País de envío</Text>
            <Text style={[styles.prefValue, { color: theme.muted }]}>
              {countryMeta.flag}  {countryMeta.name} · {countryMeta.currency}
            </Text>
          </RNView>
          <ChevronRight size={18} color={theme.muted} />
        </TouchableOpacity>
      </RNView>

      <TouchableOpacity style={styles.signOutBtn} onPress={handleSignOut} activeOpacity={0.7}>
        <LogOut size={16} color="#FF6B6B" />
        <Text style={styles.signOutText}>Cerrar sesión</Text>
      </TouchableOpacity>

      <TouchableOpacity onPress={() => router.push('/privacy' as any)} style={styles.privacyLink}>
        <Text style={styles.privacyText}>Política de Privacidad</Text>
      </TouchableOpacity>

      <RNView style={{ height: 100 }} />

      <CountryPicker
        visible={pickerOpen}
        current={country}
        onSelect={handleSelectCountry}
        onClose={() => setPickerOpen(false)}
      />
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
    overflow: 'visible',
  },
  avatarInitials: {
    fontSize: 28,
    fontWeight: '700',
    letterSpacing: 1,
  },
  avatarImage: {
    width: 76,
    height: 76,
    borderRadius: 38,
  },
  avatarBadge: {
    position: 'absolute',
    right: -2,
    bottom: -2,
    width: 28,
    height: 28,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#0D0D0D',
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
  },
  prefRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderRadius: 16,
  },
  prefLabel: {
    fontSize: 14,
    fontWeight: '600',
  },
  prefValue: {
    fontSize: 12,
    marginTop: 2,
    letterSpacing: 0.5,
  },
  signOutBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginHorizontal: 20,
    marginTop: 24,
    paddingVertical: 14,
    borderRadius: 30,
    borderWidth: 1,
    borderColor: 'rgba(255,107,107,0.3)',
    backgroundColor: 'rgba(255,107,107,0.05)',
  },
  signOutText: {
    color: '#FF6B6B',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 1,
  },
  privacyLink: {
    alignItems: 'center',
    paddingVertical: 12,
  },
  privacyText: {
    color: 'rgba(255,255,255,0.25)',
    fontSize: 11,
    letterSpacing: 0.5,
  },
});
