import {
  StyleSheet, ScrollView, TouchableOpacity, View as RNView, TextInput,
  ActivityIndicator, ImageBackground, Dimensions, StatusBar, Image,
} from 'react-native';
import { Text, View } from '@/components/Themed';
import { Search, ArrowLeft } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { MotiView } from 'moti';
import { router, useLocalSearchParams } from 'expo-router';
import { useState, useEffect, useRef } from 'react';
import { wcService, WCProduct, WCCategory } from '@/services/WooCommerceService';
import { ProductCard } from '@/components/ProductCard';
import { SafeAreaView } from 'react-native-safe-area-context';

const { width } = Dimensions.get('window');

// ── Fallback local images por si no hay internet ──
const FALLBACKS: Record<string, any> = {
  ballerina:  require('../../assets/images/cat_ballerinas.png'),
  flat:       require('../../assets/images/cat_ballerinas.png'),
  sandalia:   require('../../assets/images/cat_sandals.png'),
  sandal:     require('../../assets/images/cat_sandals.png'),
  bota:       require('../../assets/images/cat_boots.png'),
  boot:       require('../../assets/images/cat_boots.png'),
  outlet:     require('../../assets/images/cat_sale.png'),
  sale:       require('../../assets/images/cat_sale.png'),
  default:    require('../../assets/images/cat_ballerinas.png'),
};

const FILTER_KEYS: { key: string; label: string; slugMatch: string[] }[] = [
  { key: 'ballerinas', label: 'Ballerinas', slugMatch: ['ballerina', 'flat', 'plana'] },
  { key: 'sandalias',  label: 'Sandalias',  slugMatch: ['sandalia', 'sandal'] },
  { key: 'botas',      label: 'Botas',      slugMatch: ['bota', 'boot', 'bootie'] },
  { key: 'outlet',     label: 'Outlet',     slugMatch: ['outlet', 'sale', 'rebaja'] },
];

function getFallback(slugOrName: string): any {
  const s = (slugOrName ?? '').toLowerCase();
  for (const [key, img] of Object.entries(FALLBACKS)) {
    if (key !== 'default' && s.includes(key)) return img;
  }
  return FALLBACKS.default;
}

function matchesFilter(product: WCProduct, filterKey: string): boolean {
  if (filterKey === 'all') return true;
  const filter = FILTER_KEYS.find((f) => f.key === filterKey);
  if (!filter) return true;
  if (filterKey === 'outlet') {
    const onSale = product.sale_price && product.sale_price !== '' && product.sale_price !== product.regular_price;
    if (onSale) return true;
  }
  const haystack = [
    product.name,
    ...(product.categories ?? []).map((c) => `${c.name} ${c.slug}`),
  ].join(' ').toLowerCase();
  return filter.slugMatch.some((k) => haystack.includes(k));
}

// Mapea WCCategory al filterKey que le corresponde
function categoryToFilterKey(cat: WCCategory): string | null {
  const s = `${cat.name} ${cat.slug}`.toLowerCase();
  for (const f of FILTER_KEYS) {
    if (f.slugMatch.some((k) => s.includes(k))) return f.key;
  }
  return null;
}

