import React, { useEffect, useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Share,
  StatusBar, ActivityIndicator, ScrollView, Clipboard,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Users, Copy, Share2, CheckCircle } from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';
import { supabase } from '@/lib/supabase';

interface Referral {
  name: string;
  created_at: string;
  has_purchase: boolean;
}

export default function ReferralScreen() {
  const { customer } = useAuth();
  const [referrals, setReferrals] = useState<Referral[]>([]);
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);

  const code = customer?.referral_code ?? '';

  useEffect(() => {
    if (!customer?.id) { setLoading(false); return; }
    (async () => {
      const { data } = await supabase
        .from('customers')
        .select('name, created_at, loyalty_cards(total_points)')
        .eq('referred_by', customer.id);
      if (data) {
        setReferrals(data.map((r: any) => ({
          name: r.name,
          created_at: r.created_at,
          has_purchase: (r.loyalty_cards?.total_points ?? 0) > 0,
        })));
      }
      setLoading(false);
    })();
  }, [customer?.id]);

  const handleCopy = () => {
    Clipboard.setString(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleShare = () => {
    Share.share({
      message: `¡Únete a Fuxia Ballerinas! Usa mi código de referida *${code}* al registrarte. Yo gano puntos dobles en mi próxima compra cuando hagas la tuya 👠✨\nDescarga la app: fuxiaballerinas.com`,
    });
  };

  const MONTHS_ES = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
  const fmt = (iso: string) => {
    const d = new Date(iso);
    return `${d.getDate()} ${MONTHS_ES[d.getMonth()]} ${d.getFullYear()}`;
  };

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scroll}>

        <TouchableOpacity style={styles.backBtn} onPress={() => router.back()} activeOpacity={0.7}>
          <ArrowLeft size={20} color="#CD7F32" />
        </TouchableOpacity>

        <MotiView from={{ opacity: 0, translateY: 16 }} animate={{ opacity: 1, translateY: 0 }} transition={{ type: 'timing', duration: 400 }}>
          <Text style={styles.eyebrow}>PROGRAMA REFERIDOS</Text>
          <Text style={styles.title}>Refiere y{'\n'}gana doble</Text>
          <Text style={styles.subtitle}>
            Cuando una amiga use tu código y haga su primera compra, tú ganas el doble de puntos en esa misma compra.
          </Text>

          {/* Code card */}
          <View style={styles.codeCard}>
            <Text style={styles.codeLabel}>TU CÓDIGO</Text>
            <Text style={styles.codeText}>{code || '———'}</Text>
            <View style={styles.codeActions}>
              <TouchableOpacity style={styles.codeBtn} onPress={handleCopy} activeOpacity={0.8}>
                {copied
                  ? <CheckCircle size={16} color="#4CAF50" />
                  : <Copy size={16} color="#CD7F32" />}
                <Text style={[styles.codeBtnText, copied && { color: '#4CAF50' }]}>
                  {copied ? 'Copiado' : 'Copiar'}
                </Text>
              </TouchableOpacity>
              <TouchableOpacity style={[styles.codeBtn, styles.codeBtnFilled]} onPress={handleShare} activeOpacity={0.8}>
                <Share2 size={16} color="#0D0D0D" />
                <Text style={[styles.codeBtnText, { color: '#0D0D0D' }]}>Compartir</Text>
              </TouchableOpacity>
            </View>
          </View>

          {/* How it works */}
          <View style={styles.stepsCard}>
            <Text style={styles.stepsTitle}>¿Cómo funciona?</Text>
            {[
              { n: '1', text: 'Comparte tu código con una amiga' },
              { n: '2', text: 'Ella lo ingresa al registrarse en la app' },
              { n: '3', text: 'Cuando ella haga su primera compra, tú ganas el doble de puntos de esa venta' },
            ].map(step => (
              <View key={step.n} style={styles.step}>
                <View style={styles.stepNum}>
                  <Text style={styles.stepNumText}>{step.n}</Text>
                </View>
                <Text style={styles.stepText}>{step.text}</Text>
              </View>
            ))}
          </View>

          {/* Referrals list */}
          <Text style={styles.sectionTitle}>Mis referidas</Text>
          {loading
            ? <ActivityIndicator color="#CD7F32" style={{ marginTop: 20 }} />
            : referrals.length === 0
              ? <View style={styles.emptyCard}>
                  <Users size={28} color="rgba(255,255,255,0.15)" />
                  <Text style={styles.emptyText}>Aún no has referido a nadie.{'\n'}¡Comparte tu código!</Text>
                </View>
              : referrals.map((r, i) => (
                  <MotiView
                    key={i}
                    from={{ opacity: 0, translateX: -10 }}
                    animate={{ opacity: 1, translateX: 0 }}
                    transition={{ type: 'timing', duration: 300, delay: i * 60 }}
                  >
                    <View style={styles.referralRow}>
                      <View style={styles.referralAvatar}>
                        <Text style={styles.referralInitial}>{r.name?.[0]?.toUpperCase() ?? '?'}</Text>
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.referralName}>{r.name}</Text>
                        <Text style={styles.referralDate}>Se unió el {fmt(r.created_at)}</Text>
                      </View>
                      <View style={[styles.referralBadge, r.has_purchase ? styles.badgeActive : styles.badgePending]}>
                        <Text style={[styles.referralBadgeText, r.has_purchase ? styles.badgeActiveText : styles.badgePendingText]}>
                          {r.has_purchase ? '2× activo' : 'Pendiente'}
                        </Text>
                      </View>
                    </View>
                  </MotiView>
                ))}

          <View style={{ height: 60 }} />
        </MotiView>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  scroll: { padding: 24 },
  backBtn: {
    width: 40, height: 40, borderRadius: 12,
    backgroundColor: 'rgba(205,127,50,0.12)',
    justifyContent: 'center', alignItems: 'center', marginBottom: 24,
  },
  eyebrow: { fontSize: 10, color: '#CD7F32', fontWeight: '800', letterSpacing: 3, marginBottom: 8 },
  title: { fontSize: 36, color: '#fff', fontFamily: 'serif', fontWeight: '400', lineHeight: 42, marginBottom: 12 },
  subtitle: { fontSize: 14, color: 'rgba(255,255,255,0.45)', lineHeight: 21, marginBottom: 32 },
  codeCard: {
    backgroundColor: '#1A1A1A', borderRadius: 20,
    borderWidth: 1, borderColor: 'rgba(205,127,50,0.2)',
    padding: 24, alignItems: 'center', marginBottom: 20,
  },
  codeLabel: { fontSize: 10, color: 'rgba(255,255,255,0.35)', fontWeight: '800', letterSpacing: 3, marginBottom: 12 },
  codeText: { fontSize: 36, color: '#CD7F32', fontWeight: '800', letterSpacing: 6, marginBottom: 20 },
  codeActions: { flexDirection: 'row', gap: 12 },
  codeBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingVertical: 10, paddingHorizontal: 20,
    borderRadius: 30, borderWidth: 1, borderColor: 'rgba(205,127,50,0.4)',
  },
  codeBtnFilled: { backgroundColor: '#CD7F32', borderColor: '#CD7F32' },
  codeBtnText: { fontSize: 13, color: '#CD7F32', fontWeight: '700' },
  stepsCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    padding: 20, marginBottom: 32,
  },
  stepsTitle: { fontSize: 14, color: 'rgba(255,255,255,0.5)', fontWeight: '600', marginBottom: 16 },
  step: { flexDirection: 'row', alignItems: 'flex-start', gap: 14, marginBottom: 14 },
  stepNum: {
    width: 26, height: 26, borderRadius: 13,
    backgroundColor: 'rgba(205,127,50,0.15)',
    justifyContent: 'center', alignItems: 'center', marginTop: 1,
  },
  stepNumText: { fontSize: 12, color: '#CD7F32', fontWeight: '800' },
  stepText: { flex: 1, fontSize: 14, color: 'rgba(255,255,255,0.7)', lineHeight: 20 },
  sectionTitle: { fontSize: 18, color: '#fff', fontWeight: '600', marginBottom: 16 },
  emptyCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    padding: 32, alignItems: 'center', gap: 12,
  },
  emptyText: { color: 'rgba(255,255,255,0.3)', fontSize: 13, textAlign: 'center', lineHeight: 20 },
  referralRow: {
    flexDirection: 'row', alignItems: 'center', gap: 14,
    backgroundColor: '#1A1A1A', borderRadius: 14,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    padding: 14, marginBottom: 10,
  },
  referralAvatar: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(205,127,50,0.15)',
    justifyContent: 'center', alignItems: 'center',
  },
  referralInitial: { fontSize: 16, color: '#CD7F32', fontWeight: '700' },
  referralName: { fontSize: 14, color: '#fff', fontWeight: '600' },
  referralDate: { fontSize: 11, color: 'rgba(255,255,255,0.35)', marginTop: 2 },
  referralBadge: { borderRadius: 10, paddingHorizontal: 10, paddingVertical: 4 },
  badgeActive: { backgroundColor: 'rgba(76,175,80,0.15)' },
  badgePending: { backgroundColor: 'rgba(255,255,255,0.06)' },
  referralBadgeText: { fontSize: 11, fontWeight: '700' },
  badgeActiveText: { color: '#4CAF50' },
  badgePendingText: { color: 'rgba(255,255,255,0.35)' },
});
