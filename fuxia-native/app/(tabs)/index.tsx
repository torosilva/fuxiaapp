import React from 'react';
import { View, Text, StyleSheet, Image, TouchableOpacity, ScrollView, StatusBar, ImageBackground, Dimensions } from 'react-native';
import { Search, ShoppingBag, ArrowRight } from 'lucide-react-native';
import { router } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';

// 1. Sistema de Diseño (Dark Mode / Luxury Theme)
// Actualizado a un "Richer Bronze Gold" como se solicitó
const FuxiaDarkTheme = {
  colors: {
    background: '#0F0F0F', // Negro puro o casi puro para máximo contraste
    textPrimary: '#FFFFFF',
    textSecondary: '#D1D1D1',
    brandGold: '#B8860B', // Dark Goldenrod - un tono bronce más profundo y rico
    surface: '#1A1A1A',
    overlay: 'rgba(0,0,0,0.2)',
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
  return (
    <SafeAreaView style={styles.container} edges={['top', 'left', 'right']}>
      <StatusBar barStyle="light-content" />
      <ScrollView showsVerticalScrollIndicator={false}>

        {/* --- HEADER --- */}
        <View style={styles.header}>
          <Image source={LOGO_IMAGE} style={styles.logo} resizeMode="contain" />
          <View style={styles.headerIcons}>
            <TouchableOpacity style={styles.iconButton}>
              <Search size={22} color={FuxiaDarkTheme.colors.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.iconButton}>
              <ShoppingBag size={22} color={FuxiaDarkTheme.colors.textPrimary} />
            </TouchableOpacity>
          </View>
        </View>

        {/* --- HERO SECTION ASIMÉTRICO --- */}
        <ImageBackground 
          source={HERO_IMAGE} 
          style={styles.heroContainer}
          imageStyle={styles.heroImage}
        >
          <View style={styles.heroOverlay}>
            <View style={styles.heroTextWrapper}>
              <Text style={styles.collectionText}>COLECCIÓN 2026</Text>
              <Text style={styles.heroTitle}>Elegancia en{'\n'}cada paso</Text>
              
              <TouchableOpacity 
                style={styles.heroLinkButton}
                onPress={() => router.push('/(tabs)/shop')}
              >
                <Text style={styles.heroLinkText}>DESCUBRIR LA COLECCIÓN</Text>
                <ArrowRight size={16} color={FuxiaDarkTheme.colors.brandGold} style={{ marginLeft: 6 }} />
              </TouchableOpacity>
            </View>
          </View>
        </ImageBackground>

        {/* --- CATEGORÍAS: COLLAGE ARTÍSTICO 2x2 --- */}
        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>Nuestras Colecciones</Text>
        </View>

        <View style={styles.balancedGrid}>
          {/* Fila 1 */}
          <View style={styles.gridRow}>
            <TouchableOpacity 
              style={styles.gridTile}
              onPress={() => router.push('/(tabs)/shop')}
            >
              <ImageBackground source={CAT_BALLERINAS} style={styles.categoryImage}>
                <View style={styles.categoryOverlay}>
                  <Text style={styles.categoryLabel}>Ballerinas</Text>
                </View>
              </ImageBackground>
            </TouchableOpacity>

            <TouchableOpacity 
              style={styles.gridTile}
              onPress={() => router.push('/(tabs)/shop')}
            >
              <ImageBackground source={CAT_SANDALS} style={styles.categoryImage}>
                <View style={styles.categoryOverlay}>
                  <Text style={styles.categoryLabel}>Sandalias</Text>
                </View>
              </ImageBackground>
            </TouchableOpacity>
          </View>

          {/* Fila 2 */}
          <View style={styles.gridRow}>
            <TouchableOpacity 
              style={styles.gridTile}
              onPress={() => router.push('/(tabs)/shop')}
            >
              <ImageBackground source={CAT_BOOTS} style={styles.categoryImage}>
                <View style={styles.categoryOverlay}>
                  <Text style={styles.categoryLabel}>Botas</Text>
                </View>
              </ImageBackground>
            </TouchableOpacity>

            <TouchableOpacity 
              style={styles.gridTile}
              onPress={() => router.push('/(tabs)/shop')}
            >
              <ImageBackground source={CAT_SALE} style={styles.categoryImage}>
                <View style={styles.categoryOverlay}>
                  <Text style={styles.categoryLabel}>Sale</Text>
                </View>
              </ImageBackground>
            </TouchableOpacity>
          </View>
        </View>

        {/* Espacio extra al final para el scroll */}
        <View style={{ height: 100 }} />
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
    paddingHorizontal: FuxiaDarkTheme.spacing.m, 
    paddingBottom: FuxiaDarkTheme.spacing.m,
    paddingTop: 10,
    backgroundColor: FuxiaDarkTheme.colors.background 
  },
  logo: {
    width: 150,
    height: 30,
  },
  headerIcons: {
    flexDirection: 'row',
    gap: 15,
  },
  iconButton: {
    padding: 5,
  },
  
  // Hero Styles
  heroContainer: { 
    width: '100%', 
    height: 480, 
    backgroundColor: FuxiaDarkTheme.colors.surface 
  },
  heroImage: { resizeMode: 'cover' },
  heroOverlay: { 
    flex: 1, 
    backgroundColor: 'rgba(0,0,0,0.1)', 
    justifyContent: 'flex-end', 
    padding: FuxiaDarkTheme.spacing.l 
  },
  heroTextWrapper: { alignItems: 'flex-end' }, // Alineación a la derecha
  collectionText: { 
    fontSize: 12, 
    color: '#FFF', 
    letterSpacing: 4, 
    marginBottom: 8, 
    fontWeight: '600' 
  },
  heroTitle: { 
    fontSize: 34, 
    color: '#FFF', 
    fontFamily: 'serif', 
    textAlign: 'right', 
    marginBottom: 20, 
    lineHeight: 40,
    fontWeight: '700'
  },
  heroLinkButton: { 
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1, 
    borderBottomColor: FuxiaDarkTheme.colors.brandGold, 
    paddingBottom: 4 
  },
  heroLinkText: { 
    fontSize: 13, 
    color: FuxiaDarkTheme.colors.brandGold, 
    letterSpacing: 2, 
    fontWeight: '600',
    textTransform: 'uppercase'
  },

  // Sections
  sectionHeader: { 
    padding: FuxiaDarkTheme.spacing.m, 
    marginTop: FuxiaDarkTheme.spacing.l 
  },
  sectionTitle: { 
    fontSize: 22, 
    color: FuxiaDarkTheme.colors.textPrimary, 
    fontWeight: '700',
    letterSpacing: 1
  },

  // Balanced 2x2 Grid Layout
  balancedGrid: { 
    paddingHorizontal: FuxiaDarkTheme.spacing.m, 
    gap: 12 
  },
  gridRow: {
    flexDirection: 'row',
    gap: 12,
    height: 200,
  },
  gridTile: {
    flex: 1,
    borderRadius: 2,
    overflow: 'hidden',
  },
  categoryImage: { 
    flex: 1, 
    width: '100%', 
    height: '100%' 
  },
  categoryOverlay: { 
    flex: 1, 
    backgroundColor: 'rgba(0,0,0,0.3)', 
    justifyContent: 'center', 
    alignItems: 'center' 
  },
  categoryLabel: { 
    fontSize: 18, 
    color: '#FFF', 
    fontFamily: 'serif', 
    letterSpacing: 2,
    textTransform: 'uppercase',
    fontWeight: '700'
  },
});
