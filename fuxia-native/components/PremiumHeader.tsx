import React from 'react';
import { StyleSheet, Image, TouchableOpacity, View as RNView, Platform } from 'react-native';
import { Search, ShoppingBag } from 'lucide-react-native';
import { router } from 'expo-router';
import { MotiView } from 'moti';

const LOGO_IMAGE = require('../assets/images/logo-icon.png');

interface PremiumHeaderProps {
  transparent?: boolean;
}

export const PremiumHeader = ({ transparent = true }: PremiumHeaderProps) => {
  return (
    <MotiView 
      from={{ translateY: -100, opacity: 0 }}
      animate={{ translateY: 0, opacity: 1 }}
      transition={{ type: 'timing', duration: 800 }}
      style={[
        styles.header, 
        !transparent && styles.solidHeader
      ]}
    >
      <RNView style={styles.sideContainer}>
        <TouchableOpacity style={styles.iconButton} onPress={() => router.push('/(tabs)/shop')}>
          <Search size={22} color="#FFF" />
        </TouchableOpacity>
      </RNView>

      <RNView style={styles.logoContainer}>
        <Image 
          source={LOGO_IMAGE} 
          style={styles.logo} 
          resizeMode="contain" 
        />
      </RNView>

      <RNView style={styles.sideContainer}>
        <View style={{ alignItems: 'flex-end' }}>
          <TouchableOpacity style={styles.iconButton}>
            <ShoppingBag size={22} color="#FFF" />
          </TouchableOpacity>
        </View>
      </RNView>
    </MotiView>
  );
};

// Internal View to handle flexDirection: 'row' for the third container
const View = RNView;

const styles = StyleSheet.create({
  header: { 
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20, 
    height: 70,
    width: '100%',
    position: 'absolute',
    top: Platform.OS === 'ios' ? 50 : 30,
    left: 0,
    right: 0,
    zIndex: 100,
  },
  solidHeader: {
    backgroundColor: '#0D0D0D',
    position: 'relative',
    top: 0,
    marginTop: Platform.OS === 'ios' ? 0 : 30,
  },
  logoContainer: {
    flex: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logo: {
    width: 36,
    height: 36,
  },
  sideContainer: {
    flex: 1,
  },
  iconButton: {
    padding: 8,
    backgroundColor: 'rgba(255,255,255,0.05)', // Subtle luxury background
    borderRadius: 20,
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
