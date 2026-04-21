import React from 'react';
import { Tabs } from 'expo-router';
import { Home, ShoppingBag, Heart, User, CreditCard } from 'lucide-react-native';
import { View, StyleSheet, Platform } from 'react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';

export default function TabLayout() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: theme.accent,
        tabBarInactiveTintColor: 'rgba(255,255,255,0.4)',
        headerShown: false,
        tabBarShowLabel: false, // Minimalist: No labels
        tabBarStyle: {
          position: 'absolute',
          bottom: 25,
          left: 20,
          right: 20,
          height: 65,
          backgroundColor: 'rgba(18, 18, 18, 0.9)', // Glassmorphism Dark
          borderRadius: 35,
          borderTopWidth: 0,
          elevation: 5,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 10 },
          shadowOpacity: 0.3,
          shadowRadius: 15,
          paddingBottom: Platform.OS === 'ios' ? 0 : 0,
          borderWidth: 1,
          borderColor: 'rgba(255,255,255,0.05)',
        },
      }}>
      <Tabs.Screen
        name="index"
        options={{
          tabBarIcon: ({ color, focused }) => (
            <View style={[styles.iconContainer, focused && styles.activeIconContainer]}>
              <Home color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
              {focused && <View style={[styles.activeDot, { backgroundColor: theme.accent }]} />}
            </View>
          ),
        }}
      />
      <Tabs.Screen
        name="shop"
        options={{
          tabBarIcon: ({ color, focused }) => (
            <View style={[styles.iconContainer, focused && styles.activeIconContainer]}>
              <ShoppingBag color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
              {focused && <View style={[styles.activeDot, { backgroundColor: theme.accent }]} />}
            </View>
          ),
        }}
      />
      <Tabs.Screen
        name="wishlist"
        options={{
          tabBarIcon: ({ color, focused }) => (
            <View style={[styles.iconContainer, focused && styles.activeIconContainer]}>
              <Heart color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
              {focused && <View style={[styles.activeDot, { backgroundColor: theme.accent }]} />}
            </View>
          ),
        }}
      />
      <Tabs.Screen
        name="card"
        options={{
          tabBarIcon: ({ color, focused }) => (
            <View style={[styles.iconContainer, focused && styles.activeIconContainer]}>
              <CreditCard color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
              {focused && <View style={[styles.activeDot, { backgroundColor: theme.accent }]} />}
            </View>
          ),
        }}
      />
      <Tabs.Screen
        name="profile"
        options={{
          tabBarIcon: ({ color, focused }) => (
            <View style={[styles.iconContainer, focused && styles.activeIconContainer]}>
              <User color={color} size={24} strokeWidth={focused ? 2.5 : 2} />
              {focused && <View style={[styles.activeDot, { backgroundColor: theme.accent }]} />}
            </View>
          ),
        }}
      />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  iconContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: 10,
  },
  activeIconContainer: {
    // Optional: scale or glow
  },
  activeDot: {
    width: 4,
    height: 4,
    borderRadius: 2,
    marginTop: 6,
  }
});
