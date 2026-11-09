-- Fuxia 360 · Shopify México (Mario 2026-11-09: the agency moved México to Shopify, mx.fuxiaballerinas.com; Colombia stays on
-- WooCommerce). A Shopify store is one more sales target, so its orders take the SAME path as Woo orders (f360-shopify
-- translates them to the Woo shape → f360_ingest_woo_order / f360_capture_order_economics / shipping / loyalty): ventas,
-- tablero, Growth, inventario, puntos and the thank-you WhatsApp work unchanged. Plan: docs/fuxia360/omnichannel/SHOPIFY_MX.md.
--   · sales_targets.kind accepts 'shopify'.
--   · f360.shopify_variants: Fuxia 360's copy of the Shopify catalog (ids, inventory item, handle, colour, size, SKU). Loaded
--     by scripts/f360/shopify_catalog.mjs. Hints from the old Woo store (same product slug = Shopify handle) help the link.
--   · Shopify ids (e.g. variant 50958118649926) do not fit the 32-bit channel-id columns that come from Woo
--     (woo_variant_links.woo_variation_id / woo_product_id, read by the channel identity views behind every sales report).
--     Widening them means rebuilding that chain of views in production, so instead each Shopify product and variant gets a
--     short internal channel id (link_id) here; f360_shopify_localize() swaps Shopify's ids for those before an order is
--     ingested. Order, line, refund and customer ids are already bigint and stay Shopify's own.
--   · f360.shopify_link_variants(shopify target, woo target): links each Shopify variant to its Fuxia 360 variant in
--     f360.woo_variant_links (the per-target channel link every order/stock function already reads). Only UNIQUE matches:
--       1) same product (Woo slug → Fuxia 360 product) + colour name (accents/case ignored) + size;
--       2) else the old Woo variation (with its own colour) → its existing link / merged link / Carolina's homologation.
--     Ambiguous or unknown variants are left unlinked and reported (never guessed); an existing link is never changed.
--     Links are origin 'legacy_adopted' (an existing store product adopted by Fuxia 360, compared by id, not SKU). The link
--     guard (20261007001900) requires a person-confirmed homologation for that origin; on a Shopify target it now requires
--     instead that the variant exists in the Shopify catalog copy. Every automatic match inherits a link a person or the
--     publisher already made (the Woo product's link, or Carolina's homologation of the old Woo variation).
--   · commerce_payment_category: 'shopify_payments' (cards, Apple Pay, Google Pay, MSI) = card.
-- Stock push to Shopify is NOT here (next step, after Mario sees the report of sizes that would show as sold out).
-- Rollback: supabase/rollbacks/20261109000100_f360_shopify_mx.down.sql

ALTER TABLE f360.sales_targets DROP CONSTRAINT sales_targets_kind_check,
  ADD CONSTRAINT sales_targets_kind_check CHECK (kind IN ('woocommerce', 'shopify'));

CREATE TABLE f360.shopify_products (
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  shopify_product_id bigint NOT NULL CHECK (shopify_product_id > 0),
  link_id            integer GENERATED ALWAYS AS IDENTITY UNIQUE,   -- the channel product id inside Fuxia 360
  PRIMARY KEY (target_id, shopify_product_id)
);
CREATE TABLE f360.shopify_variants (
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  shopify_variant_id bigint NOT NULL CHECK (shopify_variant_id > 0),
  link_id            integer GENERATED ALWAYS AS IDENTITY UNIQUE,   -- the channel variation id inside Fuxia 360
  shopify_product_id bigint NOT NULL CHECK (shopify_product_id > 0),
  inventory_item_id  bigint CHECK (inventory_item_id > 0),
  handle             text NOT NULL,
  product_title      text,
  color              text,
  size               text,
  sku                text,
  woo_product_id     bigint CHECK (woo_product_id > 0),      -- hint: old Woo product with the same slug
  woo_variation_id   bigint CHECK (woo_variation_id > 0),    -- hint: old Woo variation with the same colour + size (only when unique)
  seen_at            timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_id, shopify_variant_id),
  FOREIGN KEY (target_id, shopify_product_id) REFERENCES f360.shopify_products (target_id, shopify_product_id) ON DELETE RESTRICT
);
ALTER TABLE f360.shopify_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.shopify_variants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.shopify_products, f360.shopify_variants FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.shopify_products, f360.shopify_variants TO service_role;

