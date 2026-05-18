import React, { useEffect, useState, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  StatusBar,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { Store, ShoppingBag, Delete } from 'lucide-react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { supabase } from '@/lib/supabase';

const LAST_CHANNEL_KEY = '@vendedora_last_channel';
const PIN_LENGTH = 4;

interface Channel {
  id: string;
  name: string;
  type: 'store' | 'bazar';
  location: string | null;
}

export default function VendedoraLoginScreen() {
  const [channels, setChannels] = useState<Channel[]>([]);
  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [loadingChannels, setLoadingChannels] = useState(true);
  const [pin, setPin] = useState('');
  const [validating, setValidating] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from('channels')
        .select('id, name, type, location')
        .eq('active', true)
        .order('name');
      if (data) {
        setChannels(data as Channel[]);
        // Restore last selected channel
        const lastId = await AsyncStorage.getItem(LAST_CHANNEL_KEY);
        if (lastId) {
          const found = (data as Channel[]).find((c) => c.id === lastId);
          if (found) setSelectedChannel(found);
        }
      }
      setLoadingChannels(false);
    })();
  }, []);

  const handleSelectChannel = async (ch: Channel) => {
    setSelectedChannel(ch);
    setPin('');
    setError('');
    await AsyncStorage.setItem(LAST_CHANNEL_KEY, ch.id);
  };

  const handleKeyPress = async (key: string) => {
    if (validating) return;
    if (key === 'back') {
      setPin((p) => p.slice(0, -1));
      setError('');
      return;
    }
    const newPin = pin + key;
    setPin(newPin);
    if (newPin.length === PIN_LENGTH) {
      await validatePin(newPin);
    }
  };

  const validatePin = async (enteredPin: string) => {
    if (!selectedChannel) return;
    setValidating(true);
    setError('');
    try {
      const { data: staffData } = await supabase
        .from('staff')
        .select('id, name, pin, channel_id')
        .eq('pin', enteredPin)
        .eq('channel_id', selectedChannel.id)
        .eq('active', true)
        .maybeSingle();

      if (!staffData) {
        setError('PIN incorrecto. Intenta de nuevo.');
        setPin('');
        setValidating(false);
        return;
      }

      setValidating(false);
      router.push({
        pathname: '/vendedora/home' as any,
        params: {
          staffId: staffData.id,
          staffName: staffData.name,
          channelId: selectedChannel.id,
          channelName: selectedChannel.name,
          channelType: selectedChannel.type,
        },
      });
    } catch {
      setError('Error de conexión. Intenta de nuevo.');
      setPin('');
      setValidating(false);
    }
  };

  const KEYS = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', 'back'],
  ];

  if (loadingChannels) {
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

      {!selectedChannel ? (
        // Step 1: Select channel
        <MotiView
          from={{ opacity: 0, translateY: 16 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 400 }}
          style={styles.step}
        >
          <Text style={styles.eyebrow}>FUXIA BALLERINAS</Text>
          <Text style={styles.title}>Selecciona{'\n'}tu canal</Text>

          {channels.length === 0 ? (
            <View style={styles.emptyCard}>
              <Text style={styles.emptyText}>No hay canales activos configurados.</Text>
            </View>
          ) : (
            channels.map((ch, idx) => (
              <MotiView
                key={ch.id}
                from={{ opacity: 0, translateX: -12 }}
                animate={{ opacity: 1, translateX: 0 }}
                transition={{ type: 'timing', duration: 300, delay: idx * 80 }}
              >
                <TouchableOpacity
                  style={styles.channelCard}
                  onPress={() => handleSelectChannel(ch)}
                  activeOpacity={0.8}
                >
                  <View style={styles.channelIcon}>
                    {ch.type === 'store' ? (
                      <Store size={22} color="#B8860B" />
                    ) : (
                      <ShoppingBag size={22} color="#B8860B" />
                    )}
                  </View>
                  <View style={styles.channelInfo}>
                    <Text style={styles.channelName}>{ch.name}</Text>
                    {ch.location ? (
                      <Text style={styles.channelLocation}>{ch.location}</Text>
                    ) : null}
                  </View>
                  <View style={[styles.typeBadge, ch.type === 'bazar' && styles.typeBadgeBazar]}>
                    <Text style={styles.typeBadgeText}>
                      {ch.type === 'store' ? 'TIENDA' : 'BAZAR'}
                    </Text>
                  </View>
                </TouchableOpacity>
              </MotiView>
            ))
          )}
        </MotiView>
      ) : (
        // Step 2: PIN keypad
        <MotiView
          from={{ opacity: 0, scale: 0.96 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: 'timing', duration: 350 }}
          style={styles.step}
        >
          <TouchableOpacity
            onPress={() => { setSelectedChannel(null); setPin(''); setError(''); }}
            style={styles.channelChip}
          >
            {selectedChannel.type === 'store' ? (
              <Store size={14} color="#B8860B" />
            ) : (
              <ShoppingBag size={14} color="#B8860B" />
            )}
            <Text style={styles.channelChipText}>{selectedChannel.name}</Text>
            <Text style={styles.channelChipChange}>Cambiar</Text>
          </TouchableOpacity>

          <Text style={styles.title}>Ingresa{'\n'}tu PIN</Text>

          {/* PIN dots */}
          <View style={styles.pinRow}>
            {Array.from({ length: PIN_LENGTH }).map((_, i) => (
              <View
                key={i}
                style={[
                  styles.pinDot,
                  i < pin.length && styles.pinDotFilled,
                ]}
              />
            ))}
          </View>

          {validating ? (
            <ActivityIndicator color="#B8860B" style={{ marginBottom: 16 }} />
          ) : error ? (
            <Text style={styles.errorText}>{error}</Text>
          ) : (
            <View style={{ height: 28 }} />
          )}

          {/* Keypad */}
          <View style={styles.keypad}>
            {KEYS.map((row, ri) => (
              <View key={ri} style={styles.keyRow}>
                {row.map((key, ki) => {
                  if (key === '') return <View key={ki} style={styles.keyBtn} />;
                  if (key === 'back') {
                    return (
                      <TouchableOpacity
                        key={ki}
                        style={styles.keyBtn}
                        onPress={() => handleKeyPress('back')}
                        activeOpacity={0.7}
                        disabled={validating}
                      >
                        <Delete size={22} color="rgba(255,255,255,0.6)" />
                      </TouchableOpacity>
                    );
                  }
                  return (
                    <TouchableOpacity
                      key={ki}
                      style={styles.keyBtn}
                      onPress={() => handleKeyPress(key)}
                      activeOpacity={0.7}
                      disabled={validating || pin.length >= PIN_LENGTH}
                    >
                      <Text style={styles.keyText}>{key}</Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            ))}
          </View>
        </MotiView>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
  },
  step: {
    flex: 1,
    padding: 24,
    paddingTop: 20,
  },
  eyebrow: {
    fontSize: 10,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 3,
    marginBottom: 4,
  },
  title: {
    fontSize: 38,
    color: '#fff',
    fontWeight: '700',
    lineHeight: 44,
    marginBottom: 32,
  },
  emptyCard: {
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 24,
    alignItems: 'center',
  },
  emptyText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    textAlign: 'center',
  },
  channelCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1A1A1A',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    padding: 18,
    marginBottom: 12,
    gap: 14,
  },
  channelIcon: {
    width: 44,
    height: 44,
    borderRadius: 12,
    backgroundColor: 'rgba(184,134,11,0.12)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  channelInfo: {
    flex: 1,
  },
  channelName: {
    fontSize: 16,
    color: '#fff',
    fontWeight: '600',
  },
  channelLocation: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.4)',
    marginTop: 2,
  },
  typeBadge: {
    backgroundColor: 'rgba(184,134,11,0.2)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
  },
  typeBadgeBazar: {
    backgroundColor: 'rgba(128,0,128,0.2)',
  },
  typeBadgeText: {
    fontSize: 9,
    color: '#B8860B',
    fontWeight: '800',
    letterSpacing: 1,
  },
  channelChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: 'rgba(184,134,11,0.1)',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    alignSelf: 'flex-start',
    marginBottom: 24,
  },
  channelChipText: {
    fontSize: 13,
    color: '#B8860B',
    fontWeight: '600',
  },
  channelChipChange: {
    fontSize: 11,
    color: 'rgba(184,134,11,0.6)',
    marginLeft: 4,
  },
  pinRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 18,
    marginBottom: 16,
  },
  pinDot: {
    width: 16,
    height: 16,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.25)',
    backgroundColor: 'transparent',
  },
  pinDotFilled: {
    backgroundColor: '#B8860B',
    borderColor: '#B8860B',
  },
  errorText: {
    color: '#FF6B6B',
    fontSize: 13,
    textAlign: 'center',
    marginBottom: 16,
  },
  keypad: {
    marginTop: 8,
    gap: 12,
  },
  keyRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 24,
  },
  keyBtn: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  keyText: {
    fontSize: 26,
    color: '#fff',
    fontWeight: '400',
  },
});
