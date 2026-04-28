import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView, TextInput, ActivityIndicator } from 'react-native';
import { Text, View } from '@/components/Themed';
import { Search, Filter, ShoppingBag, Heart } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { MotiView } from 'moti';
import { router, useLocalSearchParams } from 'expo-router';
import { useState, useEffect } from 'react';
import { wcService, WCProduct } from '@/services/WooCommerceService';

import { ProductCard } from '@/components/ProductCard';

const CATEGORY_FILTERS: { key: string; label: string; keywords: string[] }[] = [
  { key: 'all',        label: 'Todo',       keywords: [] },
  { key: 'ballerinas', label: 'Ballerinas', keywords: ['ballerina', 'flat', 'plana'] },
  { key: 'sandalias',  label: 'Sandalias',  keywords: ['sandalia', 'sandal'] },
  { key: 'botas',      label: 'Botas',      keywords: ['bota', 'boot', 'bootie'] },
  { key: 'outlet',     label: 'Outlet',     keywords: ['outlet', 'sale', 'rebaja'] },
];

function matchesCategory(product: WCProduct, filterKey: string): boolean {
  if (filterKey === 'all') return true;
  const filter = CATEGORY_FILTERS.find((f) => f.key === filterKey);
  if (!filter) return true;
  if (filterKey === 'outlet') {
    // Outlet = products on sale
    const onSale = product.sale_price && product.sale_price !== '' && product.sale_price !== product.regular_price;
    if (onSale) return true;
  }
  const haystack = [
    product.name,
    ...(product.categories ?? []).map((c) => `${c.name} ${c.slug}`),
  ].join(' ').toLowerCase();
  return filter.keywords.some((k) => haystack.includes(k));
}

export default function ShopScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  const { category } = useLocalSearchParams<{ category?: string }>();

  const [products, setProducts] = useState<WCProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeFilter, setActiveFilter] = useState<string>('all');

  useEffect(() => {
    loadProducts();
  }, []);

  useEffect(() => {
    if (category && CATEGORY_FILTERS.some((f) => f.key === category)) {
      setActiveFilter(category);
    }
  }, [category]);

  const loadProducts = async () => {
    try {
      setLoading(true);
      const data = await wcService.getProducts();
      setProducts(data);
    } catch (error) {
      console.error('Error loading products:', error);
    } finally {
      setLoading(false);
    }
  };

  const filteredProducts = products.filter((p) => {
    const nameMatch = p.name.toLowerCase().includes(searchQuery.toLowerCase());
    return nameMatch && matchesCategory(p, activeFilter);
  });

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      
      <RNView style={styles.header}>
        <RNView style={styles.searchBar}>
          <Search size={20} color={theme.muted} />
          <TextInput 
            placeholder="Buscar productos..." 
            placeholderTextColor={theme.muted}
            value={searchQuery}
            onChangeText={setSearchQuery}
            style={[styles.searchInput, { color: theme.text }]}
          />
          <TouchableOpacity style={styles.filterButton}>
            <Filter size={20} color={theme.text} />
          </TouchableOpacity>
        </RNView>
      </RNView>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.filterScroll}
        >
          {CATEGORY_FILTERS.map((f) => {
            const active = activeFilter === f.key;
            return (
              <TouchableOpacity
                key={f.key}
                onPress={() => setActiveFilter(f.key)}
                activeOpacity={0.7}
                style={[
                  styles.filterChip,
                  {
                    backgroundColor: active ? theme.text : theme.soft,
                    borderColor: active ? theme.text : theme.border,
                  },
                ]}
              >
                <Text style={[styles.filterText, { color: active ? theme.background : theme.text }]}>
                  {f.label}
                </Text>
              </TouchableOpacity>
            );
          })}
        </ScrollView>

        {loading ? (
          <RNView style={styles.loaderContainer}>
            <ActivityIndicator size="large" color={theme.accent} />
            <Text style={{ marginTop: 10, color: theme.muted }}>Cargando colección...</Text>
          </RNView>
        ) : filteredProducts.length === 0 ? (
          <RNView style={styles.loaderContainer}>
            <Text style={{ color: theme.text, fontSize: 16, fontWeight: '600' }}>
              Sin resultados
            </Text>
            <Text style={{ marginTop: 8, color: theme.muted, fontSize: 13, textAlign: 'center' }}>
              Intenta con otra categoría o búsqueda.
            </Text>
          </RNView>
        ) : (
          <RNView style={styles.grid}>
            {filteredProducts.map((product, i) => (
              <ProductCard
                key={product.id}
                product={product}
                index={i}
                fullWidth
              />
            ))}
          </RNView>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    paddingTop: 60,
    paddingHorizontal: 20,
    paddingBottom: 20,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    marginBottom: 20,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#F3F4F6',
    borderRadius: 15,
    paddingHorizontal: 15,
    height: 50,
  },
  searchInput: {
    flex: 1,
    marginLeft: 10,
    fontSize: 14,
  },
  filterButton: {
    padding: 5,
  },
  scrollContent: {
    paddingHorizontal: 20,
    paddingBottom: 100,
  },
  filterScroll: {
    flexDirection: 'row',
    gap: 10,
    marginBottom: 25,
  },
  filterChip: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
    borderWidth: 1,
  },
  filterText: {
    fontSize: 13,
    fontWeight: '600',
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    gap: 15,
  },
  productCard: {
    width: '47.5%',
    marginBottom: 20,
  },
  imageContainer: {
    height: 220,
    borderRadius: 15,
    overflow: 'hidden',
  },
  image: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  productInfo: {
    paddingTop: 12,
  },
  categoryLabel: {
    fontSize: 12,
    textTransform: 'uppercase',
  },
  productName: {
    fontSize: 14,
    fontWeight: '600',
    marginTop: 4,
  },
  productPrice: {
    fontSize: 14,
    fontWeight: '700',
    marginTop: 4,
  },
  loaderContainer: {
    padding: 100,
    alignItems: 'center',
    justifyContent: 'center',
  },
  outOfStockBadge: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: 'rgba(0,0,0,0.6)',
    paddingVertical: 5,
    alignItems: 'center',
  },
  outOfStockText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: '700',
    textTransform: 'uppercase',
  },
  wishlistButton: {
    position: 'absolute',
    top: 12,
    right: 12,
    backgroundColor: 'rgba(255,255,255,0.8)',
    padding: 8,
    borderRadius: 20,
  }
});
