import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView, TextInput, Dimensions } from 'react-native';
import { Text, View } from '@/components/Themed';
import { useLocalSearchParams, router } from 'expo-router';
import { ArrowLeft, Heart, Star, Gift, ShoppingBag } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { useState } from 'react';
import { MotiView } from 'moti';

const HERO_IMAGE = require('../../assets/images/hero.png');
const SANDALS_IMAGE = require('../../assets/images/sandals.png');
const { width } = Dimensions.get('window');

export default function ProductDetailScreen() {
  const { id } = useLocalSearchParams();
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  
  const [selectedSize, setSelectedSize] = useState<string | null>(null);
  const [isGift, setIsGift] = useState(false);

  // Mock data mapping
  const isSandal = id === '2' || id?.toString().includes('sandal');
  const productImage = isSandal ? SANDALS_IMAGE : HERO_IMAGE;
  const productName = isSandal ? 'Sandalia Bronze' : 'Ballerina Beige Gold';

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        {/* Header Image */}
        <RNView style={styles.imageContainer}>
          <Image source={productImage} style={styles.image} />
          <TouchableOpacity 
            onPress={() => router.back()}
            style={[styles.backButton, { backgroundColor: 'rgba(255,255,255,0.8)' }]}
          >
            <ArrowLeft size={24} color="#1A1A1A" />
          </TouchableOpacity>
        </RNView>

        <RNView style={styles.content}>
          <RNView style={styles.mainInfo}>
            <RNView>
              <Text style={styles.title}>{productName}</Text>
              <Text style={[styles.category, { color: theme.muted }]}>Ballerinas de Cuero</Text>
            </RNView>
            <Text style={styles.price}>$2,800</Text>
          </RNView>

          {/* Size Selector */}
          <RNView style={styles.section}>
            <RNView style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>Selecciona tu talla</Text>
              <TouchableOpacity>
                <Text style={[styles.guideLink, { color: theme.accent }]}>Guía de tallas</Text>
              </TouchableOpacity>
            </RNView>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.sizeScroll}>
              {['35', '36', '37', '38', '39', '40'].map(size => (
                <TouchableOpacity 
                  key={size}
                  onPress={() => setSelectedSize(size)}
                  style={[
                    styles.sizeChip, 
                    { 
                      borderColor: selectedSize === size ? theme.text : theme.border,
                      backgroundColor: selectedSize === size ? theme.text : theme.background 
                    }
                  ]}
                >
                  <Text style={[styles.sizeText, { color: selectedSize === size ? theme.background : theme.text }]}>{size}</Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
          </RNView>

          {/* Loyalty Banner */}
          <RNView style={[styles.loyaltyBanner, { backgroundColor: theme.soft, borderColor: theme.accent }]}>
             <Star size={20} color={theme.accent} fill={theme.accent} />
             <Text style={styles.loyaltyText}>
                Compra este modelo y gana <Text style={{ fontWeight: '700' }}>280 puntos Fuxia</Text>
             </Text>
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

          <TouchableOpacity style={[styles.buyButton, { backgroundColor: theme.text }]}>
            <ShoppingBag size={20} color={theme.background} />
            <Text style={[styles.buyButtonText, { color: theme.background }]}>Añadir al Carrito</Text>
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
    marginBottom: 30,
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
  },
  category: {
    fontSize: 16,
    marginTop: 4,
  },
  price: {
    fontSize: 22,
    fontWeight: '700',
  },
  section: {
    marginBottom: 30,
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
  },
  sizeText: {
    fontSize: 16,
    fontWeight: '600',
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
