import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  StatusBar,
  ActivityIndicator,
  Alert,
  ScrollView,
  Image,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import {
  ArrowLeft,
  Search,
  ChevronDown,
  ChevronRight,
  Package,
  Download,
  Plus,
  Minus,
} from 'lucide-react-native';
import { supabase } from '@/lib/supabase';
import { wcService, WCProduct, WCVariation } from '@/services/WooCommerceService';

const SIZE_RE = /talla|tama|size|n[uú]mero|numero/i;
const COLOR_RE = /color/i;

function attrValue(v: WCVariation, re: RegExp): string | null {
  const hit = v.attributes.find((a) => re.test(a.name));
  return hit?.option?.trim() || null;
}

/** Fila candidata a importar: variación de un producto, o el producto simple. */
interface Row {
  key: string;
  productId: number;
  productName: string;
  sku: string;
  size: string;
  color: string | null;
  price: number;
  imageUrl: string | null;
}

export default function ImportWooScreen() {
  const { channelId, channelName } = useLocalSearchParams<{
    channelId: string;
    channelName: string;
  }>();

  const [products, setProducts] = useState<WCProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [variationsByProduct, setVariationsByProduct] = useState<Record<number, WCVariation[]>>({});
  const [loadingVariations, setLoadingVariations] = useState<Set<number>>(new Set());
  const [qty, setQty] = useState<Record<string, number>>({});
  const [saving, setSaving] = useState(false);

  const fetchProducts = useCallback(async (searchTerm: string) => {
    setLoading(true);
    const params: Record<string, string | number> = { per_page: 100 };
    if (searchTerm.trim()) params.search = searchTerm.trim();
    const data = await wcService.getProducts(params);
    setProducts(data);
    setLoading(false);
  }, []);

  useEffect(() => {
    fetchProducts('');
  }, [fetchProducts]);

  // Debounce de búsqueda
  useEffect(() => {
    const t = setTimeout(() => fetchProducts(search), 400);
    return () => clearTimeout(t);
  }, [search, fetchProducts]);

  const toggleProduct = async (p: WCProduct) => {
    const opening = expandedId !== p.id;
    setExpandedId(opening ? p.id : null);
    if (opening && p.variations.length > 0 && !variationsByProduct[p.id]) {
      setLoadingVariations((s) => new Set(s).add(p.id));
      const vars = await wcService.getProductVariationsRest(p.id);
      setVariationsByProduct((prev) => ({ ...prev, [p.id]: vars }));
      setLoadingVariations((s) => {
        const next = new Set(s);
        next.delete(p.id);
        return next;
      });
    }
  };

  /** Genera las filas visibles (variaciones o producto simple) de un producto. */
  const rowsForProduct = useCallback(
    (p: WCProduct): Row[] => {
      const img = p.images[0]?.src ?? null;
      const vars = variationsByProduct[p.id];
      if (p.variations.length > 0 && vars) {
        return vars.map((v) => {
          const size = attrValue(v, SIZE_RE) ?? 'Única';
          const color = attrValue(v, COLOR_RE);
          const price = parseFloat(v.price || p.price || '0') || 0;
          return {
            key: `v${v.id}`,
            productId: p.id,
            productName: p.name,
            sku: v.sku || `WC-${p.id}-${v.id}`,
            size,
            color,
            price,
            imageUrl: img,
          };
        });
      }
      // Producto simple (sin variaciones)
      return [
        {
          key: `p${p.id}`,
          productId: p.id,
          productName: p.name,
          sku: `WC-${p.id}`,
          size: 'Única',
          color: null,
          price: parseFloat(p.price || '0') || 0,
          imageUrl: img,
        },
      ];
    },
    [variationsByProduct],
  );

  const setRowQty = (key: string, delta: number) =>
    setQty((prev) => {
      const next = Math.max(0, (prev[key] ?? 0) + delta);
      const out = { ...prev };
      if (next === 0) delete out[key];
      else out[key] = next;
      return out;
    });

  const setRowQtyRaw = (key: string, raw: string) =>
    setQty((prev) => {
      const n = parseInt(raw.replace(/\D/g, ''), 10);
      const out = { ...prev };
      if (!n || n <= 0) delete out[key];
      else out[key] = n;
      return out;
    });

  const totalPairs = useMemo(
    () => Object.values(qty).reduce((t, n) => t + n, 0),
    [qty],
  );
  const totalSkus = useMemo(() => Object.keys(qty).length, [qty]);

  const handleImport = async () => {
    if (!channelId) {
      Alert.alert('Error', 'Falta el canal de destino.');
      return;
    }
    // Reunimos todas las filas de los productos que fueron expandidos/cargados.
    const rows: Record<string, unknown>[] = [];
    for (const p of products) {
      for (const r of rowsForProduct(p)) {
        const n = qty[r.key];
        if (n && n > 0) {
          rows.push({
            channel_id: channelId,
            product_name: r.productName,
            sku: r.sku,
            size: r.size,
            color: r.color,
            price: r.price,
            stock: n,
            sold: 0,
            image_url: r.imageUrl,
          });
        }
      }
    }

    if (rows.length === 0) {
      Alert.alert('Sin cantidades', 'Marca cuántos pares llevas de al menos un producto.');
      return;
    }

    setSaving(true);
    const { error } = await supabase.from('channel_inventory').insert(rows);
    setSaving(false);

    if (error) {
      Alert.alert(
        'No se pudo importar',
        error.message.includes('row-level security')
          ? 'La base de datos rechazó la escritura (RLS). Falta aplicar la migración de permisos o tu cuenta no tiene rol admin.'
          : error.message,
      );
      return;
    }

    Alert.alert(
      '¡Inventario importado!',
      `${rows.length} SKUs (${totalPairs} pares) cargados en ${channelName ?? 'el canal'}.`,
      [{ text: 'Listo', onPress: () => router.back() }],
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        {/* Top bar */}
        <View style={styles.topBar}>
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.7}>
            <ArrowLeft size={20} color="#B8860B" />
          </TouchableOpacity>
          <View style={{ flex: 1, marginLeft: 12 }}>
            <Text style={styles.eyebrow}>IMPORTAR DE WOOCOMMERCE</Text>
            <Text style={styles.title} numberOfLines={1}>{channelName ?? 'Canal'}</Text>
          </View>
        </View>

        {/* Search */}
        <View style={styles.searchRow}>
          <Search size={18} color="rgba(255,255,255,0.4)" />
          <TextInput
            style={styles.searchInput}
            value={search}
            onChangeText={setSearch}
            placeholder="Buscar producto…"
            placeholderTextColor="rgba(255,255,255,0.3)"
            autoCorrect={false}
          />
        </View>

        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={styles.scroll}
          keyboardShouldPersistTaps="handled"
        >
          {loading ? (
            <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
          ) : products.length === 0 ? (
            <View style={styles.emptyCard}>
              <Package size={28} color="rgba(255,255,255,0.2)" />
              <Text style={styles.emptyText}>No se encontraron productos en la tienda.</Text>
            </View>
          ) : (
            products.map((p, idx) => {
              const open = expandedId === p.id;
              const rows = open ? rowsForProduct(p) : [];
              const productPairs = rows.reduce((t, r) => t + (qty[r.key] ?? 0), 0);
              const isLoadingVars = loadingVariations.has(p.id);
              return (
                <MotiView
                  key={p.id}
                  from={{ opacity: 0, translateY: 8 }}
                  animate={{ opacity: 1, translateY: 0 }}
                  transition={{ type: 'timing', duration: 260, delay: Math.min(idx, 10) * 30 }}
                >
                  <TouchableOpacity
                    style={[styles.productHeader, open && styles.productHeaderOpen]}
                    onPress={() => toggleProduct(p)}
                    activeOpacity={0.8}
                  >
                    {p.images[0]?.src ? (
                      <Image source={{ uri: p.images[0].src }} style={styles.thumb} />
                    ) : (
                      <View style={styles.thumbPlaceholder}>
                        <Package size={20} color="rgba(255,255,255,0.25)" />
                      </View>
                    )}
                    <View style={{ flex: 1 }}>
                      <Text style={styles.productName} numberOfLines={1}>{p.name}</Text>
                      <Text style={styles.productPrice}>
                        ${p.price} {p.currency_code}
                        {p.variations.length > 0 ? ` · ${p.variations.length} variaciones` : ''}
                      </Text>
                    </View>
                    {productPairs > 0 && (
                      <View style={styles.countBadge}>
                        <Text style={styles.countBadgeText}>{productPairs}</Text>
                      </View>
                    )}
                    {open
                      ? <ChevronDown size={18} color="rgba(255,255,255,0.4)" />
                      : <ChevronRight size={18} color="rgba(255,255,255,0.4)" />}
                  </TouchableOpacity>

                  {open && (
                    <View style={styles.variationsBox}>
                      {isLoadingVars ? (
                        <ActivityIndicator color="#B8860B" style={{ marginVertical: 16 }} />
                      ) : (
                        rows.map((r) => {
                          const n = qty[r.key] ?? 0;
                          return (
                            <View key={r.key} style={styles.varRow}>
                              <View style={{ flex: 1 }}>
                                <Text style={styles.varLabel}>
                                  Talla {r.size}{r.color ? ` · ${r.color}` : ''}
                                </Text>
                                <Text style={styles.varPrice}>${r.price.toFixed(2)}</Text>
                              </View>
                              <View style={styles.stepper}>
                                <TouchableOpacity
                                  style={styles.stepBtn}
                                  onPress={() => setRowQty(r.key, -1)}
                                  activeOpacity={0.7}
                                >
                                  <Minus size={14} color="#B8860B" />
                                </TouchableOpacity>
                                <TextInput
                                  style={styles.qtyInput}
                                  value={n ? String(n) : ''}
                                  onChangeText={(t) => setRowQtyRaw(r.key, t)}
                                  keyboardType="number-pad"
                                  placeholder="0"
                                  placeholderTextColor="rgba(255,255,255,0.2)"
                                  maxLength={3}
                                  textAlign="center"
                                />
                                <TouchableOpacity
                                  style={styles.stepBtn}
                                  onPress={() => setRowQty(r.key, 1)}
                                  activeOpacity={0.7}
                                >
                                  <Plus size={14} color="#B8860B" />
                                </TouchableOpacity>
                              </View>
                            </View>
                          );
                        })
                      )}
                    </View>
                  )}
                </MotiView>
              );
            })
          )}
          <View style={{ height: 120 }} />
        </ScrollView>

        {/* CTA */}
        {totalPairs > 0 && (
          <MotiView
            from={{ opacity: 0, translateY: 20 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 250 }}
            style={styles.ctaWrap}
          >
            <TouchableOpacity
              style={[styles.ctaBtn, saving && styles.ctaBtnOff]}
              onPress={handleImport}
              disabled={saving}
              activeOpacity={0.85}
            >
              {saving ? (
                <ActivityIndicator color="#0D0D0D" />
              ) : (
                <>
                  <Download size={20} color="#0D0D0D" />
                  <Text style={styles.ctaBtnText}>
                    Importar {totalSkus} SKUs · {totalPairs} pares
                  </Text>
                </>
              )}
            </TouchableOpacity>
          </MotiView>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  topBar: {
    flexDirection: 'row', alignItems: 'center',
    paddingHorizontal: 20, paddingVertical: 16,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center', alignItems: 'center',
  },
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 2 },
  title: { fontSize: 18, color: '#fff', fontWeight: '700', marginTop: 2 },
  searchRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#1A1A1A', borderRadius: 14,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    paddingHorizontal: 14, marginHorizontal: 20, marginBottom: 12,
  },
  searchInput: { flex: 1, color: '#fff', fontSize: 15, paddingVertical: 12 },
  scroll: { paddingHorizontal: 20 },
  emptyCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: 32, alignItems: 'center', gap: 12, marginTop: 20,
  },
  emptyText: { color: 'rgba(255,255,255,0.4)', fontSize: 13, textAlign: 'center' },
  productHeader: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: '#1A1A1A', borderRadius: 14,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: 12, marginBottom: 8,
  },
  productHeaderOpen: {
    borderBottomLeftRadius: 0, borderBottomRightRadius: 0,
    borderBottomWidth: 0, marginBottom: 0,
  },
  thumb: { width: 48, height: 48, borderRadius: 10 },
  thumbPlaceholder: {
    width: 48, height: 48, borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
  },
  productName: { fontSize: 15, color: '#fff', fontWeight: '600' },
  productPrice: { fontSize: 12, color: '#B8860B', fontWeight: '600', marginTop: 2 },
  countBadge: {
    backgroundColor: 'rgba(184,134,11,0.2)', borderRadius: 10,
    paddingHorizontal: 9, paddingVertical: 3,
  },
  countBadgeText: { fontSize: 12, color: '#B8860B', fontWeight: '800' },
  variationsBox: {
    backgroundColor: '#151515',
    borderBottomLeftRadius: 14, borderBottomRightRadius: 14,
    borderWidth: 1, borderTopWidth: 0, borderColor: 'rgba(255,255,255,0.08)',
    paddingHorizontal: 14, paddingVertical: 6, marginBottom: 8,
  },
  varRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.06)',
  },
  varLabel: { fontSize: 14, color: '#fff', fontWeight: '500' },
  varPrice: { fontSize: 12, color: 'rgba(255,255,255,0.4)', marginTop: 2 },
  stepper: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  stepBtn: {
    width: 30, height: 30, borderRadius: 9,
    backgroundColor: 'rgba(184,134,11,0.15)',
    justifyContent: 'center', alignItems: 'center',
  },
  qtyInput: {
    minWidth: 42, height: 34,
    backgroundColor: '#0D0D0D', borderRadius: 8,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    color: '#fff', fontSize: 15, fontWeight: '700',
    paddingHorizontal: 6,
  },
  ctaWrap: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    paddingHorizontal: 20, paddingBottom: 28, paddingTop: 12,
    backgroundColor: '#0D0D0D',
  },
  ctaBtn: {
    backgroundColor: '#B8860B', borderRadius: 20, paddingVertical: 18,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 10,
  },
  ctaBtnOff: { opacity: 0.5 },
  ctaBtnText: { fontSize: 16, color: '#0D0D0D', fontWeight: '800' },
});
