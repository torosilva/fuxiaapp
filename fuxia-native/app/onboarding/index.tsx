import React from 'react';
import { View, Text, StyleSheet, StatusBar, Image, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';
import { MotiView } from 'moti';

const LOGO_ICON = require('../../assets/images/logo-icon.png');
const LOGO_WORDMARK = require('../../assets/images/logo-wordmark.png');

export default function WelcomeScreen() {
  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" />

      <View style={styles.center}>
        {/* Icon: entrance spring, then gentle breathing float forever */}
        <MotiView
          from={{ opacity: 0, scale: 0.5 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: 'spring', damping: 12, mass: 1, delay: 200 }}
          style={styles.iconWrapper}
        >
          <MotiView
            from={{ translateY: 0 }}
            animate={{ translateY: -16 }}
            transition={{
              type: 'timing',
              duration: 1800,
              loop: true,
              repeatReverse: true,
              delay: 1000,
            }}
          >
            <Image source={LOGO_ICON} style={styles.icon} resizeMode="contain" />
          </MotiView>
        </MotiView>

        {/* Wordmark: slide up + fade, slight letter-space feel via scale */}
        <MotiView
          from={{ opacity: 0, translateY: 20, scale: 0.96 }}
          animate={{ opacity: 1, translateY: 0, scale: 1 }}
          transition={{ type: 'timing', duration: 700, delay: 1000 }}
          style={styles.wordmarkWrapper}
        >
          <Image source={LOGO_WORDMARK} style={styles.wordmark} resizeMode="contain" />
        </MotiView>

        {/* Tagline */}
        <MotiView
          from={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ type: 'timing', duration: 600, delay: 1800 }}
        >
          <Text style={styles.tagline}>UN PAR A LA VEZ</Text>
        </MotiView>
      </View>

      {/* CTA */}
      <MotiView
        from={{ opacity: 0, translateY: 24 }}
        animate={{ opacity: 1, translateY: 0 }}
        transition={{ type: 'timing', duration: 500, delay: 2300 }}
        style={styles.footer}
      >
        <TouchableOpacity
          style={styles.btn}
          onPress={() => router.push('/onboarding/country' as any)}
          activeOpacity={0.85}
        >
          <Text style={styles.btnText}>CREAR CUENTA</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.btnSecondary}
          onPress={() => router.push('/onboarding/login' as any)}
          activeOpacity={0.7}
        >
          <Text style={styles.btnSecondaryText}>Ya tengo cuenta · Iniciar sesión</Text>
        </TouchableOpacity>
      </MotiView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0D0D0D',
    paddingHorizontal: 32,
    paddingBottom: 48,
    paddingTop: 24,
  },
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  iconWrapper: {
    marginBottom: 36,
  },
  icon: {
    width: 130,
    height: 130,
  },
  glow: {
    position: 'absolute',
    top: '28%',
    width: 220,
    height: 220,
    borderRadius: 110,
    backgroundColor: '#CD7F32',
  },
  wordmarkWrapper: {
    width: '100%',
    alignItems: 'center',
    marginBottom: 28,
  },
  wordmark: {
    width: '90%',
    height: 44,
  },
  tagline: {
    color: 'rgba(205,127,50,0.55)',
    fontSize: 11,
    letterSpacing: 6,
    fontWeight: '600',
    textAlign: 'center',
  },
  footer: {
    alignItems: 'center',
  },
  btn: {
    backgroundColor: '#CD7F32',
    borderRadius: 30,
    height: 54,
    justifyContent: 'center',
    alignItems: 'center',
    width: '100%',
    marginBottom: 16,
  },
  btnText: {
    color: '#0D0D0D',
    fontSize: 13,
    fontWeight: '800',
    letterSpacing: 3,
  },
  btnSecondary: {
    height: 48,
    justifyContent: 'center',
    alignItems: 'center',
    width: '100%',
  },
  btnSecondaryText: {
    color: '#CD7F32',
    fontSize: 13,
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  hint: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 11,
    textAlign: 'center',
  },
});
