/**
 * Bulk-add de inventario: en vez de dar de alta cada (color × talla) como
 * fila separada, se elige el modelo una vez y se marcan las combinaciones
 * disponibles. Sale una tanda de N filas insertadas a channel_inventory.
 *
 * Se usa desde:
 *  - Admin: /admin/channel/[id] → botón "+ Agregar por lote"
 *  - Vendedora: /vendedora/inventory → botón "+ Agregar"
 *
 * RLS: `channel_inventory` tiene política "inventory staff write" que permite
 * INSERT a role='admin' y role='staff' (operational_writes_rls_migration.sql).
 * Requiere que la sesión del dispositivo tenga uno de esos roles.
 */
import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TextInput, TouchableOpacity, ScrollView,
  StatusBar, ActivityIndicator, Alert, KeyboardAvoidingView, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { ArrowLeft, Check } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

const COLOR_PRESETS = [
  'Negro', 'Beige', 'Camel', 'Café', 'Nude',
  'Blanco', 'Rojo', 'Rosa', 'Dorado', 'Plateado',
  'Marino', 'Verde',
];

const SIZE_PRESETS = [
  '21', '21.5', '22', '22.5', '23', '23.5',
  '24', '24.5', '25', '25.5', '26', '26.5',
  '27', '27.5', '28',
];

