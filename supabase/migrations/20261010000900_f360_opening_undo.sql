-- Fuxia 360 · Conteo de apertura: deshacer errores mientras se cuenta. STAGING.
-- Request: Carolina 2026-10-05 ("mientras cargo el inventario déjame borrar si me equivoco").
-- Before: a size could only be overwritten (incl. 0), never returned to "sin contar"; a "par que no está en la lista"
-- written by mistake could not be removed (only "resuelto" by an owner, with a note).
-- Now, ONLY while the count is open (preliminar/congelado) and only in 'simple' mode for sizes:
--   * f360_opening_clear_line: a counted size goes back to 'pendiente' (no quantity). It then blocks approval again
--     until it is counted, so nothing can be loaded "half counted".
--   * f360_opening_remove_unlisted: an open unlisted entry is marked 'quitado' (kept, never deleted). Its author or an
--     owner may do it.
--   * f360_opening_unlisted_open: the open unlisted entries, so the phone screen can show them with "Quitar".
-- Nothing here writes inventory; every change goes to the append-only change log with the previous value.
-- Rollback: supabase/rollbacks/20261010000900_f360_opening_undo.down.sql

ALTER TABLE f360.opening_count_unlisted DROP CONSTRAINT opening_count_unlisted_status_check;
ALTER TABLE f360.opening_count_unlisted ADD CONSTRAINT opening_count_unlisted_status_check CHECK (status IN ('abierto', 'resuelto', 'quitado'));

CREATE FUNCTION public.f360_opening_clear_line(p_count_id uuid, p_variant_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); c f360.opening_counts; l f360.opening_count_lines;
BEGIN
  SELECT * INTO c FROM f360.opening_counts WHERE id = p_count_id FOR UPDATE;
  IF c.id IS NULL OR c.status NOT IN ('preliminar', 'congelado') THEN RAISE EXCEPTION 'El conteo no está abierto.'; END IF;
  IF c.mode <> 'simple' THEN RAISE EXCEPTION 'Solo se puede borrar una talla en el conteo de una sola vuelta.'; END IF;
  SELECT * INTO l FROM f360.opening_count_lines WHERE count_id = c.id AND variant_id = p_variant_id FOR UPDATE;
  IF l.variant_id IS NULL OR NOT l.in_scope THEN RAISE EXCEPTION 'Esa talla no está en este conteo.'; END IF;
  IF l.status = 'pendiente' THEN RETURN public.f360_opening_state(c.id); END IF;
  IF l.status <> 'contado' THEN RAISE EXCEPTION 'La talla % no se puede borrar (%): recuéntala.', f360.variant_label(l.variant_id), l.status; END IF;
  UPDATE f360.opening_count_lines SET count1 = NULL, count1_by = NULL, count1_by_name = NULL, count1_at = NULL,
      status = 'pendiente', final_qty = NULL, final_at = NULL, affected = NULL
    WHERE count_id = c.id AND variant_id = l.variant_id;
  PERFORM f360.opening_log(c.id, 'clear_line', jsonb_build_object('variant_id', l.variant_id, 'previous_qty', l.final_qty,
    'previous_by', l.count1_by_name, 'previous_at', l.count1_at), r);
  RETURN public.f360_opening_state(c.id);
END $$;

CREATE FUNCTION public.f360_opening_remove_unlisted(p_unlisted_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); u f360.opening_count_unlisted; c f360.opening_counts;
BEGIN
  SELECT * INTO u FROM f360.opening_count_unlisted WHERE id = p_unlisted_id FOR UPDATE;
  IF u.id IS NULL OR u.status <> 'abierto' THEN RAISE EXCEPTION 'Registro no encontrado o ya resuelto.'; END IF;
  SELECT * INTO c FROM f360.opening_counts WHERE id = u.count_id;
  IF c.status NOT IN ('preliminar', 'congelado') THEN RAISE EXCEPTION 'El conteo no está abierto.'; END IF;
  IF r.role <> 'owner' AND u.found_by_name <> r.display_name THEN RAISE EXCEPTION 'Solo quien lo anotó o Carolina pueden quitarlo.'; END IF;
  UPDATE f360.opening_count_unlisted SET status = 'quitado', resolution = 'Quitado: anotado por error', resolved_by_name = r.display_name, resolved_at = clock_timestamp()
    WHERE id = u.id;
  PERFORM f360.opening_log(u.count_id, 'unlisted_remove', jsonb_build_object('id', u.id, 'description', u.description, 'size', u.size_label, 'quantity', u.quantity), r);
  RETURN public.f360_opening_state(u.count_id);
END $$;

CREATE FUNCTION public.f360_opening_unlisted_open(p_count_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'description', u.description, 'size', u.size_label, 'quantity', u.quantity,
      'found_by', u.found_by_name, 'found_at', u.found_at) ORDER BY u.found_at DESC), '[]')
    FROM f360.opening_count_unlisted u WHERE u.count_id = p_count_id AND u.status = 'abierto');
END $$;

REVOKE ALL ON FUNCTION public.f360_opening_clear_line(uuid, uuid), public.f360_opening_remove_unlisted(uuid), public.f360_opening_unlisted_open(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_opening_clear_line(uuid, uuid), public.f360_opening_remove_unlisted(uuid), public.f360_opening_unlisted_open(uuid) TO authenticated;
