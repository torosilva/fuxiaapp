-- Rollback of Track C · C1. Restores the pre-C1 receive/list functions and role rules; drops C1 objects.
-- Refuses if any user already has role 'seller' (would violate the restored CHECK): reassign those users first.
BEGIN;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM f360.user_roles WHERE role = 'seller') THEN RAISE EXCEPTION 'Hay usuarios con rol seller: cámbialos antes del rollback.'; END IF; END $$;
DROP FUNCTION IF EXISTS public.f360_list_team();
DROP FUNCTION IF EXISTS public.f360_my_locations();
DROP FUNCTION IF EXISTS public.f360_set_location_assignment(uuid, uuid, boolean);
DROP FUNCTION IF EXISTS public.f360_set_user_role(uuid, text, text);
DROP FUNCTION IF EXISTS public.f360_create_location(text, text, uuid, boolean, date, date);
CREATE OR REPLACE FUNCTION public.f360_receive_inventory(p_idempotency_key uuid, p_location_id uuid, p_lines jsonb, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_event uuid; v_line jsonb; v_qty int; v_variant uuid; v_total int := 0;
BEGIN
  r := f360.require_role('operator');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  SELECT id INTO v_event FROM f360.inventory_events WHERE idempotency_key = p_idempotency_key;
  IF v_event IS NOT NULL THEN RETURN f360.event_json(v_event) || jsonb_build_object('replayed', true); END IF;

  IF NOT EXISTS (SELECT 1 FROM f360.locations WHERE id = p_location_id AND status = 'active') THEN
    RAISE EXCEPTION 'Elige una ubicación válida.';
  END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' THEN RAISE EXCEPTION 'No hay cantidades para recibir.'; END IF;

  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note)
    VALUES ('RECEIPT', p_idempotency_key, auth.uid(), r.display_name, r.role, nullif(btrim(p_note), ''))
    RETURNING id INTO v_event;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    v_qty := (v_line->>'quantity')::int;
    v_variant := (v_line->>'variant_id')::uuid;
    CONTINUE WHEN v_qty IS NULL OR v_qty = 0;
    IF v_qty < 0 THEN RAISE EXCEPTION 'Las cantidades no pueden ser negativas.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = v_variant AND status = 'active') THEN
      RAISE EXCEPTION 'Una de las tallas no es válida.';
    END IF;
    INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity)
      VALUES (v_event, v_variant, NULL, p_location_id, v_qty);
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand, last_event_id, updated_at)
      VALUES (v_variant, p_location_id, v_qty, v_event, now())
      ON CONFLICT (variant_id, location_id)
      DO UPDATE SET on_hand = f360.inventory_balances.on_hand + EXCLUDED.on_hand, last_event_id = v_event, updated_at = now();
    v_total := v_total + v_qty;
  END LOOP;

  IF v_total = 0 THEN RAISE EXCEPTION 'Escribe al menos un par para recibir.'; END IF;
  UPDATE f360.products SET updated_at = now()
    WHERE id IN (SELECT v.product_id FROM f360.inventory_movements m JOIN f360.product_variants v ON v.id = m.variant_id WHERE m.event_id = v_event);
  RETURN f360.event_json(v_event) || jsonb_build_object('replayed', false);
END $$;
CREATE OR REPLACE FUNCTION public.f360_list_locations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'name', l.name, 'type', l.type, 'is_authoritative', l.is_authoritative,
      'sales_sync_pending', l.sales_sync_pending,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id))
      ORDER BY l.sort, l.name), '[]'::jsonb)
    FROM f360.locations l WHERE l.status = 'active');
END $$;
DROP FUNCTION IF EXISTS f360.assert_ledger_location(uuid);
DROP FUNCTION IF EXISTS f360.require_location(uuid);
DROP TABLE IF EXISTS f360.access_changes;
DROP TABLE IF EXISTS f360.location_assignments;
DROP INDEX IF EXISTS f360.locations_legacy_channel_key;
ALTER TABLE f360.locations DROP CONSTRAINT IF EXISTS locations_dates_check, DROP COLUMN IF EXISTS ends_on, DROP COLUMN IF EXISTS starts_on,
  DROP COLUMN IF EXISTS sellable, DROP COLUMN IF EXISTS ledger_authority;
CREATE OR REPLACE FUNCTION f360.role_rank(p_role text) RETURNS int LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE p_role WHEN 'owner' THEN 3 WHEN 'operator' THEN 2 WHEN 'viewer' THEN 1 ELSE 0 END $$;
ALTER TABLE f360.user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;
ALTER TABLE f360.user_roles ADD CONSTRAINT user_roles_role_check CHECK (role IN ('owner', 'operator', 'viewer'));
COMMIT;
