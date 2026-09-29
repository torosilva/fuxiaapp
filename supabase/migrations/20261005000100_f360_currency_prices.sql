-- Fuxia 360 · Prices per currency (per model) + configurable currencies. STAGING. Additive; the ledger is untouched.
-- Decision (Mario, 2026-09-29): Fuxia 360 is where the price of each shoe is set in every currency; currencies can be
-- added. The base currency (MXN) stays in f360.products.regular_price / sale_price (no duplicate source of truth).
-- Every other currency: one amount per model in f360.product_prices, published to the Woo meta key the store's own
-- variation form uses (verified on staging4: "Precio Colombia (COP $)" = _price_cop, "Resto del Mundo (USD $)" = _price_usd).
-- Suggestions (Mario's table MXN → COP) only PREFILL; a person confirms every price. "CON DESCUENTO" fields are not touched.
-- A new currency is stored and published by Fuxia 360, but the storefront shows it only once the site supports it.
-- Rollback: supabase/rollbacks/20261005000100_f360_currency_prices.down.sql

CREATE TABLE f360.currencies (
  code          text PRIMARY KEY CHECK (code ~ '^[A-Z]{3}$'),
  name          text NOT NULL CHECK (length(btrim(name)) > 0),
  symbol        text NOT NULL DEFAULT '$',
  decimals      integer NOT NULL DEFAULT 0 CHECK (decimals BETWEEN 0 AND 2),
  is_base       boolean NOT NULL DEFAULT false,
  woo_meta_key  text UNIQUE CHECK (woo_meta_key IS NULL OR woo_meta_key ~ '^_[a-z0-9_]{2,40}$'),
  active        boolean NOT NULL DEFAULT true,
  sort          integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (is_base = (woo_meta_key IS NULL))            -- the base currency is Woo's own price; every other one has its meta key
);
CREATE UNIQUE INDEX currencies_single_base ON f360.currencies ((true)) WHERE is_base;
INSERT INTO f360.currencies (code, name, symbol, decimals, is_base, woo_meta_key, sort) VALUES
  ('MXN', 'Peso mexicano', '$', 0, true, NULL, 0),
  ('COP', 'Peso colombiano', 'COP$', 0, false, '_price_cop', 1),
  ('USD', 'Dólar (resto del mundo)', 'US$', 0, false, '_price_usd', 2);

CREATE TABLE f360.product_prices (
  product_id       uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  currency_code    text NOT NULL REFERENCES f360.currencies(code) ON DELETE RESTRICT,
  amount           numeric(14,2) NOT NULL CHECK (amount > 0),
  updated_by_name  text NOT NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (product_id, currency_code)
);

-- Suggested amount in a currency for a base (MXN) price. Only a prefill.
CREATE TABLE f360.price_suggestions (
  currency_code  text NOT NULL REFERENCES f360.currencies(code) ON DELETE RESTRICT,
  base_amount    numeric(14,2) NOT NULL CHECK (base_amount > 0),
  amount         numeric(14,2) NOT NULL CHECK (amount > 0),
  PRIMARY KEY (currency_code, base_amount)
);
INSERT INTO f360.price_suggestions (currency_code, base_amount, amount) VALUES
  ('COP', 2800, 420000), ('COP', 3000, 420000), ('COP', 4200, 550000), ('COP', 4500, 600000);

-- Append-only history of every price and currency change.
CREATE TABLE f360.price_changes (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  what           text NOT NULL CHECK (what IN ('price', 'currency', 'suggestion')),
  product_id     uuid,
  currency_code  text,
  before         jsonb,
  after          jsonb,
  by_name        text NOT NULL,
  by_user        uuid,
  at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX price_changes_product_idx ON f360.price_changes (product_id, id DESC);
CREATE TRIGGER price_changes_append_only BEFORE UPDATE OR DELETE ON f360.price_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

REVOKE ALL ON f360.currencies, f360.product_prices, f360.price_suggestions, f360.price_changes FROM PUBLIC, anon, authenticated;

-- ── Reads ────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_list_currencies() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN jsonb_build_object(
    'currencies', (SELECT coalesce(jsonb_agg(to_jsonb(c) - 'created_at' ORDER BY c.sort, c.code), '[]'::jsonb) FROM f360.currencies c),
    'suggestions', (SELECT coalesce(jsonb_agg(jsonb_build_object('currency', s.currency_code, 'base', s.base_amount, 'amount', s.amount)
                     ORDER BY s.currency_code, s.base_amount), '[]'::jsonb) FROM f360.price_suggestions s));
END $$;

-- Prices of one model in every currency: base from the product; others from product_prices, with the suggestion.
CREATE FUNCTION public.f360_product_prices(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360.products;
BEGIN
  PERFORM f360.require_role('viewer');
  SELECT * INTO p FROM f360.products WHERE id = p_product_id;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'code', c.code, 'name', c.name, 'symbol', c.symbol, 'decimals', c.decimals, 'is_base', c.is_base, 'active', c.active,
      'woo_meta_key', c.woo_meta_key,
      'amount', CASE WHEN c.is_base THEN p.regular_price ELSE pp.amount END,
      'suggested', CASE WHEN c.is_base THEN NULL ELSE (SELECT s.amount FROM f360.price_suggestions s WHERE s.currency_code = c.code AND s.base_amount = p.regular_price) END,
      'updated_by_name', pp.updated_by_name, 'updated_at', pp.updated_at) ORDER BY c.sort, c.code), '[]'::jsonb)
    FROM f360.currencies c LEFT JOIN f360.product_prices pp ON pp.product_id = p.id AND pp.currency_code = c.code
    WHERE c.active OR pp.amount IS NOT NULL);
