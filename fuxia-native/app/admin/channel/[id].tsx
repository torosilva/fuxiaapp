import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  StatusBar,
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  Modal,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Plus, Package, X } from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface Channel {
  id: string;
  name: string;
  type: 'store' | 'bazar';
  location: string | null;
  active: boolean;
}

interface InventoryItem {
  id: string;
  product_name: string;
  sku: string | null;
  size: string;
  color: string | null;
  price: number;
  stock: number;
  sold: number;
}

export default function ChannelDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [channel, setChannel] = useState<Channel | null>(null);
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalVisible, setModalVisible] = useState(false);

  // Modal form state
  const [productName, setProductName] = useState('');
  const [size, setSize] = useState('');
  const [color, setColor] = useState('');
  const [price, setPrice] = useState('');
  const [stock, setStock] = useState('');
  const [saving, setSaving] = useState(false);

  const fetchData = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    const [chRes, invRes] = await Promise.all([
      supabase
        .from('channels')
        .select('id, name, type, location, active')
        .eq('id', id)
        .single(),
      supabase
        .from('channel_inventory')
        .select('id, product_name, sku, size, color, price, stock, sold')
        .eq('channel_id', id)
        .order('product_name'),
    ]);
    if (chRes.data) setChannel(chRes.data as Channel);
    if (invRes.data) setInventory(invRes.data as InventoryItem[]);
    setLoading(false);
  }, [id]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const resetForm = () => {
    setProductName('');
    setSize('');
    setColor('');
    setPrice('');
    setStock('');
  };

  const handleAddItem = async () => {
    if (!productName.trim()) {
      Alert.alert('Campo requerido', 'El nombre del producto es obligatorio.');
      return;
    }
    if (!size.trim()) {
      Alert.alert('Campo requerido', 'La talla es obligatoria.');
      return;
    }
    const priceNum = parseFloat(price);
    const stockNum = parseInt(stock, 10);
    if (isNaN(priceNum) || priceNum <= 0) {
      Alert.alert('Precio inválido', 'Ingresa un precio válido.');
      return;
    }
    if (isNaN(stockNum) || stockNum < 0) {
      Alert.alert('Stock inválido', 'Ingresa un stock válido.');
      return;
    }

    setSaving(true);
    try {
      const { error } = await supabase.from('channel_inventory').insert({
        channel_id: id,
        product_name: productName.trim(),
        size: size.trim(),
        color: color.trim() || null,
        price: priceNum,
        stock: stockNum,
        sold: 0,
      });
      if (error) throw error;
      resetForm();
      setModalVisible(false);
      await fetchData();
    } catch (err: any) {
      Alert.alert('Error', err?.message ?? 'No se pudo guardar el producto.');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" />
        <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
          <ActivityIndicator color="#B8860B" />
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scroll}>
        <MotiView
          from={{ opacity: 0, translateY: 16 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 400 }}
        >
          <TouchableOpacity
            style={styles.backBtn}
            onPress={() => router.back()}
            activeOpacity={0.7}
          >
            <ArrowLeft size={20} color="#B8860B" />
          </TouchableOpacity>

          <Text style={styles.eyebrow}>CANAL</Text>
          <Text style={styles.title}>{channel?.name ?? '...'}</Text>

          <View style={styles.channelMeta}>
            <View style={[styles.typeBadge, channel?.type === 'bazar' && styles.typeBadgeBazar]}>
              <Text style={styles.typeBadgeText}>
                {channel?.type === 'store' ? 'TIENDA' : 'BAZAR'}
              </Text>
            </View>
            {channel?.location ? (
              <Text style={styles.locationText}>{channel.location}</Text>
            ) : null}
            <View style={[styles.statusDot, channel?.active ? styles.dotActive : styles.dotInactive]} />
          </View>

          {/* Inventory section */}
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Inventario</Text>
            <TouchableOpacity
              style={styles.addBtn}
              onPress={() => setModalVisible(true)}
              activeOpacity={0.8}
            >
              <Plus size={16} color="#0D0D0D" />
            </TouchableOpacity>
          </View>

          {inventory.length === 0 ? (
            <View style={styles.emptyCard}>
              <Package size={28} color="rgba(255,255,255,0.2)" />
              <Text style={styles.emptyText}>Sin inventario. Agrega productos con el botón +</Text>
            </View>
          ) : (
            inventory.map((item, idx) => {
              const remaining = item.stock - item.sold;
              return (
                <MotiView
                  key={item.id}
                  from={{ opacity: 0, translateX: -12 }}
                  animate={{ opacity: 1, translateX: 0 }}
                  transition={{ type: 'timing', duration: 300, delay: idx * 50 }}
                >
                  <View style={styles.inventoryCard}>
                    <View style={styles.inventoryBody}>
                      <Text style={styles.inventoryName}>{item.product_name}</Text>
                      <Text style={styles.inventoryMeta}>
                        Talla {item.size}{item.color ? ` · ${item.color}` : ''}
                      </Text>
                      <Text style={styles.inventoryPrice}>
                        ${item.price.toFixed(2)} MXN
                      </Text>
                    </View>
                    <View style={styles.inventoryRight}>
                      <View
                        style={[
                          styles.stockBadge,
                          remaining > 3
                            ? styles.stockGreen
                            : remaining > 0
                            ? styles.stockYellow
                            : styles.stockRed,
                        ]}
                      >
                        <Text style={styles.stockText}>{remaining}</Text>
                      </View>
                      <Text style={styles.stockLabel}>restantes</Text>
                    </View>
                  </View>
                </MotiView>
              );
            })
          )}

          <View style={{ height: 60 }} />
        </MotiView>
      </ScrollView>

      {/* Add Inventory Modal */}
      <Modal
        visible={modalVisible}
        transparent
        animationType="slide"
        onRequestClose={() => { setModalVisible(false); resetForm(); }}
      >
        <View style={styles.modalOverlay}>
          <KeyboardAvoidingView
            behavior={Platform.OS === 'ios' ? 'padding' : undefined}
            style={styles.modalSheet}
          >
            <View style={styles.modalHandle} />
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Agregar Producto</Text>
              <TouchableOpacity
                onPress={() => { setModalVisible(false); resetForm(); }}
                style={styles.modalClose}
              >
                <X size={20} color="rgba(255,255,255,0.5)" />
              </TouchableOpacity>
            </View>

            <ScrollView
              showsVerticalScrollIndicator={false}
              keyboardShouldPersistTaps="handled"
            >
              <View style={styles.field}>
                <Text style={styles.label}>Nombre del producto</Text>
                <TextInput
                  style={styles.input}
                  value={productName}
                  onChangeText={setProductName}
                  placeholder="Ej. Ballarina Clásica Negra"
                  placeholderTextColor="rgba(255,255,255,0.25)"
                  autoCapitalize="words"
                />
              </View>

              <View style={styles.field}>
                <Text style={styles.label}>Talla</Text>
                <TextInput
                  style={styles.input}
                  value={size}
                  onChangeText={setSize}
                  placeholder="Ej. 25"
                  placeholderTextColor="rgba(255,255,255,0.25)"
                  keyboardType="default"
                />
              </View>

              <View style={styles.field}>
                <Text style={styles.label}>Color <Text style={styles.optional}>(opcional)</Text></Text>
                <TextInput
                  style={styles.input}
                  value={color}
                  onChangeText={setColor}
                  placeholder="Ej. Negro"
                  placeholderTextColor="rgba(255,255,255,0.25)"
                  autoCapitalize="words"
                />
              </View>

              <View style={styles.fieldRow}>
                <View style={[styles.field, { flex: 1 }]}>
                  <Text style={styles.label}>Precio (MXN)</Text>
                  <TextInput
                    style={styles.input}
                    value={price}
                    onChangeText={setPrice}
                    placeholder="0.00"
                    placeholderTextColor="rgba(255,255,255,0.25)"
                    keyboardType="decimal-pad"
                  />
                </View>
                <View style={[styles.field, { flex: 1 }]}>
                  <Text style={styles.label}>Stock</Text>
                  <TextInput
                    style={styles.input}
                    value={stock}
                    onChangeText={setStock}
                    placeholder="0"
                    placeholderTextColor="rgba(255,255,255,0.25)"
                    keyboardType="number-pad"
                  />
                </View>
              </View>

              <TouchableOpacity
                style={[styles.saveBtn, saving && styles.saveBtnDisabled]}
                onPress={handleAddItem}
                disabled={saving}
                activeOpacity={0.85}
              >
                {saving ? (
                  <ActivityIndicator color="#0D0D0D" size="small" />
                ) : (
                  <Text style={styles.saveBtnText}>Guardar Producto</Text>
                )}
              </TouchableOpacity>

              <View style={{ height: 20 }} />
            </ScrollView>
          </KeyboardAvoidingView>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
  },
  scroll: {
    padding: 24,
    paddingBottom: 60,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  eyebrow: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 3,
    marginBottom: 4,
  },
  title: {
    fontSize: 32,
    color: '#fff',
    fontWeight: '700',
    marginBottom: 12,
  },
  channelMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginBottom: 32,
  },
  typeBadge: {
    backgroundColor: 'rgba(184,134,11,0.2)',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 6,
  },
  typeBadgeBazar: {
    backgroundColor: 'rgba(128,0,128,0.2)',
  },
  typeBadgeText: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 1,
  },
  locationText: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.4)',
    flex: 1,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  dotActive: { backgroundColor: '#4CAF50' },
  dotInactive: { backgroundColor: 'rgba(255,255,255,0.2)' },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 14,
  },
  sectionTitle: {
    fontSize: 18,
    color: '#fff',
    fontWeight: '600',
  },
  addBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#B8860B',
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 32,
    alignItems: 'center',
    gap: 12,
  },
  emptyText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
  },
  inventoryCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 16,
    marginBottom: 10,
    gap: 12,
  },
  inventoryBody: {
    flex: 1,
  },
  inventoryName: {
    fontSize: 15,
    color: '#fff',
    fontWeight: '600',
  },
  inventoryMeta: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
  },
  inventoryPrice: {
    fontSize: 13,
    color: '#B8860B',
    fontWeight: '700',
    marginTop: 4,
  },
  inventoryRight: {
    alignItems: 'center',
    gap: 4,
  },
  stockBadge: {
    width: 40,
    height: 40,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  stockGreen: { backgroundColor: 'rgba(76,175,80,0.2)' },
  stockYellow: { backgroundColor: 'rgba(255,193,7,0.2)' },
  stockRed: { backgroundColor: 'rgba(255,107,107,0.2)' },
  stockText: {
    fontSize: 16,
    fontWeight: '700',
    color: '#fff',
  },
  stockLabel: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.4)',
  },
  // Modal
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.7)',
    justifyContent: 'flex-end',
  },
  modalSheet: {
    backgroundColor: '#1A1A1A',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    padding: 24,
    maxHeight: '90%',
  },
  modalHandle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignSelf: 'center',
    marginBottom: 20,
  },
  modalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 24,
  },
  modalTitle: {
    fontSize: 20,
    color: '#fff',
    fontWeight: '700',
  },
  modalClose: {
    width: 36,
    height: 36,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.08)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  field: {
    marginBottom: 16,
  },
  fieldRow: {
    flexDirection: 'row',
    gap: 12,
  },
  label: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.5)',
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  optional: {
    fontWeight: '400',
    textTransform: 'none',
    letterSpacing: 0,
  },
  input: {
    backgroundColor: '#0D0D0D',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 14,
    paddingHorizontal: 16,
    paddingVertical: 14,
    fontSize: 15,
    color: '#fff',
  },
  saveBtn: {
    backgroundColor: '#B8860B',
    borderRadius: 30,
    paddingVertical: 16,
    alignItems: 'center',
    marginTop: 8,
  },
  saveBtnDisabled: {
    opacity: 0.6,
  },
  saveBtnText: {
    color: '#0D0D0D',
    fontSize: 15,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
});
