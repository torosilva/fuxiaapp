// One-shot fault injection around ANY adapter (mock or real local Docker Woo). Test/local-runner only:
// the deployed Edge Function never wraps its adapter with this.
//   photo          → a product create/update that uploads new photos fails (Woo rejects the whole request, like
//                    woocommerce_product_image_upload_error)
//   product_crash  → the product IS created in Woo, then the connection drops before we get the answer
//   variation      → the first variation of the next create batch fails (per-item error, the rest succeed)
//   stock          → the stock update batch fails entirely (timeout)
import type { WooAdapter } from './types.ts';
import { WooError } from './types.ts';

export type Fault = 'photo' | 'product_crash' | 'variation' | 'stock';

export function withFaults(inner: WooAdapter, armed: Set<Fault>): WooAdapter {
  const take = (f: Fault) => armed.delete(f);
  const hasNewPhotos = (b: Record<string, unknown>) => ((b.images as { src?: string }[]) ?? []).some((i) => i.src);
  return {
    ...inner,
    createProduct: async (b) => {
      if (hasNewPhotos(b) && take('photo')) throw new WooError(400, 'woocommerce_product_image_upload_error', 'Error al subir la imagen (falla simulada).');
      const p = await inner.createProduct(b);
      if (take('product_crash')) throw new WooError(504, 'gateway_timeout', 'Se cortó la conexión después de crear el producto (falla simulada).');
      return p;
    },
    updateProduct: async (id, b) => {
      if (hasNewPhotos(b) && take('photo')) throw new WooError(400, 'woocommerce_product_image_upload_error', 'Error al subir la imagen (falla simulada).');
      return inner.updateProduct(id, b);
    },
    batchVariations: async (pid, input, purpose) => {
      if (purpose === 'stock' && take('stock')) throw new WooError(504, 'gateway_timeout', 'La tienda no respondió al actualizar el stock (falla simulada).');
      if (purpose === 'variations' && input.create?.length && take('variation')) {
        const [first, ...rest] = input.create;
        const r = rest.length ? await inner.batchVariations(pid, { ...input, create: rest }, purpose) : { create: [] };
        return { ...r, create: [{ error: { code: 'woocommerce_rest_invalid_variation', message: `No se pudo crear ${String(first.sku)} (falla simulada).` } }, ...(r.create ?? [])] };
      }
      return inner.batchVariations(pid, input, purpose);
    },
  };
}
