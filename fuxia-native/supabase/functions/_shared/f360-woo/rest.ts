// WooCommerce REST v3 adapter (fetch only; works in Deno and Node).
// Auth: HTTP Basic. A real store uses a Woo REST key (ck_/cs_) over HTTPS; the throwaway local Docker store uses a
// WordPress application password (allowed over http only when WP_ENVIRONMENT_TYPE=local). Credentials never logged.
import type { BatchInput, BatchResult, WooAdapter, WooAttribute, WooCategory, WooProduct, WooTerm, WooVariation } from './types.ts';
import { WooError } from './types.ts';

export type RestConfig = { baseUrl: string; user: string; secret: string; timeoutMs?: number };

export function restAdapter(cfg: RestConfig): WooAdapter {
  const base = `${cfg.baseUrl.replace(/\/+$/, '')}/wp-json/wc/v3`;
  const auth = 'Basic ' + btoa(`${cfg.user}:${cfg.secret}`);

  async function call<T>(method: string, path: string, body?: unknown, allow404 = false): Promise<T | null> {
    const res = await fetch(`${base}${path}`, {
      method,
      headers: { Authorization: auth, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(cfg.timeoutMs ?? 60_000),
    });
    const text = await res.text();
    let json: unknown = null;
    try { json = text ? JSON.parse(text) : null; } catch { /* non-JSON error page */ }
    if (res.status === 404 && allow404) return null;
    if (!res.ok) {
      const j = (json ?? {}) as { code?: string; message?: string };
      throw new WooError(res.status, j.code ?? `http_${res.status}`, j.message ?? `HTTP ${res.status}`);
    }
    return json as T;
  }
  async function all<T>(path: string): Promise<T[]> {
    const out: T[] = [];
    for (let page = 1; page < 50; page++) {
      const sep = path.includes('?') ? '&' : '?';
      const rows = (await call<T[]>('GET', `${path}${sep}per_page=100&page=${page}`)) ?? [];
      out.push(...rows);
      if (rows.length < 100) break;
    }
    return out;
  }

  return {
    listAttributes: () => call<WooAttribute[]>('GET', '/products/attributes').then((r) => r ?? []),
    listTerms: (id) => all<WooTerm>(`/products/attributes/${id}/terms`),
    createTerm: (id, name) => call<WooTerm>('POST', `/products/attributes/${id}/terms`, { name }).then((r) => r!),
    getCategory: (id) => call<WooCategory>('GET', `/products/categories/${id}`, undefined, true),
    findProductBySku: async (sku) => {
      const rows = (await call<WooProduct[]>('GET', `/products?sku=${encodeURIComponent(sku)}&status=any&per_page=10`)) ?? [];
      return rows.find((p) => p.sku === sku) ?? null;
    },
    getProduct: async (id) => {
      const p = await call<WooProduct>('GET', `/products/${id}`, undefined, true);
      return p && p.status !== 'trash' ? p : null;
    },
    createProduct: (body) => call<WooProduct>('POST', '/products', body).then((r) => r!),
    updateProduct: (id, body) => call<WooProduct>('PUT', `/products/${id}`, body).then((r) => r!),
    listVariations: (pid) => all<WooVariation>(`/products/${pid}/variations`),
    batchVariations: (pid, input: BatchInput) => call<BatchResult>('POST', `/products/${pid}/variations/batch`, input).then((r) => r ?? {}),
    batchProducts: (update) => call<{ update?: { id?: number; error?: { code: string; message: string } }[] }>('POST', '/products/batch', { update }).then((r) => r ?? {}),
  };
}
