import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView, TextInput, Dimensions, ActivityIndicator } from 'react-native';
import { Text, View } from '@/components/Themed';
import { useLocalSearchParams, router } from 'expo-router';
import { ArrowLeft, Heart, Star, Gift, ShoppingBag, AlertCircle } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { useState, useEffect } from 'react';
import { MotiView } from 'moti';
import { wcService, WCProduct, WCVariation } from '@/services/WooCommerceService';
import { LoyaltyCard } from '@/components/LoyaltyCard';

const { width } = Dimensions.get('window');

const stripHtml = (html: string) => {
  return html.replace(/<[^>]*>?/gm, '').trim();
};

export default function ProductDetailScreen() {
  const { id } = useLocalSearchParams();
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  
  const [product, setProduct] = useState<WCProduct | null>(null);
  const [variations, setVariations] = useState<WCVariation[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedSize, setSelectedSize] = useState<string | null>(null);
  const [isGift, setIsGift] = useState(false);

  useEffect(() => {
    if (id) {
      loadProductData();
    }
  }, [id]);

  const loadProductData = async () => {
    setLoading(true);
    const productData = await wcService.getProduct(id as string);
    if (productData) {
      setProduct(productData);
      if (productData.variations.length > 0) {
        const variationData = await wcService.getProductVariations(productData.id);
        setVariations(variationData);
      }
    }
    setLoading(false);
  };

  const selectedVariation = variations.find(v => 
    v.attributes.some(attr => attr.option === selectedSize)
  );

  const isOutOfStock = product?.stock_status === 'outofstock' || 
    (selectedSize && selectedVariation?.stock_status === 'outofstock');

  if (loading) {
    return (
      <View style={[styles.container, { backgroundColor: theme.background, justifyContent: 'center' }]}>
        <ActivityIndicator size="large" color={theme.accent} />
      </View>
    );
  }

  if (!product) {
    return (
      <View style={[styles.container, { backgroundColor: theme.background, justifyContent: 'center', alignItems: 'center' }]}>
        <Text>Producto no encontrado</Text>
        <TouchableOpacity onPress={() => router.back()} style={{ marginTop: 20 }}>
          <Text style={{ color: theme.accent }}>Volver a la tienda</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const sizes = variations.length > 0 
    ? variations.map(v => v.attributes.find(a => a.name.toLowerCase().includes('talla') || a.name.toLowerCase().includes('size'))?.option).filter(Boolean) as string[]
    : [];

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        {/* Header Image */}
        <RNView style={styles.imageContainer}>
          <Image source={{ uri: product.images[0]?.src }} style={styles.image} />
          <TouchableOpacity 
            onPress={() => router.back()}
            style={[styles.backButton, { backgroundColor: 'rgba(255,255,255,0.8)' }]}
          >
            <ArrowLeft size={24} color="#1A1A1A" />
          </TouchableOpacity>
        </RNView>

        <RNView style={styles.content}>
          <RNView style={styles.mainInfo}>
            <RNView style={{ flex: 1, marginRight: 10 }}>
              <Text style={styles.title}>{product.name}</Text>
              <Text style={[styles.category, { color: theme.muted }]}>
                {product.categories[0]?.name || 'Colección'}
              </Text>
            </RNView>
            <Text style={styles.price}>${product.price}</Text>
          </RNView>

          {/* Description */}
          <RNView style={styles.section}>
            <Text style={[styles.description, { color: theme.text }]}>
              {stripHtml(product.description || product.short_description)}
            </Text>
          </RNView>

          {/* Size Selector */}
          {sizes.length > 0 && (
            <RNView style={styles.section}>
              <RNView style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Selecciona tu talla</Text>
                <TouchableOpacity>
                  <Text style={[styles.guideLink, { color: theme.accent }]}>Guía de tallas</Text>
                </TouchableOpacity>
              </RNView>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.sizeScroll}>
                {sizes.sort().map(size => {
                  const variation = variations.find(v => v.attributes.some(a => a.option === size));
                  const out = variation?.stock_status === 'outofstock';
                  
                  return (
                    <TouchableOpacity 
                      key={size}
                      disabled={out}
                      onPress={() => setSelectedSize(size)}
                      style={[
                        styles.sizeChip, 
                        { 
                          borderColor: selectedSize === size ? theme.text : theme.border,
                          backgroundColor: selectedSize === size ? theme.text : theme.background,
                          opacity: out ? 0.4 : 1
                        }
                      ]}
                    >
                      <Text style={[styles.sizeText, { color: selectedSize === size ? theme.background : theme.text }]}>
                        {size}
                      </Text>
                      {out && <RNView style={styles.outDiagonal} />}
                    </TouchableOpacity>
                  );
                })}
              </ScrollView>
            </RNView>
          )}

          {/* Stock Info */}
          {selectedSize && selectedVariation && (
            <RNView style={styles.stockInfo}>
              {selectedVariation.stock_status === 'instock' ? (
                <Text style={{ color: '#2ecc71', fontSize: 13 }}>
                  ✓ Disponible en talla {selectedSize}
                </Text>
              ) : (
                <RNView style={{ flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                  <AlertCircle size={14} color="#e74c3c" />
                  <Text style={{ color: '#e74c3c', fontSize: 13 }}>Agotado en esta talla</Text>
                </RNView>
              )}
            </RNView>
          )}

          {/* Loyalty Banner Redesign */}
          <RNView style={styles.section}>
            <LoyaltyCard
              customerName="Ana García"
              qrCode="FX-a3f8b2c1-preview-00"
              tier="bronze"
              totalPoints={Math.floor(Number(product.price) * 0.1)}
              pairsCount={3}
              pointsToNext={500 - Math.floor(Number(product.price) * 0.1)}
              pairsToNext={3}
            />
          </RNView>

          {/* Gift Mode */}
          <RNView style={[styles.giftCard, { borderColor: theme.border }]}>
            <RNView style={styles.giftInfo}>
              <Gift size={22} color={theme.accent} />
              <RNView>
                <Text style={styles.giftTitle}>¿Es un regalo?</Text>
                <Text style={[styles.giftSubtitle, { color: theme.muted }]}>Ocultamos el precio en el ticket</Text>
              </RNView>
            </RNView>
            <TouchableOpacity 
              onPress={() => setIsGift(!isGift)}
              style={[styles.toggle, { backgroundColor: isGift ? theme.accent : '#eee' }]}
            >
              <MotiView 
                animate={{ translateX: isGift ? 24 : 2 }}
                style={styles.toggleKnob}
              />
            </TouchableOpacity>
          </RNView>

          {isGift && (
            <MotiView 
              from={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 120 }}
              style={styles.noteContainer}
            >
              <TextInput 
                placeholder="Escribe una nota personalizada..."
                placeholderTextColor={theme.muted}
                multiline
                style={[styles.noteInput, { borderColor: theme.border, color: theme.text }]}
              />
            </MotiView>
          )}

          <TouchableOpacity 
            disabled={isOutOfStock || (sizes.length > 0 && !selectedSize)}
            style={[
              styles.buyButton, 
              { 
                backgroundColor: isOutOfStock ? theme.muted : theme.text,
                opacity: (sizes.length > 0 && !selectedSize) ? 0.6 : 1
              }
            ]}
          >
            <ShoppingBag size={20} color={theme.background} />
            <Text style={[styles.buyButtonText, { color: theme.background }]}>
              {isOutOfStock ? 'Agotado' : 'Añadir al Carrito'}
            </Text>
          </TouchableOpacity>
        </RNView>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: 100,
  },
  imageContainer: {
    width: width,
    height: width * 1.2,
    position: 'relative',
  },
  image: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  backButton: {
    position: 'absolute',
    top: 60,
    left: 20,
    padding: 10,
    borderRadius: 25,
  },
  content: {
    padding: 20,
  },
  mainInfo: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    lineHeight: 30,
  },
  category: {
    fontSize: 14,
    marginTop: 4,
    textTransform: 'uppercase',
  },
  price: {
    fontSize: 22,
    fontWeight: '700',
  },
  description: {
    fontSize: 14,
    lineHeight: 22,
    marginBottom: 10,
  },
  section: {
    marginBottom: 25,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 15,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
  },
  guideLink: {
    fontSize: 12,
    fontWeight: '700',
  },
  sizeScroll: {
    gap: 10,
  },
  sizeChip: {
    width: 60,
    height: 60,
    borderRadius: 15,
    borderWidth: 1,
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
    overflow: 'hidden',
  },
  sizeText: {
    fontSize: 16,
    fontWeight: '600',
  },
  outDiagonal: {
    position: 'absolute',
    width: '140%',
    height: 1,
    backgroundColor: '#ff0000',
    transform: [{ rotate: '45deg' }],
  },
  stockInfo: {
    marginBottom: 20,
    paddingHorizontal: 5,
  },
  loyaltyBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 16,
    borderRadius: 15,
    borderWidth: 1,
    borderStyle: 'dashed',
    marginBottom: 30,
  },
  loyaltyText: {
    fontSize: 13,
    flex: 1,
  },
  giftCard: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    borderWidth: 1,
    borderRadius: 15,
    marginBottom: 15,
  },
  giftInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  giftTitle: {
    fontSize: 14,
    fontWeight: '600',
  },
  giftSubtitle: {
    fontSize: 12,
    marginTop: 2,
  },
  toggle: {
    width: 52,
    height: 28,
    borderRadius: 14,
    justifyContent: 'center',
    paddingHorizontal: 2,
  },
  toggleKnob: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: '#fff',
  },
  noteContainer: {
    marginBottom: 20,
    overflow: 'hidden',
  },
  noteInput: {
    borderWidth: 1,
    borderRadius: 12,
    padding: 15,
    height: 100,
    fontSize: 14,
    textAlignVertical: 'top',
  },
  buyButton: {
    flexDirection: 'row',
    height: 60,
    borderRadius: 30,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 12,
    marginTop: 10,
  },
  buyButtonText: {
    fontSize: 16,
    fontWeight: '600',
  }
});