END $$;

-- ── Writes ───────────────────────────────────────────────────────────────────
-- Set (or clear with NULL) a model's price in a non-base currency. The base price is edited with f360_update_product.
CREATE FUNCTION public.f360_set_product_price(p_product_id uuid, p_currency text, p_amount numeric) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.currencies; before f360.product_prices; after f360.product_prices;
BEGIN
  r := f360.require_role('operator');
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  SELECT * INTO c FROM f360.currencies WHERE code = upper(btrim(p_currency));
  IF c.code IS NULL THEN RAISE EXCEPTION 'Moneda no válida.'; END IF;
  IF c.is_base THEN RAISE EXCEPTION 'El precio en % se cambia en la información del producto.', c.code; END IF;
  IF p_amount IS NOT NULL AND p_amount <= 0 THEN RAISE EXCEPTION 'El precio debe ser mayor a cero.'; END IF;
  IF p_amount IS NOT NULL AND round(p_amount, c.decimals) <> p_amount THEN RAISE EXCEPTION 'El precio en % no lleva más de % decimales.', c.code, c.decimals; END IF;
  SELECT * INTO before FROM f360.product_prices WHERE product_id = p_product_id AND currency_code = c.code FOR UPDATE;
  IF p_amount IS NULL THEN
    DELETE FROM f360.product_prices WHERE product_id = p_product_id AND currency_code = c.code;
  ELSE
    INSERT INTO f360.product_prices (product_id, currency_code, amount, updated_by_name) VALUES (p_product_id, c.code, p_amount, r.display_name)
      ON CONFLICT (product_id, currency_code) DO UPDATE SET amount = EXCLUDED.amount, updated_by_name = EXCLUDED.updated_by_name, updated_at = now()
      RETURNING * INTO after;
  END IF;
  IF before.amount IS DISTINCT FROM after.amount THEN
    INSERT INTO f360.price_changes (what, product_id, currency_code, before, after, by_name, by_user)
      VALUES ('price', p_product_id, c.code, CASE WHEN before.amount IS NULL THEN NULL ELSE jsonb_build_object('amount', before.amount) END,
              CASE WHEN after.amount IS NULL THEN NULL ELSE jsonb_build_object('amount', after.amount) END, r.display_name, r.auth_user_id);
    UPDATE f360.products SET updated_at = now() WHERE id = p_product_id;
  END IF;
  RETURN public.f360_product_prices(p_product_id);
END $$;

