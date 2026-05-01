import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Image, TouchableOpacity, ScrollView, StatusBar, ImageBackground, Dimensions, ActivityIndicator } from 'react-native';
import { Search, ShoppingBag, ArrowRight, Sparkles } from 'lucide-react-native';
import { router } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MotiView, MotiText } from 'moti';
import { wcService, WCProduct } from '@/services/WooCommerceService';
import { ProductCard } from '@/components/ProductCard';

const { width } = Dimensions.get('window');

// Sistema de Diseño (Dark Luxury)
const FuxiaDarkTheme = {
  colors: {
    background: '#0D0D0D', // Deep black
    textPrimary: '#FFFFFF',
    textSecondary: '#A0A0A0',
    brandGold: '#B8860B', // Metallic Bronze
    brandGoldLight: '#DAA520',
    surface: '#121212',
    accent: '#B8860B',
  },
  spacing: { s: 8, m: 16, l: 24, xl: 32 }
};

const HERO_IMAGE = require('../../assets/images/hero.png');
const LOGO_IMAGE = require('../../assets/images/logo.png');
const CAT_BALLERINAS = require('../../assets/images/cat_ballerinas.png');
const CAT_SANDALS = require('../../assets/images/cat_sandals.png');
const CAT_BOOTS = require('../../assets/images/cat_boots.png');
const CAT_SALE = require('../../assets/images/cat_sale.png');


