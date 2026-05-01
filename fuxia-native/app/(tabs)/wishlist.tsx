import { useEffect, useState } from 'react';
import { StyleSheet, ScrollView, TouchableOpacity, View as RNView, StatusBar, ActivityIndicator } from 'react-native';
import { Text, View } from '@/components/Themed';
import { Heart } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { router } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useWishlist } from '@/lib/WishlistContext';
import { wcService, WCProduct } from '@/services/WooCommerceService';
import { ProductCard } from '@/components/ProductCard';

export default function WishlistScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  const { ids } = useWishlist();
  const [products, setProducts] = useState<WCProduct[]>([]);
  const [loading, setLoading] = useState(false);
  const [allProducts, setAllProducts] = useState<WCProduct[]>([]);

  useEffect(() => {
    if (ids.size === 0) { setProducts([]); return; }
    if (allProducts.length > 0) {
      setProducts(allProducts.filter(p => ids.has(p.id)));
      return;
    }
    // Carga todos los productos una sola vez
    (async () => {
      setLoading(true);
      const data = await wcService.getProducts();
      setAllProducts(data);
      setProducts(data.filter(p => ids.has(p.id)));
      setLoading(false);
    })();
  }, [ids]);

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]} edges={['top']}>
      <StatusBar barStyle={colorScheme === 'dark' ? 'light-content' : 'dark-content'} />

      <RNView style={styles.header}>
        <Text style={[styles.eyebrow, { color: theme.accent }]}>GUARDADOS</Text>
        <Text style={styles.title}>Mis favoritos</Text>
      </RNView>

      {loading ? (
        <RNView style={styles.center}>
          <ActivityIndicator color={theme.accent} />
        </RNView>
      ) : products.length === 0 ? (
        <RNView style={styles.emptyContainer}>
          <RNView style={[styles.iconContainer, { backgroundColor: theme.soft }]}>
            <Heart size={48} color={theme.accent} />
          </RNView>
          <Text style={styles.emptyTitle}>Tu lista está vacía</Text>
          <Text style={[styles.emptySubtitle, { color: theme.muted }]}>
            Toca el ❤️ en cualquier producto para guardarlo aquí.
          </Text>
          <TouchableOpacity
            onPress={() => router.push('/(tabs)/shop' as any)}
            style={[styles.button, { backgroundColor: theme.text }]}
          >
            <Text style={[styles.buttonText, { color: theme.background }]}>Ver colección</Text>
          </TouchableOpacity>
        </RNView>
      ) : (
        <ScrollView contentContainerStyle={styles.grid} showsVerticalScrollIndicator={false}>
          {products.map((product, i) => (
            <ProductCard key={product.id} product={product} index={i} fullWidth />
          ))}
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: { paddingHorizontal: 20, paddingTop: 16, paddingBottom: 8 },
  eyebrow: { fontSize: 10, fontWeight: '800', letterSpacing: 3, marginBottom: 4 },
  title: { fontSize: 30, fontFamily: 'serif', fontWeight: '400' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  emptyContainer: {
    flex: 1, justifyContent: 'center', alignItems: 'center',
    paddingHorizontal: 40, paddingBottom: 100,
  },
  iconContainer: {
    width: 100, height: 100, borderRadius: 50,
    justifyContent: 'center', alignItems: 'center', marginBottom: 24,
  },
  emptyTitle: { fontSize: 20, fontWeight: '700', marginBottom: 10 },
  emptySubtitle: { fontSize: 14, textAlign: 'center', lineHeight: 22, marginBottom: 32 },
  button: { paddingHorizontal: 40, paddingVertical: 14, borderRadius: 30 },
  buttonText: { fontSize: 14, fontWeight: '700', letterSpacing: 1 },
  grid: {
    flexDirection: 'row', flexWrap: 'wrap',
    justifyContent: 'space-between',
    paddingHorizontal: 20, paddingBottom: 110, gap: 15,
  },
});