export default function ShopScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  const { category } = useLocalSearchParams<{ category?: string }>();

  const [products, setProducts] = useState<WCProduct[]>([]);
  const [categories, setCategories] = useState<WCCategory[]>([]);
  const [loadingCats, setLoadingCats] = useState(true);
  const [loadingProds, setLoadingProds] = useState(false);
  const [loadedProds, setLoadedProds] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeFilter, setActiveFilter] = useState<string>('all');
  const [imgErrors, setImgErrors] = useState<Set<number>>(new Set());

  // Cargar categorías al montar (siempre)
  useEffect(() => {
    (async () => {
      setLoadingCats(true);
      const cats = await wcService.getCategories();
      setCategories(cats);
      setLoadingCats(false);
    })();
  }, []);

  // Sync filtro desde deep-link
  useEffect(() => {
    if (category && FILTER_KEYS.some((f) => f.key === category)) {
      setActiveFilter(category);
      loadProducts();
    }
  }, [category]);

  const loadProducts = async () => {
    if (loadedProds) return;
    setLoadingProds(true);
    try {
      const data = await wcService.getProducts({ status: 'publish' });
      setProducts(data);
      setLoadedProds(true);
    } catch (e) {
      console.error(e);
    } finally {
      setLoadingProds(false);
    }
  };

  const handleSelectCategory = (key: string) => {
    setActiveFilter(key);
    loadProducts();
  };

  const filteredProducts = products.filter((p) => {
    const nameMatch = p.name.toLowerCase().includes(searchQuery.toLowerCase());
    return nameMatch && matchesFilter(p, activeFilter);
  });

  const showCategories = activeFilter === 'all' && searchQuery.length === 0;

  // Construir tiles de categoría: una por filterKey, con imagen de WC o fallback
  const catTiles = FILTER_KEYS.map((f) => {
    const wcCat = categories.find((c) => categoryToFilterKey(c) === f.key);
    const wcImageUrl = wcCat?.image?.src ?? null;
    return { ...f, wcImageUrl, wcCatId: wcCat?.id ?? null };
  });

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]} edges={['top']}>
      <StatusBar barStyle={colorScheme === 'dark' ? 'light-content' : 'dark-content'} />

      {/* ── Search bar ── */}
      <RNView style={styles.header}>
        {!showCategories && (
          <TouchableOpacity
            style={styles.backBtn}
            onPress={() => { setActiveFilter('all'); setSearchQuery(''); }}
          >
            <ArrowLeft size={20} color={theme.text} />
          </TouchableOpacity>
        )}
        <RNView style={[styles.searchBar, { backgroundColor: theme.soft, flex: 1 }]}>
          <Search size={18} color={theme.muted} />
          <TextInput
            placeholder="Buscar productos..."
            placeholderTextColor={theme.muted}
            value={searchQuery}
            onChangeText={(t) => { setSearchQuery(t); if (t.length > 0) loadProducts(); }}
            style={[styles.searchInput, { color: theme.text }]}
          />
        </RNView>
      </RNView>

      {showCategories ? (
        /* ─── CATEGORIES LANDING ─── */
        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.catScroll}>
          <MotiView
            from={{ opacity: 0, translateY: 10 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 500 }}
          >
            <Text style={[styles.catEyebrow, { color: theme.accent }]}>COLECCIÓN</Text>
            <Text style={[styles.catTitle, { color: theme.text }]}>¿Qué estás{'\n'}buscando?</Text>
          </MotiView>

          {loadingCats ? (
            <RNView style={styles.catsLoader}>
              <ActivityIndicator color={theme.accent} />
            </RNView>
          ) : (
            <RNView style={styles.masonryGrid}>
              {/* Columna izquierda: Ballerinas (alto) + Botas (bajo) */}
              <RNView style={styles.gridCol}>
                {[catTiles[0], catTiles[2]].map((cat, i) => (
                  <MotiView
                    key={cat.key}
                    from={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ type: 'spring', damping: 16, delay: i * 80 }}
                  >
                    <TouchableOpacity
                      style={[styles.masonryTile, { height: i === 0 ? 280 : 180 }]}
                      onPress={() => handleSelectCategory(cat.key)}
                      activeOpacity={0.85}
                    >
                      <CatImage
                        url={cat.wcImageUrl}
                        fallback={getFallback(cat.key)}
                        hasError={cat.wcCatId ? imgErrors.has(cat.wcCatId) : false}
                        onError={() => cat.wcCatId && setImgErrors(prev => new Set(prev).add(cat.wcCatId!))}
                        label={cat.label}
                      />
                    </TouchableOpacity>
                  </MotiView>
                ))}
              </RNView>

              {/* Columna derecha: Sandalias (bajo) + Outlet (alto), offset */}
              <RNView style={[styles.gridCol, { marginTop: 40 }]}>
                {[catTiles[1], catTiles[3]].map((cat, i) => (
                  <MotiView
                    key={cat.key}
                    from={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ type: 'spring', damping: 16, delay: 40 + i * 80 }}
                  >
                    <TouchableOpacity
                      style={[styles.masonryTile, { height: i === 0 ? 180 : 280 }]}
                      onPress={() => handleSelectCategory(cat.key)}
                      activeOpacity={0.85}
                    >
                      <CatImage
                        url={cat.wcImageUrl}
                        fallback={getFallback(cat.key)}
                        hasError={cat.wcCatId ? imgErrors.has(cat.wcCatId) : false}
                        onError={() => cat.wcCatId && setImgErrors(prev => new Set(prev).add(cat.wcCatId!))}
                        label={cat.label}
                      />
                    </TouchableOpacity>
                  </MotiView>
                ))}
              </RNView>
            </RNView>
          )}
        </ScrollView>
      ) : (
        /* ─── PRODUCTS WITH FILTER ─── */
        <>
          <RNView style={styles.chipsRow}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chipsScroll}>
              {FILTER_KEYS.map((f) => {
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
          </RNView>

          <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
            {loadingProds ? (
              <RNView style={styles.loaderContainer}>
                <ActivityIndicator size="large" color={theme.accent} />
                <Text style={{ marginTop: 10, color: theme.muted }}>Cargando colección...</Text>
              </RNView>
            ) : filteredProducts.length === 0 ? (
              <RNView style={styles.loaderContainer}>
                <Text style={{ color: theme.text, fontSize: 16, fontWeight: '600' }}>Sin resultados</Text>
                <Text style={{ marginTop: 8, color: theme.muted, fontSize: 13, textAlign: 'center' }}>
                  Intenta con otra categoría o búsqueda.
                </Text>
              </RNView>
            ) : (
              <RNView style={styles.grid}>
                {filteredProducts.map((product, i) => (
                  <ProductCard key={product.id} product={product} index={i} fullWidth />
                ))}
              </RNView>
            )}
          </ScrollView>
        </>
      )}
    </SafeAreaView>
  );
}

