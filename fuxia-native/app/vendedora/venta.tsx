// Fuxia 360 · counter sale (design "Registro rápido en caja", Mario 2026-10-08), one screen with five steps:
//   0 · ¿Qué se lleva?  the store's stock by photo → colour → size (pairs here)          [seller]
//   1 · ¿Para quién es? her WhatsApp on a big keypad, or scan her card, or no customer   [seller]
//   2 · Clienta nueva   light screen the seller turns to her: name (+ optional e-mail, size, birthday), privacy
//   3 · Cobrar          her card (first name, last 4, size), pairs, how she paid, optional terminal folio
//   4 · Venta lista     stock already discounted; points credited now or held until she logs in; thank-you WhatsApp
// Price, total, stock, points and the customer link are the server's (f360_record_store_sale_for); the seller only ever
// sees the customer's masked card. Opened from "Apartados" with ?variant=…&para=… the reserved pair is in the bag.
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Alert, Image, KeyboardAvoidingView, Linking, Platform, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, useLocalSearchParams } from 'expo-router';
import { ArrowLeft, Check, Delete, MessageCircle, QrCode, Search, X } from 'lucide-react-native';
import QRScanner from '@/components/QRScanner';
import { currentShift } from '@/lib/sellerSession';
import { customerByCard, findCustomer, newSaleKey, photoUrl, recordSaleFor, registerCustomer, shiftCatalog, thanksWhatsApp,
  type CatalogItem, type MaskedCustomer, type SaleForResult } from '@/lib/f360Store';

type Step = 'pick' | 'who' | 'register' | 'cobro' | 'done';
type Pay = 'cash' | 'card' | 'transfer' | 'other';
const PAGOS: { k: Pay; l: string }[] = [{ k: 'cash', l: 'Efectivo' }, { k: 'card', l: 'Tarjeta' }, { k: 'transfer', l: 'Transferencia' }, { k: 'other', l: 'Otro' }];
const CATS: Record<string, string> = { ballerinas: 'Ballerinas', botas: 'Botas', 'sandalia-alta': 'Sandalias altas', 'sandalia-plana': 'Sandalias planas' };
const POINTS_PER_PAIR = 100;   // Club Fuxia rule (100 per pair); the server's answer is what the done screen shows
const money = (n: number) => `$${n.toLocaleString('es-MX', { maximumFractionDigits: 2 })}`;
const fmtPhone = (d: string) => [d.slice(0, 2), d.slice(2, 6), d.slice(6, 10)].filter(Boolean).join(' ');

