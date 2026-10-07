-- Fuxia 360 · the order of the store's shop page comes from Fuxia 360 (Mario 2026-10-06: "que se pudiera tener alguna
-- inteligencia de acomodo ... indicada desde Fuxia 360 de cuáles aparecen primero, marcar los productos como los más vendidos").
-- WooCommerce's own "popularity" cannot do it: the products published from Fuxia 360 are new in the store (0 sales there), while
-- Fuxia 360 knows the real sales (stores + online + the old store products' history read at homologation).
--   · products.store_rank: 1, 2, 3… = "⭐ Destacado" in that position (first in the shop); NULL = automatic.
--   · The order: destacados (by rank) → units sold in the last 60 days (same sources as the shop's "Más vendidas") → newest → name.
--   · f360_store_order(target): the plan as the shop will show it (viewer+, internal: shows units sold).
--   · f360_set_store_featured(ids[]): the destacados, in order (operator+, like "Nueva"); audited in catalog_changes.
--   · f360_pub_order_begin / _finish: service_role only (the publisher writes Woo menu_order); owner re-checked; audited in
--     f360.store_order_runs (append-only).
-- Rollback: supabase/rollbacks/20261012000700_f360_store_order.down.sql

ALTER TABLE f360.products ADD COLUMN store_rank integer CHECK (store_rank > 0);

CREATE TABLE f360.store_order_runs (
  id        bigserial PRIMARY KEY,
  target_id uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  items     integer NOT NULL,
  ok        boolean NOT NULL,
  message   text,
  by_user   uuid NOT NULL,
  by_name   text NOT NULL,
  at        timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER store_order_runs_append_only BEFORE UPDATE OR DELETE ON f360.store_order_runs FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
ALTER TABLE f360.store_order_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.store_order_runs FROM PUBLIC, anon, authenticated;

-- Units sold per model in the last 60 days, every channel (same sources as the shop's "Más vendidas").
CREATE FUNCTION f360.product_units_sold(p_target_id uuid) RETURNS TABLE (product_id uuid, units integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT v.product_id, sum(q)::int FROM (
    SELECT i.variant_id, i.quantity AS q FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id
      WHERE i.variant_id IS NOT NULL AND s.created_at > now() - interval '60 days'
    UNION ALL
    SELECT l.variant_id, l.quantity FROM f360.woo_order_lines l WHERE l.variant_id IS NOT NULL AND l.outcome IN ('sold', 'sobre_pedido') AND l.created_at > now() - interval '60 days'
    UNION ALL
    SELECT m.confirmed_variant_id, m.sold_90d FROM f360.legacy_woo_map m WHERE m.target_id = p_target_id AND m.status = 'confirmado' AND m.sold_90d > 0
  ) x JOIN f360.product_variants v ON v.id = x.variant_id GROUP BY v.product_id
$$;

-- Every store product of this channel, in the order the shop will show them (position 1 = first).
CREATE FUNCTION f360.store_order_plan(p_target_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH rows AS (
    SELECT pl.woo_product_id, pl.product_id, false AS legacy FROM f360.woo_product_links pl WHERE pl.target_id = p_target_id
    UNION
    -- old store products of models not merged yet (still visible in the shop)
    SELECT DISTINCT m.woo_product_id, v.product_id, true FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = p_target_id AND m.status = 'confirmado' AND m.woo_product_id IS NOT NULL AND NOT f360.is_consolidated(p_target_id, v.product_id)),
  -- an old store product sold one colour: it ranks by ITS OWN sales (read at homologation), not the whole model's
  legacy_sold AS (
    SELECT m.woo_product_id, sum(m.sold_90d)::int AS units FROM f360.legacy_woo_map m
      WHERE m.target_id = p_target_id AND m.status = 'confirmado' AND m.sold_90d > 0 GROUP BY m.woo_product_id),
  scored AS (
    SELECT r.*, p.name, p.store_rank, p.created_at,
           CASE WHEN r.legacy THEN coalesce(ls.units, 0) ELSE coalesce(s.units, 0) END AS sold
    FROM rows r JOIN f360.products p ON p.id = r.product_id AND p.status = 'active'
    LEFT JOIN f360.product_units_sold(p_target_id) s ON s.product_id = r.product_id
    LEFT JOIN legacy_sold ls ON ls.woo_product_id = r.woo_product_id),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY store_rank NULLS LAST, sold DESC, legacy, created_at DESC, name, woo_product_id) AS position FROM scored)
  SELECT coalesce(jsonb_agg(jsonb_build_object('position', position, 'woo_product_id', woo_product_id, 'product_id', product_id, 'name', name,
    'store_rank', store_rank, 'sold', sold, 'legacy', legacy) ORDER BY position), '[]'::jsonb) FROM ranked
$$;

CREATE FUNCTION public.f360_store_order(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; last jsonb;
BEGIN
  PERFORM f360.require_role('viewer');
  t := f360.catalog_target(p_target_key);
  SELECT jsonb_build_object('at', r.at, 'ok', r.ok, 'items', r.items, 'message', r.message, 'by', r.by_name) INTO last
    FROM f360.store_order_runs r WHERE r.target_id = t.id ORDER BY r.id DESC LIMIT 1;
  RETURN jsonb_build_object('items', f360.store_order_plan(t.id), 'last_run', last);
END $$;

CREATE FUNCTION public.f360_set_store_featured(p_product_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; ids uuid[] := coalesce(p_product_ids, '{}'); p record; n int;
BEGIN
  r := f360.require_role('operator');
  IF cardinality(ids) > 60 THEN RAISE EXCEPTION 'Máximo 60 destacados.'; END IF;
  IF cardinality(ids) <> (SELECT count(DISTINCT x) FROM unnest(ids) x) THEN RAISE EXCEPTION 'Un modelo aparece dos veces.'; END IF;
  SELECT count(*) INTO n FROM f360.products WHERE id = ANY (ids) AND status = 'active';
  IF n <> cardinality(ids) THEN RAISE EXCEPTION 'Algún modelo no existe o está archivado.'; END IF;
  FOR p IN
    SELECT pr.id, pr.store_rank AS before, a.ord::int AS after
    FROM f360.products pr LEFT JOIN unnest(ids) WITH ORDINALITY a(id, ord) ON a.id = pr.id
    WHERE (pr.store_rank IS NOT NULL OR a.id IS NOT NULL) ORDER BY pr.id FOR UPDATE OF pr
  LOOP
    CONTINUE WHEN p.before IS NOT DISTINCT FROM p.after;
    UPDATE f360.products SET store_rank = p.after, updated_at = now() WHERE id = p.id;
    INSERT INTO f360.catalog_changes (product_id, what, detail, actor_auth_user_id, actor_name)
      VALUES (p.id, 'store_rank', jsonb_build_object('from', p.before, 'to', p.after), r.auth_user_id, r.display_name);
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'featured', cardinality(ids));
END $$;

CREATE FUNCTION public.f360_pub_order_begin(p_target_key text, p_caller uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner') THEN
    RAISE EXCEPTION 'Solo una dueña puede cambiar el orden de la tienda.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  t := f360.catalog_target(p_target_key);
  RETURN jsonb_build_object('target', jsonb_build_object('key', t.key, 'base_url', t.base_url),
    'items', (SELECT coalesce(jsonb_agg(jsonb_build_object('woo_product_id', (x->>'woo_product_id')::int, 'position', (x->>'position')::int)), '[]'::jsonb)
              FROM jsonb_array_elements(f360.store_order_plan(t.id)) x));
END $$;

CREATE FUNCTION public.f360_pub_order_finish(p_target_key text, p_caller uuid, p_ok boolean, p_items integer, p_message text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; r f360.user_roles;
BEGIN
  SELECT * INTO r FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner';
  IF r.auth_user_id IS NULL THEN RAISE EXCEPTION 'Solo una dueña puede cambiar el orden de la tienda.' USING ERRCODE = 'insufficient_privilege'; END IF;
  t := f360.catalog_target(p_target_key);
  INSERT INTO f360.store_order_runs (target_id, items, ok, message, by_user, by_name)
    VALUES (t.id, greatest(coalesce(p_items, 0), 0), p_ok, left(p_message, 500), p_caller, r.display_name);
  RETURN jsonb_build_object('ok', p_ok, 'items', p_items);
END $$;

REVOKE ALL ON FUNCTION f360.product_units_sold(uuid), f360.store_order_plan(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_store_order(text), public.f360_set_store_featured(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_store_order(text), public.f360_set_store_featured(uuid[]) TO authenticated;
REVOKE ALL ON FUNCTION public.f360_pub_order_begin(text, uuid), public.f360_pub_order_finish(text, uuid, boolean, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_pub_order_begin(text, uuid), public.f360_pub_order_finish(text, uuid, boolean, integer, text) TO service_role;
