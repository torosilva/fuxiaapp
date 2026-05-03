import React from 'react';
import { StyleSheet, Image, TouchableOpacity, View as RNView, Dimensions } from 'react-native';
import { Text } from './Themed';
import { MotiView } from 'moti';
import { router } from 'expo-router';
import { Heart } from 'lucide-react-native';
import { WCProduct } from '@/services/WooCommerceService';
import Colors from '@/constants/Colors';
import { useColorScheme } from './useColorScheme';
import { useWishlist } from '@/lib/WishlistContext';
import { formatMoney } from '@/lib/CountryService';

const { width } = Dimensions.get('window');
const CARD_WIDTH = width * 0.42;

interface ProductCardProps {
  product: WCProduct;
  index: number;
  featured?: boolean;
  fullWidth?: boolean;
}

export const ProductCard = ({ product, index, featured, fullWidth }: ProductCardProps) => {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  const { has, toggle } = useWishlist();
  const liked = has(product.id);

  return (
    <TouchableOpacity 
      activeOpacity={0.9}
      onPress={() => router.push(`/product/${product.id}`)}
      style={[
        styles.container, 
        featured && styles.featuredContainer,
        fullWidth && styles.fullWidthContainer
      ]}
    >
      <MotiView
        from={{ opacity: 0, scale: 0.9, translateY: 15 }}
        animate={{ opacity: 1, scale: 1, translateY: 0 }}
        transition={{ delay: index * 100, type: 'timing', duration: 500 }}
      >
        <RNView style={[styles.imageContainer, { backgroundColor: '#1A1A1A' }]}>
          {product.images[0] ? (
            <Image source={{ uri: product.images[0].src }} style={styles.image} />
          ) : (
            <RNView style={styles.placeholder} />
          )}
          
          {product.stock_status === 'outofstock' && (
            <RNView style={styles.stockBadge}>
              <Text style={styles.stockText}>AGOTADO</Text>
            </RNView>
          )}

          <TouchableOpacity
            style={styles.heartBtn}
            onPress={(e) => { e.stopPropagation(); toggle(product.id); }}
            activeOpacity={0.8}
            hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
          >
            <Heart
              size={18}
              color={liked ? '#E05C7A' : 'rgba(255,255,255,0.85)'}
              fill={liked ? '#E05C7A' : 'transparent'}
            />
          </TouchableOpacity>
        </RNView>

        <RNView style={styles.info}>
          <Text style={[styles.category, { color: '#B8860B' }]}>
            {product.categories[0]?.name || 'Colección'}
          </Text>
          <Text numberOfLines={1} style={[styles.name, { color: '#FFF' }]}>
            {product.name}
          </Text>
          <Text style={[styles.price, { color: '#D1D1D1' }]}>
            {formatMoney(product.price, product.currency_code, product.currency_symbol)}
          </Text>
        </RNView>
      </MotiView>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  container: {
    width: CARD_WIDTH,
    marginBottom: 20,
    marginRight: 16,
  },
  featuredContainer: {
    width: width * 0.7,
  },
  fullWidthContainer: {
    width: '48.5%', // Optimized for a 2-column grid
    marginRight: 0,
  },
  imageContainer: {
    height: width * 0.55,
    borderRadius: 4,
    overflow: 'hidden',
    position: 'relative',
  },
  image: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  placeholder: {
    flex: 1,
    backgroundColor: '#333',
  },
  info: {
    marginTop: 12,
  },
  category: {
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 2,
    fontWeight: '700',
    marginBottom: 4,
  },
  name: {
    fontSize: 15,
    fontWeight: '600',
    fontFamily: 'serif',
    marginBottom: 4,
  },
  price: {
    fontSize: 13,
    fontWeight: '400',
    letterSpacing: 1,
  },
  heartBtn: {
    position: 'absolute',
    top: 10,
    right: 10,
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.35)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  stockBadge: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  stockText: {
    color: '#FFF',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 1,
  }
});
