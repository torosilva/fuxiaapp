import React, { useState } from 'react';
import { Image, ImageStyle, StyleProp, StyleSheet, View } from 'react-native';

const FALLBACK = require('../assets/images/logo-icon.png');

interface Props {
  uri?: string | null;
  style?: StyleProp<ImageStyle>;
  resizeMode?: 'cover' | 'contain';
}

/**
 * Imagen de producto con respaldo de marca. Si el producto no tiene foto
 * (p.ej. borrada en la web) o la URL falla al cargar, muestra el logo Fuxia
 * en vez de un hueco vacío. React Native puro, sin dependencias extra.
 *
 * La preferencia override(Supabase) → web → placeholder se resuelve antes, en
 * WooCommerceService (tabla `product_image_overrides`). Acá solo cae al
 * placeholder cuando ni el override ni la web dieron una imagen usable.
 */
export const ProductImage = ({ uri, style, resizeMode = 'cover' }: Props) => {
  const [failed, setFailed] = useState(false);

  if (uri && !failed) {
    return (
      <Image
        source={{ uri }}
        style={style}
        resizeMode={resizeMode}
        onError={() => setFailed(true)}
      />
    );
  }

  return (
    <View style={[styles.fallbackWrap, style]}>
      <Image source={FALLBACK} style={styles.fallbackLogo} resizeMode="contain" />
    </View>
  );
};

const styles = StyleSheet.create({
  fallbackWrap: {
    backgroundColor: '#1A1A1A',
    justifyContent: 'center',
    alignItems: 'center',
  },
  fallbackLogo: {
    width: '45%',
    height: '45%',
    opacity: 0.5,
  },
});
