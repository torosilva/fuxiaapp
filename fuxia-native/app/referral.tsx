import React, { useEffect, useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Share,
  StatusBar, ActivityIndicator, ScrollView, Clipboard,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { MotiView } from 'moti';
import { ArrowLeft, Users, Copy, Share2, CheckCircle, Sparkles } from 'lucide-react-native';
import { useAuth } from '@/lib/hooks/useAuth';
import { supabase } from '@/lib/supabase';

interface ReferralEntry {
  id: string;
  name: string;
  phone: string;
  joined_at: string;
  has_purchase: boolean;
  bonus?: {
    pts: number;
    before: number;
    after: number;
    applied_at: string;
  };
}

function parseNotes(notes: string | null): { pts: number; before: number; after: number } | null {
  if (!notes?.startsWith('referral_bonus|')) return null;
  const get = (key: string) => {
    const m = notes.match(new RegExp(`${key}:(\\d+)`));
    return m ? parseInt(m[1], 10) : 0;
  };
  return { pts: get('pts'), before: get('before'), after: get('after') };
}

const MONTHS_ES = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
function fmt(iso: string) {
  const d = new Date(iso);
  return `${d.getDate()} ${MONTHS_ES[d.getMonth()]} ${d.getFullYear()}`;
}

export default function ReferralScreen() {
  const { customer, loyaltyCard } = useAuth();
  const [entries, setEntries] = useState<ReferralEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);

  const code = (customer as any)?.referral_code ?? '';

  useEffect(() => {
    if (!customer?.id || !loyaltyCard?.id) { setLoading(false); return; }
    (async () => {
      const [referredsRes, bonusTxsRes] = await Promise.all([
        supabase
          .from('customers')
          .select('id, name, phone, created_at, loyalty_cards(total_points)')
          .eq('referred_by', customer.id),
        supabase
          .from('transactions')
          .select('notes, created_at')
          .eq('loyalty_card_id', loyaltyCard.id)
          .like('notes', 'referral_bonus|%'),
      ]);

      // Build phone → bonus map from transactions
      const bonusByPhone: Record<string, { pts: number; before: number; after: number; applied_at: string }> = {};
      for (const tx of bonusTxsRes.data ?? []) {
        const parsed = parseNotes(tx.notes);
        if (!parsed) continue;
        const phoneMatch = tx.notes?.match(/phone:(\+?\d+)/);
        if (phoneMatch) {
          bonusByPhone[phoneMatch[1]] = { ...parsed, applied_at: tx.created_at };
        }
      }

      const mapped: ReferralEntry[] = (referredsRes.data ?? []).map((r: any) => ({
        id: r.id,
        name: r.name,
        phone: r.phone,
        joined_at: r.created_at,
        has_purchase: (r.loyalty_cards?.total_points ?? 0) > 0,
        bonus: bonusByPhone[r.phone],
      }));

      setEntries(mapped);
      setLoading(false);
    })();
  }, [customer?.id, loyaltyCard?.id]);

  const handleCopy = () => {
    Clipboard.setString(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleShare = () => {
    Share.share({
      message: `¡Únete a Fuxia Ballerinas! Usa mi código *${code}* al registrarte en la app. Yo gano puntos dobles cuando hagas tu primera compra 👠✨\nDescarga la app: fuxiaballerinas.com`,
    });
  };

  const totalBonusEarned = entries.reduce((s, e) => s + (e.bonus?.pts ?? 0), 0);

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
            Cuando tu referida haga su primera compra, tú ganas el doble de puntos de esa venta automáticamente.
          </Text>

          {/* Bonus earned banner */}
          {totalBonusEarned > 0 && (
            <MotiView
              from={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ type: 'timing', duration: 400 }}
              style={styles.bonusBanner}
            >
              <Sparkles size={20} color="#CD7F32" />
              <Text style={styles.bonusBannerText}>
                Has ganado <Text style={styles.bonusBannerPts}>+{totalBonusEarned} pts</Text> en bonos de referidos
              </Text>
            </MotiView>
          )}

          {/* Code card */}
          <View style={styles.codeCard}>
            <Text style={styles.codeLabel}>TU CÓDIGO</Text>
            <Text style={styles.codeText}>{code || '———'}</Text>
            <View style={styles.codeActions}>
              <TouchableOpacity style={styles.codeBtn} onPress={handleCopy} activeOpacity={0.8}>
                {copied ? <CheckCircle size={16} color="#4CAF50" /> : <Copy size={16} color="#CD7F32" />}
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
              { n: '3', text: 'Cuando haga su primera compra, tú recibes el mismo número de puntos que ella ganó (2× en total)' },
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
          <Text style={styles.sectionTitle}>
            Mis referidas{entries.length > 0 ? ` (${entries.length})` : ''}
          </Text>

          {loading
            ? <ActivityIndicator color="#CD7F32" style={{ marginTop: 20 }} />
            : entries.length === 0
              ? (
                <View style={styles.emptyCard}>
                  <Users size={28} color="rgba(255,255,255,0.15)" />
                  <Text style={styles.emptyText}>Aún no has referido a nadie.{'\n'}¡Comparte tu código!</Text>
                </View>
              )
              : entries.map((entry, i) => (
                <MotiView
                  key={entry.id}
                  from={{ opacity: 0, translateY: 10 }}
                  animate={{ opacity: 1, translateY: 0 }}
                  transition={{ type: 'timing', duration: 300, delay: i * 70 }}
                >
                  <View style={styles.entryCard}>
                    {/* Header row */}
                    <View style={styles.entryHeader}>
                      <View style={styles.entryAvatar}>
                        <Text style={styles.entryInitial}>{entry.name?.[0]?.toUpperCase() ?? '?'}</Text>
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.entryName}>{entry.name}</Text>
                        <Text style={styles.entryDate}>Se unió el {fmt(entry.joined_at)}</Text>
                      </View>
                      <View style={[styles.statusBadge, entry.bonus ? styles.badgeDone : entry.has_purchase ? styles.badgeWait : styles.badgePending]}>
                        <Text style={[styles.statusText, entry.bonus ? styles.textDone : entry.has_purchase ? styles.textWait : styles.textPending]}>
                          {entry.bonus ? '2× aplicado' : entry.has_purchase ? 'Procesando' : 'Sin compra aún'}
                        </Text>
                      </View>
                    </View>

                    {/* Bonus detail */}
                    {entry.bonus && (
                      <View style={styles.bonusDetail}>
                        <View style={styles.bonusRow}>
                          <Text style={styles.bonusLabel}>Bono aplicado</Text>
                          <Text style={styles.bonusDate}>{fmt(entry.bonus.applied_at)}</Text>
                        </View>
                        <View style={styles.pointsFlow}>
                          <View style={styles.pointsBox}>
                            <Text style={styles.pointsBoxLabel}>Antes</Text>
                            <Text style={styles.pointsBoxValue}>{entry.bonus.before}</Text>
                            <Text style={styles.pointsBoxUnit}>pts</Text>
                          </View>
                          <View style={styles.pointsArrow}>
                            <Text style={styles.pointsArrowText}>+{entry.bonus.pts} pts</Text>
                            <Text style={styles.pointsArrowSub}>bono 2×</Text>
                          </View>
                          <View style={[styles.pointsBox, styles.pointsBoxAfter]}>
                            <Text style={styles.pointsBoxLabel}>Después</Text>
                            <Text style={[styles.pointsBoxValue, styles.pointsBoxValueAfter]}>{entry.bonus.after}</Text>
                            <Text style={styles.pointsBoxUnit}>pts</Text>
                          </View>
                        </View>
                      </View>
                    )}
                  </View>
                </MotiView>
              ))
          }

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
  subtitle: { fontSize: 14, color: 'rgba(255,255,255,0.45)', lineHeight: 21, marginBottom: 24 },
  bonusBanner: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: 'rgba(205,127,50,0.1)',
    borderWidth: 1, borderColor: 'rgba(205,127,50,0.25)',
    borderRadius: 14, padding: 14, marginBottom: 20,
  },
  bonusBannerText: { fontSize: 14, color: 'rgba(255,255,255,0.7)', flex: 1 },
  bonusBannerPts: { color: '#CD7F32', fontWeight: '800' },
  codeCard: {
    backgroundColor: '#1A1A1A', borderRadius: 20,
    borderWidth: 1, borderColor: 'rgba(205,127,50,0.2)',
    padding: 24, alignItems: 'center', marginBottom: 16,
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
    padding: 20, marginBottom: 28,
  },
  stepsTitle: { fontSize: 13, color: 'rgba(255,255,255,0.4)', fontWeight: '600', marginBottom: 14 },
  step: { flexDirection: 'row', alignItems: 'flex-start', gap: 12, marginBottom: 12 },
  stepNum: {
    width: 24, height: 24, borderRadius: 12,
    backgroundColor: 'rgba(205,127,50,0.15)',
    justifyContent: 'center', alignItems: 'center', marginTop: 1,
  },
  stepNumText: { fontSize: 11, color: '#CD7F32', fontWeight: '800' },
  stepText: { flex: 1, fontSize: 13, color: 'rgba(255,255,255,0.65)', lineHeight: 19 },
  sectionTitle: { fontSize: 18, color: '#fff', fontWeight: '600', marginBottom: 14 },
  emptyCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
    padding: 32, alignItems: 'center', gap: 12,
  },
  emptyText: { color: 'rgba(255,255,255,0.3)', fontSize: 13, textAlign: 'center', lineHeight: 20 },
  // Entry card
  entryCard: {
    backgroundColor: '#1A1A1A', borderRadius: 16,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.07)',
    padding: 16, marginBottom: 12,
  },
  entryHeader: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  entryAvatar: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(205,127,50,0.15)',
    justifyContent: 'center', alignItems: 'center',
  },
  entryInitial: { fontSize: 16, color: '#CD7F32', fontWeight: '700' },
  entryName: { fontSize: 14, color: '#fff', fontWeight: '600' },
  entryDate: { fontSize: 11, color: 'rgba(255,255,255,0.35)', marginTop: 2 },
  statusBadge: { borderRadius: 10, paddingHorizontal: 10, paddingVertical: 4 },
  badgeDone: { backgroundColor: 'rgba(76,175,80,0.15)' },
  badgeWait: { backgroundColor: 'rgba(255,193,7,0.12)' },
  badgePending: { backgroundColor: 'rgba(255,255,255,0.06)' },
  statusText: { fontSize: 11, fontWeight: '700' },
  textDone: { color: '#4CAF50' },
  textWait: { color: '#FFC107' },
  textPending: { color: 'rgba(255,255,255,0.3)' },
  // Bonus detail
  bonusDetail: {
    marginTop: 14,
    paddingTop: 14,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.06)',
  },
  bonusRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 },
  bonusLabel: { fontSize: 12, color: '#4CAF50', fontWeight: '700' },
  bonusDate: { fontSize: 11, color: 'rgba(255,255,255,0.35)' },
  pointsFlow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderRadius: 12, padding: 14,
  },
  pointsBox: { alignItems: 'center', flex: 1 },
  pointsBoxAfter: {},
  pointsBoxLabel: { fontSize: 10, color: 'rgba(255,255,255,0.35)', fontWeight: '700', letterSpacing: 1, marginBottom: 4 },
  pointsBoxValue: { fontSize: 22, color: 'rgba(255,255,255,0.6)', fontWeight: '700' },
  pointsBoxValueAfter: { color: '#4CAF50' },
  pointsBoxUnit: { fontSize: 10, color: 'rgba(255,255,255,0.25)', marginTop: 2 },
  pointsArrow: { alignItems: 'center', paddingHorizontal: 8 },
  pointsArrowText: { fontSize: 14, color: '#CD7F32', fontWeight: '800' },
  pointsArrowSub: { fontSize: 10, color: 'rgba(205,127,50,0.6)', marginTop: 2 },
});
