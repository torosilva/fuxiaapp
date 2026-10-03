-- Fuxia 360 — rename a colour + stores screen support (STAGING). Additive. Asked by Mario 2026-10-02.
--   * f360_rename_color: changes the colour's visible NAME only. Its code and every SKU stay as they are (SKUs are
--     identity; a store-adopted variation is matched by woo_variation_id). Logged in f360.catalog_changes.
--   * f360_legacy_channels_available: the stores / bazaars of the legacy system not yet linked to a Fuxia 360
--     location, so an owner can create the location linked to it (it then starts on the legacy ledger until its C3 cut).
-- Rollback: supabase/rollbacks/20261007001000_f360_stores_rename_color.down.sql

CREATE FUNCTION public.f360_rename_color(p_color_id uuid, p_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.product_colors; v_name text := btrim(p_name);
BEGIN
  r := f360.require_role('operator');
  IF coalesce(v_name, '') = '' THEN RAISE EXCEPTION 'Escribe el nombre del color.'; END IF;
  SELECT * INTO c FROM f360.product_colors WHERE id = p_color_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Color no encontrado.'; END IF;
  IF c.name = v_name THEN RETURN public.f360_get_product(c.product_id); END IF;
  IF EXISTS (SELECT 1 FROM f360.product_colors WHERE product_id = c.product_id AND id <> c.id AND lower(name) = lower(v_name)) THEN
    RAISE EXCEPTION 'Este modelo ya tiene un color llamado "%".', v_name;
  END IF;
  UPDATE f360.product_colors SET name = v_name WHERE id = c.id;          -- code (and SKUs) unchanged on purpose
  UPDATE f360.products SET updated_at = now() WHERE id = c.product_id;
  INSERT INTO f360.catalog_changes (product_id, what, detail, actor_auth_user_id, actor_name)
    VALUES (c.product_id, 'rename_color', jsonb_build_object('from', c.name, 'to', v_name, 'code', c.code), auth.uid(), r.display_name);
  RETURN public.f360_get_product(c.product_id);
END $$;

CREATE FUNCTION public.f360_legacy_channels_available() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('owner');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', ch.id, 'name', ch.name, 'type', ch.type, 'active', ch.active,
      'legacy_pairs', (SELECT coalesce(sum(greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0)), 0) FROM public.channel_inventory ci WHERE ci.channel_id = ch.id))
      ORDER BY ch.name), '[]')
    FROM public.channels ch WHERE NOT EXISTS (SELECT 1 FROM f360.locations l WHERE l.legacy_channel_id = ch.id));
END $$;

REVOKE ALL ON FUNCTION public.f360_rename_color(uuid, text), public.f360_legacy_channels_available() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_rename_color(uuid, text), public.f360_legacy_channels_available() TO authenticated, service_role;