CREATE FUNCTION f360.shopify_norm(p text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT lower(btrim(regexp_replace(translate(coalesce(p, ''), 'áéíóúüÁÉÍÓÚÜñÑ', 'aeiouuAEIOUUnN'), '\s+', ' ', 'g')))
$$;

CREATE FUNCTION f360.shopify_link_variants(p_target_key text, p_woo_target_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; w f360.sales_targets; v_new int; v_total int; v_linked int; v_pending jsonb;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND kind = 'shopify';
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda Shopify % no configurada.', p_target_key; END IF;
  SELECT * INTO w FROM f360.sales_targets WHERE key = p_woo_target_key AND kind = 'woocommerce';
  IF w.id IS NULL THEN RAISE EXCEPTION 'Tienda Woo % no configurada.', p_woo_target_key; END IF;

  WITH s AS (SELECT * FROM f360.shopify_variants WHERE target_id = t.id
               AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links l WHERE l.target_id = t.id AND l.woo_variation_id = link_id)),
  prods AS (   -- the Fuxia 360 product behind the old Woo product (same slug)
    SELECT s.link_id sid, pl.product_id FROM s JOIN f360.woo_product_links pl ON pl.target_id = w.id AND pl.woo_product_id = s.woo_product_id
    UNION SELECT s.link_id, p.id FROM s JOIN f360.products p ON p.wc_product_id = s.woo_product_id),
  by_product AS (
    SELECT s.link_id sid, v.id vid FROM s JOIN prods ON prods.sid = s.link_id
      JOIN f360.product_variants v ON v.product_id = prods.product_id AND v.status = 'active' AND v.size_label = btrim(s.size)
      JOIN f360.product_colors c ON c.id = v.color_id AND f360.shopify_norm(c.name) = f360.shopify_norm(s.color)),
  by_variation AS (   -- the old Woo variation (its own colour + size) → whatever Fuxia 360 already knows about it
    SELECT s.link_id sid, coalesce(vl.variant_id, rl.variant_id, m.confirmed_variant_id) vid FROM s
      LEFT JOIN f360.woo_variant_links vl ON vl.target_id = w.id AND vl.woo_variation_id = s.woo_variation_id
      LEFT JOIN f360.retired_woo_links rl ON rl.target_id = w.id AND rl.woo_variation_id = s.woo_variation_id
      LEFT JOIN f360.legacy_woo_map m ON m.target_id = w.id AND m.woo_variation_id = s.woo_variation_id AND m.status = 'confirmado'
     WHERE s.woo_variation_id IS NOT NULL AND coalesce(vl.variant_id, rl.variant_id, m.confirmed_variant_id) IS NOT NULL),
  cand AS (SELECT sid, vid FROM by_product
           UNION SELECT sid, vid FROM by_variation WHERE sid NOT IN (SELECT sid FROM by_product)),
  uniq AS (SELECT sid, min(vid::text)::uuid vid FROM cand GROUP BY sid HAVING count(DISTINCT vid) = 1),
  -- one Fuxia 360 pair ↔ one Shopify variant: two Shopify variants claiming the same pair are both left for review
  safe AS (SELECT u.* FROM uniq u WHERE (SELECT count(*) FROM uniq u2 WHERE u2.vid = u.vid) = 1
             AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links l WHERE l.target_id = t.id AND l.variant_id = u.vid))
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, woo_product_id, origin)
    SELECT t.id, safe.vid, safe.sid, p.link_id, 'legacy_adopted' FROM safe
      JOIN f360.shopify_variants s ON s.target_id = t.id AND s.link_id = safe.sid
      JOIN f360.shopify_products p ON p.target_id = t.id AND p.shopify_product_id = s.shopify_product_id
    ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_new = ROW_COUNT;

  SELECT count(*), count(l.variant_id) INTO v_total, v_linked FROM f360.shopify_variants s
    LEFT JOIN f360.woo_variant_links l ON l.target_id = t.id AND l.woo_variation_id = s.link_id WHERE s.target_id = t.id;
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'handle'), '[]') INTO v_pending FROM (
    SELECT jsonb_build_object('handle', s.handle, 'color', s.color, 'tallas', count(*)) x FROM f360.shopify_variants s
     WHERE s.target_id = t.id AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links l WHERE l.target_id = t.id AND l.woo_variation_id = s.link_id)
     GROUP BY s.handle, s.color) q;
  RETURN jsonb_build_object('nuevas', v_new, 'variantes', v_total, 'ligadas', v_linked, 'sin_ligar', v_total - v_linked, 'pendientes', v_pending);
END $$;

