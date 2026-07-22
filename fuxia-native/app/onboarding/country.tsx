import React, { useState } from 'react';
import {
  Text, StyleSheet, TouchableOpacity, StatusBar,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { CountryPicker } from 'react-native-country-codes-picker';

export default function CountryScreen() {
  const [showPicker, setShowPicker] = useState(false);
  const [selected, setSelected] = useState<{ flag: string; code: string; name: string } | null>(null);

  const handleSelect = (item: any) => {
    const country = {
      flag: item.flag,
      code: item.dial_code,
      name: (item.name && (item.name.es || item.name.en)) || item.code,
    };
    setSelected(country);
    setShowPicker(false);
    setTimeout(
      () => router.push({ pathname: '/onboarding/phone' as any, params: { countryCode: country.code } }),
      150
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <MotiView
        from={{ opacity: 0, translateY: 20 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 600 }}
        style={styles.content}
      >
        <Text style={styles.eyebrow}>BIENVENIDA</Text>
        <Text style={styles.title}>¿En qué país{'\n'}estás?</Text>
        <Text style={styles.subtitle}>Selecciona tu país para continuar</Text>

        <TouchableOpacity
          style={styles.pickerBtn}
          onPress={() => setShowPicker(true)}
          activeOpacity={0.7}
        >
          {selected ? (
            <>
              <Text style={styles.flag}>{selected.flag}</Text>
              <Text style={styles.countryName}>{selected.name}</Text>
              <Text style={styles.countryCode}>{selected.code}</Text>
            </>
          ) : (
            <Text style={styles.placeholder}>Toca para elegir tu país</Text>
          )}
        </TouchableOpacity>
      </MotiView>

      <CountryPicker
        show={showPicker}
        lang="es"
        pickerButtonOnPress={handleSelect}
        onBackdropPress={() => setShowPicker(false)}
        style={{
          modal: { height: 500, backgroundColor: '#1A1A1A' },
          backdrop: { backgroundColor: 'rgba(0,0,0,0.6)' },
          line: { backgroundColor: 'rgba(255,255,255,0.1)' },
          itemsList: { backgroundColor: '#1A1A1A' },
          textInput: {
            color: '#FFF',
            backgroundColor: 'rgba(255,255,255,0.06)',
            borderRadius: 12,
            paddingHorizontal: 16,
            height: 48,
          },
          countryButtonStyles: {
            backgroundColor: 'transparent',
            borderBottomWidth: 1,
            borderBottomColor: 'rgba(255,255,255,0.06)',
          },
          dialCode: { color: '#CD7F32', fontWeight: '600' },
          countryName: { color: '#FFF' },
          countryMessageContainer: { backgroundColor: '#1A1A1A' },
          searchMessageText: { color: 'rgba(255,255,255,0.5)' },
        }}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  content: {
    flex: 1,
    padding: 24,
    justifyContent: 'center',
    width: '100%',
    maxWidth: 480,
    alignSelf: 'center',
  },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 8,
  },
  title: {
    fontSize: 38, color: '#FFF', fontFamily: 'serif',
    fontWeight: '400', lineHeight: 44, marginBottom: 8,
  },
  subtitle: { fontSize: 14, color: 'rgba(255,255,255,0.4)', marginBottom: 36 },
  pickerBtn: {
    padding: 16,
    borderRadius: 16,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    minHeight: 60,
  },
  flag: { fontSize: 28 },
  countryName: { flex: 1, fontSize: 15, color: '#FFF', fontWeight: '600' },
  countryCode: { fontSize: 13, color: 'rgba(255,255,255,0.35)' },
  placeholder: {
    flex: 1,
    fontSize: 15,
    color: 'rgba(255,255,255,0.5)',
    textAlign: 'center',
  },
});