export default function BulkAddScreen() {
  const { channelId, channelName } = useLocalSearchParams<{
    channelId: string;
    channelName?: string;
  }>();

  const [productName, setProductName] = useState('');
  const [price, setPrice] = useState('');
  const [sku, setSku] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [selectedColors, setSelectedColors] = useState<Set<string>>(new Set());
  const [customColor, setCustomColor] = useState('');
  const [selectedSizes, setSelectedSizes] = useState<Set<string>>(new Set());
  const [stockPerCombo, setStockPerCombo] = useState('1');
  const [saving, setSaving] = useState(false);

  const toggleColor = (c: string) => {
    const next = new Set(selectedColors);
    next.has(c) ? next.delete(c) : next.add(c);
    setSelectedColors(next);
  };
  const toggleSize = (s: string) => {
    const next = new Set(selectedSizes);
    next.has(s) ? next.delete(s) : next.add(s);
    setSelectedSizes(next);
  };
  const addCustomColor = () => {
    const c = customColor.trim();
    if (!c) return;
    const next = new Set(selectedColors);
    next.add(c);
    setSelectedColors(next);
    setCustomColor('');
  };

  const colorsList = Array.from(selectedColors);
  const sizesList = Array.from(selectedSizes);
  const combosCount = Math.max(1, colorsList.length || 1) * sizesList.length;
  const stockNum = parseInt(stockPerCombo || '0', 10);
  const priceNum = parseFloat(price || '0');

  const canSubmit =
    productName.trim().length > 0 &&
    priceNum > 0 &&
    sizesList.length > 0 &&
    stockNum >= 0 &&
    !saving;

  const handleCreate = async () => {
    if (!canSubmit) return;
    if (!channelId) { Alert.alert('Error', 'Falta el canal.'); return; }

    // Si no eligió color, insertamos 1 combinación por talla con color=null.
    const colorsForInsert: (string | null)[] = colorsList.length > 0 ? colorsList : [null];
    const rows = colorsForInsert.flatMap((color) =>
      sizesList.map((size) => ({
        channel_id: channelId,
        product_name: productName.trim(),
        sku: sku.trim() || null,
        color,
        size,
        price: priceNum,
        stock: stockNum,
        sold: 0,
        image_url: imageUrl.trim() || null,
      })),
    );

    setSaving(true);
    const { error } = await supabase.from('channel_inventory').insert(rows);
    setSaving(false);

    if (error) {
      Alert.alert('Error', error.message);
      return;
    }
    Alert.alert(
      '¡Listo!',
      `Se agregaron ${rows.length} combinaciones al inventario${channelName ? ` de ${channelName}` : ''}.`,
      [{ text: 'OK', onPress: () => router.back() }],
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.8}>
            <ArrowLeft size={22} color="#FFF" />
          </TouchableOpacity>

          <Text style={styles.eyebrow}>INVENTARIO{channelName ? ` · ${channelName.toUpperCase()}` : ''}</Text>
          <Text style={styles.title}>Agregar por lote</Text>
          <Text style={styles.subtitle}>
            Un modelo con varios colores y tallas de una vez. El sistema crea todas las combinaciones.
          </Text>

          <View style={styles.field}>
            <Text style={styles.label}>Modelo *</Text>
            <TextInput
              style={styles.input}
              value={productName}
              onChangeText={setProductName}
              placeholder="Ej: Ballerina Mafalda"
              placeholderTextColor="rgba(255,255,255,0.25)"
            />
          </View>

          <View style={styles.row}>
            <View style={[styles.field, { flex: 1, marginRight: 8 }]}>
              <Text style={styles.label}>Precio *</Text>
              <TextInput
                style={styles.input}
                value={price}
                onChangeText={setPrice}
                placeholder="2800"
                placeholderTextColor="rgba(255,255,255,0.25)"
                keyboardType="decimal-pad"
              />
            </View>
            <View style={[styles.field, { flex: 1, marginLeft: 8 }]}>
              <Text style={styles.label}>SKU (opcional)</Text>
              <TextInput
                style={styles.input}
                value={sku}
                onChangeText={setSku}
                placeholder="MAF-001"
                placeholderTextColor="rgba(255,255,255,0.25)"
                autoCapitalize="characters"
              />
            </View>
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>URL de imagen (opcional)</Text>
            <TextInput
              style={styles.input}
              value={imageUrl}
              onChangeText={setImageUrl}
              placeholder="https://..."
              placeholderTextColor="rgba(255,255,255,0.25)"
              autoCapitalize="none"
              keyboardType="url"
            />
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>Colores <Text style={styles.optional}>(opcional)</Text></Text>
            <View style={styles.chipRow}>
              {COLOR_PRESETS.map((c) => {
                const on = selectedColors.has(c);
                return (
                  <TouchableOpacity
                    key={c}
                    style={[styles.chip, on && styles.chipOn]}
                    onPress={() => toggleColor(c)}
                    activeOpacity={0.75}
                  >
                    {on && <Check size={12} color="#0D0D0D" strokeWidth={3} style={{ marginRight: 4 }} />}
                    <Text style={[styles.chipText, on && styles.chipTextOn]}>{c}</Text>
                  </TouchableOpacity>
                );
              })}
            </View>
            {/* Colores fuera del preset (dorado rosé, etc.) */}
            <View style={[styles.row, { marginTop: 10 }]}>
              <TextInput
                style={[styles.input, { flex: 1, marginRight: 8, height: 44 }]}
                value={customColor}
                onChangeText={setCustomColor}
                placeholder="Otro color..."
                placeholderTextColor="rgba(255,255,255,0.25)"
                onSubmitEditing={addCustomColor}
              />
              <TouchableOpacity style={styles.addSmallBtn} onPress={addCustomColor} activeOpacity={0.85}>
                <Text style={styles.addSmallBtnText}>+</Text>
              </TouchableOpacity>
            </View>
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>Tallas *</Text>
            <View style={styles.chipRow}>
              {SIZE_PRESETS.map((s) => {
                const on = selectedSizes.has(s);
                return (
                  <TouchableOpacity
                    key={s}
                    style={[styles.chipSize, on && styles.chipSizeOn]}
                    onPress={() => toggleSize(s)}
                    activeOpacity={0.75}
                  >
                    <Text style={[styles.chipText, on && styles.chipTextOn]}>{s}</Text>
                  </TouchableOpacity>
                );
              })}
            </View>
          </View>

          <View style={styles.field}>
            <Text style={styles.label}>Stock por cada combinación</Text>
            <TextInput
              style={[styles.input, { width: 100 }]}
              value={stockPerCombo}
              onChangeText={(t) => setStockPerCombo(t.replace(/[^0-9]/g, ''))}
              keyboardType="number-pad"
              maxLength={4}
            />
            <Text style={styles.fieldHint}>
              Este número se aplica a cada combinación color × talla. Podés ajustar caso por caso después.
            </Text>
          </View>

          {/* Resumen antes de crear */}
          <View style={styles.summary}>
            <Text style={styles.summaryTitle}>Vas a crear</Text>
            <Text style={styles.summaryNum}>{combosCount}</Text>
            <Text style={styles.summaryLabel}>
              {combosCount === 1 ? 'combinación' : 'combinaciones'}
              {colorsList.length > 0 ? ` (${colorsList.length} colores × ${sizesList.length} tallas)` : ` (${sizesList.length} tallas sin color)`}
            </Text>
            <Text style={styles.summarySub}>Stock total inicial: {combosCount * stockNum} pares</Text>
          </View>

          <TouchableOpacity
            style={[styles.saveBtn, !canSubmit && { opacity: 0.5 }]}
            onPress={handleCreate}
            disabled={!canSubmit}
            activeOpacity={0.85}
          >
            {saving
              ? <ActivityIndicator color="#0D0D0D" />
              : <Text style={styles.saveBtnText}>Crear {combosCount} entradas de inventario</Text>}
          </TouchableOpacity>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 80 },
  backBtn: { width: 40, height: 40, justifyContent: 'center', marginBottom: 8 },
  eyebrow: { fontSize: 10, color: '#B8860B', fontWeight: '800', letterSpacing: 2, marginBottom: 6 },
  title: { fontSize: 28, color: '#FFF', fontFamily: 'serif', marginBottom: 6 },
  subtitle: { fontSize: 13, color: 'rgba(255,255,255,0.5)', marginBottom: 24, lineHeight: 18 },
  field: { marginBottom: 20 },
  row: { flexDirection: 'row' },
  label: {
    fontSize: 11, color: 'rgba(255,255,255,0.6)', fontWeight: '700',
    letterSpacing: 1, textTransform: 'uppercase', marginBottom: 8,
  },
  optional: { fontWeight: '400', textTransform: 'none', letterSpacing: 0, color: 'rgba(255,255,255,0.35)' },
  input: {
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12, paddingHorizontal: 14, height: 50, fontSize: 15, color: '#FFF',
  },
  fieldHint: { color: 'rgba(255,255,255,0.35)', fontSize: 11, marginTop: 6, lineHeight: 15 },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    flexDirection: 'row', alignItems: 'center',
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: 20,
    backgroundColor: '#1A1A1A', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
  },
  chipOn: { backgroundColor: '#B8860B', borderColor: '#B8860B' },
  chipText: { color: 'rgba(255,255,255,0.75)', fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: '#0D0D0D', fontWeight: '800' },
  chipSize: {
    minWidth: 44, alignItems: 'center', paddingHorizontal: 8, paddingVertical: 10,
    borderRadius: 8, backgroundColor: '#1A1A1A',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
  },
  chipSizeOn: { backgroundColor: '#B8860B', borderColor: '#B8860B' },
  addSmallBtn: {
    width: 44, height: 44, borderRadius: 12, backgroundColor: '#B8860B',
    justifyContent: 'center', alignItems: 'center',
  },
  addSmallBtnText: { color: '#0D0D0D', fontSize: 22, fontWeight: '800', lineHeight: 22 },
  summary: {
    backgroundColor: '#141414', borderRadius: 16, borderWidth: 1,
    borderColor: 'rgba(184,134,11,0.35)', padding: 18, marginTop: 8, marginBottom: 20,
    alignItems: 'center',
  },
  summaryTitle: { fontSize: 11, color: '#B8860B', fontWeight: '800', letterSpacing: 2, marginBottom: 4 },
  summaryNum: { fontSize: 44, color: '#FFF', fontWeight: '800', lineHeight: 50 },
  summaryLabel: { color: 'rgba(255,255,255,0.6)', fontSize: 12, marginTop: 2 },
  summarySub: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 8 },
  saveBtn: {
    backgroundColor: '#B8860B', borderRadius: 30, paddingVertical: 16,
    alignItems: 'center', marginTop: 8,
  },
  saveBtnText: { color: '#0D0D0D', fontSize: 15, fontWeight: '800', letterSpacing: 0.5 },
});
