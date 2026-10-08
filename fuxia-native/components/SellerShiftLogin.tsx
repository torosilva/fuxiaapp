// S0.2 shift start: the seller is ALREADY logged in with her own account. She picks one of HER locations (from the
// server) and enters her PIN; the server verifies everything and returns an opaque shift token.
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { router } from 'expo-router';
import { myShiftLocations, startShift, type ShiftLocation } from '@/lib/sellerSession';

const PIN_LENGTH = 4;
const KEYS = [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', 'back']];

export default function SellerShiftLogin() {
  const [locations, setLocations] = useState<ShiftLocation[] | null>(null);
  const [loadError, setLoadError] = useState('');
  const [selected, setSelected] = useState<ShiftLocation | null>(null);
  const [pin, setPin] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    myShiftLocations()
      .then((ls) => { setLocations(ls); if (ls.length === 1) setSelected(ls[0]); })
      .catch(() => setLoadError('Tu cuenta no tiene acceso de vendedora. Pídele a Carolina o Mario que te asignen una tienda.'));
  }, []);

  const press = async (k: string) => {
    if (busy || !selected) return;
    if (k === 'back') { setPin((p) => p.slice(0, -1)); setError(''); return; }
    if (!k) return;
    const next = pin + k;
    setPin(next);
    if (next.length < PIN_LENGTH) return;
    setBusy(true); setError('');
    const r = await startShift(selected.id, next);
    setBusy(false); setPin('');
    if (!r.ok) { setError(r.error); return; }
    if (r.shift.location.ledger_authority === 'f360') {
      // The store's stock lives in Fuxia 360 (e.g. Tienda Polanco): sale, inventory and Gold reservations from there.
      router.replace('/vendedora/tienda' as any);
      return;
    }
    if (!r.shift.location.legacy_channel_id) {
      setError('Turno iniciado, pero la venta en esta ubicación todavía no está habilitada.');
      return;
    }
    router.push({
      pathname: '/vendedora/home' as any,
      params: {
        staffId: '', staffName: r.shift.person, channelId: r.shift.location.legacy_channel_id,
        channelName: r.shift.location.name, channelType: r.shift.location.type === 'bazaar' ? 'bazar' : 'store',
      },
    });
  };

  if (loadError) return <View style={s.center}><Text style={s.error}>{loadError}</Text></View>;
  if (!locations) return <View style={s.center}><ActivityIndicator color="#B8860B" /></View>;
  if (locations.length === 0) return <View style={s.center}><Text style={s.error}>No tienes ninguna tienda asignada todavía.</Text></View>;

  return (
    <View style={s.wrap}>
      {!selected ? (
        <>
          <Text style={s.title}>¿Dónde trabajas hoy?</Text>
          {locations.map((l) => (
            <TouchableOpacity key={l.id} style={s.loc} onPress={() => setSelected(l)} accessibilityLabel={`Ubicación ${l.name}`}>
              <Text style={s.locText}>{l.name}</Text>
            </TouchableOpacity>
          ))}
        </>
      ) : (
        <>
          <Text style={s.title}>{selected.name}</Text>
          {locations.length > 1 && <TouchableOpacity onPress={() => { setSelected(null); setPin(''); setError(''); }}><Text style={s.link}>Cambiar ubicación</Text></TouchableOpacity>}
          <Text style={s.sub}>Escribe tu PIN</Text>
          <View style={s.dots}>{Array.from({ length: PIN_LENGTH }).map((_, i) => <View key={i} style={[s.dot, i < pin.length && s.dotOn]} />)}</View>
          {busy && <ActivityIndicator color="#B8860B" />}
          {!!error && <Text style={s.error}>{error}</Text>}
          {KEYS.map((row, r) => (
            <View key={r} style={s.row}>
              {row.map((k, i) => (
                <TouchableOpacity key={i} style={[s.key, !k && { opacity: 0 }]} disabled={!k} onPress={() => press(k)} accessibilityLabel={k === 'back' ? 'Borrar' : k}>
                  <Text style={s.keyText}>{k === 'back' ? '⌫' : k}</Text>
                </TouchableOpacity>
              ))}
            </View>
          ))}
        </>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, padding: 24, alignItems: 'center', justifyContent: 'center' },
  center: { flex: 1, padding: 24, alignItems: 'center', justifyContent: 'center' },
  title: { color: '#F5F0E8', fontSize: 26, marginBottom: 12, textAlign: 'center' },
  sub: { color: '#B8B0A2', marginVertical: 12 },
  link: { color: '#B8860B', marginBottom: 8 },
  loc: { width: '100%', borderWidth: 1, borderColor: '#3A352D', borderRadius: 14, padding: 18, marginVertical: 6 },
  locText: { color: '#F5F0E8', fontSize: 18 },
  dots: { flexDirection: 'row', gap: 14, marginBottom: 16 },
  dot: { width: 14, height: 14, borderRadius: 7, borderWidth: 1, borderColor: '#B8860B' },
  dotOn: { backgroundColor: '#B8860B' },
  error: { color: '#E07A6A', textAlign: 'center', marginVertical: 8 },
  row: { flexDirection: 'row', gap: 18, marginVertical: 8 },
  key: { width: 72, height: 72, borderRadius: 36, backgroundColor: '#1C1A17', alignItems: 'center', justifyContent: 'center' },
  keyText: { color: '#F5F0E8', fontSize: 26 },
});
