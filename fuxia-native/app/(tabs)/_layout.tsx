import React from 'react';
import { Tabs } from 'expo-router';
import { Home, ShoppingBag, Heart, User } from 'lucide-react-native';
import { View, StyleSheet, Platform, Image } from 'react-native';
import Colors from '@/constants/Colors';
import { useColorScheme } from '@/components/useColorScheme';

const LEAF_ICON = require('../../assets/images/logo-icon.png');

export default function TabLayout() {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: theme.accent,
        tabBarInactiveTintColor: 'rgba(255,255,255,0.4)',
        headerShown: false,
        tabBarShowLabel: false,
        tabBarStyle: {
          height: Platform.OS === 'ios' ? 88 : 70,
          paddingBottom: Platform.OS === 'ios' ? 28 : 10,
          paddingTop: 10,
          backgroundColor: '#0D0D0D',
          borderTopWidth: 1,
          borderTopColor: 'rgba(255,255,255,0.08)',
          elevation: 0,
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
        name="card"
        options={{
          tabBarIcon: ({ focused }) => (
            <View style={[styles.fab, focused && styles.fabFocused]}>
              <Image source={LEAF_ICON} style={styles.fabIcon} resizeMode="contain" />
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
  },
  activeDot: {
    width: 4,
    height: 4,
    borderRadius: 2,
    marginTop: 6,
  },
  fab: {
    width: 62,
    height: 62,
    borderRadius: 31,
    backgroundColor: '#0D0D0D',
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: -28,
    shadowColor: '#CD7F32',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.5,
    shadowRadius: 12,
    elevation: 8,
    borderWidth: 2,
    borderColor: '#CD7F32',
  },
  fabFocused: {
    backgroundColor: '#1A1A1A',
    borderColor: '#E89148',
  },
  fabIcon: {
    width: 32,
    height: 32,
  },
});
