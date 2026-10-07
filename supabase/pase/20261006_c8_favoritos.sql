-- Fuxia 360 · pase C8 — ♡ Favoritos V1 + V1.1 (same as migrations 20261012000800 + 20261012000900). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · Favoritos V1 (Mario 2026-10-06, STAGING first): the store's ♡ is an INTENT signal of Fuxia 360 from day one,
-- not an isolated browser list. V1 captures, anonymously, every favorite_added / favorite_removed from the store (/mx/ and /co/)
-- with the CANONICAL model (and colour / size when known) resolved server-side from the existing identity
-- (woo_product_links / woo_variant_links / legacy_woo_map) — no second product identity.
--   · f360.anon_visitors: one random browser id (uuid generated in the browser; never a name, phone, e-mail or IP).
--     customer_id / merged_at exist for V2 (anonymous → Club Fuxia customer) and are NOT written in V1.
--   · f360.favorite_events: append-only events. "Active favorites" = the latest event per (visitor, store product) is an add.
--   · f360_favorite_record(p): service_role only (the store's public endpoint f360-store-reserve calls it), validated and
--     rate-limited (120 events per visitor per hour).
--   · f360_favorites_report(target, days): "Favoritos / Intent" per model — active favorites, adds, removes, ATC (not
--     captured in Fuxia 360 yet: NULL, never invented) and units sold (stores + online) in the same window. viewer+; no PII.
-- Not in V1 (by decision): merging into customers, WhatsApp, Hilo reading favorites, store auto-ordering, recommendations, marketing.
-- Rollback: supabase/rollbacks/20261012000800_f360_favorites_intent.down.sql

CREATE TABLE f360.anon_visitors (
  anon_id      uuid PRIMARY KEY,
  first_seen   timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_seen    timestamptz NOT NULL DEFAULT clock_timestamp(),
  customer_id  uuid,          -- V2: the Club Fuxia customer she becomes (anonymous → identified). Not written in V1.
  merged_at    timestamptz    -- V2
);
ALTER TABLE f360.anon_visitors ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.anon_visitors FROM PUBLIC, anon, authenticated;

CREATE TABLE f360.favorite_events (
  id                bigserial PRIMARY KEY,
  anon_id           uuid NOT NULL REFERENCES f360.anon_visitors(anon_id) ON DELETE RESTRICT,
  event             text NOT NULL CHECK (event IN ('favorite_added', 'favorite_removed')),
  target_id         uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  market            text NOT NULL CHECK (market IN ('mx', 'co')),
  channel           text NOT NULL DEFAULT 'web' CHECK (channel IN ('web')),
  woo_product_id    integer NOT NULL CHECK (woo_product_id > 0),
  woo_variation_id  integer CHECK (woo_variation_id > 0),
  product_id        uuid REFERENCES f360.products(id) ON DELETE RESTRICT,          -- canonical model (NULL = not identified)
  color_id          uuid REFERENCES f360.product_colors(id) ON DELETE RESTRICT,
  variant_id        uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  at                timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX favorite_events_visitor_idx ON f360.favorite_events (anon_id, woo_product_id, id);
CREATE INDEX favorite_events_model_idx ON f360.favorite_events (target_id, product_id, at);
CREATE TRIGGER favorite_events_append_only BEFORE UPDATE OR DELETE ON f360.favorite_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
ALTER TABLE f360.favorite_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.favorite_events FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.f360_favorite_record(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t f360.sales_targets; anon uuid; ev text := p->>'event'; mk text := lower(coalesce(p->>'market', ''));
  wp int; wv int; prod uuid; col uuid; var uuid; color_name text := nullif(btrim(coalesce(p->>'color', '')), '');
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p->>'target_key' AND (active OR catalog_mode = 'on');
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  IF ev NOT IN ('favorite_added', 'favorite_removed') THEN RAISE EXCEPTION 'Evento no válido.'; END IF;
  IF mk NOT IN ('mx', 'co') THEN RAISE EXCEPTION 'Mercado no válido.'; END IF;
  BEGIN anon := (p->>'anon_id')::uuid; EXCEPTION WHEN OTHERS THEN anon := NULL; END;
  IF anon IS NULL THEN RAISE EXCEPTION 'Visitante no válido.'; END IF;
  wp := CASE WHEN (p->>'woo_product_id') ~ '^[0-9]{1,9}$' THEN (p->>'woo_product_id')::int END;
  wv := CASE WHEN (p->>'woo_variation_id') ~ '^[0-9]{1,9}$' THEN (p->>'woo_variation_id')::int END;
  IF coalesce(wp, 0) <= 0 THEN RAISE EXCEPTION 'Producto no válido.'; END IF;

  INSERT INTO f360.anon_visitors (anon_id) VALUES (anon) ON CONFLICT (anon_id) DO UPDATE SET last_seen = clock_timestamp();
  IF (SELECT count(*) FROM f360.favorite_events WHERE anon_id = anon AND at > clock_timestamp() - interval '1 hour') >= 120 THEN
    RETURN jsonb_build_object('ok', false, 'limited', true);
  END IF;

  -- canonical identity: published / merged product → its model; old store product → the model it was homologated to
  SELECT pl.product_id INTO prod FROM f360.woo_product_links pl WHERE pl.target_id = t.id AND pl.woo_product_id = wp;
  IF prod IS NULL THEN
    SELECT v.product_id INTO prod FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = t.id AND m.woo_product_id = wp AND m.status = 'confirmado' GROUP BY v.product_id ORDER BY count(*) DESC LIMIT 1;
  END IF;
  IF wv IS NOT NULL THEN
    SELECT vl.variant_id INTO var FROM f360.woo_variant_links vl WHERE vl.target_id = t.id AND vl.woo_variation_id = wv;
    IF var IS NULL THEN
      SELECT m.confirmed_variant_id INTO var FROM f360.legacy_woo_map m WHERE m.target_id = t.id AND m.woo_variation_id = wv AND m.status = 'confirmado' LIMIT 1;
    END IF;
    IF var IS NOT NULL THEN SELECT v.color_id, coalesce(prod, v.product_id) INTO col, prod FROM f360.product_variants v WHERE v.id = var; END IF;
  END IF;
  IF col IS NULL AND prod IS NOT NULL AND color_name IS NOT NULL THEN
    SELECT c.id INTO col FROM f360.product_colors c WHERE c.product_id = prod AND lower(btrim(c.name)) = lower(color_name) LIMIT 1;
  END IF;

  INSERT INTO f360.favorite_events (anon_id, event, target_id, market, woo_product_id, woo_variation_id, product_id, color_id, variant_id)
    VALUES (anon, ev, t.id, mk, wp, wv, prod, col, var);
  RETURN jsonb_build_object('ok', true, 'identified', prod IS NOT NULL);
END $$;

-- "Favoritos / Intent": one row per model (or per unidentified store product). ATC is not captured by Fuxia 360 yet → NULL.
CREATE FUNCTION public.f360_favorites_report(p_target_key text, p_days integer DEFAULT 30) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; d int := greatest(1, least(coalesce(p_days, 30), 365));
BEGIN
  PERFORM f360.require_role('viewer');
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND (active OR catalog_mode = 'on');
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  RETURN (WITH
    ev AS (SELECT e.*, coalesce(e.product_id::text, 'woo:' || e.woo_product_id) AS k FROM f360.favorite_events e WHERE e.target_id = t.id),
    latest AS (SELECT DISTINCT ON (anon_id, woo_product_id) anon_id, woo_product_id, k, event FROM ev ORDER BY anon_id, woo_product_id, id DESC),
    active AS (SELECT k, count(DISTINCT anon_id) AS n FROM latest WHERE event = 'favorite_added' GROUP BY k),
    win AS (SELECT k, count(*) FILTER (WHERE event = 'favorite_added') AS adds, count(*) FILTER (WHERE event = 'favorite_removed') AS removes
            FROM ev WHERE at > now() - make_interval(days => d) GROUP BY k),
    sold AS (SELECT v.product_id::text AS k, sum(q)::int AS units FROM (
               SELECT i.variant_id, i.quantity AS q FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id
                 WHERE i.variant_id IS NOT NULL AND s.created_at > now() - make_interval(days => d)
               UNION ALL
               SELECT l.variant_id, l.quantity FROM f360.woo_order_lines l WHERE l.variant_id IS NOT NULL AND l.outcome IN ('sold', 'sobre_pedido')
                 AND l.created_at > now() - make_interval(days => d)) x
             JOIN f360.product_variants v ON v.id = x.variant_id GROUP BY v.product_id),
    keys AS (SELECT k FROM active UNION SELECT k FROM win)
    SELECT jsonb_build_object('days', d, 'generated_at', now(), 'atc_captured', false,
      'rows', coalesce(jsonb_agg(jsonb_build_object(
        'key', keys.k, 'product_id', p.id, 'model', coalesce(p.name, 'Producto de la tienda #' || substr(keys.k, 5)),
        'identified', p.id IS NOT NULL, 'active', coalesce(a.n, 0), 'adds', coalesce(w.adds, 0), 'removes', coalesce(w.removes, 0),
        'atc', NULL, 'sold', CASE WHEN p.id IS NULL THEN NULL ELSE coalesce(s.units, 0) END)
        ORDER BY coalesce(a.n, 0) DESC, coalesce(w.adds, 0) DESC, coalesce(p.name, keys.k)), '[]'::jsonb))
    FROM keys LEFT JOIN active a ON a.k = keys.k LEFT JOIN win w ON w.k = keys.k LEFT JOIN sold s ON s.k = keys.k
    LEFT JOIN f360.products p ON p.id::text = keys.k);
END $$;

REVOKE ALL ON FUNCTION public.f360_favorite_record(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_favorite_record(jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.f360_favorites_report(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_favorites_report(text, integer) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261012000800', 'f360_favorites_intent', '{}');
-- Fuxia 360 · Favoritos V1.1 (Mario 2026-10-06: "sube de nivel el sitio"): "Agregar a la bolsa" right inside "Mis favoritos".
-- The store records favorite_add_to_cart (anonymous, with the variant) and the "Favoritos / Intent" report fills its ATC column
-- with REAL adds-to-cart made from favorites (atc_scope = 'favoritos'; adds from the product page are still only in GA4).
-- Active favorites ignore the add-to-cart events (a favourite stays a favourite after it goes to the bag).
-- Rollback: supabase/rollbacks/20261012000900_f360_favorites_add_to_cart.down.sql
ALTER TABLE f360.favorite_events DROP CONSTRAINT favorite_events_event_check;
ALTER TABLE f360.favorite_events ADD CONSTRAINT favorite_events_event_check CHECK (event IN ('favorite_added', 'favorite_removed', 'favorite_add_to_cart'));

CREATE OR REPLACE FUNCTION public.f360_favorite_record(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t f360.sales_targets; anon uuid; ev text := p->>'event'; mk text := lower(coalesce(p->>'market', ''));
  wp int; wv int; prod uuid; col uuid; var uuid; color_name text := nullif(btrim(coalesce(p->>'color', '')), '');
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p->>'target_key' AND (active OR catalog_mode = 'on');
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  IF ev NOT IN ('favorite_added', 'favorite_removed', 'favorite_add_to_cart') THEN RAISE EXCEPTION 'Evento no válido.'; END IF;
  IF mk NOT IN ('mx', 'co') THEN RAISE EXCEPTION 'Mercado no válido.'; END IF;
  BEGIN anon := (p->>'anon_id')::uuid; EXCEPTION WHEN OTHERS THEN anon := NULL; END;
  IF anon IS NULL THEN RAISE EXCEPTION 'Visitante no válido.'; END IF;
  wp := CASE WHEN (p->>'woo_product_id') ~ '^[0-9]{1,9}$' THEN (p->>'woo_product_id')::int END;
  wv := CASE WHEN (p->>'woo_variation_id') ~ '^[0-9]{1,9}$' THEN (p->>'woo_variation_id')::int END;
  IF coalesce(wp, 0) <= 0 THEN RAISE EXCEPTION 'Producto no válido.'; END IF;

  INSERT INTO f360.anon_visitors (anon_id) VALUES (anon) ON CONFLICT (anon_id) DO UPDATE SET last_seen = clock_timestamp();
  IF (SELECT count(*) FROM f360.favorite_events WHERE anon_id = anon AND at > clock_timestamp() - interval '1 hour') >= 120 THEN
    RETURN jsonb_build_object('ok', false, 'limited', true);
  END IF;

  -- canonical identity: published / merged product → its model; old store product → the model it was homologated to
  SELECT pl.product_id INTO prod FROM f360.woo_product_links pl WHERE pl.target_id = t.id AND pl.woo_product_id = wp;
  IF prod IS NULL THEN
    SELECT v.product_id INTO prod FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = t.id AND m.woo_product_id = wp AND m.status = 'confirmado' GROUP BY v.product_id ORDER BY count(*) DESC LIMIT 1;
  END IF;
  IF wv IS NOT NULL THEN
    SELECT vl.variant_id INTO var FROM f360.woo_variant_links vl WHERE vl.target_id = t.id AND vl.woo_variation_id = wv;
    IF var IS NULL THEN
      SELECT m.confirmed_variant_id INTO var FROM f360.legacy_woo_map m WHERE m.target_id = t.id AND m.woo_variation_id = wv AND m.status = 'confirmado' LIMIT 1;
    END IF;
    IF var IS NOT NULL THEN SELECT v.color_id, coalesce(prod, v.product_id) INTO col, prod FROM f360.product_variants v WHERE v.id = var; END IF;
  END IF;
  IF col IS NULL AND prod IS NOT NULL AND color_name IS NOT NULL THEN
    SELECT c.id INTO col FROM f360.product_colors c WHERE c.product_id = prod AND lower(btrim(c.name)) = lower(color_name) LIMIT 1;
  END IF;

  INSERT INTO f360.favorite_events (anon_id, event, target_id, market, woo_product_id, woo_variation_id, product_id, color_id, variant_id)
    VALUES (anon, ev, t.id, mk, wp, wv, prod, col, var);
  RETURN jsonb_build_object('ok', true, 'identified', prod IS NOT NULL);
END $$;


CREATE OR REPLACE FUNCTION public.f360_favorites_report(p_target_key text, p_days integer DEFAULT 30) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; d int := greatest(1, least(coalesce(p_days, 30), 365));
BEGIN
  PERFORM f360.require_role('viewer');
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND (active OR catalog_mode = 'on');
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  RETURN (WITH
    ev AS (SELECT e.*, coalesce(e.product_id::text, 'woo:' || e.woo_product_id) AS k FROM f360.favorite_events e WHERE e.target_id = t.id),
    latest AS (SELECT DISTINCT ON (anon_id, woo_product_id) anon_id, woo_product_id, k, event FROM ev WHERE event <> 'favorite_add_to_cart' ORDER BY anon_id, woo_product_id, id DESC),
    active AS (SELECT k, count(DISTINCT anon_id) AS n FROM latest WHERE event = 'favorite_added' GROUP BY k),
    win AS (SELECT k, count(*) FILTER (WHERE event = 'favorite_added') AS adds, count(*) FILTER (WHERE event = 'favorite_removed') AS removes,
                   count(*) FILTER (WHERE event = 'favorite_add_to_cart') AS atc
            FROM ev WHERE at > now() - make_interval(days => d) GROUP BY k),
    sold AS (SELECT v.product_id::text AS k, sum(q)::int AS units FROM (
               SELECT i.variant_id, i.quantity AS q FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id
                 WHERE i.variant_id IS NOT NULL AND s.created_at > now() - make_interval(days => d)
               UNION ALL
               SELECT l.variant_id, l.quantity FROM f360.woo_order_lines l WHERE l.variant_id IS NOT NULL AND l.outcome IN ('sold', 'sobre_pedido')
                 AND l.created_at > now() - make_interval(days => d)) x
             JOIN f360.product_variants v ON v.id = x.variant_id GROUP BY v.product_id),
    keys AS (SELECT k FROM active UNION SELECT k FROM win)
    SELECT jsonb_build_object('days', d, 'generated_at', now(), 'atc_captured', true, 'atc_scope', 'favoritos',
      'rows', coalesce(jsonb_agg(jsonb_build_object(
        'key', keys.k, 'product_id', p.id, 'model', coalesce(p.name, 'Producto de la tienda #' || substr(keys.k, 5)),
        'identified', p.id IS NOT NULL, 'active', coalesce(a.n, 0), 'adds', coalesce(w.adds, 0), 'removes', coalesce(w.removes, 0),
        'atc', coalesce(w.atc, 0), 'sold', CASE WHEN p.id IS NULL THEN NULL ELSE coalesce(s.units, 0) END)
        ORDER BY coalesce(a.n, 0) DESC, coalesce(w.adds, 0) DESC, coalesce(p.name, keys.k)), '[]'::jsonb))
    FROM keys LEFT JOIN active a ON a.k = keys.k LEFT JOIN win w ON w.k = keys.k LEFT JOIN sold s ON s.k = keys.k
    LEFT JOIN f360.products p ON p.id::text = keys.k);
END $$;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261012000900', 'f360_favorites_add_to_cart', '{}');
COMMIT;