-- Add or edit a currency (owner). The base currency cannot be changed here; a currency in use cannot change its Woo key.
CREATE FUNCTION public.f360_save_currency(p_code text, p_name text, p_symbol text, p_decimals integer, p_woo_meta_key text,
  p_active boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; before f360.currencies; after f360.currencies; v_code text := upper(btrim(p_code));
BEGIN
  r := f360.require_role('owner');
  IF v_code !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'El código de moneda son 3 letras (por ejemplo EUR).'; END IF;
  IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'Escribe el nombre de la moneda.'; END IF;
  IF coalesce(btrim(p_woo_meta_key), '') !~ '^_[a-z0-9_]{2,40}$' THEN
    RAISE EXCEPTION 'Indica el campo de la tienda donde se guarda este precio (por ejemplo _price_eur).';
  END IF;
  SELECT * INTO before FROM f360.currencies WHERE code = v_code FOR UPDATE;
  IF before.is_base THEN RAISE EXCEPTION 'La moneda base no se modifica aquí.'; END IF;
  IF before.code IS NOT NULL AND before.woo_meta_key <> btrim(p_woo_meta_key)
     AND EXISTS (SELECT 1 FROM f360.product_prices WHERE currency_code = v_code) THEN
    RAISE EXCEPTION 'Esta moneda ya tiene precios capturados: su campo en la tienda no se puede cambiar.';
  END IF;
  INSERT INTO f360.currencies (code, name, symbol, decimals, is_base, woo_meta_key, active, sort)
    VALUES (v_code, btrim(p_name), coalesce(nullif(btrim(p_symbol), ''), '$'), coalesce(p_decimals, 0), false, btrim(p_woo_meta_key), coalesce(p_active, true),
            coalesce((SELECT max(sort) + 1 FROM f360.currencies), 1))
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, symbol = EXCLUDED.symbol, decimals = EXCLUDED.decimals,
      woo_meta_key = EXCLUDED.woo_meta_key, active = EXCLUDED.active
    RETURNING * INTO after;
  INSERT INTO f360.price_changes (what, currency_code, before, after, by_name, by_user)
    VALUES ('currency', v_code, to_jsonb(before) - 'created_at', to_jsonb(after) - 'created_at', r.display_name, r.auth_user_id);
  RETURN public.f360_list_currencies();
END $$;

-- ── Publishing: prices are content ("Cambios pendientes" when they change) and travel in the snapshot ──
-- The prices key is added only when a model has prices, so hashes of products without them do not change.
CREATE OR REPLACE FUNCTION f360.publish_hash(p_product_id uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT md5((jsonb_build_object(
    'name', p.name, 'code', p.code, 'description', p.description, 'short', p.short_description,
    'regular', p.regular_price, 'sale', p.sale_price, 'category', p.category_key,
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]') FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'name', c.name,
                 'media', (SELECT coalesce(jsonb_agg(m.storage_path ORDER BY m.sort, m.created_at), '[]') FROM f360.product_media m WHERE m.color_id = c.id))
               ORDER BY c.sort, c.created_at), '[]') FROM f360.product_colors c WHERE c.product_id = p.id),
    'variants', (SELECT coalesce(jsonb_agg(v.sku || ':' || v.status ORDER BY v.sku), '[]') FROM f360.product_variants v WHERE v.product_id = p.id)
  ) || coalesce((SELECT jsonb_build_object('prices', jsonb_object_agg(pp.currency_code || ':' || c.woo_meta_key, pp.amount))
                 FROM f360.product_prices pp JOIN f360.currencies c ON c.code = pp.currency_code AND c.active
                 WHERE pp.product_id = p.id HAVING count(*) > 0), '{}'::jsonb))::text) FROM f360.products p WHERE p.id = p_product_id
$$;

CREATE FUNCTION f360.snapshot_prices(p_product_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'woo_meta_key', c.woo_meta_key, 'amount', pp.amount) ORDER BY c.sort), '[]'::jsonb)
  FROM f360.product_prices pp JOIN f360.currencies c ON c.code = pp.currency_code
  WHERE pp.product_id = p_product_id AND c.active AND NOT c.is_base
$$;

