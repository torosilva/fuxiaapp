// Woo order webhooks → Fuxia 360 (pure helpers, runtime-agnostic: WebCrypto only).

const enc = new TextEncoder();

function toBase64(buf: ArrayBuffer) {
  let s = '';
  for (const b of new Uint8Array(buf)) s += String.fromCharCode(b);
  return btoa(s);
}

/** Constant-time string comparison (no early exit). */
export function safeEqual(a: string, b: string) {
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}

/** WooCommerce signs the RAW body: X-WC-Webhook-Signature = base64(HMAC-SHA256(body, secret)). */
export async function wooSignature(rawBody: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return toBase64(await crypto.subtle.sign('HMAC', key, enc.encode(rawBody)));
}

export async function verifyWooSignature(rawBody: string, signature: string | null, secret: string) {
  if (!signature || !secret) return false;
  return safeEqual(await wooSignature(rawBody, secret), signature.trim());
}

export type MinimalOrder = {
  id: number; status: string; date_modified_gmt: string; currency: string | null;
  refunds: { id: number }[];
  line_items: { id: number; product_id: number | null; variation_id: number | null; sku: string | null; quantity: number }[];
};

/**
 * Keeps ONLY what inventory needs. Customer name, email, phone, addresses, notes, payment data… never leave this
 * function (Fuxia 360 does not store customer PII from orders in P2.3A).
 */
export function minimizeOrder(o: Record<string, unknown>): MinimalOrder {
  const num = (x: unknown) => (x === null || x === undefined || x === '' || Number(x) === 0 ? null : Number(x));
  const items = (o.line_items as Record<string, unknown>[] | undefined) ?? [];
  return {
    id: Number(o.id),
    status: String(o.status ?? ''),
    date_modified_gmt: String(o.date_modified_gmt ?? o.date_modified ?? ''),
    currency: o.currency ? String(o.currency) : null,
    refunds: ((o.refunds as Record<string, unknown>[] | undefined) ?? []).map((r) => ({ id: Number(r.id) })),
    line_items: items.map((li) => ({
      id: Number(li.id), product_id: num(li.product_id), variation_id: num(li.variation_id),
      sku: li.sku ? String(li.sku) : null, quantity: Number(li.quantity),
    })),
  };
}
