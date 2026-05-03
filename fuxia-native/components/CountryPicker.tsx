import React from 'react';
import { Modal, StyleSheet, TouchableOpacity, View as RNView, ScrollView, Pressable } from 'react-native';
import { Text } from './Themed';
import { Check, X } from 'lucide-react-native';
import { SUPPORTED_COUNTRIES, type CountryCode } from '@/lib/CountryService';
import Colors from '@/constants/Colors';
import { useColorScheme } from './useColorScheme';

interface Props {
  visible: boolean;
  current: CountryCode;
  onSelect: (code: CountryCode) => void;
  onClose: () => void;
}

export const CountryPicker = ({ visible, current, onSelect, onClose }: Props) => {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={[styles.sheet, { backgroundColor: theme.background, borderColor: theme.border }]}>
          <RNView style={styles.header}>
            <Text style={styles.title}>País de envío</Text>
            <TouchableOpacity onPress={onClose} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
              <X size={22} color={theme.text} />
            </TouchableOpacity>
          </RNView>
          <Text style={[styles.subtitle, { color: theme.muted }]}>
            Define los precios y la moneda que verás en la tienda.
          </Text>
          <ScrollView style={styles.list} showsVerticalScrollIndicator={false}>
            {SUPPORTED_COUNTRIES.map((c) => {
              const isCurrent = c.code === current;
              return (
                <TouchableOpacity
                  key={c.code}
                  style={[
                    styles.row,
                    { borderColor: theme.border },
                    isCurrent && { backgroundColor: theme.soft },
                  ]}
                  onPress={() => onSelect(c.code)}
                  activeOpacity={0.7}
                >
                  <Text style={styles.flag}>{c.flag}</Text>
                  <RNView style={{ flex: 1 }}>
                    <Text style={styles.name}>{c.name}</Text>
                    <Text style={[styles.currency, { color: theme.muted }]}>{c.currency}</Text>
                  </RNView>
                  {isCurrent && <Check size={20} color={theme.accent} />}
                </TouchableOpacity>
              );
            })}
            <RNView style={{ height: 24 }} />
          </ScrollView>
        </Pressable>
      </Pressable>
    </Modal>
  );
};

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  sheet: {
    maxHeight: '75%',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingTop: 16,
    paddingHorizontal: 20,
    borderTopWidth: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 4,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
  },
  subtitle: {
    fontSize: 13,
    marginBottom: 16,
  },
  list: {
    flexGrow: 0,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingVertical: 14,
    paddingHorizontal: 12,
    borderRadius: 12,
    marginBottom: 6,
    borderWidth: 1,
  },
  flag: {
    fontSize: 26,
  },
  name: {
    fontSize: 15,
    fontWeight: '600',
  },
  currency: {
    fontSize: 12,
    marginTop: 2,
    letterSpacing: 1,
  },
});
