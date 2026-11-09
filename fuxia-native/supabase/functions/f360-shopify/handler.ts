// f360-shopify — Shopify México order webhooks → Fuxia 360 (Mario 2026-11-09). Same path as WooCommerce orders
// (f360-woo-orders → ingestOrder): the order is translated to the Woo shape first and its ids localized. Topics: orders/create, orders/updated
// (Shopify sends orders/updated on payment, refund, cancellation and fulfilment). Authenticity: X-Shopify-Hmac-Sha256 =
// base64(HMAC-SHA256(raw body, app client secret)) + the shop domain must be ours. Shopify test orders are acknowledged and
// never recorded (they would otherwise count as sales).
import { verifyWooSignature } from '../_shared/f360-woo/orders.ts';
import { serviceRpc, type SupabaseEnv } from '../_shared/f360-woo/supabase.ts';
import { ingestOrder } from '../f360-woo-orders/handler.ts';
import { refundDetails, toWooOrder, wooTopic } from '../_shared/f360-shopify/orders.ts';

export type ShopifyEnv = SupabaseEnv & { SHOPIFY_SHOP: string; SHOPIFY_CLIENT_SECRET: string; SHOPIFY_TARGET_KEY: string };

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
const TOPICS = new Set(['orders/create', 'orders/updated']);

export async function handleShopify(req: Request, env: ShopifyEnv): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY || !env.SHOPIFY_SHOP || !env.SHOPIFY_CLIENT_SECRET || !env.SHOPIFY_TARGET_KEY) {
    return json({ error: 'No configurado.' }, 500);
  }
  const raw = await req.text();
  const topic = req.headers.get('x-shopify-topic') ?? '';
  const delivery = { delivery_id: req.headers.get('x-shopify-webhook-id') ?? req.headers.get('x-shopify-event-id'), topic: wooTopic(topic) };
  const rpc = serviceRpc(env);
  const reject = async (reason: string, status: number, message: string) => {
    try { await rpc('f360_record_webhook_rejection', { p_target_key: env.SHOPIFY_TARGET_KEY, p_delivery: delivery, p_reason: reason }); } catch { /* still reject */ }
    return json({ error: message }, status);
  };
  if (!(await verifyWooSignature(raw, req.headers.get('x-shopify-hmac-sha256'), env.SHOPIFY_CLIENT_SECRET))) return reject('firma inválida', 401, 'Firma inválida.');
  const shop = (req.headers.get('x-shopify-shop-domain') ?? '').toLowerCase();
  if (shop !== env.SHOPIFY_SHOP.toLowerCase()) return reject(`origen distinto: ${shop || 'sin origen'}`, 403, 'Este servicio no acepta pedidos de esa tienda.');
  if (!TOPICS.has(topic)) return json({ ok: true, ignored: topic });

  let order: Record<string, unknown>;
  try { order = JSON.parse(raw); } catch { return json({ error: 'Cuerpo no válido.' }, 400); }
  if (order.test === true) return json({ ok: true, ignored: 'pedido de prueba' });
  const refunds = refundDetails(order);
  // Shopify's product/variant ids → Fuxia 360's channel ids (they do not fit the Woo-era columns; 20261109000100).
  let local: Record<string, unknown>;
  try { local = await rpc<Record<string, unknown>>('f360_shopify_localize', { p_target_key: env.SHOPIFY_TARGET_KEY, p_order: toWooOrder(order) }); }
  catch (e) { return json({ error: (e as Error).message }, 500); }
  return ingestOrder(rpc, env.SHOPIFY_TARGET_KEY, delivery, local, { refundDetails: refunds.length ? async () => refunds : undefined, log: 'f360-shopify' });
}
