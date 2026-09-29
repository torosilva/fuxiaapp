-- Fuxia 360 Track C · C1 — Staff identity (roles) + locations + assignments. STAGING. Additive; no real
-- locations, sellers or counts are created (D-L1 pending). The mobile app is NOT changed.
--
--   · role `seller` (read level = viewer; writes only through location-scoped RPCs at ASSIGNED locations)
--   · f360.locations: ledger_authority (legacy|f360) = ONE master per location; sellable; bazaar dates
--   · f360.location_assignments: user → location, explicit, several allowed (D-L2)
--   · f360.access_changes: append-only audit of every role / assignment / location change
--   · f360.require_location(): the server rule every seller operation will use
--   · f360_receive_inventory now refuses locations whose master is still the legacy system
-- Boundary: authentication mechanics (PIN hash, seller sessions, lockout, public.staff link) belong to S0.2,
-- which will build ON these tables (docs/fuxia360/ops/TRACK_C_BOUNDARY_S0.md).
-- Rollback: supabase/rollbacks/20260930000100_f360_c1_locations_roles.down.sql

-- ── Roles ───────────────────────────────────────────────────────────────────
ALTER TABLE f360.user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;
ALTER TABLE f360.user_roles ADD CONSTRAINT user_roles_role_check CHECK (role IN ('owner', 'operator', 'seller', 'viewer'));
-- seller reads like a viewer; everything a seller WRITES goes through f360.require_location (assigned locations only)
CREATE OR REPLACE FUNCTION f360.role_rank(p_role text) RETURNS int LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE p_role WHEN 'owner' THEN 3 WHEN 'operator' THEN 2 WHEN 'seller' THEN 1 WHEN 'viewer' THEN 1 ELSE 0 END $$;

-- ── Locations ───────────────────────────────────────────────────────────────
ALTER TABLE f360.locations
  ADD COLUMN ledger_authority text NOT NULL DEFAULT 'f360' CHECK (ledger_authority IN ('legacy', 'f360')),
  ADD COLUMN sellable boolean NOT NULL DEFAULT false,
  ADD COLUMN starts_on date,
  ADD COLUMN ends_on date,
  ADD CONSTRAINT locations_dates_check CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on);
CREATE UNIQUE INDEX locations_legacy_channel_key ON f360.locations (legacy_channel_id) WHERE legacy_channel_id IS NOT NULL;
COMMENT ON COLUMN f360.locations.ledger_authority IS
  'Which system may change stock here. legacy = public.channel_inventory (pre-cutover); f360 = the f360 ledger. Changed ONLY by the C3 cutover procedure.';

CREATE TABLE f360.location_assignments (
  auth_user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  location_id       uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  active            boolean NOT NULL DEFAULT true,
  granted_by_name   text NOT NULL,
  granted_at        timestamptz NOT NULL DEFAULT now(),
  revoked_by_name   text,
  revoked_at        timestamptz,
  PRIMARY KEY (auth_user_id, location_id)
);

CREATE TABLE f360.access_changes (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  what        text NOT NULL,          -- role | assignment | location
  subject     text NOT NULL,          -- auth user id or location id
  before      jsonb,
  after       jsonb,
  by_name     text NOT NULL,
  by_user     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  at          timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER access_changes_append_only BEFORE UPDATE OR DELETE ON f360.access_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ── Server rules ────────────────────────────────────────────────────────────
-- Caller may act at p_location: owner/operator anywhere; seller ONLY with an active assignment; viewer never.
CREATE FUNCTION f360.require_location(p_location uuid) RETURNS f360.user_roles
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  IF NOT EXISTS (SELECT 1 FROM f360.locations WHERE id = p_location AND status = 'active') THEN RAISE EXCEPTION 'Ubicación no válida.'; END IF;
  IF r.role IN ('owner', 'operator') THEN RETURN r; END IF;
  IF r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = p_location AND a.active) THEN
    RETURN r;
  END IF;
  RAISE EXCEPTION 'No tienes asignada esta ubicación.' USING ERRCODE = 'insufficient_privilege';
END $$;

