// f360-woo-orders — Woo order webhooks for Fuxia 360-managed products. SEPARATE from `woocommerce-webhook`
// (loyalty), which is not touched. Own HMAC secret. Idempotent and order-safe (the database decides; see
// public.f360_ingest_woo_order). Customer data is dropped before anything is stored.
import { minimizeOrder, verifyWooSignature } from '../_shared/f360-woo/orders.ts';
import { commerceWoo, orderEconomics, refundDetail, type CommerceWoo } from '../_shared/f360-woo/commerce.ts';
import { serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';

export type OrdersEnv = SupabaseEnv & { WOO_TARGET_KEY: string; WOO_WEBHOOK_SECRET: string; WOO_BASE_URL?: string; WOO_USER?: string; WOO_SECRET?: string };
export type OrdersOptions = { afterApplied?: () => Promise<unknown>; commerceWoo?: CommerceWoo | null };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });

export async function handleOrders(req: Request, env: OrdersEnv, opts: OrdersOptions = {}): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY || !env.WOO_TARGET_KEY || !env.WOO_WEBHOOK_SECRET) return json({ error: 'No configurado.' }, 500);
  const raw = await req.text();
  const topic = req.headers.get('x-wc-webhook-topic') ?? '';
  const delivery = { delivery_id: req.headers.get('x-wc-webhook-delivery-id'), topic };
  const rpc = serviceRpc(env);

  // Woo "ping" when a webhook is created/activated: form-encoded "webhook_id=…", no topic. Acknowledge only.
  if (!topic && /^webhook_id=\d+$/.test(raw.trim())) return json({ ok: true, ping: true });

  if (!(await verifyWooSignature(raw, req.headers.get('x-wc-webhook-signature'), env.WOO_WEBHOOK_SECRET))) {
    try { await rpc('f360_record_webhook_rejection', { p_target_key: env.WOO_TARGET_KEY, p_delivery: delivery, p_reason: 'firma inválida' }); } catch { /* still reject */ }
    return json({ error: 'Firma inválida.' }, 401);
  }
  if (!topic.startsWith('order.')) return json({ ok: true, ignored: topic });

  let order: Record<string, unknown>;
  try { order = JSON.parse(raw); } catch { return json({ error: 'Cuerpo no válido.' }, 400); }
  try {
    const result = await rpc<{ result: string }>('f360_ingest_woo_order', { p_target_key: env.WOO_TARGET_KEY, p_delivery: delivery, p_order: minimizeOrder(order) });
    // Push the new Bodega stock right away (best effort; the queue + worker guarantee it anyway).
    if (result.result === 'applied' && opts.afterApplied) { try { await opts.afterApplied(); } catch { /* retried by the worker */ } }
    // G1 Commerce Facts: the order's economics + first-party attribution (whitelist only; inventory above is unaffected).
    // Refund detail is read from Woo when there are refunds; if that read fails the refund is kept header-only (PARTIAL)
    // and the 15-minute poll completes it. A capture failure answers 5xx so Woo retries (both steps are idempotent).
    const woo = opts.commerceWoo !== undefined ? opts.commerceWoo
      : env.WOO_BASE_URL && env.WOO_USER && env.WOO_SECRET ? commerceWoo({ baseUrl: env.WOO_BASE_URL, user: env.WOO_USER, secret: env.WOO_SECRET }) : null;
    let detailed: Record<string, unknown>[] | undefined;
    if (woo && Array.isArray(order.refunds) && order.refunds.length) {
      try { detailed = (await woo.listRefunds(Number(order.id))).map(refundDetail); } catch { detailed = undefined; }
    }
    const commerce = await rpc<{ result: string }>('f360_capture_order_economics', { p_target_key: env.WOO_TARGET_KEY, p_order: orderEconomics(order, detailed), p_via: 'webhook' });
    return json({ ...result, commerce: commerce.result });
  } catch (e) {
    // 5xx → Woo retries the delivery later; the database side is atomic, so a retry is always safe.
    return json({ error: (e as Error).message }, 500);
  }
}