export default function VentaF360() {
  const { variant, para } = useLocalSearchParams<{ variant?: string; para?: string }>();
  const shift = currentShift();
  const [step, setStep] = useState<Step>('pick');
  const [items, setItems] = useState<CatalogItem[] | null>(null);
  const [bag, setBag] = useState<Record<string, number>>(variant ? { [variant]: 1 } : {});
  const [q, setQ] = useState('');
  const [cat, setCat] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);              // product_id|color of the expanded card
  const [phone, setPhone] = useState('');                              // 10 digits typed by the seller (never shown back by the server)
  const [looking, setLooking] = useState(false);
  const [isNew, setIsNew] = useState(false);
  const [customer, setCustomer] = useState<MaskedCustomer | null>(null);
  const [reg, setReg] = useState({ name: '', email: '', size: '', day: '', month: '', privacy: false });
  const [pago, setPago] = useState<Pay | null>(null);
  const [folio, setFolio] = useState('');
  const [scanning, setScanning] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<SaleForResult | null>(null);
  const key = useRef(newSaleKey());                                    // one key per sale: a retry or double tap never sells twice

  useEffect(() => {
    if (!shift) { router.replace('/vendedora' as any); return; }
    shiftCatalog().then((c) => setItems(c.items ?? [])).catch((e) => Alert.alert('No se pudo cargar', e.message));
  }, []);

  const byId = useMemo(() => Object.fromEntries((items ?? []).map((i) => [i.variant_id, i])), [items]);
  const free = (i: CatalogItem) => Math.max(0, i.available - (i.reserved ?? 0)) + (variant === i.variant_id ? 1 : 0);
  const groups = useMemo(() => {
    const t = q.trim().toLowerCase();
    const m = new Map<string, CatalogItem[]>();
    for (const i of items ?? []) {
      if (cat && i.category !== cat) continue;
      if (t && !`${i.product_name} ${i.color} ${i.size}`.toLowerCase().includes(t)) continue;
      const k = `${i.product_id ?? i.product_name}|${i.color}`;
      m.set(k, [...(m.get(k) ?? []), i]);
    }
    return [...m.entries()].map(([k, list]) => ({ k, list: list.sort((a, b) => a.size.localeCompare(b.size, 'es', { numeric: true })), first: list[0] }));
  }, [items, q, cat]);
  const cats = useMemo(() => [...new Set((items ?? []).map((i) => i.category).filter(Boolean) as string[])], [items]);
  const lines = Object.entries(bag).filter(([id, n]) => n > 0 && byId[id]);
  const pairs = lines.reduce((a, [, n]) => a + n, 0);
  const total = lines.reduce((a, [id, n]) => a + Number(byId[id]?.price ?? 0) * n, 0);
  const add = (i: CatalogItem) => setBag((b) => ({ ...b, [i.variant_id]: Math.min((b[i.variant_id] ?? 0) + 1, free(i)) }));
  const remove = (id: string) => setBag((b) => { const n = { ...b }; delete n[id]; return n; });

  const lookUp = async (digits: string) => {
    setLooking(true); setIsNew(false);
    try {
      const r = await findCustomer(digits);
      if (r.found && r.customer) { setCustomer(r.customer); setStep('cobro'); } else setIsNew(true);
    } catch (e) { Alert.alert('No se pudo buscar', (e as Error).message); }
    setLooking(false);
  };
  const press = (k: string) => {
    if (looking) return;
    if (k === 'back') { setPhone((p) => p.slice(0, -1)); setIsNew(false); return; }
    if (phone.length >= 10) return;
    const next = phone + k; setPhone(next);
    if (next.length === 10) lookUp(next);
  };
  const onCard = async (data: string) => {
    setScanning(false);
    try { const r = await customerByCard(data); if (r.customer) { setCustomer(r.customer); setPhone(''); setStep('cobro'); } }
    catch (e) { Alert.alert('Tarjeta', (e as Error).message); }
  };
  const register = async () => {
    const day = reg.day ? Number(reg.day) : null, month = reg.month ? Number(reg.month) : null;
    setBusy(true);
    try {
      const r = await registerCustomer({ phone, name: reg.name, email: reg.email, size: reg.size, birthdayDay: day, birthdayMonth: month });
      if (r.customer) { setCustomer(r.customer); setStep('cobro'); }
    } catch (e) { Alert.alert('Revisa los datos', (e as Error).message); }
    setBusy(false);
  };
  const cobrar = async () => {
    if (!pago) { Alert.alert('Falta el pago', 'Elige cómo pagó la clienta.'); return; }
    setBusy(true);
    try {
      setDone(await recordSaleFor(key.current, lines.map(([variant_id, quantity]) => ({ variant_id, quantity })), pago, folio.trim() || null, customer?.customer_ref ?? null));
      setStep('done');
    } catch (e) { Alert.alert('No se registró la venta', (e as Error).message); }
    setBusy(false);
  };
  const nueva = () => {
    key.current = newSaleKey();
    setBag({}); setPhone(''); setCustomer(null); setIsNew(false); setPago(null); setFolio(''); setDone(null); setOpen(null); setQ('');
    setReg({ name: '', email: '', size: '', day: '', month: '', privacy: false });
    setStep('pick');
    shiftCatalog().then((c) => setItems(c.items ?? [])).catch(() => {});
  };
  const back = () => {
    if (step === 'pick') router.back();
    else if (step === 'who') setStep('pick');
    else if (step === 'register') setStep('who');
    else if (step === 'cobro') setStep('who');
  };
  if (!shift) return null;

  const header = (title: string) => (
    <View style={s.top}>
      {step !== 'done' && <TouchableOpacity onPress={back} style={s.back} accessibilityLabel="Regresar"><ArrowLeft size={20} color="#fff" /></TouchableOpacity>}
      <View style={{ flexShrink: 1 }}>
        <Text style={s.kicker}>{shift.location.name.toUpperCase()} · {(shift.person || 'Vendedora').toUpperCase()}</Text>
        <Text style={s.title}>{title}</Text>
      </View>
    </View>
  );

  // ── 2 · the customer's own screen (light) ────────────────────────────────────────────────────────────────
  if (step === 'register') {
    const ok = reg.name.trim().length >= 2 && reg.privacy && !busy;
    return (
      <SafeAreaView style={[s.container, { backgroundColor: '#F6EFE4' }]}>
        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
          <ScrollView contentContainerStyle={[s.page, { gap: 18 }]} keyboardShouldPersistTaps="handled">
            <TouchableOpacity onPress={back} style={[s.back, { backgroundColor: 'rgba(29,29,27,0.06)' }]} accessibilityLabel="Regresar"><ArrowLeft size={20} color="#1D1D1B" /></TouchableOpacity>
            <Text style={s.lBrand}>FUXIA</Text>
            <Text style={s.lTitle}>Suma {pairs * POINTS_PER_PAIR} puntos{'\n'}con esta compra</Text>
            <Text style={s.lSub}>Escribe tu nombre y te mandamos por WhatsApp tu tarjeta del Club Fuxia.</Text>
            <Text style={s.lLabel}>Tu WhatsApp</Text>
            <View style={[s.lInput, { backgroundColor: '#EFE6D6' }]}><Text style={s.lInputText}>+52 {fmtPhone(phone)}</Text></View>
            <Text style={s.lLabel}>Tu nombre</Text>
            <TextInput value={reg.name} onChangeText={(v) => setReg({ ...reg, name: v })} autoFocus autoCapitalize="words" style={[s.lInput, s.lInputText, { borderColor: '#1D1D1B', borderWidth: 2 }]} accessibilityLabel="Tu nombre" />
            <Text style={s.lLabel}>Correo (opcional)</Text>
            <TextInput value={reg.email} onChangeText={(v) => setReg({ ...reg, email: v })} keyboardType="email-address" autoCapitalize="none" placeholder="nombre@correo.com" placeholderTextColor="#A39886" style={[s.lInput, s.lInputText]} accessibilityLabel="Correo, opcional" />
            <View style={{ flexDirection: 'row', gap: 12 }}>
              <View style={{ flex: 1, gap: 8 }}>
                <Text style={s.lLabel}>Tu talla (opcional)</Text>
                <TextInput value={reg.size} onChangeText={(v) => setReg({ ...reg, size: v.replace(/[^0-9.]/g, '') })} keyboardType="decimal-pad" maxLength={4} style={[s.lInput, s.lInputText]} accessibilityLabel="Tu talla, opcional" />
              </View>
              <View style={{ flex: 1, gap: 8 }}>
                <Text style={s.lLabel}>Cumpleaños (opcional)</Text>
                <View style={{ flexDirection: 'row', gap: 8 }}>
                  <TextInput value={reg.day} onChangeText={(v) => setReg({ ...reg, day: v.replace(/\D/g, '') })} keyboardType="number-pad" maxLength={2} placeholder="día" placeholderTextColor="#A39886" style={[s.lInput, s.lInputText, { flex: 1 }]} accessibilityLabel="Día de cumpleaños" />
                  <TextInput value={reg.month} onChangeText={(v) => setReg({ ...reg, month: v.replace(/\D/g, '') })} keyboardType="number-pad" maxLength={2} placeholder="mes" placeholderTextColor="#A39886" style={[s.lInput, s.lInputText, { flex: 1 }]} accessibilityLabel="Mes de cumpleaños" />
                </View>
              </View>
            </View>
            <TouchableOpacity onPress={() => setReg({ ...reg, privacy: !reg.privacy })} style={s.lCheckRow} accessibilityRole="checkbox" accessibilityState={{ checked: reg.privacy }}>
              <View style={[s.lCheck, reg.privacy && { backgroundColor: '#1D1D1B' }]}>{reg.privacy && <Check size={18} color="#F6EFE4" />}</View>
              <Text style={s.lCheckText}>Acepto el <Text style={{ textDecorationLine: 'underline' }} onPress={() => router.push('/privacy' as any)}>aviso de privacidad</Text> de Fuxia Ballerinas.</Text>
            </TouchableOpacity>
            <TouchableOpacity disabled={!ok} onPress={register} style={[s.lCta, !ok && { opacity: 0.4 }]}>
              {busy ? <ActivityIndicator color="#F6EFE4" /> : <Text style={s.lCtaText}>Listo</Text>}
            </TouchableOpacity>
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    );
  }

  // ── 4 · done ────────────────────────────────────────────────────────────────────────────────────────────
  if (step === 'done' && done) {
    const name = done.customer?.first_name ?? customer?.first_name ?? null;
    const pts = Number(done.points ?? 0);
    return (
      <SafeAreaView style={s.container}>
        <ScrollView contentContainerStyle={[s.page, { alignItems: 'center', gap: 14, paddingTop: 40 }]}>
          <View style={s.okCircle}><Check size={56} color="#0D0D0D" /></View>
          <Text style={s.okKicker}>VENTA REGISTRADA</Text>
          <Text style={s.okTotal}>{money(Number(done.total))}</Text>
          <Text style={s.okSub}>{name ? `Para ${name} · ` : ''}{pairs} {pairs === 1 ? 'par descontado' : 'pares descontados'} de {shift.location.name}</Text>
          {name ? (
            <View style={s.info}>
              <Text style={s.infoBig}>+{pts}</Text>
              <View style={{ flex: 1 }}>
                <Text style={s.infoTitle}>{done.points_state === 'held' ? `Puntos guardados para ${name}` : `Puntos acreditados a ${name}`}</Text>
                <Text style={s.infoSub}>{done.points_state === 'held' ? 'Se le acreditan en cuanto entre a la app con su WhatsApp.' : 'Ya están en su tarjeta del Club Fuxia.'}</Text>
              </View>
            </View>
          ) : done.code ? (
            <View style={s.info}><View style={{ flex: 1 }}>
              <Text style={s.infoTitle}>Código para que la clienta sume sus puntos</Text>
              <Text style={[s.infoBig, { fontSize: 28, letterSpacing: 3 }]}>{done.code}</Text>
            </View></View>
          ) : null}
          {name && phone.length === 10 && (
            <TouchableOpacity style={s.ghost} onPress={() => Linking.openURL(thanksWhatsApp(phone, name, shift.location.name, done.points_state === 'held' ? pts : 0))}>
              <MessageCircle size={20} color="#E6C36A" /><Text style={s.ghostText}>Mandarle el WhatsApp de gracias</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={[s.cta, { alignSelf: 'stretch', marginTop: 10 }]} onPress={nueva}><Text style={s.ctaText}>Nueva venta</Text></TouchableOpacity>
          <TouchableOpacity onPress={() => router.replace('/vendedora/tienda' as any)}><Text style={s.link}>Volver al inicio de la tienda</Text></TouchableOpacity>
        </ScrollView>
      </SafeAreaView>
    );
  }

  // ── 3 · cobrar ─────────────────────────────────────────────────────────────────────────────────────────
  if (step === 'cobro') {
    return (
      <SafeAreaView style={s.container}>
        {header('Cobrar')}
        <ScrollView contentContainerStyle={[s.page, { gap: 14 }]} keyboardShouldPersistTaps="handled">
          {customer ? (
            <View style={s.custCard}>
              <View style={s.avatar}><Text style={s.avatarText}>{customer.first_name.slice(0, 1)}</Text></View>
              <View style={{ flex: 1 }}>
                <Text style={s.custName}>{customer.first_name}</Text>
                <Text style={s.custSub}>WhatsApp ···{customer.phone_last4} · {customer.tier[0].toUpperCase() + customer.tier.slice(1)} · {customer.points} pts</Text>
              </View>
              {customer.shoe_size ? <View style={{ alignItems: 'center' }}><Text style={s.sizeLabel}>TALLA</Text><Text style={s.sizeBig}>{customer.shoe_size}</Text></View> : null}
            </View>
          ) : <Text style={s.muted}>Venta sin clienta: se da un código para que sume sus puntos después.</Text>}
          {para ? <Text style={s.banner}>Apartado de {para}: ligado a ella para entregarle su par.</Text> : null}
          {lines.map(([id, n]) => { const i = byId[id]; return (
            <View key={id} style={s.line}>
              <View style={{ flex: 1 }}><Text style={s.lineName}>{i.product_name}</Text><Text style={s.lineSub}>{i.color} · talla {i.size}{n > 1 ? ` · ${n} pares` : ''}</Text></View>
              <Text style={s.linePrice}>{money(Number(i.price) * n)}</Text>
            </View>); })}
          {customer && <View style={s.ptsRow}><Text style={s.muted}>Puntos de esta compra</Text><Text style={s.pts}>+{pairs * POINTS_PER_PAIR}</Text></View>}
          <Text style={s.label}>¿CÓMO PAGÓ?</Text>
          <View style={s.pagos}>
            {PAGOS.map((p) => (
              <TouchableOpacity key={p.k} style={[s.pago, pago === p.k && s.pagoOn]} onPress={() => setPago(p.k)}>
                <Text style={[s.pagoText, pago === p.k && { color: '#0D0D0D' }]}>{p.l}</Text>
              </TouchableOpacity>))}
          </View>
          <Text style={s.label}>FOLIO DE LA TERMINAL (OPCIONAL)</Text>
          <TextInput value={folio} onChangeText={setFolio} placeholder="Ej. 004518" placeholderTextColor="rgba(255,255,255,0.35)" maxLength={20} style={s.input} />
        </ScrollView>
        <View style={s.footer}>
          <TouchableOpacity style={[s.cta, (busy || !pago) && { opacity: 0.5 }]} disabled={busy} onPress={cobrar}>
            {busy ? <ActivityIndicator color="#0D0D0D" /> : <Text style={s.ctaText}>Cobrar {money(total)}</Text>}
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  // ── 1 · ¿para quién es? ───────────────────────────────────────────────────────────────────────────────
  if (step === 'who') {
    return (
      <SafeAreaView style={s.container}>
        {header('¿Para quién es?')}
        <ScrollView contentContainerStyle={[s.page, { gap: 14 }]}>
          <Text style={s.muted}>Su WhatsApp. Si ya es clienta aparece sola; si es nueva, le pasas el teléfono.</Text>
          <View style={s.phoneBox}>
            <Text style={s.phonePrefix}>+52</Text>
            <Text style={[s.phoneText, !phone && { color: 'rgba(255,255,255,0.25)' }]}>{phone ? fmtPhone(phone) : '55 1234 5678'}</Text>
            {looking && <ActivityIndicator color="#B8860B" />}
          </View>
          <View style={s.keys}>
            {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((k) => (
              <TouchableOpacity key={k} style={s.key} onPress={() => press(k)}><Text style={s.keyText}>{k}</Text></TouchableOpacity>))}
            <TouchableOpacity style={[s.key, s.keyGold]} onPress={() => setScanning(true)} accessibilityLabel="Escanear tarjeta"><QrCode size={22} color="#B8860B" /><Text style={s.keySmall}>Tarjeta</Text></TouchableOpacity>
            <TouchableOpacity style={s.key} onPress={() => press('0')}><Text style={s.keyText}>0</Text></TouchableOpacity>
            <TouchableOpacity style={s.key} onPress={() => press('back')} accessibilityLabel="Borrar"><Delete size={24} color="#fff" /></TouchableOpacity>
          </View>
          {isNew && (
            <View style={s.newBox}>
              <Text style={s.newTitle}>Clienta nueva</Text>
              <Text style={s.newSub}>Ese número no está registrado. Pásale el teléfono para que escriba su nombre.</Text>
            </View>
          )}
        </ScrollView>
        <View style={s.footer}>
          {isNew && <TouchableOpacity style={s.cta} onPress={() => setStep('register')}><Text style={s.ctaText}>Pasarle el teléfono a la clienta</Text></TouchableOpacity>}
          <TouchableOpacity onPress={() => { setCustomer(null); setPhone(''); setStep('cobro'); }}><Text style={[s.link, { textAlign: 'center', paddingVertical: 10 }]}>Venta sin clienta</Text></TouchableOpacity>
        </View>
        <QRScanner visible={scanning} onScan={onCard} onClose={() => setScanning(false)} />
      </SafeAreaView>
    );
  }

  // ── 0 · ¿qué se lleva? ───────────────────────────────────────────────────────────────────────────────
  return (
    <SafeAreaView style={s.container}>
      {header('¿Qué se lleva?')}
      <View style={[s.pageX, { gap: 10 }]}>
        <View style={s.searchBox}>
          <Search size={20} color="rgba(255,255,255,0.45)" />
          <TextInput value={q} onChangeText={setQ} placeholder="Busca modelo, color o talla" placeholderTextColor="rgba(255,255,255,0.35)" style={s.searchInput} />
          {q ? <TouchableOpacity onPress={() => setQ('')} accessibilityLabel="Borrar búsqueda"><X size={18} color="rgba(255,255,255,0.5)" /></TouchableOpacity> : null}
        </View>
        {cats.length > 1 && (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
            {[null, ...cats].map((c) => (
              <TouchableOpacity key={c ?? 'all'} onPress={() => setCat(c)} style={[s.chip, cat === c && s.chipOn]}>
                <Text style={[s.chipText, cat === c && { color: '#0D0D0D' }]}>{c ? CATS[c] ?? c : 'Todo'}</Text>
              </TouchableOpacity>))}
          </ScrollView>
        )}
      </View>
      {para ? <Text style={[s.banner, { marginHorizontal: 20 }]}>Apartado de {para}: el par ya está en la bolsa.</Text> : null}
      <ScrollView contentContainerStyle={[s.page, { gap: 10, paddingTop: 10 }]} keyboardShouldPersistTaps="handled">
        {items === null && <ActivityIndicator color="#B8860B" style={{ marginTop: 30 }} />}
        {items && groups.length === 0 && <Text style={[s.muted, { textAlign: 'center', marginTop: 30 }]}>{q || cat ? 'Nada con esa búsqueda.' : 'No hay pares en esta tienda.'}</Text>}
        {groups.map(({ k, list, first }) => {
          const isOpen = open === k || groups.length === 1;
          const img = photoUrl(first.image);
          const inBag = list.reduce((a, i) => a + (bag[i.variant_id] ?? 0), 0);
          return (
            <View key={k} style={[s.model, isOpen && s.modelOpen]}>
              <TouchableOpacity style={s.modelHead} onPress={() => setOpen(isOpen ? null : k)} activeOpacity={0.8}>
                {img ? <Image source={{ uri: img }} style={s.photo} /> : <View style={[s.photo, { backgroundColor: first.color_hex ?? '#2A2A2A' }]} />}
                <View style={{ flex: 1 }}>
                  <Text style={s.modelName}>{first.product_name}</Text>
                  <View style={s.row}>
                    <View style={[s.dot, { backgroundColor: first.color_hex ?? '#777' }]} />
                    <Text style={s.modelSub}>{first.color} · {first.price != null ? money(Number(first.price)) : 'sin precio'}</Text>
                  </View>
                </View>
                {inBag > 0 ? <Text style={s.inBag}>{inBag} en la bolsa</Text> : !isOpen ? <Text style={s.muted}>Ver tallas</Text> : null}
              </TouchableOpacity>
              {isOpen && (
                <>
                  <Text style={s.label}>TALLA · PARES EN {shift.location.name.toUpperCase()}</Text>
                  <View style={s.sizes}>
                    {list.map((i) => { const n = bag[i.variant_id] ?? 0; const f = free(i); const on = n > 0; return (
                      <TouchableOpacity key={i.variant_id} disabled={f === 0 || i.price == null} onPress={() => add(i)} onLongPress={() => remove(i.variant_id)}
                        style={[s.size, on && s.sizeOn, (f === 0 || i.price == null) && { opacity: 0.35 }]} accessibilityLabel={`Talla ${i.size}, ${f} pares`}>
                        <Text style={[s.sizeN, on && { color: '#0D0D0D' }]}>{i.size}</Text>
                        <Text style={[s.sizeF, on && { color: '#0D0D0D' }]}>{on ? `${n} en bolsa` : f === 1 ? '1 par' : `${f} pares`}</Text>
                      </TouchableOpacity>); })}
                  </View>
                  <Text style={s.hint}>Toca la talla para agregarla. Déjala presionada para quitarla.</Text>
                </>
              )}
            </View>
          );
        })}
      </ScrollView>
      {pairs > 0 && (
        <View style={s.bagBar}>
          <View style={{ flex: 1 }}>
            <Text style={s.bagKicker}>EN LA BOLSA · {pairs} {pairs === 1 ? 'PAR' : 'PARES'}</Text>
            <Text style={s.bagText} numberOfLines={1}>{lines.map(([id]) => `${byId[id].product_name} ${byId[id].color} ${byId[id].size}`).join(' · ')}</Text>
          </View>
          <TouchableOpacity style={s.bagCta} onPress={() => setStep('who')}><Text style={s.ctaText}>Siguiente · {money(total)}</Text></TouchableOpacity>
        </View>
      )}
    </SafeAreaView>
  );
}

const GOLD = '#B8860B', INK = '#0D0D0D', CARD = '#1A1A1A', MUTED = 'rgba(255,255,255,0.6)';
const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: INK },
  page: { padding: 20, paddingBottom: 40, width: '100%', maxWidth: 820, alignSelf: 'center' },
  pageX: { paddingHorizontal: 20, width: '100%', maxWidth: 820, alignSelf: 'center' },
  top: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 20, paddingBottom: 10, width: '100%', maxWidth: 820, alignSelf: 'center' },
  back: { width: 44, height: 44, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.06)', alignItems: 'center', justifyContent: 'center' },
  kicker: { color: GOLD, fontSize: 11, fontWeight: '800', letterSpacing: 2 },
  title: { color: '#fff', fontSize: 26, fontWeight: '700' },
  muted: { color: MUTED, fontSize: 14 },
  label: { color: MUTED, fontSize: 12, fontWeight: '700', letterSpacing: 1, marginTop: 6 },
  link: { color: GOLD, fontSize: 15, fontWeight: '600' },
  banner: { padding: 12, borderRadius: 12, backgroundColor: 'rgba(184,134,11,0.15)', color: '#E6C36A', fontSize: 13 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  searchBox: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: CARD, borderRadius: 14, paddingHorizontal: 16, height: 56 },
  searchInput: { flex: 1, color: '#fff', fontSize: 17 },
  chip: { height: 40, paddingHorizontal: 16, borderRadius: 20, backgroundColor: CARD, justifyContent: 'center' },
  chipOn: { backgroundColor: '#fff' },
  chipText: { color: '#fff', fontSize: 14, fontWeight: '600' },
  model: { backgroundColor: CARD, borderRadius: 18, padding: 14, gap: 10, borderWidth: 2, borderColor: 'transparent' },
  modelOpen: { borderColor: GOLD },
  modelHead: { flexDirection: 'row', alignItems: 'center', gap: 14 },
  photo: { width: 72, height: 72, borderRadius: 12, backgroundColor: '#2A2A2A' },
  modelName: { color: '#fff', fontSize: 17, fontWeight: '700' },
  modelSub: { color: 'rgba(255,255,255,0.75)', fontSize: 14 },
  dot: { width: 14, height: 14, borderRadius: 7, borderWidth: 1, borderColor: 'rgba(255,255,255,0.3)' },
  inBag: { color: '#E6C36A', fontSize: 13, fontWeight: '700' },
  sizes: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  size: { width: 76, height: 66, borderRadius: 12, backgroundColor: '#262626', alignItems: 'center', justifyContent: 'center' },
  sizeOn: { backgroundColor: GOLD },
  sizeN: { color: '#fff', fontSize: 20, fontWeight: '800' },
  sizeF: { color: MUTED, fontSize: 11, fontWeight: '600' },
  hint: { color: 'rgba(255,255,255,0.4)', fontSize: 12 },
  bagBar: { flexDirection: 'row', alignItems: 'center', gap: 12, margin: 12, padding: 12, paddingLeft: 18, borderRadius: 18, backgroundColor: CARD, width: '94%', maxWidth: 800, alignSelf: 'center' },
  bagKicker: { color: GOLD, fontSize: 11, fontWeight: '800', letterSpacing: 1 },
  bagText: { color: '#fff', fontSize: 14, marginTop: 2 },
  bagCta: { backgroundColor: GOLD, borderRadius: 14, paddingVertical: 16, paddingHorizontal: 18 },
  phoneBox: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: CARD, borderWidth: 2, borderColor: GOLD, borderRadius: 18, padding: 18 },
  phonePrefix: { color: MUTED, fontSize: 26, fontWeight: '600' },
  phoneText: { flex: 1, color: '#fff', fontSize: 32, fontWeight: '700', letterSpacing: 1 },
  keys: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, justifyContent: 'space-between' },
  key: { width: '31.5%', height: 74, borderRadius: 16, backgroundColor: CARD, alignItems: 'center', justifyContent: 'center' },
  keyGold: { borderWidth: 1, borderColor: GOLD, backgroundColor: 'transparent', gap: 2 },
  keyText: { color: '#fff', fontSize: 30, fontWeight: '600' },
  keySmall: { color: GOLD, fontSize: 12, fontWeight: '700' },
  newBox: { backgroundColor: 'rgba(184,134,11,0.14)', borderRadius: 16, padding: 16, gap: 4 },
  newTitle: { color: '#E6C36A', fontSize: 17, fontWeight: '700' },
  newSub: { color: '#D9D2C5', fontSize: 14 },
  footer: { padding: 16, gap: 6, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.08)', width: '100%', maxWidth: 820, alignSelf: 'center' },
  cta: { backgroundColor: GOLD, borderRadius: 16, paddingVertical: 20, alignItems: 'center' },
  ctaText: { color: INK, fontSize: 18, fontWeight: '800' },
  custCard: { flexDirection: 'row', alignItems: 'center', gap: 16, backgroundColor: CARD, borderWidth: 2, borderColor: GOLD, borderRadius: 20, padding: 18 },
  avatar: { width: 60, height: 60, borderRadius: 30, backgroundColor: GOLD, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: INK, fontSize: 26, fontWeight: '800' },
  custName: { color: '#fff', fontSize: 22, fontWeight: '700' },
  custSub: { color: MUTED, fontSize: 14, marginTop: 2 },
  sizeLabel: { color: MUTED, fontSize: 11, fontWeight: '700' },
  sizeBig: { color: '#E6C36A', fontSize: 34, fontWeight: '800' },
  line: { flexDirection: 'row', alignItems: 'center', backgroundColor: CARD, borderRadius: 16, padding: 16 },
  lineName: { color: '#fff', fontSize: 16, fontWeight: '700' },
  lineSub: { color: MUTED, fontSize: 14, marginTop: 2 },
  linePrice: { color: '#fff', fontSize: 17, fontWeight: '700' },
  ptsRow: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 4 },
  pts: { color: '#E6C36A', fontSize: 16, fontWeight: '800' },
  pagos: { flexDirection: 'row', gap: 8 },
  pago: { flex: 1, height: 58, borderRadius: 14, backgroundColor: CARD, alignItems: 'center', justifyContent: 'center' },
  pagoOn: { backgroundColor: '#fff' },
  pagoText: { color: '#fff', fontSize: 14, fontWeight: '700' },
  input: { backgroundColor: CARD, borderRadius: 14, padding: 16, color: '#fff', fontSize: 17 },
  okCircle: { width: 104, height: 104, borderRadius: 52, backgroundColor: GOLD, alignItems: 'center', justifyContent: 'center' },
  okKicker: { color: GOLD, fontSize: 13, fontWeight: '800', letterSpacing: 3 },
  okTotal: { color: '#fff', fontSize: 52, fontWeight: '700' },
  okSub: { color: '#D9D2C5', fontSize: 16, textAlign: 'center' },
  info: { flexDirection: 'row', alignItems: 'center', gap: 16, backgroundColor: CARD, borderRadius: 18, padding: 18, alignSelf: 'stretch' },
  infoBig: { color: '#E6C36A', fontSize: 32, fontWeight: '800' },
  infoTitle: { color: '#fff', fontSize: 16, fontWeight: '700' },
  infoSub: { color: MUTED, fontSize: 14, marginTop: 2 },
  ghost: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 10, alignSelf: 'stretch', borderWidth: 1, borderColor: GOLD, borderRadius: 16, paddingVertical: 18 },
  ghostText: { color: '#E6C36A', fontSize: 16, fontWeight: '700' },
  lBrand: { color: '#6B5A2E', fontSize: 22, fontWeight: '600', letterSpacing: 8, textAlign: 'center' },
  lTitle: { color: '#1D1D1B', fontSize: 36, fontWeight: '500', textAlign: 'center', lineHeight: 42, fontFamily: Platform.OS === 'ios' ? 'Georgia' : 'serif' },
  lSub: { color: '#5E574C', fontSize: 16, textAlign: 'center', lineHeight: 23 },
  lLabel: { color: '#5E574C', fontSize: 13, fontWeight: '700' },
  lInput: { minHeight: 60, borderRadius: 14, borderWidth: 1.5, borderColor: '#D8C9AE', backgroundColor: '#FFFDF9', paddingHorizontal: 18, justifyContent: 'center' },
  lInputText: { color: '#1D1D1B', fontSize: 20, fontWeight: '600' },
  lCheckRow: { flexDirection: 'row', gap: 12, alignItems: 'center', paddingVertical: 6 },
  lCheck: { width: 30, height: 30, borderRadius: 8, borderWidth: 2, borderColor: '#1D1D1B', alignItems: 'center', justifyContent: 'center' },
  lCheckText: { flex: 1, color: '#1D1D1B', fontSize: 15, lineHeight: 21 },
  lCta: { backgroundColor: '#1D1D1B', borderRadius: 16, paddingVertical: 20, alignItems: 'center', marginTop: 6 },
  lCtaText: { color: '#F6EFE4', fontSize: 20, fontWeight: '800' },
});
