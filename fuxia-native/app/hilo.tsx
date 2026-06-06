import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View, Text, TextInput, FlatList, TouchableOpacity,
  KeyboardAvoidingView, Platform, StyleSheet,
  ActivityIndicator, StatusBar, Image, ScrollView,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { ArrowLeft, Send, Heart, ChevronRight } from 'lucide-react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { wcService, WCProduct } from '@/services/WooCommerceService';
import { useWishlist } from '@/lib/WishlistContext';
import { useAuth } from '@/lib/hooks/useAuth';

const API_URL = 'https://hilo.hilolabs.ai';
const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

type MessageRole = 'user' | 'assistant' | 'system';
interface Message {
  role: MessageRole;
  content: string;
}

// Extract fuxiaballerinas.com/producto/* slugs from text
function extractSlugs(text: string): string[] {
  const re = /fuxiaballerinas\.com\/producto\/([a-z0-9-]+)\/?/gi;
  const slugs: string[] = [];
  let m;
  while ((m = re.exec(text)) !== null) slugs.push(m[1]);
  return [...new Set(slugs)];
}

// Strip product URLs and clean up blank lines
function cleanText(text: string): string {
  return text
    .replace(/https?:\/\/fuxiaballerinas\.com\/producto\/[a-z0-9-]+\/?\s*/gi, '')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// ── Product mini-card rendered inside chat ────────────────────────────────────
function ProductMiniCard({ product }: { product: WCProduct }) {
  const { has, toggle } = useWishlist();
  const liked = has(product.id);
  const hasImage = !!product.images[0]?.src;

  return (
    <TouchableOpacity
      style={cardStyles.card}
      onPress={() => router.push(`/product/${product.id}` as any)}
      activeOpacity={0.88}
    >
      {hasImage
        ? <Image source={{ uri: product.images[0].src }} style={cardStyles.image} />
        : <View style={[cardStyles.image, cardStyles.imagePlaceholder]} />}

      <View style={cardStyles.info}>
        <Text style={cardStyles.name} numberOfLines={2}>{product.name}</Text>
        <View style={cardStyles.ctaRow}>
          <Text style={cardStyles.cta}>Ver producto</Text>
          <ChevronRight size={12} color="#CD7F32" />
        </View>
      </View>

      <TouchableOpacity
        style={cardStyles.heartBtn}
        onPress={(e) => { e.stopPropagation(); toggle(product.id); }}
        hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
      >
        <Heart
          size={18}
          color={liked ? '#E05C7A' : 'rgba(255,255,255,0.5)'}
          fill={liked ? '#E05C7A' : 'transparent'}
        />
      </TouchableOpacity>
    </TouchableOpacity>
  );
}

const cardStyles = StyleSheet.create({
  card: {
    width: 150,
    backgroundColor: '#242424',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    marginRight: 10,
    overflow: 'hidden',
  },
  image: { width: '100%', height: 120, resizeMode: 'cover' },
  imagePlaceholder: { backgroundColor: '#333' },
  info: { padding: 10, paddingBottom: 10 },
  name: { color: '#fff', fontSize: 12, fontWeight: '600', lineHeight: 16, marginBottom: 6 },
  ctaRow: { flexDirection: 'row', alignItems: 'center', gap: 2 },
  cta: { color: '#CD7F32', fontSize: 11, fontWeight: '700', letterSpacing: 0.3 },
  heartBtn: {
    position: 'absolute', top: 8, right: 8,
    width: 28, height: 28, borderRadius: 14,
    backgroundColor: 'rgba(0,0,0,0.4)',
    justifyContent: 'center', alignItems: 'center',
  },
});

// ─────────────────────────────────────────────────────────────────────────────

export default function HiloScreen() {
  const insets = useSafeAreaInsets();
  const { customer } = useAuth();
  const [messages, setMessages] = useState<Message[]>([
    { role: 'assistant', content: '¡Hola! Soy Hilo 💛 ¿En qué puedo ayudarte hoy?' },
  ]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [msgProducts, setMsgProducts] = useState<Record<number, WCProduct[] | 'loading'>>({});
  const userId = useRef<string | null>(null);
  const flatListRef = useRef<FlatList>(null);

  useEffect(() => {
    (async () => {
      let id = await AsyncStorage.getItem('fuxia_anon_id');
      if (!id) {
        id = `mobile_anon_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
        await AsyncStorage.setItem('fuxia_anon_id', id);
      }
      userId.current = id;
    })();
  }, []);

  const fetchProductsForMsg = useCallback(async (msgIdx: number, text: string) => {
    const slugs = extractSlugs(text);
    if (slugs.length === 0) return;
    setMsgProducts(prev => ({ ...prev, [msgIdx]: 'loading' }));
    const results = await Promise.all(
      slugs.map(slug =>
        wcService.getProducts({ search: slug.replace(/-/g, ' '), per_page: 1 })
          .then(ps => ps[0] ?? null)
      )
    );
    setMsgProducts(prev => ({
      ...prev,
      [msgIdx]: results.filter(Boolean) as WCProduct[],
    }));
  }, []);

  const send = async () => {
    if (!input.trim() || loading) return;

    // userId may not have hydrated from AsyncStorage yet — generate one
    // synchronously so the user can send right after opening the chat.
    if (!userId.current) {
      const fallback = `mobile_anon_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
      userId.current = fallback;
      AsyncStorage.setItem('fuxia_anon_id', fallback).catch(() => {});
    }

    const userMsg: Message = { role: 'user', content: input.trim() };
    setMessages(prev => [...prev, userMsg]);
    setInput('');
    setLoading(true);

    try {
      // Hilo a veces tarda 15-20s (chequea inventario de varios productos en
      // serie). Damos 90s antes de cortar, así una respuesta lenta no se
      // confunde con un fallo de red.
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 90000);
      let response: Response;
      try {
        response = await fetch(`${API_URL}/api/v1/chat/web`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-App-Platform': 'mobile',
          },
          body: JSON.stringify({
            user_id: userId.current,
            message: userMsg.content,
            metadata: { source: 'mobile_app', os: Platform.OS, app_version: '1.0.0' },
          }),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }

      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      const botText: string = data.response;

      setMessages(prev => {
        const next = [...prev, { role: 'assistant' as MessageRole, content: botText }];
        const newIdx = next.length - 1;
        // Fetch products asynchronously for this message index
        fetchProductsForMsg(newIdx, botText);
        return next;
      });

      if (data.escalate) {
        // Fire the real escalation: insert support_tickets row + WhatsApp the team.
        // We capture the conversation context as it is BEFORE adding the system
        // confirmation, so the staff sees what the customer actually said.
        const userText = userMsg.content;
        const userTopic = userText.length > 80 ? userText.slice(0, 80) + '…' : userText;
        const conversationSnapshot = [...messages, userMsg, { role: 'assistant' as const, content: botText }];
        try {
          await fetch(`${SUPABASE_URL}/functions/v1/escalate-to-staff`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            },
            body: JSON.stringify({
              customer_id: customer?.id ?? null,
              customer_phone: customer?.phone ?? null,
              customer_name: customer?.name ?? null,
              last_messages: conversationSnapshot.slice(-6),
              topic: userTopic,
            }),
          });
        } catch (err) {
          // Don't break the user-facing flow if the notification fails — the
          // ticket itself is the source of truth; staff can also poll the panel.
          console.error('[hilo] escalate-to-staff threw:', err);
        }
        setMessages(prev => [
          ...prev,
          { role: 'system', content: 'Te conectaremos con el equipo. Una persona te escribirá por WhatsApp en breve.' },
        ]);
      }
    } catch {
      // Restauramos lo que escribió el cliente para que pueda reenviar con un
      // toque, sin retipear. Hilo falló (lento o caído), no se creó ticket.
      setInput(userMsg.content);
      setMessages(prev => [
        ...prev,
        { role: 'system', content: 'No pudimos enviar tu mensaje (la conexión tardó demasiado). Tu texto quedó listo abajo para reintentar, o escríbenos por WhatsApp.' },
      ]);
    } finally {
      setLoading(false);
      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 100);
    }
  };

  const renderMessage = ({ item, index }: { item: Message; index: number }) => {
    const isUser = item.role === 'user';
    const isSystem = item.role === 'system';

    if (!isUser && !isSystem) {
      const slugs = extractSlugs(item.content);
      const hasProducts = slugs.length > 0;
      const products = msgProducts[index];

      return (
        <View style={[styles.messageRow, styles.rowBot]}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>H</Text>
          </View>
          <View style={{ flex: 1 }}>
            <View style={styles.bubbleBot}>
              <Text style={styles.textBot}>
                {hasProducts ? cleanText(item.content) : item.content}
              </Text>
            </View>
            {hasProducts && (
              <View style={styles.productCardsWrap}>
                {products === 'loading' || products === undefined
                  ? (
                    <View style={styles.cardsLoading}>
                      <ActivityIndicator size="small" color="#CD7F32" />
                      <Text style={styles.cardsLoadingText}>Buscando productos…</Text>
                    </View>
                  )
                  : products.length > 0
                    ? (
                      <ScrollView
                        horizontal
                        showsHorizontalScrollIndicator={false}
                        contentContainerStyle={{ paddingRight: 16 }}
                      >
                        {products.map(p => (
                          <ProductMiniCard key={p.id} product={p} />
                        ))}
                      </ScrollView>
                    )
                    : null}
              </View>
            )}
          </View>
        </View>
      );
    }

    return (
      <View style={[
        styles.messageRow,
        isUser ? styles.rowUser : styles.rowSystem,
      ]}>
        <View style={[
          styles.bubble,
          isUser ? styles.bubbleUser : styles.bubbleSystem,
        ]}>
          <Text style={isUser ? styles.textUser : styles.textSystem}>
            {item.content}
          </Text>
        </View>
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.closeBtn}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>
        <View style={styles.headerCenter}>
          <View style={styles.headerDot} />
          <Text style={styles.headerTitle}>Hilo</Text>
          <Text style={styles.headerSubtitle}>Asistente Fuxia · En línea</Text>
        </View>
        <View style={{ width: 40 }} />
      </View>

      <KeyboardAvoidingView
        style={styles.chatArea}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={0}
      >
        <FlatList
          ref={flatListRef}
          data={messages}
          keyExtractor={(_, i) => String(i)}
          renderItem={renderMessage}
          contentContainerStyle={styles.messagesList}
          onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: true })}
          showsVerticalScrollIndicator={false}
        />

        {loading && (
          <View style={styles.typing}>
            <View style={styles.typingDots}>
              <View style={styles.dot} />
              <View style={[styles.dot, { opacity: 0.6 }]} />
              <View style={[styles.dot, { opacity: 0.3 }]} />
            </View>
            <Text style={styles.typingText}>Hilo está escribiendo</Text>
          </View>
        )}

        <View style={[styles.inputBar, { paddingBottom: Math.max(insets.bottom, 10) }]}>
          <TextInput
            style={styles.input}
            value={input}
            onChangeText={setInput}
            placeholder="Escribe tu pregunta..."
            placeholderTextColor="rgba(255,255,255,0.2)"
            onSubmitEditing={send}
            onKeyPress={(e: any) => {
              if (e?.nativeEvent?.key === 'Enter') send();
            }}
            editable={!loading}
            maxLength={4000}
            returnKeyType="send"
            blurOnSubmit={false}
          />
          <TouchableOpacity
            onPress={send}
            style={[styles.sendBtn, (!input.trim() || loading) && styles.sendBtnDisabled]}
            disabled={!input.trim() || loading}
            activeOpacity={0.8}
          >
            <Send size={18} color="#0D0D0D" />
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(205,127,50,0.15)',
  },
  closeBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
  },
  headerCenter: { flex: 1, alignItems: 'center' },
  headerDot: {
    width: 8, height: 8, borderRadius: 4,
    backgroundColor: '#4ade80', marginBottom: 4,
  },
  headerTitle: { color: '#FFF', fontSize: 16, fontWeight: '700', letterSpacing: 1 },
  headerSubtitle: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },

  chatArea: { flex: 1 },
  messagesList: { padding: 16, paddingBottom: 8 },

  messageRow: { marginVertical: 6, flexDirection: 'row', alignItems: 'flex-end' },
  rowUser: { justifyContent: 'flex-end' },
  rowBot: { justifyContent: 'flex-start', gap: 8, alignItems: 'flex-start' },
  rowSystem: { justifyContent: 'center' },

  avatar: {
    width: 32, height: 32, borderRadius: 16,
    backgroundColor: '#CD7F32',
    justifyContent: 'center', alignItems: 'center',
    marginTop: 4,
  },
  avatarText: { color: '#0D0D0D', fontSize: 14, fontWeight: '800' },

  bubble: {
    paddingHorizontal: 14, paddingVertical: 10,
    borderRadius: 18, maxWidth: '78%',
  },
  bubbleUser: {
    backgroundColor: '#CD7F32',
    borderBottomRightRadius: 4,
  },
  bubbleBot: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    borderRadius: 18, borderBottomLeftRadius: 4,
    paddingHorizontal: 14, paddingVertical: 10,
    maxWidth: '100%',
  },
  bubbleSystem: {
    backgroundColor: 'rgba(205,127,50,0.1)',
    borderWidth: 1, borderColor: 'rgba(205,127,50,0.25)',
    borderRadius: 12, maxWidth: '90%',
  },

  textUser: { color: '#0D0D0D', fontSize: 15, lineHeight: 21, fontWeight: '500' },
  textBot: { color: 'rgba(255,255,255,0.9)', fontSize: 15, lineHeight: 22 },
  textSystem: { color: '#CD7F32', fontSize: 13, fontStyle: 'italic', textAlign: 'center', lineHeight: 18 },

  productCardsWrap: { marginTop: 8, marginLeft: 0 },
  cardsLoading: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    paddingVertical: 10,
  },
  cardsLoadingText: { color: 'rgba(255,255,255,0.3)', fontSize: 12 },

  typing: {
    flexDirection: 'row', alignItems: 'center',
    paddingHorizontal: 20, paddingVertical: 10, gap: 10,
  },
  typingDots: { flexDirection: 'row', gap: 4 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#CD7F32' },
  typingText: { color: 'rgba(255,255,255,0.4)', fontSize: 13 },

  inputBar: {
    flexDirection: 'row',
    paddingHorizontal: 12, paddingTop: 10,
    borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.07)',
    backgroundColor: '#0D0D0D',
    alignItems: 'flex-end', gap: 10,
  },
  input: {
    flex: 1,
    backgroundColor: '#1A1A1A',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 22,
    paddingHorizontal: 16,
    paddingVertical: Platform.OS === 'ios' ? 10 : 8,
    fontSize: 15, color: '#FFF', maxHeight: 100,
  },
  sendBtn: {
    width: 44, height: 44, borderRadius: 22,
    backgroundColor: '#CD7F32',
    justifyContent: 'center', alignItems: 'center',
  },
  sendBtnDisabled: { backgroundColor: 'rgba(205,127,50,0.3)' },
});
