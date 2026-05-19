import React, { useState, useCallback } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  TextInput, StatusBar, ActivityIndicator, Alert, KeyboardAvoidingView, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, ChevronDown, ChevronRight, Package } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';
import wcService from '@/services/WooCommerceService';

const TEMPLATE = [
  {
    model: 'Paula',
    colors: ['Taupe', 'Dorado', 'Plata', 'Verde', 'Vino', 'Cafe', 'Nude', 'Negro', 'Gamusa Cafe', 'Gamusa Vino'],
  },
  {
    model: 'Cucarron',
    colors: ['Taupe', 'Dorado', 'Plata', 'Verde', 'Vino', 'Cafe', 'Nude', 'Negro'],
  },
  {
    model: 'Ballerinas Taches',
    colors: ['Negro', 'Taupe', 'Nude', 'Vino', 'Verde', 'Gamusa Cafe', 'Gamusa Vino'],
  },
  {
    model: 'Cucarron Sueco',
    colors: ['Taupe', 'Dorado', 'Plata', 'Verde', 'Vino', 'Cafe', 'Nude', 'Negro'],
  },
] as const;

const SIZES = ['35', '36', '37', '38', '39', '40'];

function buildInitialQtys() {
  const out: Record<string, Record<string, Record<string, string>>> = {};
  for (const m of TEMPLATE) {
    out[m.model] = {};
    for (const c of m.colors) {
      out[m.model][c] = Object.fromEntries(SIZES.map(s => [s, '']));
    }
  }
  return out;
}