/* ── Componente de imagen de categoría con fallback ── */
function CatImage({
  url,
  fallback,
  hasError,
  onError,
  label,
}: {
  url: string | null;
  fallback: any;
  hasError: boolean;
  onError: () => void;
  label: string;
}) {
  const useLocal = !url || hasError;
  return useLocal ? (
    <ImageBackground source={fallback} style={styles.catImage}>
      <RNView style={styles.catOverlay}>
        <Text style={styles.catLabel}>{label}</Text>
      </RNView>
    </ImageBackground>
  ) : (
    <RNView style={{ flex: 1 }}>
      <Image
        source={{ uri: url }}
        style={styles.catImageRemote}
        onError={onError}
      />
      <RNView style={[styles.catOverlay, StyleSheet.absoluteFillObject]}>
        <Text style={styles.catLabel}>{label}</Text>
      </RNView>
    </RNView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 16,
    gap: 10,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    justifyContent: 'center', alignItems: 'center',
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 14,
    paddingHorizontal: 14,
    height: 46,
  },
  searchInput: { flex: 1, marginLeft: 8, fontSize: 14 },

  /* Categories landing */
  catScroll: { paddingHorizontal: 20, paddingBottom: 120 },
  catEyebrow: { fontSize: 10, fontWeight: '800', letterSpacing: 3, marginBottom: 6 },
  catTitle: {
    fontSize: 34, fontFamily: 'serif', fontWeight: '400',
    lineHeight: 40, marginBottom: 30,
  },
  catsLoader: { paddingTop: 80, alignItems: 'center' },
  masonryGrid: { flexDirection: 'row', gap: 15 },
  gridCol: { flex: 1, gap: 15 },
  masonryTile: { width: '100%', borderRadius: 4, overflow: 'hidden' },
  catImage: { flex: 1 },
  catImageRemote: { width: '100%', height: '100%', resizeMode: 'cover' },
  catOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.28)',
    justifyContent: 'flex-end',
    padding: 14,
  },
  catLabel: {
    color: '#FFF', fontSize: 17, fontFamily: 'serif',
    letterSpacing: 2, textTransform: 'uppercase', fontWeight: '400',
  },

  /* Products view */
  chipsRow: { paddingBottom: 10 },
  chipsScroll: { paddingHorizontal: 20, gap: 8 },
  filterChip: {
    paddingHorizontal: 18, paddingVertical: 9,
    borderRadius: 20, borderWidth: 1,
  },
  filterText: { fontSize: 13, fontWeight: '600' },
  scrollContent: { paddingHorizontal: 20, paddingBottom: 110 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', gap: 15 },
  loaderContainer: { padding: 100, alignItems: 'center', justifyContent: 'center' },
});