-- The location's stock is mastered by the f360 ledger (not the legacy channel_inventory).
CREATE FUNCTION f360.assert_ledger_location(p_location uuid) RETURNS f360.locations
LANGUAGE plpgsql STABLE AS $$
DECLARE l f360.locations;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = p_location AND status = 'active';
  IF l.id IS NULL THEN RAISE EXCEPTION 'Elige una ubicación válida.'; END IF;
  IF l.ledger_authority <> 'f360' THEN
    RAISE EXCEPTION '% todavía lleva su inventario en el sistema anterior. Se podrá operar aquí cuando se migre.', l.name;
  END IF;
  RETURN l;
END $$;

-- ── Receive: one master per location ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.f360_receive_inventory(p_idempotency_key uuid, p_location_id uuid, p_lines jsonb, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_event uuid; v_line jsonb; v_qty int; v_variant uuid; v_total int := 0;
BEGIN
  r := f360.require_role('operator');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  SELECT id INTO v_event FROM f360.inventory_events WHERE idempotency_key = p_idempotency_key;
  IF v_event IS NOT NULL THEN RETURN f360.event_json(v_event) || jsonb_build_object('replayed', true); END IF;

  PERFORM f360.assert_ledger_location(p_location_id);   -- C1: never write f360 stock where the legacy system is master
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

-- Location list now tells the UI whether a location can be operated in Fuxia 360.
CREATE OR REPLACE FUNCTION public.f360_list_locations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'name', l.name, 'type', l.type, 'is_authoritative', l.is_authoritative,
      'sales_sync_pending', l.sales_sync_pending, 'ledger_authority', l.ledger_authority, 'sellable', l.sellable,
      'starts_on', l.starts_on, 'ends_on', l.ends_on,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id))
      ORDER BY l.sort, l.name), '[]'::jsonb)
    FROM f360.locations l WHERE l.status = 'active');
END $$;

-- ── Owner RPCs: locations, roles, assignments (every change audited) ─────────
CREATE FUNCTION public.f360_create_location(p_name text, p_type text, p_legacy_channel_id uuid DEFAULT NULL,
  p_sellable boolean DEFAULT NULL, p_starts_on date DEFAULT NULL, p_ends_on date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; l f360.locations;
BEGIN
  r := f360.require_role('owner');
  IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'Escribe el nombre de la ubicación.'; END IF;
  IF p_type NOT IN ('warehouse', 'receiving', 'store', 'bazaar', 'workshop', 'other') THEN RAISE EXCEPTION 'Tipo de ubicación no válido.'; END IF;
  IF p_legacy_channel_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.channels WHERE id = p_legacy_channel_id) THEN
    RAISE EXCEPTION 'Esa tienda/bazar del sistema anterior no existe.';
  END IF;
  INSERT INTO f360.locations (name, type, legacy_channel_id, ledger_authority, sellable, starts_on, ends_on, is_authoritative, sales_sync_pending)
    VALUES (btrim(p_name), p_type, p_legacy_channel_id,
            -- a location that already has stock in the legacy system starts LEGACY (one master); C3 switches it
            CASE WHEN p_legacy_channel_id IS NULL THEN 'f360' ELSE 'legacy' END,
            coalesce(p_sellable, p_type IN ('store', 'bazaar')), p_starts_on, p_ends_on,
            p_type IN ('warehouse', 'receiving'), false)
    RETURNING * INTO l;
  INSERT INTO f360.access_changes (what, subject, after, by_name, by_user) VALUES ('location', l.id::text, to_jsonb(l), r.display_name, r.auth_user_id);
  RETURN to_jsonb(l);
END $$;