-- Same as 20261007001900 + a first branch for Shopify targets (see the header).
CREATE OR REPLACE FUNCTION f360.woo_variant_link_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT kind FROM f360.sales_targets WHERE id = NEW.target_id) = 'shopify' THEN
    IF NOT EXISTS (SELECT 1 FROM f360.shopify_variants s WHERE s.target_id = NEW.target_id AND s.link_id = NEW.woo_variation_id) THEN
      RAISE EXCEPTION 'Una liga de Shopify solo se crea para una variante del catálogo de Shopify (id interno %).', NEW.woo_variation_id;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.origin = 'legacy_adopted' AND NOT EXISTS (SELECT 1 FROM f360.legacy_woo_map m
       WHERE m.target_id = NEW.target_id AND m.woo_variation_id = NEW.woo_variation_id AND m.woo_product_id = NEW.woo_product_id
         AND m.status = 'confirmado' AND m.confirmed_variant_id = NEW.variant_id) THEN
    RAISE EXCEPTION 'Un vínculo legacy solo se crea desde una homologación confirmada por una persona (variación Woo %).', NEW.woo_variation_id;
  END IF;
  IF NEW.origin = 'legacy_adopted' AND f360.is_consolidated(NEW.target_id, (SELECT product_id FROM f360.product_variants WHERE id = NEW.variant_id)) THEN
    RAISE EXCEPTION 'Este modelo ya se unió en un solo producto de la tienda: ya no se liga a los productos anteriores.';
  END IF;
  IF NEW.origin = 'f360_published' AND EXISTS (SELECT 1 FROM f360.legacy_woo_map m WHERE m.confirmed_variant_id = NEW.variant_id)
     AND NOT f360.is_consolidated(NEW.target_id, (SELECT product_id FROM f360.product_variants WHERE id = NEW.variant_id)) THEN
    RAISE EXCEPTION 'Esta variante viene del catálogo Woo anterior: no se publica como producto nuevo.';
  END IF;
  RETURN NEW;
END $$;

-- Called by f360-shopify before ingesting: Shopify's product/variant ids in the (Woo-shaped) order → Fuxia 360's link ids.
-- A variant Fuxia 360 has never seen keeps no variation id (the sale is then recorded as unmatched and raises the usual
-- exception for Carolina, exactly like an unknown Woo SKU); its Shopify id is kept in shopify_variant_id for the record.
CREATE FUNCTION public.f360_shopify_localize(p_target_key text, p_order jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t uuid; li jsonb; out jsonb := '[]';
BEGIN
  SELECT id INTO t FROM f360.sales_targets WHERE key = p_target_key AND kind = 'shopify';
  IF t IS NULL THEN RAISE EXCEPTION 'Tienda Shopify % no configurada.', p_target_key; END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(coalesce(p_order->'line_items', '[]')) LOOP
    out := out || jsonb_build_array(li || jsonb_build_object(
      'shopify_variant_id', li->'variation_id', 'shopify_product_id', li->'product_id',
      'variation_id', (SELECT v.link_id FROM f360.shopify_variants v WHERE v.target_id = t AND v.shopify_variant_id = nullif(li->>'variation_id', '')::bigint),
      'product_id', (SELECT p.link_id FROM f360.shopify_products p WHERE p.target_id = t AND p.shopify_product_id = nullif(li->>'product_id', '')::bigint)));
  END LOOP;
  RETURN p_order || jsonb_build_object('line_items', out);
END $$;

-- Same as 20261008000100 + Shopify Payments.
CREATE OR REPLACE FUNCTION f360.commerce_payment_category(p_method text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN coalesce(p_method, '') = '' THEN 'unknown'
              WHEN p_method LIKE 'woo-mercado-pago%' OR p_method IN ('epayco', 'ppcp-card-button-gateway', 'stripe', 'ppcp-credit-card-gateway', 'shopify_payments') THEN 'card'
              WHEN p_method LIKE 'ppcp%' OR p_method LIKE 'paypal%' THEN 'paypal'
              WHEN p_method = 'bacs' THEN 'transfer'
              WHEN p_method = 'cod' THEN 'cash'
              WHEN p_method LIKE '%prueba%' OR p_method LIKE '%test%' THEN 'test'
              ELSE 'other' END $$;

REVOKE ALL ON FUNCTION f360.shopify_norm(text), f360.shopify_link_variants(text, text), public.f360_shopify_localize(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION f360.shopify_link_variants(text, text), public.f360_shopify_localize(text, jsonb) TO service_role;
