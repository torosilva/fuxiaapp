-- Track C · C3 fix (STAGING): a count may be added/corrected while the cutover is in verification or ready (e.g. a
-- legacy model gets its C2 mapping late and that size must be counted). Any count sends the cutover back to 'counting',
-- and the recounted line loses its verification, so completion always requires a fresh double control.
-- Rollback: previous definition in 20261004000100_f360_c3_cutover_and_f360_sale.sql (same signature).

CREATE OR REPLACE FUNCTION public.f360_cutover_count(p_cutover_id uuid, p_lines jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.location_cutovers; li jsonb; k text; v uuid; q int; old_status text; audit jsonb := '[]';
BEGIN
  SELECT * INTO c FROM f360.location_cutovers WHERE id = p_cutover_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Corte no encontrado.'; END IF;
  r := f360.require_counter(c.location_id);
  IF c.status NOT IN ('preparing', 'counting', 'verification', 'ready') THEN RAISE EXCEPTION 'El conteo no está abierto (estado: %).', c.status; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN RAISE EXCEPTION 'No hay cantidades.'; END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN ('variant_id', 'quantity') THEN RAISE EXCEPTION 'Solo se aceptan talla y cantidad (campo "%").', k; END IF;
    END LOOP;
    IF coalesce(li->>'variant_id', '') !~ '^[0-9a-fA-F-]{36}$' OR coalesce(li->>'quantity', '') !~ '^\d{1,5}$' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    v := (li->>'variant_id')::uuid; q := (li->>'quantity')::int;
    IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = v AND status = 'active') THEN RAISE EXCEPTION 'Una de las tallas no es válida.'; END IF;
    INSERT INTO f360.cutover_counts (cutover_id, variant_id, counted_qty, counted_by, counted_by_name)
      VALUES (c.id, v, q, r.auth_user_id, r.display_name)
      ON CONFLICT (cutover_id, variant_id) DO UPDATE SET counted_qty = EXCLUDED.counted_qty, counted_by = EXCLUDED.counted_by,
        counted_by_name = EXCLUDED.counted_by_name, counted_at = now(), verified_qty = NULL, verified_by = NULL, verified_by_name = NULL,
        verified_at = NULL, status = 'counted', recounts = f360.cutover_counts.recounts + 1;
    audit := audit || jsonb_build_object('variant_id', v, 'label', f360.variant_label(v), 'quantity', q);
  END LOOP;
  old_status := c.status;
  UPDATE f360.location_cutovers SET status = 'counting' WHERE id = c.id RETURNING * INTO c;
  PERFORM f360.cutover_log(c, 'count', old_status, audit, NULL, r);
  RETURN f360.cutover_json(c.id, r);
END $$;
