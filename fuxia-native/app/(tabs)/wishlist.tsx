import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView } from 'react-native';
import { Text, View } from '@/components/Themed';
import { Heart, Home } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { router } from 'expo-router';

export default function WishlistScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <RNView style={styles.header}>
        <Text style={styles.headerTitle}>Wishlist</Text>
      </RNView>

      <RNView style={styles.emptyContainer}>
        <RNView style={[styles.iconContainer, { backgroundColor: theme.soft }]}>
          <Heart size={60} color={theme.accent} fill={theme.soft} />
        </RNView>
        <Text style={styles.emptyTitle}>Tu lista está vacía</Text>
        <Text style={[styles.emptySubtitle, { color: theme.muted }]}>Guarda tus modelos favoritos para verlos después.</Text>
        
        <TouchableOpacity 
          onPress={() => router.push('/(tabs)')}
          style={[styles.button, { backgroundColor: theme.text }]}
        >
          <Text style={[styles.buttonText, { color: theme.background }]}>Ir a la Tienda</Text>
        </TouchableOpacity>
      </RNView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    paddingTop: 60,
    paddingHorizontal: 20,
    paddingBottom: 20,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 40,
    paddingBottom: 100,
  },
  iconContainer: {
    width: 120,
    height: 120,
    borderRadius: 60,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 30,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 10,
  },
  emptySubtitle: {
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 40,
  },
  button: {
    paddingHorizontal: 40,
    paddingVertical: 15,
    borderRadius: 30,
  },
  buttonText: {
    fontSize: 14,
    fontWeight: '600',
  }
});
