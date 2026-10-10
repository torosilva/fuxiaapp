// Conciliación de Ventas — read-only gateway evidence for ONE Woo order (GET /orders/{id} + GET /orders/{id}/notes).
// Two outputs, kept apart on purpose:
//   · `stored`: the minimal structured snapshot Fuxia 360 records (status, paid date, transaction reference, method, totals,
//     derived result + signal codes). Never note text, never customer data, never anything card-like.
//   · `display`: shown once to Carolina / Mario and NOT stored (customer name + email, gateway notes with emails, phones and
//     card-like numbers masked).
type Obj = Record<string, unknown>;
const arr = (x: unknown) => (Array.isArray(x) ? (x as Obj[]) : []);
const str = (x: unknown) => (x === null || x === undefined ? '' : String(x));
const num = (x: unknown) => { const n = Number(x); return Number.isFinite(n) ? n : 0; };

export type GatewayResult = 'approved' | 'rejected' | 'pending' | 'refunded' | 'transaction_only' | 'no_evidence';
const PAID = new Set(['processing', 'completed', 'on-hold', 'refunded']);
// Woo's own status-change notes are not gateway evidence.
const WOO_STATUS_NOTE = /(order status changed|estado del pedido cambi|status changed from|cambió de)/i;
const GATEWAY_NOTE = /(mercado ?pago|\bmp\b|epayco|paypal|ppcp|stripe|openpay|conekta|transacci|transaction|captur|payment|pago|cobro|ref_payco|autorizaci)/i;
const RX: [Exclude<GatewayResult, 'transaction_only' | 'no_evidence'>, RegExp][] = [
  ['refunded', /(reembols|refund|devoluci)/i],
  ['rejected', /(rechaz|reject|declin|denied|denegad|fall[oó]|failed|cancelad|cancelled|expir|error)/i],
  ['approved', /(aprobad|approved|accredited|acreditad|aceptad|accepted|exitos|success|captured|capturad|completed payment|pago completado|paid)/i],
  ['pending', /(pendiente|pending|in_process|en proceso|waiting|esperando)/i],
];

export function classifyNote(text: string): GatewayResult | null {
  if (WOO_STATUS_NOTE.test(text) || !GATEWAY_NOTE.test(text)) return null;
  for (const [k, rx] of RX) if (rx.test(text)) return k;
  return null;
}

/** Masks emails, card-like numbers (13–19 digits) and phone-like runs (8–12 digits) for display. */
export function maskText(text: string): string {
  return text
    .replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '[correo]')
    .replace(/\b\d(?:[ -]?\d){12,18}\b/g, '[número oculto]')
    // phones: "+52 81…" or after a phone word; bare digit runs are kept (gateway ids look like that)
    .replace(/\+\d[\d ()-]{7,16}\d/g, '[teléfono]')
    .replace(/\b(tel|tel[eé]fono|cel|celular|whatsapp|phone|m[oó]vil)\b[:\s]*[\d ()-]{7,}\d/gi, '$1 [teléfono]')
    .replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 240);
}

const TX_META = ['_Mercado_Pago_Payment_IDs', '_transaction_id', '_ref_payco', 'ref_payco', '_epayco_ref_payco', '_ppcp_paypal_capture_id'];
const cardLike = (s: string) => /^\d{13,19}$/.test(s.replace(/[\s-]/g, ''));

export function orderEvidence(order: Obj, notes: Obj[]) {
  const status = str(order.status);
  // Transaction reference: Woo's transaction_id; Mercado Pago leaves it empty and keeps its payment ids in a meta (whitelisted keys only).
  const meta = arr(order.meta_data);
  const metaTx = TX_META.map((k) => ({ k, v: str(meta.find((m) => m.key === k)?.value).trim() })).find((m) => m.v);
  const txSource = str(order.transaction_id).trim() ? 'tx_field' : metaTx ? (metaTx.k === '_Mercado_Pago_Payment_IDs' ? 'tx_meta_mercadopago' : 'tx_meta_other') : null;
  const tx0 = str(order.transaction_id).trim() || metaTx?.v || '';
  const tx = tx0 && !cardLike(tx0) && tx0.length <= 100 ? tx0 : '';
  const refundTotal = Math.round(arr(order.refunds).reduce((s, r) => s + Math.abs(num(r.total)), 0) * 100) / 100;
  const gw = notes
    .filter((n) => !n.customer_note && !n.added_by_user)
    .map((n) => ({ at: str(n.date_created_gmt) || str(n.date_created), text: str(n.note), kind: classifyNote(str(n.note)) }))
    .filter((n) => n.kind !== null)
    .sort((a, b) => a.at.localeCompare(b.at));
  const latest = gw.length ? gw[gw.length - 1].kind! : null;
  const result: GatewayResult = refundTotal > 0 || latest === 'refunded' ? 'refunded' : latest ?? (tx ? 'transaction_only' : 'no_evidence');
  const signals = [
    tx ? 'tx_present' : null, tx ? txSource : null, tx0 && !tx ? 'tx_redacted' : null, order.date_paid_gmt ? 'date_paid' : null,
    ...(['approved', 'rejected', 'pending', 'refunded'] as const).filter((k) => gw.some((n) => n.kind === k)).map((k) => `note_${k}`),
    refundTotal > 0 ? 'refund_records' : null, PAID.has(status) ? 'status_paid' : 'status_unpaid', gw.length ? null : 'no_gateway_notes',
  ].filter(Boolean) as string[];
  const datePaid = str(order.date_paid_gmt);
  const billing = (order.billing ?? {}) as Obj;
  return {
    stored: {
      woo_status: status, date_paid: datePaid ? `${datePaid.replace(/Z$/, '')}Z` : null, transaction_ref: tx || null,
      payment_method: str(order.payment_method) || null, order_total: num(order.total), currency: str(order.currency) || null,
      refund_total: refundTotal, gateway_result: result, signals,
    },
    display: {
      customer: { name: [str(billing.first_name), str(billing.last_name)].filter(Boolean).join(' ') || null, email: str(billing.email) || null },
      payment_method_title: str(order.payment_method_title) || null,
      gateway_notes: gw.slice(-10).map((n) => ({ at: n.at, kind: n.kind, text: maskText(n.text) })),
    },
  };
}
