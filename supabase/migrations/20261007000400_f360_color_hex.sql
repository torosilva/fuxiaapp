-- Fuxia 360 — set a colour's swatch (hex) by hand after creation (STAGING). Additive.
-- The swatch is display only: it is not part of any code, SKU, inventory or Woo link. NULL removes it.
-- Rollback: supabase/rollbacks/20261007000400_f360_color_hex.down.sql
CREATE FUNCTION public.f360_set_color_hex(p_color_id uuid, p_hex text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_product uuid; v_hex text := nullif(btrim(p_hex), '');
BEGIN
  r := f360.require_role('operator');
  IF v_hex IS NOT NULL AND v_hex !~ '^#[0-9A-Fa-f]{6}$' THEN RAISE EXCEPTION 'Color no válido.'; END IF;
  UPDATE f360.product_colors SET hex = upper(v_hex) WHERE id = p_color_id RETURNING product_id INTO v_product;
  IF v_product IS NULL THEN RAISE EXCEPTION 'Color no encontrado.'; END IF;
  UPDATE f360.products SET updated_at = now() WHERE id = v_product;
  RETURN public.f360_get_product(v_product);
END $$;
REVOKE ALL ON FUNCTION public.f360_set_color_hex(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_set_color_hex(uuid, text) TO authenticated, service_role;