CREATE FUNCTION public.f360_set_user_role(p_auth_user_id uuid, p_role text, p_display_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; before jsonb; ur f360.user_roles;
BEGIN
  r := f360.require_role('owner');
  IF p_role NOT IN ('owner', 'operator', 'seller', 'viewer') THEN RAISE EXCEPTION 'Rol no válido.'; END IF;
  IF coalesce(btrim(p_display_name), '') = '' THEN RAISE EXCEPTION 'Escribe el nombre de la persona.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_user_id) THEN RAISE EXCEPTION 'La persona debe tener su propia cuenta (iniciar sesión una vez).'; END IF;
  SELECT to_jsonb(u) INTO before FROM f360.user_roles u WHERE auth_user_id = p_auth_user_id;
  IF before->>'role' = 'owner' AND p_role <> 'owner' AND (SELECT count(*) FROM f360.user_roles WHERE role = 'owner') = 1 THEN
    RAISE EXCEPTION 'Debe quedar al menos una dueña.';
  END IF;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (p_auth_user_id, p_role, btrim(p_display_name), r.display_name)
    ON CONFLICT (auth_user_id) DO UPDATE SET role = EXCLUDED.role, display_name = EXCLUDED.display_name, granted_by = EXCLUDED.granted_by
    RETURNING * INTO ur;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user) VALUES ('role', p_auth_user_id::text, before, to_jsonb(ur), r.display_name, r.auth_user_id);
  RETURN to_jsonb(ur);
END $$;

CREATE FUNCTION public.f360_set_location_assignment(p_auth_user_id uuid, p_location_id uuid, p_active boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; a f360.location_assignments; before jsonb;
BEGIN
  r := f360.require_role('owner');
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_auth_user_id AND role = 'seller') THEN
    RAISE EXCEPTION 'Solo se asignan ubicaciones a vendedoras.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.locations WHERE id = p_location_id AND status = 'active') THEN RAISE EXCEPTION 'Ubicación no válida.'; END IF;
  SELECT to_jsonb(x) INTO before FROM f360.location_assignments x WHERE auth_user_id = p_auth_user_id AND location_id = p_location_id;
  IF p_active THEN
    INSERT INTO f360.location_assignments (auth_user_id, location_id, active, granted_by_name) VALUES (p_auth_user_id, p_location_id, true, r.display_name)
      ON CONFLICT (auth_user_id, location_id) DO UPDATE SET active = true, granted_by_name = EXCLUDED.granted_by_name, granted_at = now(),
        revoked_by_name = NULL, revoked_at = NULL
      RETURNING * INTO a;
  ELSE
    UPDATE f360.location_assignments SET active = false, revoked_by_name = r.display_name, revoked_at = now()
      WHERE auth_user_id = p_auth_user_id AND location_id = p_location_id RETURNING * INTO a;
    IF a.auth_user_id IS NULL THEN RAISE EXCEPTION 'Esa asignación no existe.'; END IF;
  END IF;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user) VALUES ('assignment', p_auth_user_id::text, before, to_jsonb(a), r.display_name, r.auth_user_id);
  RETURN to_jsonb(a);
END $$;

-- Start of shift (D-L2): the locations the caller may choose. Sellers: ONLY their active assignments.
CREATE FUNCTION public.f360_my_locations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'sellable', l.sellable,
      'ledger_authority', l.ledger_authority) ORDER BY l.sort, l.name), '[]')
    FROM f360.locations l
    WHERE l.status = 'active' AND (
      r.role IN ('owner', 'operator')
      OR (r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = l.id AND a.active))));
END $$;

CREATE FUNCTION public.f360_list_team() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('owner');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('auth_user_id', u.auth_user_id, 'display_name', u.display_name, 'role', u.role,
      'locations', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) ORDER BY l.name), '[]')
                    FROM f360.location_assignments a JOIN f360.locations l ON l.id = a.location_id WHERE a.auth_user_id = u.auth_user_id AND a.active))
    ORDER BY u.role, u.display_name), '[]') FROM f360.user_roles u);
END $$;

-- ── Grants ──────────────────────────────────────────────────────────────────
REVOKE ALL ON f360.location_assignments, f360.access_changes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.f360_create_location(text, text, uuid, boolean, date, date), public.f360_set_user_role(uuid, text, text),
  public.f360_set_location_assignment(uuid, uuid, boolean), public.f360_my_locations(), public.f360_list_team() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_create_location(text, text, uuid, boolean, date, date), public.f360_set_user_role(uuid, text, text),
  public.f360_set_location_assignment(uuid, uuid, boolean), public.f360_my_locations(), public.f360_list_team() TO authenticated, service_role;
