-- Fuxia 360 · Tiendas: Cambios y Bajas (Altas already exist: f360_create_location). Mario 2026-10-05.
--   f360_update_location      owner edits name, type (store/bazaar/warehouse) and bazaar dates. Never the inventory master
--                             (ledger_authority) nor the legacy link: those belong to the cut (C3).
--   f360_deactivate_location  owner gives a location of baja = status 'inactive' (history kept; it disappears from every
--                             list that already filters status = 'active'). Refused while it still has pairs, transfers
--                             in progress, active Gold apartados, an open count, or is the online store's fulfillment.
-- Both write f360.access_changes (before/after). Seller shifts there end at once (require_seller_session re-checks live).
-- Rollback: supabase/rollbacks/20261010001100_f360_location_edit_deactivate.down.sql

CREATE FUNCTION public.f360_update_location(p_location_id uuid, p_name text, p_type text,
  p_starts_on date DEFAULT NULL, p_ends_on date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; b f360.locations; l f360.locations;
BEGIN
  r := f360.require_role('owner');
  SELECT * INTO b FROM f360.locations WHERE id = p_location_id FOR UPDATE;
  IF b.id IS NULL OR b.status <> 'active' THEN RAISE EXCEPTION 'Esa ubicación no existe o ya está dada de baja.'; END IF;
  IF b.type = 'transit' THEN RAISE EXCEPTION '"En camino" la maneja el sistema; no se edita.'; END IF;
  IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'Escribe el nombre de la ubicación.'; END IF;
  IF p_type NOT IN ('store', 'bazaar', 'warehouse') THEN RAISE EXCEPTION 'Tipo de ubicación no válido.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.locations WHERE lower(name) = lower(btrim(p_name)) AND id <> b.id) THEN
    RAISE EXCEPTION 'Ya hay una ubicación con ese nombre.';
  END IF;
  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'La fecha de fin no puede ser antes del inicio.';
  END IF;
  -- becoming a warehouse stops selling there: not while a Gold customer has pairs apartados in it
  IF p_type = 'warehouse' AND b.sellable AND EXISTS (SELECT 1 FROM f360.reservations WHERE location_id = b.id AND status = 'activa') THEN
    RAISE EXCEPTION 'Tiene apartados Gold activos. Espera a que se vendan, cancelen o venzan.';
  END IF;
  UPDATE f360.locations SET name = btrim(p_name), type = p_type,
      sellable = p_type IN ('store', 'bazaar'),                     -- same rule as the Alta
      starts_on = CASE WHEN p_type = 'bazaar' THEN p_starts_on END,
      ends_on   = CASE WHEN p_type = 'bazaar' THEN p_ends_on END
    WHERE id = b.id RETURNING * INTO l;
  IF NOT l.sellable THEN PERFORM f360.revoke_seller_sessions(a.auth_user_id, l.id, 'ubicación ya no vende')
    FROM f360.seller_sessions a WHERE a.location_id = l.id AND a.revoked_at IS NULL; END IF;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
    VALUES ('location', l.id::text, to_jsonb(b), to_jsonb(l), r.display_name, r.auth_user_id);
  RETURN to_jsonb(l);
END $$;

CREATE FUNCTION public.f360_deactivate_location(p_location_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; b f360.locations; l f360.locations; n int;
BEGIN
  r := f360.require_role('owner');
  SELECT * INTO b FROM f360.locations WHERE id = p_location_id FOR UPDATE;
  IF b.id IS NULL OR b.status <> 'active' THEN RAISE EXCEPTION 'Esa ubicación no existe o ya está dada de baja.'; END IF;
  IF b.type = 'transit' THEN RAISE EXCEPTION '"En camino" la maneja el sistema; no se da de baja.'; END IF;
  SELECT coalesce(sum(on_hand), 0) INTO n FROM f360.inventory_balances WHERE location_id = b.id;
  IF n <> 0 THEN RAISE EXCEPTION 'Todavía tiene % pares. Muévelos a otra ubicación antes de darla de baja.', n; END IF;
  IF EXISTS (SELECT 1 FROM f360.transfers WHERE b.id IN (from_location_id, to_location_id) AND status IN ('requested', 'in_transit', 'with_difference')) THEN
    RAISE EXCEPTION 'Tiene transferencias sin terminar. Ciérralas primero.';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.reservations WHERE location_id = b.id AND status = 'activa') THEN
    RAISE EXCEPTION 'Tiene apartados Gold activos. Espera a que se vendan, cancelen o venzan.';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.opening_counts WHERE location_id = b.id AND status IN ('preliminar', 'congelado')) THEN
    RAISE EXCEPTION 'Tiene un conteo abierto. Termínalo o cancélalo primero.';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.sales_targets WHERE fulfillment_location_id = b.id AND active) THEN
    RAISE EXCEPTION 'Desde aquí se surte la tienda en línea; no se puede dar de baja.';
  END IF;
  UPDATE f360.locations SET status = 'inactive' WHERE id = b.id RETURNING * INTO l;
  PERFORM f360.revoke_seller_sessions(s.auth_user_id, l.id, 'ubicación dada de baja')
    FROM f360.seller_sessions s WHERE s.location_id = l.id AND s.revoked_at IS NULL;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
    VALUES ('location', l.id::text, to_jsonb(b), to_jsonb(l), r.display_name, r.auth_user_id);
  RETURN jsonb_build_object('ok', true, 'name', l.name);
END $$;

REVOKE ALL ON FUNCTION public.f360_update_location(uuid, text, text, date, date), public.f360_deactivate_location(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_update_location(uuid, text, text, date, date), public.f360_deactivate_location(uuid) TO authenticated, service_role;
