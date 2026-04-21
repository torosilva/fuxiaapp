import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView, TextInput, ActivityIndicator } from 'react-native';
import { Text, View } from '@/components/Themed';
import { Search, Filter, ShoppingBag, Heart } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { MotiView } from 'moti';
import { router } from 'expo-router';
import { useState, useEffect } from 'react';
import { wcService, WCProduct } from '@/services/WooCommerceService';

import { ProductCard } from '@/components/ProductCard';

import { PremiumHeader } from '@/components/PremiumHeader';

export default function ShopScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  
  const [products, setProducts] = useState<WCProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    loadProducts();
  }, []);

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

  const filteredProducts = products.filter(p => 
    p.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <PremiumHeader transparent={false} />
      
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
        <RNView style={styles.filterScroll}>
          {['Todo', 'Ballerinas', 'Sandalias', 'Planas', 'Botas'].map((f, i) => (
            <TouchableOpacity 
              key={f} 
              style={[
                styles.filterChip, 
                { backgroundColor: i === 0 ? theme.text : theme.soft, borderColor: theme.border }
              ]}
            >
              <Text style={[styles.filterText, { color: i === 0 ? theme.background : theme.text }]}>{f}</Text>
            </TouchableOpacity>
          ))}
        </RNView>

        {loading ? (
          <RNView style={styles.loaderContainer}>
            <ActivityIndicator size="large" color={theme.accent} />
            <Text style={{ marginTop: 10, color: theme.muted }}>Cargando colección...</Text>
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
