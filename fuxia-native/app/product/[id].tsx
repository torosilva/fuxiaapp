import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView, TextInput, Dimensions, ActivityIndicator } from 'react-native';
import { Text, View } from '@/components/Themed';
import { useLocalSearchParams, router, Stack } from 'expo-router';
import { useAuth } from '@/lib/hooks/useAuth';
import * as WebBrowser from 'expo-web-browser';
import { Sparkles } from 'lucide-react-native';
import { ArrowLeft, Heart, Star, Gift, ShoppingBag, AlertCircle } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { useState, useEffect } from 'react';
import { MotiView } from 'moti';
import { wcService, WCProduct, WCVariation, withCountryParam } from '@/services/WooCommerceService';
import { formatMoney, priceToPoints } from '@/lib/CountryService';
import { LoyaltyCard } from '@/components/LoyaltyCard';
import { TryOnModal } from '@/components/TryOnModal';

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
  const [tryOnVisible, setTryOnVisible] = useState(false);
  const { customer, loyaltyCard } = useAuth();

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
        const variationData = await wcService.getProductVariations(productData.id, productData.variations);
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
        <Stack.Screen options={{ headerShown: false }} />
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
      <Stack.Screen options={{ headerShown: false }} />
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
            <Text style={styles.price}>
              {formatMoney(product.price, product.currency_code, product.currency_symbol)}
            </Text>
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

          {/* Try-On Button */}
          {product.images[0] && (
            <TouchableOpacity
              style={styles.tryOnBtn}
              onPress={() => setTryOnVisible(true)}
              activeOpacity={0.85}
            >
              <Sparkles size={16} color="#0D0D0D" />
              <Text style={styles.tryOnBtnText}>✨ Pruébatelo con IA</Text>
            </TouchableOpacity>
          )}

          {/* Points preview for this purchase */}
          {product.price && (
            <RNView style={styles.pointsPreview}>
              <Sparkles size={18} color={theme.accent} />
              <Text style={[styles.pointsPreviewText, { color: theme.accent }]}>
                Con esta compra ganarás{' '}
                <Text style={{ fontWeight: '800' }}>
                  +{priceToPoints(product.price, product.currency_code ?? 'MXN').toLocaleString()} puntos
                </Text>
              </Text>
            </RNView>
          )}

          {/* Try-On Modal */}
          {product.images[0] && (
            <TryOnModal
              visible={tryOnVisible}
              onClose={() => setTryOnVisible(false)}
              productImage={product.images[0].src}
              productName={product.name}
            />
          )}

          {/* Loyalty Banner — real user's card */}
          {customer && loyaltyCard && (
            <RNView style={styles.section}>
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
          )}

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
            onPress={async () => {
              if (!product.permalink) return;
              const base = selectedSize
                ? `${product.permalink}?attribute_pa_size=${encodeURIComponent(selectedSize)}`
                : product.permalink;
              const url = await withCountryParam(base);
              await WebBrowser.openBrowserAsync(url);
            }}
            style={[
              styles.buyButton,
              {
                backgroundColor: isOutOfStock ? theme.muted : theme.text,
                opacity: (sizes.length > 0 && !selectedSize) ? 0.6 : 1
              }
            ]}
            activeOpacity={0.85}
          >
            <ShoppingBag size={20} color={theme.background} />
            <Text style={[styles.buyButtonText, { color: theme.background }]}>
              {isOutOfStock ? 'Agotado' : 'Comprar en la web'}
            </Text>
          </TouchableOpacity>
        </RNView>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  tryOnBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 8, backgroundColor: '#CD7F32', borderRadius: 30,
    paddingVertical: 14, marginHorizontal: 20, marginBottom: 14,
  },
  tryOnBtnText: {
    color: '#0D0D0D', fontSize: 14, fontWeight: '800', letterSpacing: 0.5,
  },
  pointsPreview: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginHorizontal: 20,
    marginBottom: 12,
    paddingVertical: 10,
    paddingHorizontal: 14,
    borderRadius: 12,
    backgroundColor: 'rgba(205,127,50,0.08)',
    borderWidth: 1,
    borderColor: 'rgba(205,127,50,0.2)',
  },
  pointsPreviewText: {
    fontSize: 13,
    flex: 1,
  },
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