export default function HomeScreen() {
  const [newArrivals, setNewArrivals] = useState<WCProduct[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadHomeData();
  }, []);

  const loadHomeData = async () => {
    try {
      setLoading(true);
      const data = await wcService.getProducts({ per_page: 6, orderby: 'date' });
      setNewArrivals(data);
    } catch (error) {
      console.error('Error loading home data:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <StatusBar barStyle="light-content" />
      
      <ScrollView showsVerticalScrollIndicator={false} stickyHeaderIndices={[]} scrollEventThrottle={16}>
        
        {/* --- HERO SECTION: EDITORIAL IMPACT --- */}
        <ImageBackground 
          source={HERO_IMAGE} 
          style={styles.heroContainer}
          imageStyle={styles.heroImage}
        >
          <View style={styles.heroOverlay}>
            <MotiView 
              from={{ opacity: 0, translateX: 50 }}
              animate={{ opacity: 1, translateX: 0 }}
              transition={{ delay: 300, type: 'timing', duration: 1000 }}
              style={styles.heroTextWrapper}
            >
              <Text style={styles.collectionText}>ÉDITION LIMITÉE 2026</Text>
              <MotiText 
                from={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: 500, type: 'timing', duration: 1200 }}
                style={styles.heroTitle}
              >
                Fuxia{'\n'}Essence
              </MotiText>
              
              <TouchableOpacity 
                style={styles.heroLinkButton}
                onPress={() => router.push('/(tabs)/shop')}
              >
                <Text style={styles.heroLinkText}>VER COLECCIÓN</Text>
                <ArrowRight size={16} color={FuxiaDarkTheme.colors.brandGold} style={{ marginLeft: 8 }} />
              </TouchableOpacity>
            </MotiView>
          </View>
        </ImageBackground>

        {/* --- NEW ARRIVALS: DYNAMIC CATALOG --- */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <View>
              <Text style={styles.sectionLabel}>LATEST DROP</Text>
              <Text style={styles.sectionTitle}>Novedades</Text>
            </View>
            <TouchableOpacity onPress={() => router.push('/(tabs)/shop')}>
              <Text style={[styles.viewAll, { color: FuxiaDarkTheme.colors.brandGold }]}>Ver todo</Text>
            </TouchableOpacity>
          </View>

          {loading ? (
            <View style={styles.loader}>
              <ActivityIndicator color={FuxiaDarkTheme.colors.brandGold} />
            </View>
          ) : (
            <ScrollView 
              horizontal 
              showsHorizontalScrollIndicator={false} 
              contentContainerStyle={styles.carouselContent}
              snapToInterval={width * 0.45}
              decelerationRate="fast"
            >
              {newArrivals.map((product, index) => (
                <ProductCard key={product.id} product={product} index={index} />
              ))}
            </ScrollView>
          )}
        </View>

        {/* --- BRAND STORY / DIVIDER --- */}
        <MotiView 
          from={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          transition={{ duration: 1000 }}
          style={styles.brandPitch}
        >
          <Sparkles size={18} color={FuxiaDarkTheme.colors.brandGold} />
          <Text style={styles.pitchText}>
            Diseñadas en México, inspiradas en el mundo. Calzado de lujo artesanal para la mujer contemporánea.
          </Text>
        </MotiView>

        {/* --- CATEGORIES: MASONRY STYLE --- */}
        <View style={[styles.section, { marginBottom: 100 }]}>
          <Text style={styles.sectionTitleCenter}>Categorías</Text>
          
          <View style={styles.masonryGrid}>
            <View style={styles.gridCol}>
              <TouchableOpacity
                style={[styles.masonryTile, { height: 280 }]}
                onPress={() => router.push({ pathname: '/(tabs)/shop' as any, params: { category: 'ballerinas' } })}
                activeOpacity={0.85}
              >
                <ImageBackground source={CAT_BALLERINAS} style={styles.catImage}>
                   <View style={styles.catOverlay}>
                     <Text style={styles.catLabel}>Ballerinas</Text>
                   </View>
                </ImageBackground>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.masonryTile, { height: 180 }]}
                onPress={() => router.push({ pathname: '/(tabs)/shop' as any, params: { category: 'botas' } })}
                activeOpacity={0.85}
              >
                <ImageBackground source={CAT_BOOTS} style={styles.catImage}>
                   <View style={styles.catOverlay}>
                     <Text style={styles.catLabel}>Botas</Text>
                   </View>
                </ImageBackground>
              </TouchableOpacity>
            </View>

            <View style={styles.gridCol}>
              <TouchableOpacity
                style={[styles.masonryTile, { height: 180, marginTop: 40 }]}
                onPress={() => router.push({ pathname: '/(tabs)/shop' as any, params: { category: 'sandalias' } })}
                activeOpacity={0.85}
              >
                <ImageBackground source={CAT_SANDALS} style={styles.catImage}>
                   <View style={styles.catOverlay}>
                     <Text style={styles.catLabel}>Sandalias</Text>
                   </View>
                </ImageBackground>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.masonryTile, { height: 280 }]}
                onPress={() => router.push({ pathname: '/(tabs)/shop' as any, params: { category: 'outlet' } })}
                activeOpacity={0.85}
              >
                <ImageBackground source={CAT_SALE} style={styles.catImage}>
                   <View style={styles.catOverlay}>
                     <Text style={styles.catLabel}>Outlet</Text>
                   </View>
                </ImageBackground>
              </TouchableOpacity>
            </View>
          </View>
        </View>

      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { 
    flex: 1, 
    backgroundColor: FuxiaDarkTheme.colors.background 
  },
  header: { 
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20, 
    height: 70,
    position: 'absolute',
    top: 50,
    left: 0,
    right: 0,
    zIndex: 10,
  },
  logo: {
    width: 140,
    height: 40,
  },
  headerIcons: {
    flexDirection: 'row',
    gap: 15,
  },
  iconButton: {
    padding: 8,
    backgroundColor: 'rgba(0,0,0,0.3)',
    borderRadius: 20,
  },
  
  // Hero
  heroContainer: {
    width: '100%',
    height: width * 1.1,
    backgroundColor: '#000'
  },
  heroImage: { resizeMode: 'cover', opacity: 0.85 },
  heroOverlay: { 
    flex: 1, 
    justifyContent: 'flex-end', 
    padding: 30,
    paddingBottom: 60,
  },
  heroTextWrapper: { alignItems: 'flex-end' },
  collectionText: { 
    fontSize: 10, 
    color: FuxiaDarkTheme.colors.brandGold, 
    letterSpacing: 4, 
    marginBottom: 10, 
    fontWeight: '700' 
  },
  heroTitle: { 
    fontSize: 62, 
    color: '#FFF', 
    fontFamily: 'serif', 
    textAlign: 'right', 
    lineHeight: 65,
    marginBottom: 25,
    fontWeight: '300'
  },
  heroLinkButton: { 
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.05)',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 30,
    borderWidth: 1,
    borderColor: 'rgba(184, 134, 11, 0.3)',
  },
  heroLinkText: { 
    fontSize: 12, 
    color: '#FFF', 
    letterSpacing: 2, 
    fontWeight: '700'
  },

  // Sections
  section: {
    marginTop: 40,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    paddingHorizontal: 20,
    marginBottom: 20,
  },
  sectionLabel: {
    fontSize: 10,
    color: FuxiaDarkTheme.colors.brandGold,
    letterSpacing: 3,
    fontWeight: '800',
    marginBottom: 4,
  },
  sectionTitle: {
    fontSize: 32,
    color: '#FFF',
    fontFamily: 'serif',
    fontWeight: '400',
  },
  sectionTitleCenter: {
    fontSize: 28,
    color: '#FFF',
    fontFamily: 'serif',
    textAlign: 'center',
    marginBottom: 30,
  },
  viewAll: {
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  carouselContent: {
    paddingLeft: 20,
    paddingRight: 20,
  },
  loader: {
    height: 200,
    justifyContent: 'center',
    alignItems: 'center',
  },

  // Brand Pitch
  brandPitch: {
    padding: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#151515',
    marginVertical: 24,
  },
  pitchText: {
    color: '#A0A0A0',
    textAlign: 'center',
    fontSize: 14,
    lineHeight: 22,
    marginTop: 15,
    fontStyle: 'italic',
    paddingHorizontal: 20,
  },

  // Masonry Grid
  masonryGrid: {
    flexDirection: 'row',
    paddingHorizontal: 20,
    gap: 15,
  },
  gridCol: {
    flex: 1,
    gap: 15,
  },
  masonryTile: {
    width: '100%',
    borderRadius: 2,
    overflow: 'hidden',
  },
  catImage: {
    flex: 1,
  },
  catOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 10,
  },
  catLabel: {
    color: '#FFF',
    fontSize: 18,
    fontFamily: 'serif',
    letterSpacing: 3,
    textTransform: 'uppercase',
    fontWeight: '400',
    textAlign: 'center',
  }
});