export default function BazarTemplateScreen() {
  const { channelId, channelName } = useLocalSearchParams<{ channelId: string; channelName: string }>();

  const [prices, setPrices] = useState<Record<string, string>>(
    Object.fromEntries(TEMPLATE.map(m => [m.model, '2800']))
  );
  const [quantities, setQuantities] = useState(buildInitialQtys);
  const [expanded, setExpanded] = useState<Set<string>>(new Set([TEMPLATE[0].model]));
  const [saving, setSaving] = useState(false);

  const toggleModel = (model: string) =>
    setExpanded(prev => {
      const next = new Set(prev);
      next.has(model) ? next.delete(model) : next.add(model);
      return next;
    });

  const setQty = useCallback((model: string, color: string, size: string, raw: string) => {
    const v = raw.replace(/\D/g, '').slice(0, 2);
    setQuantities(prev => ({
      ...prev,
      [model]: { ...prev[model], [color]: { ...prev[model][color], [size]: v } },
    }));
  }, []);

  const totalPairs = Object.values(quantities).reduce(
    (t, byColor) => t + Object.values(byColor).reduce(
      (t2, bySize) => t2 + Object.values(bySize).reduce((t3, v) => t3 + (parseInt(v) || 0), 0), 0), 0);

  function modelTotal(model: string) {
    return Object.values(quantities[model]).reduce(
      (t, bySize) => t + Object.values(bySize).reduce((t2, v) => t2 + (parseInt(v) || 0), 0), 0);
  }

  const handleLoad = async () => {
    for (const m of TEMPLATE) {
      const p = parseFloat(prices[m.model]);
      if (!prices[m.model] || isNaN(p) || p <= 0) {
        Alert.alert('Precio requerido', `Ingresa el precio de ${m.model}.`);
        return;
      }
    }
    if (totalPairs === 0) {
      Alert.alert('Sin productos', 'Agrega al menos un par antes de continuar.');
      return;
    }

    const rows: Record<string, unknown>[] = [];
    for (const m of TEMPLATE) {
      const price = parseFloat(prices[m.model]);
      for (const color of m.colors) {
        for (const size of SIZES) {
          const qty = parseInt(quantities[m.model][color][size] || '0', 10);
          if (qty > 0) {
            rows.push({
              channel_id: channelId,
              product_name: m.model,
              sku: `${m.model.replace(/\s+/g, '-').toUpperCase()}-${color.replace(/\s+/g, '-').toUpperCase()}-T${size}`,
              size,
              color,
              price,
              stock: qty,
              sold: 0,
            });
          }
        }
      }
    }

    setSaving(true);

    // Fetch one WC image per model (4 lookups, run in parallel)
    const imageResults = await Promise.all(
      TEMPLATE.map(m => wcService.getProducts({ search: m.model, per_page: 1 }))
    );
    const modelImages: Record<string, string | null> = Object.fromEntries(
      TEMPLATE.map((m, i) => [m.model, imageResults[i]?.[0]?.images[0]?.src ?? null])
    );
    for (const row of rows) {
      row.image_url = modelImages[row.product_name as string] ?? null;
    }

    const { error } = await supabase.from('channel_inventory').insert(rows);
    setSaving(false);

    if (error) {
      Alert.alert('Error', error.message);
      return;
    }

    Alert.alert(
      '¡Inventario cargado!',
      `${rows.length} SKUs (${totalPairs} pares) listos en ${channelName}.`,
      [{ text: 'Ver inventario', onPress: () => router.back() }],
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>

        <View style={styles.topBar}>
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.7}>
            <ArrowLeft size={20} color="#B8860B" />
          </TouchableOpacity>
          <View style={{ flex: 1, marginLeft: 12 }}>
            <Text style={styles.eyebrow}>PLANTILLA BAZAR</Text>
            <Text style={styles.title} numberOfLines={1}>{channelName}</Text>
          </View>
          {totalPairs > 0 && (
            <View style={styles.pairsBadge}>
              <Text style={styles.pairsBadgeText}>{totalPairs} pares</Text>
            </View>
          )}
        </View>

        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={styles.scroll}
          keyboardShouldPersistTaps="handled"
        >
          {/* ── Precios ── */}
          <Text style={styles.sectionLabel}>PRECIO POR MODELO (MXN)</Text>
          <View style={styles.pricesGrid}>
            {TEMPLATE.map(m => (
              <View key={m.model} style={styles.priceCard}>
                <Text style={styles.priceModelName} numberOfLines={2}>{m.model}</Text>
                <View style={styles.priceRow}>
                  <Text style={styles.priceCurrency}>$</Text>
                  <TextInput
                    style={styles.priceInput}
                    value={prices[m.model]}
                    onChangeText={v => setPrices(p => ({ ...p, [m.model]: v.replace(/\D/g, '') }))}
                    keyboardType="number-pad"
                    placeholder="0"
                    placeholderTextColor="rgba(255,255,255,0.2)"
                    selectTextOnFocus
                  />
                </View>
              </View>
            ))}
          </View>

          {/* ── Cantidades ── */}
          <Text style={[styles.sectionLabel, { marginTop: 28 }]}>CANTIDADES POR TALLA</Text>

          {TEMPLATE.map((m, mi) => {
            const open = expanded.has(m.model);
            const mTotal = modelTotal(m.model);
            return (
              <MotiView
                key={m.model}
                from={{ opacity: 0, translateY: 8 }}
                animate={{ opacity: 1, translateY: 0 }}
                transition={{ type: 'timing', duration: 280, delay: mi * 50 }}
              >
                <TouchableOpacity
                  style={[styles.modelHeader, open && styles.modelHeaderOpen]}
                  onPress={() => toggleModel(m.model)}
                  activeOpacity={0.8}
                >
                  <Text style={styles.modelName}>{m.model}</Text>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                    {mTotal > 0 && (
                      <View style={styles.modelBadge}>
                        <Text style={styles.modelBadgeText}>{mTotal}</Text>
                      </View>
                    )}
                    {open
                      ? <ChevronDown size={18} color="rgba(255,255,255,0.4)" />
                      : <ChevronRight size={18} color="rgba(255,255,255,0.4)" />}
                  </View>
                </TouchableOpacity>

                {open && (
                  <View style={styles.modelBody}>
                    <ScrollView horizontal showsHorizontalScrollIndicator={false} keyboardShouldPersistTaps="handled">
                      <View>
                        {/* Size header */}
                        <View style={styles.gridRow}>
                          <View style={styles.colorCell} />
                          {SIZES.map(s => (
                            <View key={s} style={styles.sizeHeaderCell}>
                              <Text style={styles.sizeHeaderText}>{s}</Text>
                            </View>
                          ))}
                        </View>
                        {/* Color rows */}
                        {m.colors.map(color => (
                          <View key={color} style={styles.gridRow}>
                            <View style={styles.colorCell}>
                              <Text style={styles.colorName} numberOfLines={1}>{color}</Text>
                            </View>
                            {SIZES.map(size => (
                              <TextInput
                                key={size}
                                style={styles.qtyInput}
                                value={quantities[m.model][color][size]}
                                onChangeText={v => setQty(m.model, color, size, v)}
                                keyboardType="number-pad"
                                placeholder="–"
                                placeholderTextColor="rgba(255,255,255,0.12)"
                                maxLength={2}
                                selectTextOnFocus
                                textAlign="center"
                              />
                            ))}
                          </View>
                        ))}
                      </View>
                    </ScrollView>
                  </View>
                )}
              </MotiView>
            );
          })}

          <View style={{ height: 100 }} />
        </ScrollView>

        {/* ── CTA ── */}
        <View style={styles.ctaWrap}>
          <TouchableOpacity
            style={[styles.ctaBtn, (saving || totalPairs === 0) && styles.ctaBtnOff]}
            onPress={handleLoad}
            disabled={saving || totalPairs === 0}
            activeOpacity={0.85}
          >
            {saving
              ? <ActivityIndicator color="#0D0D0D" />
              : (
                <>
                  <Package size={20} color="#0D0D0D" />
                  <Text style={styles.ctaBtnText}>
                    Cargar inventario{totalPairs > 0 ? ` · ${totalPairs} pares` : ''}
                  </Text>
                </>
              )}
          </TouchableOpacity>
        </View>

      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const CELL_W = 44;
const COLOR_W = 104;

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
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 3 },
  title: { fontSize: 18, color: '#fff', fontWeight: '700', marginTop: 2 },
  pairsBadge: {
    backgroundColor: 'rgba(184,134,11,0.2)', borderRadius: 12,
    paddingHorizontal: 12, paddingVertical: 6,
  },
  pairsBadgeText: { fontSize: 13, color: '#B8860B', fontWeight: '800' },
  scroll: { paddingHorizontal: 20 },
  sectionLabel: {
    fontSize: 10, color: 'rgba(255,255,255,0.35)',
    fontWeight: '800', letterSpacing: 2, marginBottom: 12,
  },
  // Prices
  pricesGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  priceCard: {
    flex: 1, minWidth: '45%',
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)', padding: 16,
  },
  priceModelName: { fontSize: 11, color: 'rgba(255,255,255,0.45)', fontWeight: '600', marginBottom: 8 },
  priceRow: { flexDirection: 'row', alignItems: 'center' },
  priceCurrency: { fontSize: 18, color: 'rgba(255,255,255,0.35)', marginRight: 4 },
  priceInput: { fontSize: 22, color: '#fff', fontWeight: '700', flex: 1 },
  // Models
  modelHeader: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: '#1A1A1A', borderRadius: 14,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    padding: 16, marginBottom: 4,
  },
  modelHeaderOpen: {
    borderBottomLeftRadius: 0, borderBottomRightRadius: 0,
    borderBottomWidth: 0, marginBottom: 0,
  },
  modelName: { fontSize: 16, color: '#fff', fontWeight: '700' },
  modelBadge: {
    backgroundColor: 'rgba(184,134,11,0.2)', borderRadius: 10,
    paddingHorizontal: 8, paddingVertical: 3,
  },
  modelBadgeText: { fontSize: 12, color: '#B8860B', fontWeight: '800' },
  modelBody: {
    backgroundColor: '#1A1A1A', borderTopLeftRadius: 0, borderTopRightRadius: 0,
    borderBottomLeftRadius: 14, borderBottomRightRadius: 14,
    borderWidth: 1, borderTopWidth: 0, borderColor: 'rgba(255,255,255,0.08)',
    paddingHorizontal: 12, paddingVertical: 10, marginBottom: 10,
  },
  gridRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 5 },
  colorCell: { width: COLOR_W, justifyContent: 'center', paddingRight: 8 },
  colorName: { fontSize: 12, color: 'rgba(255,255,255,0.55)', fontWeight: '500' },
  sizeHeaderCell: { width: CELL_W, alignItems: 'center' },
  sizeHeaderText: { fontSize: 11, color: 'rgba(255,255,255,0.28)', fontWeight: '700' },
  qtyInput: {
    width: CELL_W - 6, height: 36, marginHorizontal: 3,
    backgroundColor: '#0D0D0D', borderRadius: 8,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    fontSize: 14, color: '#fff', fontWeight: '700',
  },
  // CTA
  ctaWrap: { paddingHorizontal: 20, paddingBottom: 28, paddingTop: 12 },
  ctaBtn: {
    backgroundColor: '#B8860B', borderRadius: 20, paddingVertical: 18,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 10,
  },
  ctaBtnOff: { opacity: 0.35 },
  ctaBtnText: { fontSize: 16, color: '#0D0D0D', fontWeight: '800' },
});
