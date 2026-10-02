-- Fuxia 360 — archive / reactivate a product (STAGING). Additive. Nothing is deleted: history (inventory events,
-- sales, transfers, homologation) stays intact; an archived product just leaves the lists (f360_list_products,
-- f360_home, Homologación already show status = 'active' only).
-- Archive is refused while the product still matters operationally:
--   pairs in inventory (any location, incl. "En camino") · published by F360 to a store · adopted legacy link to a store
--   · open transfer · homologation confirmed on a real (non-practice) channel. Practice channels = key 'demo_…'.
-- Rollback: supabase/rollbacks/20261007000500_f360_product_archive.down.sql

CREATE TABLE f360.product_status_changes (
  id                  bigserial PRIMARY KEY,
  product_id          uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  from_status         text NOT NULL,
  to_status           text NOT NULL,
  reason              text NOT NULL,
  actor_auth_user_id  uuid,
  actor_name          text NOT NULL,
  at                  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION f360.product_status_log_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'El historial de archivado no se puede modificar.';
END $$;
CREATE TRIGGER product_status_changes_append_only BEFORE UPDATE OR DELETE ON f360.product_status_changes
  FOR EACH ROW EXECUTE FUNCTION f360.product_status_log_append_only();

-- Why a product cannot be archived right now (empty = it can).
CREATE FUNCTION f360.archive_blockers(p_product_id uuid) RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT array_remove(ARRAY[
    (SELECT format('Tiene %s pares en inventario', sum(b.on_hand)) FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
      WHERE v.product_id = p_product_id HAVING sum(b.on_hand) > 0),
    CASE WHEN EXISTS (SELECT 1 FROM f360.woo_product_links WHERE product_id = p_product_id) THEN 'Está publicado en la tienda en línea' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
      WHERE v.product_id = p_product_id AND vl.origin = 'legacy_adopted') THEN 'Está ligado a la tienda en línea' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.transfer_lines tl JOIN f360.transfers t ON t.id = tl.transfer_id JOIN f360.product_variants v ON v.id = tl.variant_id
      WHERE v.product_id = p_product_id AND t.status IN ('requested', 'in_transit', 'with_difference')) THEN 'Tiene transferencias abiertas' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      JOIN f360.sales_targets t ON t.id = m.target_id WHERE v.product_id = p_product_id AND t.key NOT LIKE 'demo\_%')
      THEN 'Está confirmado en Homologación: reabre esa confirmación primero' END
  ], NULL)
$$;

CREATE FUNCTION public.f360_product_archive_state(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360.products; last f360.product_status_changes;
BEGIN
  PERFORM f360.require_role('viewer');
  SELECT * INTO p FROM f360.products WHERE id = p_product_id;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  SELECT * INTO last FROM f360.product_status_changes WHERE product_id = p.id ORDER BY at DESC LIMIT 1;
  RETURN jsonb_build_object('status', p.status, 'blockers', to_jsonb(f360.archive_blockers(p.id)),
    'last_change', CASE WHEN last.id IS NULL THEN NULL ELSE jsonb_build_object('to', last.to_status, 'by', last.actor_name, 'at', last.at, 'reason', last.reason) END);
END $$;

CREATE FUNCTION public.f360_set_product_archived(p_product_id uuid, p_archived boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; p f360.products; b text[]; v_to text := CASE WHEN p_archived THEN 'archived' ELSE 'active' END;
BEGIN
  r := f360.require_role('operator');
  IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT * INTO p FROM f360.products WHERE id = p_product_id FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  IF p.status = v_to THEN RETURN public.f360_product_archive_state(p.id); END IF;
  IF p_archived THEN
    b := f360.archive_blockers(p.id);
    IF cardinality(b) > 0 THEN RAISE EXCEPTION 'No se puede archivar: %.', array_to_string(b, '; '); END IF;
  END IF;
  UPDATE f360.products SET status = v_to, updated_at = now() WHERE id = p.id;
  INSERT INTO f360.product_status_changes (product_id, from_status, to_status, reason, actor_auth_user_id, actor_name)
    VALUES (p.id, p.status, v_to, btrim(p_reason), auth.uid(), r.display_name);
  RETURN public.f360_product_archive_state(p.id);
END $$;

REVOKE ALL ON f360.product_status_changes FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.product_status_changes TO service_role;
GRANT USAGE, SELECT ON SEQUENCE f360.product_status_changes_id_seq TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_product_archive_state(uuid), public.f360_set_product_archived(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_product_archive_state(uuid), public.f360_set_product_archived(uuid, boolean, text) TO authenticated, service_role;
