import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, StatusBar, ScrollView, Image,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';

const COUNTRIES = [
  { iso: 'mx', name: 'México',      code: '+52' },
  { iso: 'co', name: 'Colombia',    code: '+57' },
  { iso: 'gt', name: 'Guatemala',   code: '+502' },
  { iso: 'sv', name: 'El Salvador', code: '+503' },
  { iso: 'cr', name: 'Costa Rica',  code: '+506' },
  { iso: 'pa', name: 'Panamá',      code: '+507' },
  { iso: 'hn', name: 'Honduras',    code: '+504' },
];

export default function CountryScreen() {
  const [selected, setSelected] = useState<string | null>(null);

  const handleSelect = (code: string) => {
    setSelected(code);
    setTimeout(() => router.push({ pathname: '/onboarding/phone' as any, params: { countryCode: code } }), 150);
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView contentContainerStyle={styles.scroll}>
        <MotiView
          from={{ opacity: 0, translateY: 20 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 600 }}
        >
          <Text style={styles.eyebrow}>BIENVENIDA</Text>
          <Text style={styles.title}>¿En qué país{'\n'}estás?</Text>
          <Text style={styles.subtitle}>Selecciona tu país para continuar</Text>
        </MotiView>

        <View style={styles.grid}>
          {COUNTRIES.map((c, i) => (
            <MotiView
              key={c.code}
              from={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 100 + i * 60, type: 'spring', damping: 15 }}
            >
              <TouchableOpacity
                style={[styles.countryBtn, selected === c.code && styles.countryBtnSelected]}
                onPress={() => handleSelect(c.code)}
                activeOpacity={0.7}
              >
                <Image
                  source={{ uri: `https://flagcdn.com/w40/${c.iso}.png` }}
                  style={styles.flag}
                />
                <Text style={styles.countryName}>{c.name}</Text>
                <Text style={styles.countryCode}>{c.code}</Text>
              </TouchableOpacity>
            </MotiView>
          ))}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24, paddingBottom: 60 },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 8,
  },
  title: {
    fontSize: 38, color: '#FFF', fontFamily: 'serif',
    fontWeight: '400', lineHeight: 44, marginBottom: 8,
  },
  subtitle: { fontSize: 14, color: 'rgba(255,255,255,0.4)', marginBottom: 36 },
  grid: { gap: 12 },
  countryBtn: {
    padding: 16,
    borderRadius: 16,
    backgroundColor: '#1A1A1A',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  countryBtnSelected: {
    borderColor: '#CD7F32',
    backgroundColor: 'rgba(205,127,50,0.1)',
  },
  flag: { width: 36, height: 24, borderRadius: 3 },
  countryName: { flex: 1, fontSize: 15, color: '#FFF', fontWeight: '600' },
  countryCode: { fontSize: 13, color: 'rgba(255,255,255,0.35)' },
});
