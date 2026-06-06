import React, { useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import { ShoppingCart, Package, LogOut, Store, ShoppingBag } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

export default function VendedoraHomeScreen() {
  const { staffId, staffName, channelId, channelName, channelType } =
    useLocalSearchParams<{
      staffId: string;
      staffName: string;
      channelId: string;
      channelName: string;
      channelType: string;
    }>();

  const [salesCount, setSalesCount] = useState<number | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!channelId) return;
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      supabase
        .from('offline_sales')
        .select('id', { count: 'exact', head: true })
        .eq('channel_id', channelId)
        .gte('created_at', today.toISOString())
        .then(({ count }) => setSalesCount(count ?? 0));
    }, [channelId]),
  );

  const handleExit = () => {
    router.replace('/vendedora' as any);
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />

      <MotiView
        from={{ opacity: 0, translateY: 16 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 400 }}
        style={styles.content}
      >
        {/* Header */}
        <View style={styles.header}>
          <View>
            <Text style={styles.greeting}>Hola, {staffName ?? 'Vendedora'}</Text>
            <View style={styles.channelRow}>
              {channelType === 'bazar' ? (
                <ShoppingBag size={14} color="#B8860B" />
              ) : (
                <Store size={14} color="#B8860B" />
              )}
              <Text style={styles.channelLabel}>{channelName}</Text>
            </View>
          </View>
          <TouchableOpacity onPress={handleExit} style={styles.exitBtn} activeOpacity={0.7}>
            <LogOut size={18} color="rgba(255,255,255,0.4)" />
          </TouchableOpacity>
        </View>

        {/* Sales counter */}
        <MotiView
          from={{ opacity: 0, scale: 0.92 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: 'timing', duration: 400, delay: 100 }}
        >
          <TouchableOpacity
            style={styles.counterCard}
            activeOpacity={0.8}
            onPress={() => router.push({
              pathname: '/vendedora/sales-today' as any,
              params: { channelId, channelName },
            })}
          >
            <Text style={styles.counterLabel}>Ventas de hoy</Text>
            {salesCount === null ? (
              <ActivityIndicator color="#B8860B" />
            ) : (
              <Text style={styles.counterValue}>{salesCount}</Text>
            )}
            <Text style={styles.counterSub}>toca para ver detalle</Text>
          </TouchableOpacity>
        </MotiView>

        {/* Actions */}
        <MotiView
          from={{ opacity: 0, translateY: 20 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 400, delay: 200 }}
          style={styles.actionsContainer}
        >
          <TouchableOpacity
            style={styles.primaryAction}
            onPress={() =>
              router.push({
                pathname: '/vendedora/sale' as any,
                params: { staffId, staffName, channelId, channelName, channelType },
              })
            }
            activeOpacity={0.85}
          >
            <ShoppingCart size={28} color="#0D0D0D" />
            <Text style={styles.primaryActionText}>Registrar Venta</Text>
            <Text style={styles.primaryActionSub}>Crear nueva venta con código</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.secondaryAction}
            onPress={() =>
              router.push({
                pathname: '/vendedora/inventory' as any,
                params: { channelId, channelName },
              })
            }
            activeOpacity={0.8}
          >
            <Package size={24} color="#B8860B" />
            <Text style={styles.secondaryActionText}>Mi Inventario</Text>
          </TouchableOpacity>
        </MotiView>
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
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: 28,
  },
  greeting: {
    fontSize: 28,
    color: '#fff',
    fontWeight: '700',
    marginBottom: 6,
  },
  channelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  channelLabel: {
    fontSize: 13,
    color: '#B8860B',
    fontWeight: '600',
  },
  exitBtn: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.06)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  counterCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 28,
    alignItems: 'center',
    marginBottom: 24,
  },
  counterLabel: {
    fontSize: 11,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 2,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  counterValue: {
    fontSize: 64,
    color: '#fff',
    fontWeight: '700',
    lineHeight: 72,
  },
  counterSub: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 4,
  },
  actionsContainer: {
    gap: 14,
  },
  primaryAction: {
    backgroundColor: '#B8860B',
    borderRadius: 20,
    padding: 28,
    alignItems: 'center',
    gap: 8,
  },
  primaryActionText: {
    fontSize: 20,
    color: '#0D0D0D',
    fontWeight: '800',
  },
  primaryActionSub: {
    fontSize: 13,
    color: 'rgba(0,0,0,0.5)',
  },
  secondaryAction: {
    backgroundColor: '#1A1A1A',
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 22,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  secondaryActionText: {
    fontSize: 16,
    color: '#fff',
    fontWeight: '600',
  },
});
