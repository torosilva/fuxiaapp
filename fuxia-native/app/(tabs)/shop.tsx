import { StyleSheet, Image, ScrollView, TouchableOpacity, View as RNView, TextInput } from 'react-native';
import { Text, View } from '@/components/Themed';
import { Search, Filter, ShoppingBag, Heart } from 'lucide-react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';
import { MotiView } from 'moti';
import { router } from 'expo-router';

const HERO_IMAGE = require('../../assets/images/hero.png');
const SANDALS_IMAGE = require('../../assets/images/sandals.png');

export default function ShopScreen() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <RNView style={styles.header}>
        <Text style={styles.headerTitle}>Tienda</Text>
        <RNView style={styles.searchBar}>
          <Search size={20} color={theme.muted} />
          <TextInput 
            placeholder="Buscar productos..." 
            placeholderTextColor={theme.muted}
            style={[styles.searchInput, { color: theme.text }]}
          />
          <TouchableOpacity style={styles.filterButton}>
            <Filter size={20} color={theme.text} />
          </TouchableOpacity>
        </RNView>
      </RNView>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        <RNView style={styles.filterScroll}>
          {['Todo', 'Ballerinas', 'Sandalias', 'Planas', 'Botas'].map((f, i) => (
            <TouchableOpacity 
              key={f} 
              style={[
                styles.filterChip, 
                { backgroundColor: i === 0 ? theme.text : theme.soft, borderColor: theme.border }
              ]}
            >
              <Text style={[styles.filterText, { color: i === 0 ? theme.background : theme.text }]}>{f}</Text>
            </TouchableOpacity>
          ))}
        </RNView>

        <RNView style={styles.grid}>
          {[1, 2, 3, 4].map((i) => (
            <TouchableOpacity 
              key={i}
              onPress={() => router.push(`/product/${i}`)}
              style={styles.productCard}
            >
              <MotiView 
                from={{ opacity: 0, translateY: 20 }}
                animate={{ opacity: 1, translateY: 0 }}
                transition={{ delay: i * 100 }}
              >
              <RNView style={[styles.imageContainer, { backgroundColor: theme.soft }]}>
                <Image source={i % 2 === 0 ? SANDALS_IMAGE : HERO_IMAGE} style={styles.image} />
                <TouchableOpacity style={styles.wishlistButton}>
                  <Heart size={18} color={theme.accent} fill={i === 1 ? theme.accent : 'transparent'} />
                </TouchableOpacity>
              </RNView>
              <RNView style={styles.productInfo}>
                <Text style={[styles.categoryLabel, { color: theme.muted }]}>Ballerinas</Text>
                <Text style={styles.productName}>Modelo Clásico Fuxia</Text>
                <Text style={styles.productPrice}>$3,200 MXN</Text>
              </RNView>
              </MotiView>
            </TouchableOpacity>
          ))}
        </RNView>
      </ScrollView>
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
    marginBottom: 20,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#F3F4F6',
    borderRadius: 15,
    paddingHorizontal: 15,
    height: 50,
  },
  searchInput: {
    flex: 1,
    marginLeft: 10,
    fontSize: 14,
  },
  filterButton: {
    padding: 5,
  },
  scrollContent: {
    paddingHorizontal: 20,
    paddingBottom: 100,
  },
  filterScroll: {
    flexDirection: 'row',
    gap: 10,
    marginBottom: 25,
  },
  filterChip: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
    borderWidth: 1,
  },
  filterText: {
    fontSize: 13,
    fontWeight: '600',
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    gap: 15,
  },
  productCard: {
    width: '47.5%',
    marginBottom: 20,
  },
  imageContainer: {
    height: 220,
    borderRadius: 15,
    overflow: 'hidden',
  },
  image: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  productInfo: {
    paddingTop: 12,
  },
  categoryLabel: {
    fontSize: 12,
    textTransform: 'uppercase',
  },
  productName: {
    fontSize: 14,
    fontWeight: '600',
    marginTop: 4,
  },
  productPrice: {
    fontSize: 14,
    fontWeight: '700',
    marginTop: 4,
  },
  wishlistButton: {
    position: 'absolute',
    top: 12,
    right: 12,
    backgroundColor: 'rgba(255,255,255,0.8)',
    padding: 8,
    borderRadius: 20,
  }
});
