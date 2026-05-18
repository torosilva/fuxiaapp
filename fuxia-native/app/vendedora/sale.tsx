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
  ScrollView,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { MotiView } from 'moti';
import {
  ArrowLeft,
  ArrowRight,
  Plus,
  Minus,
  ShoppingCart,
  Phone,
  CheckCircle2,
  RefreshCcw,
} from 'lucide-react-native';
import { supabase } from '@/lib/supabase';

interface InventoryItem {
  id: string;
  product_name: string;
  size: string;
  color: string | null;
  price: number;
  stock: number;
  sold: number;
}

interface CartItem extends InventoryItem {
  quantity: number;
}

const SAFE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function generateCode(length = 6): string {
  let code = '';
  for (let i = 0; i < length; i++) {
    code += SAFE_CHARS[Math.floor(Math.random() * SAFE_CHARS.length)];
  }
  return code;
}

type Step = 'products' | 'phone' | 'confirm' | 'success';

export default function VendedoraSaleScreen() {
  const { staffId, staffName, channelId, channelName, channelType } =
    useLocalSearchParams<{
      staffId: string;
      staffName: string;
      channelId: string;
      channelName: string;
      channelType: string;
    }>();

  const [step, setStep] = useState<Step>('products');
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [loadingInventory, setLoadingInventory] = useState(true);
  const [cart, setCart] = useState<Map<string, CartItem>>(new Map());
  const [phone, setPhone] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [saleCode, setSaleCode] = useState('');

  const fetchInventory = useCallback(async () => {
    if (!channelId) return;
    setLoadingInventory(true);
    const { data } = await supabase
      .from('channel_inventory')
      .select('id, product_name, size, color, price, stock, sold')
      .eq('channel_id', channelId)
      .order('product_name');
    if (data) {
      const available = (data as InventoryItem[]).filter(
        (it) => it.stock - it.sold > 0,
      );
      setInventory(available);
    }
    setLoadingInventory(false);
  }, [channelId]);

  useEffect(() => {
    fetchInventory();
  }, [fetchInventory]);

  const addToCart = (item: InventoryItem) => {
    const remaining = item.stock - item.sold;
    setCart((prev) => {
      const next = new Map(prev);
      const existing = next.get(item.id);
      if (existing) {
        if (existing.quantity >= remaining) return prev;
        next.set(item.id, { ...existing, quantity: existing.quantity + 1 });
      } else {
        next.set(item.id, { ...item, quantity: 1 });
      }
      return next;
    });
  };

  const removeFromCart = (itemId: string) => {
    setCart((prev) => {
      const next = new Map(prev);
      const existing = next.get(itemId);
      if (!existing) return prev;
      if (existing.quantity <= 1) {
        next.delete(itemId);
      } else {
        next.set(itemId, { ...existing, quantity: existing.quantity - 1 });
      }
      return next;
    });
  };

  const cartItems = Array.from(cart.values());
  const total = cartItems.reduce((sum, it) => sum + it.price * it.quantity, 0);
  const totalPairs = cartItems.reduce((sum, it) => sum + it.quantity, 0);

  const handleConfirm = async () => {
    if (cartItems.length === 0) {
      Alert.alert('Carrito vacío', 'Agrega al menos un producto.');
      return;
    }

    setSubmitting(true);
    try {
      const code = generateCode(6);
      const items = cartItems.map((it) => ({
        inventory_id: it.id,
        product_name: it.product_name,
        size: it.size,
        color: it.color ?? null,
        quantity: it.quantity,
        unit_price: it.price,
      }));

      const { error: saleErr } = await supabase.from('offline_sales').insert({
        code,
        channel_id: channelId ?? null,
        staff_id: staffId ?? null,
        customer_phone: phone.trim() ? `+52${phone.replace(/\D/g, '')}` : null,
        items,
        total,
        points_earned: totalPairs * 100,
      });
      if (saleErr) throw saleErr;

      // Decrement sold count for each item
      const decrements = cartItems.map((it) =>
        supabase
          .from('channel_inventory')
          .update({ sold: it.sold + it.quantity })
          .eq('id', it.id),
      );
      await Promise.all(decrements);

      setSaleCode(code);
      setStep('success');
    } catch (err: any) {
      Alert.alert('Error', err?.message ?? 'No se pudo registrar la venta.');
    } finally {
      setSubmitting(false);
    }
  };

  const resetSale = () => {
    setCart(new Map());
    setPhone('');
    setSaleCode('');
    setStep('products');
    fetchInventory();
  };

  // ─── Step: Products ────────────────────────────────────────────────────────
  if (step === 'products') {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" />
        <View style={styles.topBar}>
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.7}>
            <ArrowLeft size={20} color="#B8860B" />
          </TouchableOpacity>
          <Text style={styles.stepLabel}>Paso 1 — Productos</Text>
        </View>

        <ScrollView
          style={{ flex: 1 }}
          contentContainerStyle={styles.scroll}
          showsVerticalScrollIndicator={false}
        >
          {loadingInventory ? (
            <ActivityIndicator color="#B8860B" style={{ marginTop: 40 }} />
          ) : inventory.length === 0 ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyText}>Sin productos disponibles con stock.</Text>
            </View>
          ) : (
            inventory.map((item, idx) => {
              const inCart = cart.get(item.id);
              const remaining = item.stock - item.sold;
              return (
                <MotiView
                  key={item.id}
                  from={{ opacity: 0, translateX: -10 }}
                  animate={{ opacity: 1, translateX: 0 }}
                  transition={{ type: 'timing', duration: 280, delay: idx * 40 }}
                >
                  <View style={styles.productCard}>
                    <View style={styles.productInfo}>
                      <Text style={styles.productName}>{item.product_name}</Text>
                      <Text style={styles.productMeta}>
                        Talla {item.size}{item.color ? ` · ${item.color}` : ''}
                      </Text>
                      <Text style={styles.productPrice}>${item.price.toFixed(2)}</Text>
                    </View>
                    <View style={styles.productStock}>
                      <Text style={styles.stockRemaining}>{remaining} disp.</Text>
                    </View>
                    <View style={styles.qtyControl}>
                      {inCart ? (
                        <>
                          <TouchableOpacity
                            style={styles.qtyBtn}
                            onPress={() => removeFromCart(item.id)}
                            activeOpacity={0.7}
                          >
                            <Minus size={14} color="#B8860B" />
                          </TouchableOpacity>
                          <Text style={styles.qtyText}>{inCart.quantity}</Text>
                          <TouchableOpacity
                            style={styles.qtyBtn}
                            onPress={() => addToCart(item)}
                            activeOpacity={0.7}
                            disabled={inCart.quantity >= remaining}
                          >
                            <Plus size={14} color={inCart.quantity >= remaining ? 'rgba(184,134,11,0.3)' : '#B8860B'} />
                          </TouchableOpacity>
                        </>
                      ) : (
                        <TouchableOpacity
                          style={styles.addBtn}
                          onPress={() => addToCart(item)}
                          activeOpacity={0.8}
                        >
                          <Plus size={16} color="#0D0D0D" />
                        </TouchableOpacity>
                      )}
                    </View>
                  </View>
                </MotiView>
              );
            })
          )}
          <View style={{ height: 120 }} />
        </ScrollView>

        {/* Bottom total bar */}
        {cartItems.length > 0 && (
          <MotiView
            from={{ opacity: 0, translateY: 20 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 300 }}
            style={styles.bottomBar}
          >
            <View>
              <Text style={styles.totalLabel}>Total</Text>
              <Text style={styles.totalValue}>${total.toFixed(2)}</Text>
              <Text style={styles.totalSub}>{totalPairs} {totalPairs === 1 ? 'par' : 'pares'}</Text>
            </View>
            <TouchableOpacity
              style={styles.nextBtn}
              onPress={() => setStep('phone')}
              activeOpacity={0.85}
            >
              <Text style={styles.nextBtnText}>Continuar</Text>
              <ArrowRight size={18} color="#0D0D0D" />
            </TouchableOpacity>
          </MotiView>
        )}
      </SafeAreaView>
    );
  }

  // ─── Step: Phone ───────────────────────────────────────────────────────────
  if (step === 'phone') {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" />
        <KeyboardAvoidingView
          style={{ flex: 1 }}
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        >
          <View style={styles.topBar}>
            <TouchableOpacity onPress={() => setStep('products')} style={styles.backBtn} activeOpacity={0.7}>
              <ArrowLeft size={20} color="#B8860B" />
            </TouchableOpacity>
            <Text style={styles.stepLabel}>Paso 2 — Teléfono</Text>
          </View>

          <MotiView
            from={{ opacity: 0, translateY: 16 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 350 }}
            style={styles.phoneStep}
          >
            <Text style={styles.phoneTitle}>¿La clienta tiene{'\n'}la app?</Text>
            <Text style={styles.phoneSub}>
              Ingresa su número para que gane puntos al reclamar.{'\n'}
              <Text style={{ color: 'rgba(255,255,255,0.3)' }}>Puedes omitirlo si no tiene la app.</Text>
            </Text>

            <View style={styles.phoneInputRow}>
              <View style={styles.phonePrefix}>
                <Text style={styles.phonePrefixText}>+52</Text>
              </View>
              <TextInput
                style={styles.phoneInput}
                value={phone}
                onChangeText={(t) => setPhone(t.replace(/\D/g, ''))}
                placeholder="10 dígitos"
                placeholderTextColor="rgba(255,255,255,0.25)"
                keyboardType="phone-pad"
                maxLength={10}
              />
            </View>

            <TouchableOpacity
              style={styles.nextBtnFull}
              onPress={() => setStep('confirm')}
              activeOpacity={0.85}
            >
              <Text style={styles.nextBtnText}>Continuar</Text>
              <ArrowRight size={18} color="#0D0D0D" />
            </TouchableOpacity>

            <TouchableOpacity
              style={styles.skipBtn}
              onPress={() => { setPhone(''); setStep('confirm'); }}
              activeOpacity={0.7}
            >
              <Text style={styles.skipBtnText}>Omitir — sin app</Text>
            </TouchableOpacity>
          </MotiView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    );
  }

  // ─── Step: Confirm ─────────────────────────────────────────────────────────
  if (step === 'confirm') {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" />
        <View style={styles.topBar}>
          <TouchableOpacity onPress={() => setStep('phone')} style={styles.backBtn} activeOpacity={0.7}>
            <ArrowLeft size={20} color="#B8860B" />
          </TouchableOpacity>
          <Text style={styles.stepLabel}>Paso 3 — Confirmar</Text>
        </View>

        <ScrollView
          style={{ flex: 1 }}
          contentContainerStyle={styles.scroll}
          showsVerticalScrollIndicator={false}
        >
          <MotiView
            from={{ opacity: 0, translateY: 16 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 350 }}
          >
            <Text style={styles.confirmTitle}>Resumen de Venta</Text>

            {cartItems.map((item) => (
              <View key={item.id} style={styles.confirmItem}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.confirmItemName}>{item.product_name}</Text>
                  <Text style={styles.confirmItemMeta}>
                    Talla {item.size}{item.color ? ` · ${item.color}` : ''} · x{item.quantity}
                  </Text>
                </View>
                <Text style={styles.confirmItemPrice}>
                  ${(item.price * item.quantity).toFixed(2)}
                </Text>
              </View>
            ))}

            <View style={styles.confirmTotalRow}>
              <Text style={styles.confirmTotalLabel}>TOTAL</Text>
              <Text style={styles.confirmTotalValue}>${total.toFixed(2)} MXN</Text>
            </View>

            {phone ? (
              <View style={styles.phoneChip}>
                <Phone size={14} color="#B8860B" />
                <Text style={styles.phoneChipText}>+52 {phone}</Text>
              </View>
            ) : (
              <View style={styles.phoneChip}>
                <Text style={styles.phoneChipTextMuted}>Sin teléfono registrado</Text>
              </View>
            )}

            <TouchableOpacity
              style={[styles.confirmBtn, submitting && styles.confirmBtnDisabled]}
              onPress={handleConfirm}
              activeOpacity={0.85}
              disabled={submitting}
            >
              {submitting ? (
                <ActivityIndicator color="#0D0D0D" size="small" />
              ) : (
                <>
                  <ShoppingCart size={20} color="#0D0D0D" />
                  <Text style={styles.confirmBtnText}>Confirmar Venta</Text>
                </>
              )}
            </TouchableOpacity>
          </MotiView>
          <View style={{ height: 40 }} />
        </ScrollView>
      </SafeAreaView>
    );
  }

  // ─── Step: Success ─────────────────────────────────────────────────────────
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <MotiView
        from={{ opacity: 0, scale: 0.9 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ type: 'spring', stiffness: 200, damping: 20 }}
        style={styles.successContainer}
      >
        <CheckCircle2 size={56} color="#4CAF50" />
        <Text style={styles.successTitle}>¡Venta registrada!</Text>

        <View style={styles.codeCard}>
          <Text style={styles.codeLabel}>CÓDIGO DE PUNTOS</Text>
          <Text style={styles.codeValue}>{saleCode}</Text>
        </View>

        <Text style={styles.codeInstructions}>
          Díselo a tu clienta para que reclame{'\n'}sus puntos en la app
        </Text>

        <Text style={styles.pointsEarned}>
          +{totalPairs * 100} puntos al reclamar
        </Text>

        <TouchableOpacity
          style={styles.newSaleBtn}
          onPress={resetSale}
          activeOpacity={0.85}
        >
          <RefreshCcw size={18} color="#0D0D0D" />
          <Text style={styles.newSaleBtnText}>Nueva Venta</Text>
        </TouchableOpacity>
      </MotiView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    gap: 12,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  stepLabel: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.5)',
    fontWeight: '600',
  },
  scroll: {
    padding: 20,
    paddingBottom: 40,
  },
  emptyCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 32,
    alignItems: 'center',
    marginTop: 20,
  },
  emptyText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
  },
  productCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 14,
    marginBottom: 10,
    gap: 10,
  },
  productInfo: {
    flex: 1,
  },
  productName: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '600',
  },
  productMeta: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
  },
  productPrice: {
    fontSize: 13,
    color: '#B8860B',
    fontWeight: '700',
    marginTop: 2,
  },
  productStock: {
    alignItems: 'center',
  },
  stockRemaining: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.35)',
  },
  qtyControl: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  qtyBtn: {
    width: 30,
    height: 30,
    borderRadius: 10,
    backgroundColor: 'rgba(184,134,11,0.15)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  qtyText: {
    fontSize: 16,
    color: '#fff',
    fontWeight: '700',
    minWidth: 20,
    textAlign: 'center',
  },
  addBtn: {
    width: 34,
    height: 34,
    borderRadius: 10,
    backgroundColor: '#B8860B',
    justifyContent: 'center',
    alignItems: 'center',
  },
  bottomBar: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: '#1A1A1A',
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.08)',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
    paddingBottom: 28,
  },
  totalLabel: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.4)',
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  totalValue: {
    fontSize: 24,
    color: '#fff',
    fontWeight: '700',
  },
  totalSub: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.4)',
  },
  nextBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: '#B8860B',
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 30,
  },
  nextBtnFull: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    backgroundColor: '#B8860B',
    paddingVertical: 16,
    borderRadius: 30,
    marginTop: 12,
  },
  nextBtnText: {
    fontSize: 15,
    color: '#0D0D0D',
    fontWeight: '800',
  },
  // Phone step
  phoneStep: {
    flex: 1,
    padding: 24,
    paddingTop: 16,
  },
  phoneTitle: {
    fontSize: 32,
    color: '#fff',
    fontWeight: '700',
    lineHeight: 38,
    marginBottom: 12,
  },
  phoneSub: {
    fontSize: 14,
    color: 'rgba(255,255,255,0.5)',
    lineHeight: 22,
    marginBottom: 32,
  },
  phoneInputRow: {
    flexDirection: 'row',
    gap: 0,
    marginBottom: 24,
  },
  phonePrefix: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderRightWidth: 0,
    borderTopLeftRadius: 14,
    borderBottomLeftRadius: 14,
    paddingHorizontal: 14,
    justifyContent: 'center',
  },
  phonePrefixText: {
    fontSize: 15,
    color: '#B8860B',
    fontWeight: '700',
  },
  phoneInput: {
    flex: 1,
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderTopRightRadius: 14,
    borderBottomRightRadius: 14,
    paddingHorizontal: 16,
    paddingVertical: 14,
    fontSize: 18,
    color: '#fff',
    letterSpacing: 2,
  },
  skipBtn: {
    alignItems: 'center',
    paddingVertical: 16,
  },
  skipBtnText: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 14,
    fontWeight: '600',
  },
  // Confirm step
  confirmTitle: {
    fontSize: 26,
    color: '#fff',
    fontWeight: '700',
    marginBottom: 20,
  },
  confirmItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1A1A1A',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 14,
    marginBottom: 8,
  },
  confirmItemName: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '600',
  },
  confirmItemMeta: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
  },
  confirmItemPrice: {
    fontSize: 14,
    color: '#B8860B',
    fontWeight: '700',
  },
  confirmTotalRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.08)',
    paddingTop: 16,
    marginTop: 8,
    marginBottom: 20,
  },
  confirmTotalLabel: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.5)',
    fontWeight: '800',
    letterSpacing: 2,
  },
  confirmTotalValue: {
    fontSize: 22,
    color: '#fff',
    fontWeight: '700',
  },
  phoneChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: 'rgba(184,134,11,0.1)',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 12,
    alignSelf: 'flex-start',
    marginBottom: 24,
  },
  phoneChipText: {
    fontSize: 14,
    color: '#B8860B',
    fontWeight: '600',
  },
  phoneChipTextMuted: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.3)',
  },
  confirmBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    backgroundColor: '#B8860B',
    borderRadius: 30,
    paddingVertical: 16,
  },
  confirmBtnDisabled: {
    opacity: 0.6,
  },
  confirmBtnText: {
    fontSize: 16,
    color: '#0D0D0D',
    fontWeight: '800',
  },
  // Success step
  successContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
  },
  successTitle: {
    fontSize: 28,
    color: '#fff',
    fontWeight: '700',
    marginTop: 16,
    marginBottom: 32,
  },
  codeCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(184,134,11,0.3)',
    paddingVertical: 28,
    paddingHorizontal: 40,
    alignItems: 'center',
    marginBottom: 20,
    width: '100%',
  },
  codeLabel: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 3,
    marginBottom: 12,
  },
  codeValue: {
    fontSize: 52,
    color: '#fff',
    fontWeight: '800',
    letterSpacing: 8,
  },
  codeInstructions: {
    fontSize: 15,
    color: 'rgba(255,255,255,0.5)',
    textAlign: 'center',
    lineHeight: 24,
    marginBottom: 12,
  },
  pointsEarned: {
    fontSize: 16,
    color: '#B8860B',
    fontWeight: '700',
    marginBottom: 40,
  },
  newSaleBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: '#B8860B',
    borderRadius: 30,
    paddingHorizontal: 32,
    paddingVertical: 16,
  },
  newSaleBtnText: {
    fontSize: 15,
    color: '#0D0D0D',
    fontWeight: '800',
  },
});
