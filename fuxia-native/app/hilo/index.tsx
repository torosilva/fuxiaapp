import React, { useState, useEffect, useRef } from 'react';
import {
  View, Text, TextInput, FlatList, TouchableOpacity,
  KeyboardAvoidingView, Platform, StyleSheet,
  ActivityIndicator, StatusBar,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { X, Send } from 'lucide-react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

const API_URL = 'https://hilo.hilolabs.ai';

type MessageRole = 'user' | 'assistant' | 'system';
interface Message {
  role: MessageRole;
  content: string;
}

export default function HiloScreen() {
  const [messages, setMessages] = useState<Message[]>([
    { role: 'assistant', content: '¡Hola! Soy Hilo 💛 ¿En qué puedo ayudarte hoy?' },
  ]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
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

  const send = async () => {
    if (!input.trim() || loading || !userId.current) return;

    const userMsg: Message = { role: 'user', content: input.trim() };
    setMessages(prev => [...prev, userMsg]);
    setInput('');
    setLoading(true);

    try {
      const response = await fetch(`${API_URL}/api/v1/chat/web`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-App-Platform': 'mobile',
        },
        body: JSON.stringify({
          user_id: userId.current,
          message: userMsg.content,
          metadata: {
            source: 'mobile_app',
            os: Platform.OS,
            app_version: '1.0.0',
          },
        }),
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      setMessages(prev => [...prev, { role: 'assistant', content: data.response }]);

      if (data.escalate) {
        setMessages(prev => [
          ...prev,
          { role: 'system', content: 'Te conectaremos con el equipo. Una persona te escribirá por WhatsApp en breve.' },
        ]);
      }
    } catch {
      setMessages(prev => [
        ...prev,
        { role: 'assistant', content: 'Tuve un problema de conexión. Inténtalo de nuevo o escríbenos por WhatsApp.' },
      ]);
    } finally {
      setLoading(false);
      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 100);
    }
  };

  const renderMessage = ({ item }: { item: Message }) => {
    const isUser = item.role === 'user';
    const isSystem = item.role === 'system';

    return (
      <View style={[
        styles.messageRow,
        isUser ? styles.rowUser : isSystem ? styles.rowSystem : styles.rowBot,
      ]}>
        {!isUser && !isSystem && (
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>H</Text>
          </View>
        )}
        <View style={[
          styles.bubble,
          isUser ? styles.bubbleUser : isSystem ? styles.bubbleSystem : styles.bubbleBot,
        ]}>
          <Text style={isUser ? styles.textUser : isSystem ? styles.textSystem : styles.textBot}>
            {item.content}
          </Text>
        </View>
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.closeBtn}>
          <X size={22} color="rgba(255,255,255,0.7)" />
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
        keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 25}
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

        <View style={styles.inputBar}>
          <TextInput
            style={styles.input}
            value={input}
            onChangeText={setInput}
            placeholder="Escribe tu pregunta..."
            placeholderTextColor="rgba(255,255,255,0.2)"
            onSubmitEditing={send}
            editable={!loading}
            multiline
            maxLength={4000}
            returnKeyType="send"
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
    width: 40,
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerCenter: { flex: 1, alignItems: 'center' },
  headerDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#4ade80',
    marginBottom: 4,
  },
  headerTitle: { color: '#FFF', fontSize: 16, fontWeight: '700', letterSpacing: 1 },
  headerSubtitle: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginTop: 2 },

  chatArea: { flex: 1 },
  messagesList: { padding: 16, paddingBottom: 8 },

  messageRow: { marginVertical: 6, flexDirection: 'row', alignItems: 'flex-end' },
  rowUser: { justifyContent: 'flex-end' },
  rowBot: { justifyContent: 'flex-start', gap: 8 },
  rowSystem: { justifyContent: 'center' },

  avatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#CD7F32',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: { color: '#0D0D0D', fontSize: 14, fontWeight: '800' },

  bubble: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 18,
    maxWidth: '78%',
  },
  bubbleUser: {
    backgroundColor: '#CD7F32',
    borderBottomRightRadius: 4,
  },
  bubbleBot: {
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    borderBottomLeftRadius: 4,
  },
  bubbleSystem: {
    backgroundColor: 'rgba(205,127,50,0.1)',
    borderWidth: 1,
    borderColor: 'rgba(205,127,50,0.25)',
    borderRadius: 12,
    maxWidth: '90%',
  },

  textUser: { color: '#0D0D0D', fontSize: 15, lineHeight: 21, fontWeight: '500' },
  textBot: { color: 'rgba(255,255,255,0.9)', fontSize: 15, lineHeight: 21 },
  textSystem: { color: '#CD7F32', fontSize: 13, fontStyle: 'italic', textAlign: 'center', lineHeight: 18 },

  typing: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 10,
    gap: 10,
  },
  typingDots: { flexDirection: 'row', gap: 4 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#CD7F32' },
  typingText: { color: 'rgba(255,255,255,0.4)', fontSize: 13 },

  inputBar: {
    flexDirection: 'row',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.07)',
    backgroundColor: '#0D0D0D',
    alignItems: 'flex-end',
    gap: 10,
  },
  input: {
    flex: 1,
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 22,
    paddingHorizontal: 16,
    paddingVertical: Platform.OS === 'ios' ? 10 : 8,
    fontSize: 15,
    color: '#FFF',
    maxHeight: 100,
  },
  sendBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#CD7F32',
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendBtnDisabled: { backgroundColor: 'rgba(205,127,50,0.3)' },
});