-- f360_pub_claim: same as P2.2 plus "prices" in the product snapshot.
CREATE OR REPLACE FUNCTION public.f360_pub_claim(p_job_id uuid, p_caller uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE j f360.sync_jobs; t f360.sales_targets; p f360.products; cat f360.woo_category_links;
BEGIN
  SELECT * INTO j FROM f360.sync_jobs WHERE id = p_job_id FOR UPDATE;
  IF j.id IS NULL THEN RAISE EXCEPTION 'Publicación no encontrada.'; END IF;
  IF j.requested_by IS DISTINCT FROM p_caller THEN RAISE EXCEPTION 'Esta publicación la pidió otra persona.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner') THEN
    RAISE EXCEPTION 'Solo una dueña puede publicar.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF j.status = 'running' AND coalesce(j.heartbeat_at, j.started_at) >= now() - interval '10 minutes' THEN
    RAISE EXCEPTION 'Esta publicación ya está en curso.';
  END IF;
  IF j.status NOT IN ('queued', 'running') THEN RAISE EXCEPTION 'Esta publicación ya terminó.'; END IF;
  IF NOT (f360.product_readiness(j.product_id)->>'ready')::boolean THEN RAISE EXCEPTION 'El producto todavía no está listo para publicar.'; END IF;

  UPDATE f360.products SET codes_locked_at = now() WHERE id = j.product_id AND codes_locked_at IS NULL;
  UPDATE f360.sync_jobs SET status = 'running', started_at = coalesce(started_at, now()), heartbeat_at = now(),
    attempt = attempt + 1, content_hash = f360.publish_hash(j.product_id) WHERE id = j.id RETURNING * INTO j;
  SELECT * INTO t FROM f360.sales_targets WHERE id = j.target_id;
  SELECT * INTO p FROM f360.products WHERE id = j.product_id;
  SELECT * INTO cat FROM f360.woo_category_links WHERE target_id = t.id AND category_key = p.category_key;

  RETURN jsonb_build_object(
    'job', jsonb_build_object('id', j.id, 'attempt', j.attempt, 'requested_by_name', j.requested_by_name, 'content_hash', j.content_hash),
    'target', jsonb_build_object('id', t.id, 'key', t.key, 'base_url', t.base_url, 'is_production', t.is_production,
               'fulfillment_location_id', t.fulfillment_location_id),
    'product', jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'slug', p.slug, 'description', p.description,
               'short_description', p.short_description, 'regular_price', p.regular_price, 'sale_price', p.sale_price,
               'category_key', p.category_key,
               'woo_category', CASE WHEN cat.woo_term_id IS NULL THEN NULL ELSE jsonb_build_object('id', cat.woo_term_id, 'slug', cat.woo_slug) END,
               'woo_product_id', (SELECT woo_product_id FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p.id),
               'prices', f360.snapshot_prices(p.id)),
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]') FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'hex', c.hex,
                 'media', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'path', m.storage_path, 'alt', m.alt,
                             'woo_media_id', (SELECT woo_media_id FROM f360.woo_media_links ml WHERE ml.target_id = t.id AND ml.media_id = m.id))
                           ORDER BY m.sort, m.created_at), '[]') FROM f360.product_media m WHERE m.color_id = c.id))
               ORDER BY c.sort, c.created_at), '[]') FROM f360.product_colors c WHERE c.product_id = p.id),
    'variants', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'color_id', v.color_id, 'size', v.size_label, 'sku', v.sku,
                   'status', v.status, 'ats', f360.online_ats(v.id, t.fulfillment_location_id),
                   'woo_variation_id', vl.woo_variation_id, 'last_pushed_stock', vl.last_pushed_stock)
                 ORDER BY c.sort, c.created_at, s.sort), '[]')
                 FROM f360.product_variants v JOIN f360.product_colors c ON c.id = v.color_id
                 JOIN f360.product_sizes s ON s.product_id = v.product_id AND s.label = v.size_label
                 LEFT JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = v.id
                 WHERE v.product_id = p.id));
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_list_currencies(), public.f360_product_prices(uuid), public.f360_set_product_price(uuid, text, numeric),
  public.f360_save_currency(text, text, text, integer, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_list_currencies(), public.f360_product_prices(uuid), public.f360_set_product_price(uuid, text, numeric),
  public.f360_save_currency(text, text, text, integer, text, boolean) TO authenticated, service_role;
