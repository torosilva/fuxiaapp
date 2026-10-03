// Fuxia 360 → CURRENT store products (legacy Woo): photos, description, price and colour name (Mario 2026-10-02,
// staging only; the database refuses production targets). One store product per call. Never touches SKU, slug,
// status, stock, attributes or categories. Runtime-agnostic (Deno Edge Functions and Node tests).
import { mediaName, money, publicImageUrl } from './mapping.ts';
import type { WooAdapter, WooImageInput } from './types.ts';
import type { Rpc } from './sync.ts';

type Media = { id: string; path: string; alt: string | null; woo_media_id: number | null };
export type ContentSnap = {
  woo_product_id: number; base_url: string;
  product: { id: string; name: string; description: string | null; short_description: string | null; regular_price: number | string | null; sale_price: number | string | null };
  prices: { woo_meta_key: string; amount: number | string }[];
  colors: { id: string; name: string; media: Media[] }[];
  variations: number[];
};
const msg = (e: unknown) => (e instanceof Error ? e.message : String(e));

export function buildContent(s: ContentSnap, storageBase: string) {
  const media = s.colors.flatMap((c) => c.media.map((m) => ({ m, color: c.name })));
  const images: WooImageInput[] = media.map(({ m, color }) => m.woo_media_id
    ? { id: m.woo_media_id } : { src: publicImageUrl(storageBase, m.path), name: mediaName(m.id), alt: m.alt || `${s.product.name} ${color}` });
  const meta = s.prices.map((p) => ({ key: p.woo_meta_key, value: money(p.amount) }));
  const parent: Record<string, unknown> = { name: s.colors.length === 1 ? `${s.product.name} ${s.colors[0].name}` : s.product.name };
  if (s.product.description?.trim()) parent.description = s.product.description;
  if (s.product.short_description?.trim()) parent.short_description = s.product.short_description;
  if (images.length) parent.images = images;          // a model without photos in Fuxia 360 keeps the store's photos
  if (meta.length) parent.meta_data = meta;
  const priced = s.product.regular_price != null && s.product.regular_price !== '';
  const variation = priced ? { regular_price: money(s.product.regular_price), sale_price: money(s.product.sale_price), ...(meta.length ? { meta_data: meta } : {}) } : null;
  return { parent, variation, media: media.map(({ m }) => m) };
}

export async function pushContent(rpc: Rpc, woo: WooAdapter, targetKey: string, wooProductId: number, storageBase: string, who: string) {
  const s = await rpc<ContentSnap>('f360_legacy_content_snapshot', { p_target_key: targetKey, p_woo_product_id: wooProductId });
  const { parent, variation, media } = buildContent(s, storageBase);
  const sent = { name: parent.name, description: 'description' in parent, photos: media.length, price: variation?.regular_price ?? null, variations: variation ? s.variations.length : 0 };
  const links: { media_id: string; woo_media_id: number }[] = [];
  try {
    const p = await woo.updateProduct(wooProductId, parent);
    if (parent.images) media.forEach((m, i) => { const id = p.images?.[i]?.id; if (!m.woo_media_id && id) links.push({ media_id: m.id, woo_media_id: id }); });
    let failed = 0;
    if (variation && s.variations.length) {
      const r = await woo.batchVariations(wooProductId, { update: s.variations.map((id) => ({ id, ...variation })) }, 'variations');
      failed = (r.update ?? []).filter((x) => (x as { error?: unknown }).error).length;
    }
    const message = failed ? `${failed} tallas no aceptaron el precio` : 'ok';
    await rpc('f360_legacy_content_result', { p_target_key: targetKey, p_woo_product_id: wooProductId, p_product_id: s.product.id, p_by: who, p_ok: !failed, p_message: message, p_sent: sent, p_media: links });
    return { ok: !failed, name: String(parent.name), photos: media.length, message };
  } catch (e) {
    await rpc('f360_legacy_content_result', { p_target_key: targetKey, p_woo_product_id: wooProductId, p_product_id: s.product.id, p_by: who, p_ok: false, p_message: msg(e), p_sent: sent, p_media: links });
    return { ok: false, name: String(parent.name), photos: media.length, message: msg(e) };
  }
}
