// Fuxia 360 · store operations from the app: the seller's shift catalog, sale and Gold reservations ("apartados"), and
// the customer's "Entrega inmediata" / "Apartar 2 horas". Every rule (price, stock, reservations, Gold, 2 pairs, 2 hours)
// is enforced by the server; the app only sends ids and quantities. The shift token comes from lib/sellerSession.
import { supabase } from '@/lib/supabase';
import { currentShift } from '@/lib/sellerSession';
import { alertNow } from '@/lib/notifications';

// Customer-side reservations are only offered by builds pointing at a database with Fuxia 360 (staging for now).
export const F360_RESERVE = process.env.EXPO_PUBLIC_F360_RESERVE === '1';

export type CatalogItem = { variant_id: string; product_name: string; color: string; color_hex: string | null; size: string; sku: string; price: number | null; available: number; reserved: number };
export type ShiftReservation = {
  id: string; variant_id: string; product: string; color: string; color_hex: string | null; size: string; sku: string;
  customer: string; phone_last4: string; channel: 'app' | 'web' | 'tienda';
  status: 'activa' | 'vendida' | 'vencida' | 'cancelada'; created_at: string; expires_at: string;
  separated_at: string | null; separated_by: string | null; closed_at: string | null; closed_by: string | null;
};
export type SaleResult = { ok: true; total: number; points: number; claimed: boolean; code: string | null; location: string };
export type StoreOption = { location_id: string; name: string };

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data as T;
}
function token() {
  const s = currentShift();
  if (!s) throw new Error('No hay turno activo. Vuelve a iniciar turno.');
  return s.token;
}

export const shiftCatalog = () => call<{ location: string; ledger: string; items: CatalogItem[] }>('f360_shift_catalog', { p_token: token() });
export const shiftReservations = () => call<ShiftReservation[]>('f360_shift_reservations', { p_token: token() });
export const markSeparated = (id: string) => call<{ separated_by: string }>('f360_shift_reservation_separate', { p_token: token(), p_reservation_id: id });

// UUID v4 in plain JS (no native module, so this ships as an over-the-air update to the published app). It is only the
// sale's idempotency key: the server makes a retry with the same key a no-op.
export const newSaleKey = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
  const r = (Math.random() * 16) | 0;
  return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
});
export const recordSale = (key: string, lines: { variant_id: string; quantity: number }[], payment: 'cash' | 'card' | 'transfer' | 'other', customerQr?: string | null) =>
  call<SaleResult>('f360_record_store_sale', { p_token: token(), p_idempotency_key: key, p_lines: lines, p_payment_method: payment, p_customer_qr: customerQr || null });

// Customer
export const storeAvailability = (wooVariationId: number) =>
  call<{ variant_id: string | null; stores: StoreOption[] }>('f360_store_availability', { p_woo_variation_id: wooVariationId });
export const reserve = (locationId: string, variantId: string) =>
  call<{ id: string; store: string; variant: string; expires_at: string }>('f360_reserve', { p_location_id: locationId, p_variant_id: variantId });

export const hora = (iso: string) => new Date(iso).toLocaleTimeString('es-MX', { hour: 'numeric', minute: '2-digit' }).replace(/\.$/, '');
export function faltan(iso: string, now = Date.now()) {
  const m = Math.max(0, Math.round((new Date(iso).getTime() - now) / 60000));
  return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`;
}

// While a shift is open: check the store's reservations every 20 s and alert on each NEW active one (in-app alert +
// vibration). Server push covers the app being closed; this covers phones without push (e.g. Android without Firebase).
let watch: ReturnType<typeof setInterval> | null = null;
let seen: Set<string> | null = null;
const listeners = new Set<(list: ShiftReservation[]) => void>();
export function onReservations(cb: (list: ShiftReservation[]) => void) { listeners.add(cb); return () => { listeners.delete(cb); }; }
export async function refreshReservations() {
  const list = await shiftReservations();
  const active = list.filter((r) => r.status === 'activa');
  if (seen) {
    for (const r of active) if (!seen.has(r.id)) {
      alertNow('Apartado Fuxia Gold', `Separa ${r.product} ${r.color} ${r.size} para ${r.customer} · hasta las ${hora(r.expires_at)}`, { type: 'f360_reservation', reservation_id: r.id });
    }
  }
  seen = new Set(list.map((r) => r.id));
  listeners.forEach((cb) => cb(list));
  return list;
}
export function startReservationWatch() {
  if (watch) return;
  refreshReservations().catch(() => {});
  watch = setInterval(() => { if (currentShift()) refreshReservations().catch(() => {}); }, 20000);
}
export function stopReservationWatch() {
  if (watch) clearInterval(watch);
  watch = null; seen = null; listeners.clear();
}
