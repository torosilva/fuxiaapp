// Fuxia 360 · discount at the counter (Mario 2026-10-11): ONE percentage on the whole sale. Up to the seller limit (10 %) she
// applies it alone; above it Carolina approves — her PIN typed here (she is in the store) or a request she approves from
// Fuxia 360 (she is not). Carolina on her own shift: any %. Discounted pairs have no exchange. The server re-prices and
// decides; this only asks and shows its answers.
import React, { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { discountByPin, discountPolicy, discountRequest, discountStatus, type DiscountPolicy, type SaleLines } from '@/lib/f360Store';

export type DiscountValue = { pct: number; reason: string; requestId: string | null; approvedBy: string | null; ready: boolean };
export const NO_DISCOUNT: DiscountValue = { pct: 0, reason: '', requestId: null, approvedBy: null, ready: true };

const money = (n: number) => `$${n.toLocaleString('es-MX', { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 })}`;
const PRESETS = [0, 5, 10];

export function SaleDiscount({ lines, gross, value, onChange }: { lines: SaleLines; gross: number; value: DiscountValue; onChange: (v: DiscountValue) => void }) {
  const [policy, setPolicy] = useState<DiscountPolicy | null>(null);
  const [available, setAvailable] = useState(false);                 // a server without store discounts: the block never shows
  const [other, setOther] = useState(false);
  const [pctText, setPctText] = useState('');
  const [mode, setMode] = useState<'none' | 'pin' | 'waiting'>('none');
  const [pin, setPin] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const poll = useRef<ReturnType<typeof setInterval> | null>(null);
  const linesKey = JSON.stringify(lines);

  useEffect(() => {
    discountPolicy().then((p) => { setPolicy(p); setAvailable(true); }).catch(() => setAvailable(false));
    return () => { if (poll.current) clearInterval(poll.current); };
  }, []);
  // any change to the bag invalidates an approval (the server would refuse it anyway)
  useEffect(() => { if (value.requestId) set(value.pct); }, [linesKey]);   // eslint-disable-line react-hooks/exhaustive-deps

  const max = policy?.seller_max_pct ?? 10;
  const needs = (p: number) => p > max && !policy?.can_any;
  const who = policy?.approvers || 'Carolina';
  const stopPoll = () => { if (poll.current) clearInterval(poll.current); poll.current = null; };
  const set = (p: number, reason = value.reason) => {
    stopPoll(); setMode('none'); setPin(''); setMsg(null);
    onChange({ pct: p, reason, requestId: null, approvedBy: null, ready: !needs(p) });
  };
  const pickPreset = (p: number) => { setOther(false); setPctText(''); set(p); };
  const typeOther = (t: string) => {
    const clean = t.replace(/[^0-9.]/g, '').replace(/^(\d*\.?\d{0,2}).*$/, '$1');
    setPctText(clean);
    const p = Number(clean);
    set(Number.isFinite(p) && p > 0 && p <= 100 ? p : 0);
  };

  const approveByPin = async () => {
    setBusy(true); setMsg(null);
    try {
      const r = await discountByPin(lines, value.pct, value.reason, pin);
      if (r.ok && r.request_id) { setMode('none'); setPin(''); onChange({ ...value, requestId: r.request_id, approvedBy: r.approved_by ?? who, ready: true }); }
      else { setPin(''); setMsg(r.error ?? 'PIN incorrecto.'); }
    } catch (e) { setMsg((e as Error).message); }
    setBusy(false);
  };
  const sendRequest = async () => {
    setBusy(true); setMsg(null);
    try {
      const r = await discountRequest(lines, value.pct, value.reason);
      setMode('waiting');
      stopPoll();
      poll.current = setInterval(async () => {
        try {
          const st = await discountStatus(r.request_id);
          if (st.status === 'approved') { stopPoll(); setMode('none'); onChange({ ...value, requestId: r.request_id, approvedBy: st.decided_by ?? who, ready: true }); }
          else if (st.status !== 'pending') {
            stopPoll(); setMode('none');
            setMsg(st.status === 'rejected' ? `${st.decided_by ?? who} no aprobó el descuento${st.note ? `: ${st.note}` : '.'}` : 'La solicitud venció. Puedes enviarla de nuevo.');
          }
        } catch { /* keep waiting; the next tick retries */ }
      }, 4000);
    } catch (e) { setMsg((e as Error).message); }
    setBusy(false);
  };

  if (!available) return null;
  const disc = Math.round(gross * value.pct) / 100;
  const net = gross - disc;

  return (
    <View style={{ gap: 10 }}>
      <Text style={s.label}>DESCUENTO</Text>
      <View style={s.row}>
        {PRESETS.map((p) => (
          <TouchableOpacity key={p} style={[s.chip, !other && value.pct === p && s.chipOn]} onPress={() => pickPreset(p)}>
            <Text style={[s.chipText, !other && value.pct === p && s.chipTextOn]}>{p === 0 ? 'Sin descuento' : `${p}%`}</Text>
          </TouchableOpacity>))}
        <TouchableOpacity style={[s.chip, other && s.chipOn]} onPress={() => { setOther(true); set(Number(pctText) || 0); }}>
          <Text style={[s.chipText, other && s.chipTextOn]}>Otro</Text>
        </TouchableOpacity>
      </View>
      {other && (
        <View style={s.otherRow}>
          <TextInput value={pctText} onChangeText={typeOther} keyboardType="decimal-pad" placeholder="Ej. 15" placeholderTextColor="rgba(255,255,255,0.35)"
            autoFocus maxLength={6} style={s.otherInput} accessibilityLabel="Porcentaje de descuento" />
          <Text style={s.otherPct}>%</Text>
        </View>
      )}

      {value.pct > 0 && (
        <>
          <View style={s.sum}>
            <View style={s.sumRow}><Text style={s.muted}>Subtotal</Text><Text style={s.sumVal}>{money(gross)}</Text></View>
            <View style={s.sumRow}><Text style={s.muted}>Descuento {value.pct}%</Text><Text style={s.sumVal}>−{money(disc)}</Text></View>
            <View style={s.sumRow}><Text style={s.total}>Total</Text><Text style={s.total}>{money(net)}</Text></View>
            <Text style={s.noExchange}>Con descuento: sin cambio.</Text>
          </View>
          <TextInput value={value.reason} onChangeText={(t) => onChange({ ...value, reason: t.slice(0, 200), requestId: needs(value.pct) ? null : value.requestId, ready: !needs(value.pct) })}
            placeholder="Motivo (opcional)" placeholderTextColor="rgba(255,255,255,0.35)" style={s.input} maxLength={200} editable={mode !== 'waiting'} />
        </>
      )}

      {value.pct > 0 && needs(value.pct) && !value.requestId && (
        <View style={s.approve}>
          <Text style={s.approveTitle}>Más de {max}% lo aprueba {who}</Text>
          {mode === 'none' && (
            <View style={{ gap: 8 }}>
              <TouchableOpacity style={s.btn} disabled={busy} onPress={() => { setMode('pin'); setMsg(null); }}><Text style={s.btnText}>{who} está aquí · su PIN</Text></TouchableOpacity>
              <TouchableOpacity style={s.btnGhost} disabled={busy} onPress={sendRequest}>{busy ? <ActivityIndicator color="#E6C36A" /> : <Text style={s.btnGhostText}>Enviar a {who}</Text>}</TouchableOpacity>
            </View>
          )}
          {mode === 'pin' && (
            <View style={{ gap: 8 }}>
              <Text style={s.muted}>Que {who} escriba su PIN.</Text>
              <TextInput value={pin} onChangeText={(t) => setPin(t.replace(/\D/g, '').slice(0, 8))} keyboardType="number-pad" secureTextEntry autoFocus
                style={[s.input, { letterSpacing: 8, fontSize: 24, textAlign: 'center' }]} accessibilityLabel={`PIN de ${who}`} />
              <View style={s.row}>
                <TouchableOpacity style={[s.btn, { flex: 1 }, (busy || pin.length < 4) && { opacity: 0.5 }]} disabled={busy || pin.length < 4} onPress={approveByPin}>
                  {busy ? <ActivityIndicator color="#0D0D0D" /> : <Text style={s.btnText}>Aprobar</Text>}
                </TouchableOpacity>
                <TouchableOpacity style={s.cancel} onPress={() => { setMode('none'); setPin(''); }}><Text style={s.link}>Cancelar</Text></TouchableOpacity>
              </View>
            </View>
          )}
          {mode === 'waiting' && (
            <View style={s.row}>
              <ActivityIndicator color="#E6C36A" />
              <Text style={[s.muted, { flex: 1 }]}>Esperando a {who}… Le llegó a Fuxia 360 (Avisos).</Text>
              <TouchableOpacity onPress={() => { stopPoll(); setMode('none'); }}><Text style={s.link}>Cancelar</Text></TouchableOpacity>
            </View>
          )}
        </View>
      )}
      {value.pct > 0 && value.approvedBy ? <Text style={s.ok}>Aprobado por {value.approvedBy}</Text> : null}
      {msg && <Text style={s.err}>{msg}</Text>}
    </View>
  );
}

const GOLD = '#B8860B', INK = '#0D0D0D', CARD = '#1A1A1A', MUTED = 'rgba(255,255,255,0.6)';
const s = StyleSheet.create({
  label: { color: MUTED, fontSize: 12, fontWeight: '700', letterSpacing: 1, marginTop: 6 },
  row: { flexDirection: 'row', gap: 8, alignItems: 'center', flexWrap: 'wrap' },
  chip: { height: 48, paddingHorizontal: 16, borderRadius: 14, backgroundColor: CARD, justifyContent: 'center' },
  chipOn: { backgroundColor: '#fff' },
  chipText: { color: '#fff', fontSize: 15, fontWeight: '700' },
  chipTextOn: { color: INK },
  otherRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  otherInput: { flex: 1, backgroundColor: CARD, borderRadius: 14, padding: 14, color: '#fff', fontSize: 22, fontWeight: '700' },
  otherPct: { color: '#fff', fontSize: 22, fontWeight: '700' },
  sum: { backgroundColor: CARD, borderRadius: 16, padding: 16, gap: 6 },
  sumRow: { flexDirection: 'row', justifyContent: 'space-between' },
  sumVal: { color: '#fff', fontSize: 16, fontWeight: '600' },
  total: { color: '#fff', fontSize: 19, fontWeight: '800' },
  noExchange: { color: '#E6C36A', fontSize: 13, fontWeight: '700', marginTop: 4 },
  muted: { color: MUTED, fontSize: 14 },
  input: { backgroundColor: CARD, borderRadius: 14, padding: 14, color: '#fff', fontSize: 16 },
  approve: { backgroundColor: 'rgba(184,134,11,0.14)', borderRadius: 16, padding: 16, gap: 10 },
  approveTitle: { color: '#E6C36A', fontSize: 16, fontWeight: '800' },
  btn: { backgroundColor: GOLD, borderRadius: 14, paddingVertical: 16, alignItems: 'center' },
  btnText: { color: INK, fontSize: 16, fontWeight: '800' },
  btnGhost: { borderWidth: 1, borderColor: GOLD, borderRadius: 14, paddingVertical: 16, alignItems: 'center' },
  btnGhostText: { color: '#E6C36A', fontSize: 16, fontWeight: '700' },
  cancel: { paddingHorizontal: 12, paddingVertical: 14 },
  link: { color: GOLD, fontSize: 15, fontWeight: '600' },
  ok: { color: '#7FD49A', fontSize: 14, fontWeight: '700' },
  err: { color: '#FF8A7A', fontSize: 14, fontWeight: '600' },
});
