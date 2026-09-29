-- Track C · C3 — Location cutover (legacy → f360) by verified physical count + the F360 store-sale branch. STAGING.
-- Design: docs/fuxia360/ops/CLOSED_LOOP_STORE_SALE.md §3–4, decisions D-K1 (double control; no sell/receive/transfer
-- during the cutover), D-M1 (one master per location), D-X1 (single ledger).
--
-- C3.1 cutover:  preparing → counting ⇄ verification → ready → completed      (cancelled from any non-final state)
--   * the opening balance comes ONLY from the verified physical count (never from channel_inventory);
--   * C2 is only a gate: every legacy row with units must be mapped (checked LIVE at completion);
--   * counter ≠ verifier per line (CHECK); verification is blind (neither sees the other's number until it matches);
--   * completion is ONE transaction: gate → OPENING_PHYSICAL_COUNT event → movements/balances → balances == count →
--     ledger_authority legacy→f360 → legacy writes frozen. Any failure rolls all of it back (the location stays legacy)
--     and the failed attempt is audited;
--   * one completed cutover per location, idempotent by key; f360 → legacy is impossible (trigger). Corrections after
--     the cutover are compensating ledger events, never a rewrite.
-- C3.2 sale: f360_record_store_sale's f360 branch: variant lines, master price, ledger SALE, same S0.2/S0.3/S0.5
--   guarantees; the legacy branch is unchanged except that it refuses to sell during a cutover.
-- online_location: derived from the active sales target's fulfillment location (no more "first warehouse by sort").
-- Rollback: supabase/rollbacks/20261004000100_f360_c3_cutover_and_f360_sale.down.sql

-- ── Ledger: the opening event type ───────────────────────────────────────────
ALTER TABLE f360.inventory_events DROP CONSTRAINT inventory_events_event_type_check;
ALTER TABLE f360.inventory_events ADD CONSTRAINT inventory_events_event_type_check CHECK (event_type IN
  ('RECEIPT', 'TRANSFER', 'SALE', 'RETURN', 'ADJUSTMENT', 'RESERVATION', 'RELEASE', 'WRITE_OFF', 'FULFILLMENT', 'PRODUCTION_RECEIPT',
   'OPENING_PHYSICAL_COUNT'));
-- a location has at most ONE opening count, ever
CREATE UNIQUE INDEX inventory_events_one_opening_per_location ON f360.inventory_events (business_reference_id)
  WHERE event_type = 'OPENING_PHYSICAL_COUNT';

-- ── Cutover tables ───────────────────────────────────────────────────────────
CREATE TABLE f360.location_cutovers (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id        uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  legacy_channel_id  uuid NOT NULL,
  status             text NOT NULL DEFAULT 'preparing'
                       CHECK (status IN ('preparing', 'counting', 'verification', 'ready', 'completed', 'cancelled')),
  start_key          uuid NOT NULL UNIQUE,
  started_by         uuid, started_by_name text NOT NULL, started_at timestamptz NOT NULL DEFAULT now(),
  complete_key       uuid UNIQUE,
  completed_by_name  text, completed_at timestamptz,
  opening_event_id   uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT,
  c2_readiness       jsonb,          -- the C2 gate as evaluated at completion (evidence)
  counted_pairs      integer,
  cancelled_by_name  text, cancelled_at timestamptz, cancel_reason text,
  note               text,
  CHECK (status <> 'completed' OR (opening_event_id IS NOT NULL AND completed_at IS NOT NULL))
);
-- one cutover in progress per location; one completed cutover per location (never two opening balances)
CREATE UNIQUE INDEX location_cutovers_one_active ON f360.location_cutovers (location_id) WHERE status IN ('preparing', 'counting', 'verification', 'ready');
CREATE UNIQUE INDEX location_cutovers_one_completed ON f360.location_cutovers (location_id) WHERE status = 'completed';

CREATE TABLE f360.cutover_counts (
  cutover_id        uuid NOT NULL REFERENCES f360.location_cutovers(id) ON DELETE RESTRICT,
  variant_id        uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  counted_qty       integer NOT NULL CHECK (counted_qty >= 0),
  counted_by        uuid NOT NULL, counted_by_name text NOT NULL, counted_at timestamptz NOT NULL DEFAULT now(),
  verified_qty      integer CHECK (verified_qty >= 0),
  verified_by       uuid, verified_by_name text, verified_at timestamptz,
  status            text NOT NULL DEFAULT 'counted' CHECK (status IN ('counted', 'verified', 'mismatch')),
  recounts          integer NOT NULL DEFAULT 0,
  PRIMARY KEY (cutover_id, variant_id),
  CHECK (verified_by IS NULL OR verified_by <> counted_by),                     -- double control: A ≠ B
  CHECK (status <> 'verified' OR (verified_qty = counted_qty AND verified_by IS NOT NULL))
);

CREATE TABLE f360.cutover_changes (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cutover_id    uuid NOT NULL REFERENCES f360.location_cutovers(id) ON DELETE RESTRICT,
  location_id   uuid NOT NULL,
  location_name text NOT NULL,
  action        text NOT NULL,        -- start | count | finish_count | verify | complete | complete_failed | cancel
  from_status   text,
  to_status     text,
  lines         jsonb,
  detail        text,
  actor_auth_user_id uuid, actor_name text NOT NULL, actor_role text NOT NULL,
  at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX cutover_changes_idx ON f360.cutover_changes (cutover_id, id);
CREATE TRIGGER cutover_changes_append_only BEFORE UPDATE OR DELETE ON f360.cutover_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Cutover rows: no delete; final states are frozen; counts of a final cutover are frozen.
CREATE FUNCTION f360.guard_cutover() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Un corte de inventario no se puede borrar.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF OLD.status IN ('completed', 'cancelled') THEN RAISE EXCEPTION 'Este corte ya terminó y no se puede modificar.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NEW.location_id <> OLD.location_id OR NEW.legacy_channel_id <> OLD.legacy_channel_id OR NEW.start_key <> OLD.start_key
     OR NEW.started_by_name <> OLD.started_by_name OR NEW.started_at <> OLD.started_at THEN
    RAISE EXCEPTION 'Un corte de inventario no se puede editar.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER location_cutovers_guard BEFORE UPDATE OR DELETE ON f360.location_cutovers FOR EACH ROW EXECUTE FUNCTION f360.guard_cutover();

CREATE FUNCTION f360.guard_cutover_count() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM f360.location_cutovers WHERE id = coalesce(OLD.cutover_id, NEW.cutover_id) AND status IN ('completed', 'cancelled')) THEN
    RAISE EXCEPTION 'Este conteo ya se cerró y no se puede modificar.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Un conteo no se puede borrar: se corrige recontando.' USING ERRCODE = 'insufficient_privilege'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER cutover_counts_guard BEFORE UPDATE OR DELETE ON f360.cutover_counts FOR EACH ROW EXECUTE FUNCTION f360.guard_cutover_count();

REVOKE ALL ON f360.location_cutovers, f360.cutover_counts, f360.cutover_changes FROM PUBLIC, anon, authenticated;

-- ── Invariants on locations ──────────────────────────────────────────────────
CREATE FUNCTION f360.location_in_cutover(p_location uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM f360.location_cutovers WHERE location_id = p_location AND status IN ('preparing', 'counting', 'verification', 'ready')) $$;

-- legacy → f360 ONLY with a completed, verified cutover; f360 → legacy NEVER; an f360 location never carries a legacy
-- channel it could write to (the channel stays linked only for history, and is frozen below).
CREATE FUNCTION f360.guard_ledger_authority() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.ledger_authority = 'f360' AND NEW.legacy_channel_id IS NOT NULL THEN
      RAISE EXCEPTION 'Una ubicación con inventario del sistema anterior empieza como legacy; se migra con un corte (C3).';
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.ledger_authority = 'f360' AND NEW.ledger_authority = 'legacy' THEN
    RAISE EXCEPTION 'Una ubicación migrada no vuelve al sistema anterior. Las correcciones se hacen con ajustes auditados.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF OLD.ledger_authority = 'legacy' AND NEW.ledger_authority = 'f360' AND NOT EXISTS (
       SELECT 1 FROM f360.location_cutovers c WHERE c.location_id = NEW.id AND c.status = 'completed' AND c.opening_event_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Solo un corte con conteo físico verificado puede migrar esta ubicación.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NEW.legacy_channel_id IS DISTINCT FROM OLD.legacy_channel_id AND (OLD.ledger_authority = 'f360' OR f360.location_in_cutover(OLD.id)) THEN
    RAISE EXCEPTION 'No se puede cambiar la tienda del sistema anterior de una ubicación migrada o en corte.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER locations_guard_ledger_authority BEFORE INSERT OR UPDATE ON f360.locations FOR EACH ROW EXECUTE FUNCTION f360.guard_ledger_authority();

-- ── Legacy freeze: the legacy stock of a location in cutover or migrated can never change again ────────────
-- (covers the old app path, the S0.3 legacy RPC, admin edits, anything — even SECURITY DEFINER code)
CREATE FUNCTION f360.legacy_channel_frozen(p_channel uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN l.ledger_authority = 'f360' THEN 'migrada' WHEN f360.location_in_cutover(l.id) THEN 'en_corte' END
  FROM f360.locations l WHERE l.legacy_channel_id = p_channel
$$;
CREATE FUNCTION public.channel_inventory_freeze_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE why text;
BEGIN
  why := f360.legacy_channel_frozen(CASE WHEN TG_OP = 'DELETE' THEN OLD.channel_id ELSE NEW.channel_id END);
  IF why IS NULL AND TG_OP = 'UPDATE' THEN why := f360.legacy_channel_frozen(OLD.channel_id); END IF;
  IF why = 'en_corte' THEN RAISE EXCEPTION 'Esta tienda está en corte de inventario: no se puede vender ni cambiar existencias hasta terminar.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF why = 'migrada' THEN RAISE EXCEPTION 'Esta tienda ya lleva su inventario en Fuxia 360: el sistema anterior quedó congelado.' USING ERRCODE = 'insufficient_privilege'; END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER channel_inventory_freeze BEFORE INSERT OR UPDATE OR DELETE ON public.channel_inventory
  FOR EACH ROW EXECUTE FUNCTION public.channel_inventory_freeze_guard();

-- A client (the old app path) can no longer create a sale for a frozen store, nor forge RPC-only columns.
-- The guard runs as the INVOKER on purpose: current_user is 'authenticated' for a direct client insert and the function
-- owner for the SECURITY DEFINER sale RPC. The frozen-state lookup is a definer helper (clients have no f360 access).
CREATE FUNCTION public.f360_legacy_channel_frozen(p_channel uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$ SELECT f360.legacy_channel_frozen(p_channel) $$;
CREATE FUNCTION public.offline_sales_client_guard() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE why text;
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF NEW.created_by_rpc OR NEW.location_id IS NOT NULL OR NEW.idempotency_key IS NOT NULL OR NEW.sale_event_id IS NOT NULL THEN
      RAISE EXCEPTION 'Esta venta solo se puede registrar con el flujo de venta de Fuxia 360.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    why := public.f360_legacy_channel_frozen(NEW.channel_id);
    IF why IS NOT NULL THEN
      RAISE EXCEPTION 'Esta tienda %: registra la venta con el flujo de Fuxia 360.', CASE why WHEN 'en_corte' THEN 'está en corte de inventario' ELSE 'ya lleva su inventario en Fuxia 360' END
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.channel_inventory_freeze_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_legacy_channel_frozen(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_legacy_channel_frozen(uuid) TO authenticated, service_role;

-- ── online_location: the active sales target's fulfillment location (sort never decides) ─────────────────
CREATE OR REPLACE FUNCTION f360.online_location() RETURNS f360.locations LANGUAGE sql STABLE AS $$
  SELECT l.* FROM f360.sales_targets t JOIN f360.locations l ON l.id = t.fulfillment_location_id
  WHERE t.active ORDER BY t.is_production DESC, t.created_at, t.id LIMIT 1
$$;

-- The variants that MUST be counted: every legacy row of the store with units NOW (frozen during the cutover), through its
-- confirmed C2 mapping. (A count may add more variants: pairs found that the legacy system did not know about.)
CREATE FUNCTION f360.cutover_required_variants(p_cutover uuid) RETURNS TABLE (variant_id uuid) LANGUAGE sql STABLE AS $$
  SELECT DISTINCT m.confirmed_variant_id FROM f360.location_cutovers c
  JOIN public.channel_inventory ci ON ci.channel_id = c.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0
  JOIN f360.legacy_inventory_map m ON m.channel_inventory_id = ci.id AND m.status = 'confirmado'
  WHERE c.id = p_cutover
$$;

-- ── Cutover read model ───────────────────────────────────────────────────────
-- Blind double control: while counting/verifying, a person sees only her OWN number for a line; both numbers become
-- visible when the line is in mismatch (to resolve it) or when the cutover is ready / finished.
CREATE FUNCTION f360.cutover_json(p_id uuid, r f360.user_roles) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', c.id, 'status', c.status, 'location', jsonb_build_object('id', l.id, 'name', l.name, 'ledger_authority', l.ledger_authority),
    'started_by_name', c.started_by_name, 'started_at', c.started_at, 'completed_by_name', c.completed_by_name, 'completed_at', c.completed_at,
    'cancelled_by_name', c.cancelled_by_name, 'cancelled_at', c.cancelled_at, 'cancel_reason', c.cancel_reason,
    'opening_event_id', c.opening_event_id, 'counted_pairs', c.counted_pairs, 'c2_readiness', c.c2_readiness,
    'required_variants', (SELECT coalesce(jsonb_agg(x.variant_id), '[]'::jsonb) FROM f360.cutover_required_variants(c.id) x),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'variant_id', k.variant_id, 'label', f360.variant_label(k.variant_id), 'status', k.status, 'recounts', k.recounts,
        'counted_by_name', k.counted_by_name, 'verified_by_name', k.verified_by_name,
        'counted_qty', CASE WHEN c.status IN ('ready', 'completed', 'cancelled') OR k.status = 'mismatch' OR k.counted_by = r.auth_user_id THEN k.counted_qty END,
        'verified_qty', CASE WHEN c.status IN ('ready', 'completed', 'cancelled') OR k.status = 'mismatch' OR k.verified_by = r.auth_user_id THEN k.verified_qty END)
        ORDER BY f360.variant_label(k.variant_id)), '[]'::jsonb) FROM f360.cutover_counts k WHERE k.cutover_id = c.id),
    'history', (SELECT coalesce(jsonb_agg(jsonb_build_object('action', h.action, 'from_status', h.from_status, 'to_status', h.to_status,
        'actor_name', h.actor_name, 'at', h.at, 'detail', h.detail) ORDER BY h.id), '[]'::jsonb) FROM f360.cutover_changes h WHERE h.cutover_id = c.id))
  FROM f360.location_cutovers c JOIN f360.locations l ON l.id = c.location_id WHERE c.id = p_id
$$;

CREATE FUNCTION f360.cutover_log(c f360.location_cutovers, p_action text, p_from text, p_lines jsonb, p_detail text, r f360.user_roles) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO f360.cutover_changes (cutover_id, location_id, location_name, action, from_status, to_status, lines, detail, actor_auth_user_id, actor_name, actor_role)
  SELECT c.id, c.location_id, l.name, p_action, p_from, c.status, p_lines, p_detail, r.auth_user_id, r.display_name, r.role
  FROM f360.locations l WHERE l.id = c.location_id
$$;

-- Who may count / verify: owner, operator, or a seller assigned to that location (live).
CREATE FUNCTION f360.require_counter(p_location uuid) RETURNS f360.user_roles
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  IF r.role IN ('owner', 'operator') THEN RETURN r; END IF;
  IF r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = p_location AND a.active) THEN RETURN r; END IF;
  RAISE EXCEPTION 'No tienes permiso para contar en esta ubicación.' USING ERRCODE = 'insufficient_privilege';
END $$;

-- ── C3.1 RPCs ─────────────────────────────────────────────────────────────────
-- Start: from this moment the location cannot sell, receive, transfer, or change legacy stock.
CREATE FUNCTION public.f360_start_cutover(p_idempotency_key uuid, p_location_id uuid, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; l f360.locations; c f360.location_cutovers;
BEGIN
  r := f360.require_role('operator');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  SELECT * INTO c FROM f360.location_cutovers WHERE start_key = p_idempotency_key;
  IF c.id IS NOT NULL THEN
    IF c.location_id <> p_location_id THEN RAISE EXCEPTION 'Esa operación ya se registró con otros datos.'; END IF;
    RETURN f360.cutover_json(c.id, r) || jsonb_build_object('replayed', true);
  END IF;
  SELECT * INTO l FROM f360.locations WHERE id = p_location_id AND status = 'active' FOR UPDATE;
  IF l.id IS NULL OR l.type = 'transit' THEN RAISE EXCEPTION 'Ubicación no válida.'; END IF;
  IF l.ledger_authority = 'f360' THEN RAISE EXCEPTION '% ya lleva su inventario en Fuxia 360.', l.name; END IF;
  IF l.legacy_channel_id IS NULL THEN RAISE EXCEPTION '% no tiene inventario del sistema anterior.', l.name; END IF;
  IF f360.location_in_cutover(l.id) THEN RAISE EXCEPTION '% ya tiene un corte en curso.', l.name; END IF;
  INSERT INTO f360.location_cutovers (location_id, legacy_channel_id, start_key, started_by, started_by_name, note)
    VALUES (l.id, l.legacy_channel_id, p_idempotency_key, r.auth_user_id, r.display_name, nullif(btrim(p_note), '')) RETURNING * INTO c;
  PERFORM f360.cutover_log(c, 'start', NULL, NULL, 'Ventas, recepciones, transferencias y existencias del sistema anterior bloqueadas', r);
  RETURN f360.cutover_json(c.id, r) || jsonb_build_object('replayed', false);
END $$;

-- Count (person A): absolute physical quantities per variant (0 allowed). Recounting a line resets its verification.
CREATE FUNCTION public.f360_cutover_count(p_cutover_id uuid, p_lines jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.location_cutovers; li jsonb; k text; v uuid; q int; old_status text; audit jsonb := '[]';
BEGIN
  SELECT * INTO c FROM f360.location_cutovers WHERE id = p_cutover_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Corte no encontrado.'; END IF;
  r := f360.require_counter(c.location_id);
  IF c.status NOT IN ('preparing', 'counting') THEN RAISE EXCEPTION 'El conteo no está abierto (estado: %).', c.status; END IF;
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

-- A declares the count finished → verification. Every product the legacy system says has units must have a count line.
CREATE FUNCTION public.f360_cutover_finish_count(p_cutover_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.location_cutovers; missing int;
BEGIN
  SELECT * INTO c FROM f360.location_cutovers WHERE id = p_cutover_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Corte no encontrado.'; END IF;
  r := f360.require_counter(c.location_id);
  IF c.status <> 'counting' THEN RAISE EXCEPTION 'No hay un conteo abierto (estado: %).', c.status; END IF;
  SELECT count(*) INTO missing FROM f360.cutover_required_variants(c.id) x
    WHERE NOT EXISTS (SELECT 1 FROM f360.cutover_counts k WHERE k.cutover_id = c.id AND k.variant_id = x.variant_id);
  IF missing > 0 THEN RAISE EXCEPTION 'Faltan % tallas por contar (escribe 0 si no hay pares).', missing; END IF;
  IF EXISTS (SELECT 1 FROM f360.cutover_counts WHERE cutover_id = c.id AND status = 'mismatch') THEN
    RAISE EXCEPTION 'Hay tallas con diferencia: vuelve a contarlas antes de pasar a verificación.';
  END IF;
  UPDATE f360.location_cutovers SET status = 'verification' WHERE id = c.id RETURNING * INTO c;
  PERFORM f360.cutover_log(c, 'finish_count', 'counting', NULL, NULL, r);
  RETURN f360.cutover_json(c.id, r);
END $$;

-- Verify (person B ≠ A, per line), blind: B enters her own count. Match → verified; different → mismatch (back to counting).
CREATE FUNCTION public.f360_cutover_verify(p_cutover_id uuid, p_lines jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.location_cutovers; li jsonb; k text; v uuid; q int; cnt f360.cutover_counts; audit jsonb := '[]'; nxt text;
BEGIN
  SELECT * INTO c FROM f360.location_cutovers WHERE id = p_cutover_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Corte no encontrado.'; END IF;
  r := f360.require_counter(c.location_id);
  IF c.status <> 'verification' THEN RAISE EXCEPTION 'El conteo no está en verificación (estado: %).', c.status; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN RAISE EXCEPTION 'No hay cantidades.'; END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN ('variant_id', 'quantity') THEN RAISE EXCEPTION 'Solo se aceptan talla y cantidad (campo "%").', k; END IF;
    END LOOP;
    IF coalesce(li->>'variant_id', '') !~ '^[0-9a-fA-F-]{36}$' OR coalesce(li->>'quantity', '') !~ '^\d{1,5}$' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    v := (li->>'variant_id')::uuid; q := (li->>'quantity')::int;
    SELECT * INTO cnt FROM f360.cutover_counts WHERE cutover_id = c.id AND variant_id = v FOR UPDATE;
    IF cnt.variant_id IS NULL THEN RAISE EXCEPTION 'Esa talla no está en el conteo: la persona que cuenta debe agregarla.'; END IF;
    IF cnt.counted_by = r.auth_user_id THEN RAISE EXCEPTION 'Doble control: quien contó no puede verificar su propio conteo.' USING ERRCODE = 'insufficient_privilege'; END IF;
    UPDATE f360.cutover_counts SET verified_qty = q, verified_by = r.auth_user_id, verified_by_name = r.display_name, verified_at = now(),
      status = CASE WHEN q = cnt.counted_qty THEN 'verified' ELSE 'mismatch' END
      WHERE cutover_id = c.id AND variant_id = v;
    audit := audit || jsonb_build_object('variant_id', v, 'label', f360.variant_label(v), 'quantity', q, 'match', q = cnt.counted_qty);
  END LOOP;
  nxt := CASE WHEN EXISTS (SELECT 1 FROM f360.cutover_counts WHERE cutover_id = c.id AND status = 'mismatch') THEN 'counting'
              WHEN NOT EXISTS (SELECT 1 FROM f360.cutover_counts WHERE cutover_id = c.id AND status <> 'verified') THEN 'ready'
              ELSE 'verification' END;
  UPDATE f360.location_cutovers SET status = nxt WHERE id = c.id RETURNING * INTO c;
  PERFORM f360.cutover_log(c, 'verify', 'verification', audit,
    CASE nxt WHEN 'counting' THEN 'Diferencia detectada: hay que recontar' WHEN 'ready' THEN 'Conteo verificado' END, r);
  RETURN f360.cutover_json(c.id, r);
END $$;

CREATE FUNCTION public.f360_cancel_cutover(p_cutover_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.location_cutovers; old_status text;
BEGIN
  r := f360.require_role('operator');
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT * INTO c FROM f360.location_cutovers WHERE id = p_cutover_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Corte no encontrado.'; END IF;
  IF c.status IN ('completed', 'cancelled') THEN RAISE EXCEPTION 'Este corte ya terminó (%).', c.status; END IF;
  old_status := c.status;
  UPDATE f360.location_cutovers SET status = 'cancelled', cancelled_by_name = r.display_name, cancelled_at = now(), cancel_reason = btrim(p_reason)
    WHERE id = c.id RETURNING * INTO c;
  PERFORM f360.cutover_log(c, 'cancel', old_status, NULL, btrim(p_reason), r);
  RETURN f360.cutover_json(c.id, r);
END $$;

-- Complete: ONE transaction. On any failure everything inside is rolled back (location stays legacy, no event, no
-- balances), the attempt is recorded in the audit, and the cutover stays 'ready' so the cause can be fixed and retried.
CREATE FUNCTION f360.cutover_do_complete(p_key uuid, c f360.location_cutovers, r f360.user_roles) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE l f360.locations; gate jsonb; v_event uuid; x record; bad int; total int := 0;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = c.location_id FOR UPDATE;
  IF l.ledger_authority <> 'legacy' THEN RAISE EXCEPTION '% ya no es legacy.', l.name; END IF;

  -- 1 · C2 gate, LIVE: every legacy row of this store with units must be confirmed to an F360 variant
  SELECT count(*) INTO bad FROM public.channel_inventory ci
    LEFT JOIN f360.legacy_inventory_map m ON m.channel_inventory_id = ci.id
    WHERE ci.channel_id = c.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0
      AND (m.channel_inventory_id IS NULL OR m.status <> 'confirmado' OR m.confirmed_variant_id IS NULL);
  IF bad > 0 THEN RAISE EXCEPTION 'C2 incompleto: % productos con existencia en el sistema anterior no están mapeados a Fuxia 360.', bad; END IF;
  gate := public.f360_location_migration_readiness(l.id);
  IF NOT coalesce((gate->>'catalog_ready')::boolean, false) THEN RAISE EXCEPTION 'C2 incompleto: el mapeo del catálogo no está listo.'; END IF;

  -- 2 · double control complete
  IF NOT EXISTS (SELECT 1 FROM f360.cutover_counts WHERE cutover_id = c.id) THEN RAISE EXCEPTION 'No hay conteo.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.cutover_counts WHERE cutover_id = c.id AND (status <> 'verified' OR verified_by IS NULL OR verified_by = counted_by OR verified_qty <> counted_qty)) THEN
    RAISE EXCEPTION 'El conteo no tiene doble control completo.';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.cutover_required_variants(c.id) x
             WHERE NOT EXISTS (SELECT 1 FROM f360.cutover_counts k WHERE k.cutover_id = c.id AND k.variant_id = x.variant_id)) THEN
    RAISE EXCEPTION 'Faltan tallas por contar.';
  END IF;

  -- 3 · never two opening balances: the location must have no ledger history at all
  IF EXISTS (SELECT 1 FROM f360.inventory_movements WHERE from_location_id = l.id OR to_location_id = l.id)
     OR EXISTS (SELECT 1 FROM f360.inventory_balances WHERE location_id = l.id AND on_hand <> 0) THEN
    RAISE EXCEPTION '% ya tiene movimientos en Fuxia 360: no puede recibir un segundo saldo inicial.', l.name;
  END IF;

  -- 4 · the opening event + one movement per counted variant (quantity 0 = no movement)
  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
    VALUES ('OPENING_PHYSICAL_COUNT', p_key, r.auth_user_id, r.display_name, r.role, 'Saldo inicial por conteo físico verificado · ' || l.name, 'location_cutover', l.id::text)
    RETURNING id INTO v_event;
  FOR x IN SELECT variant_id, counted_qty FROM f360.cutover_counts WHERE cutover_id = c.id AND counted_qty > 0 ORDER BY variant_id LOOP
    PERFORM f360.ledger_move(v_event, x.variant_id, NULL, l.id, x.counted_qty);
    total := total + x.counted_qty;
  END LOOP;

  -- 5 · balances == physical count, exactly (every variant, both directions)
  SELECT count(*) INTO bad FROM (
    SELECT variant_id, counted_qty AS q FROM f360.cutover_counts WHERE cutover_id = c.id AND counted_qty > 0) k
    FULL JOIN (SELECT variant_id, on_hand AS q FROM f360.inventory_balances WHERE location_id = l.id AND on_hand <> 0) b ON b.variant_id = k.variant_id
    WHERE coalesce(k.q, -1) <> coalesce(b.q, -1);
  IF bad > 0 THEN RAISE EXCEPTION 'Los saldos no coinciden con el conteo (% diferencias).', bad; END IF;

  -- 6 · mark completed, THEN switch authority (the location trigger requires the completed, verified cutover)
  UPDATE f360.location_cutovers SET status = 'completed', complete_key = p_key, completed_by_name = r.display_name, completed_at = now(),
      opening_event_id = v_event, c2_readiness = gate, counted_pairs = total WHERE id = c.id;
  UPDATE f360.locations SET ledger_authority = 'f360', is_authoritative = true, sales_sync_pending = false WHERE id = l.id;
  -- 7 · legacy writes for this store are now frozen by channel_inventory_freeze / offline_sales_client_guard (authority = f360)
  RETURN v_event;
END $$;

CREATE FUNCTION public.f360_complete_cutover(p_idempotency_key uuid, p_cutover_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.location_cutovers; err text;
BEGIN
  r := f360.require_role('operator');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  SELECT * INTO c FROM f360.location_cutovers WHERE id = p_cutover_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Corte no encontrado.'; END IF;
  IF c.status = 'completed' THEN
    IF c.complete_key = p_idempotency_key THEN RETURN f360.cutover_json(c.id, r) || jsonb_build_object('ok', true, 'replayed', true); END IF;
    RAISE EXCEPTION 'Este corte ya se ejecutó: una ubicación solo tiene un saldo inicial.';
  END IF;
  IF c.status <> 'ready' THEN RAISE EXCEPTION 'El corte no está listo (estado: %). Falta verificar el conteo.', c.status; END IF;
  BEGIN
    PERFORM f360.cutover_do_complete(p_idempotency_key, c, r);
  EXCEPTION WHEN OTHERS THEN
    err := SQLERRM;   -- everything inside the block is already rolled back: no event, no balances, still legacy
    PERFORM f360.cutover_log(c, 'complete_failed', c.status, NULL, err, r);
    RETURN f360.cutover_json(c.id, r) || jsonb_build_object('ok', false, 'error', err);
  END;
  SELECT * INTO c FROM f360.location_cutovers WHERE id = c.id;
  PERFORM f360.cutover_log(c, 'complete', 'ready', NULL, c.counted_pairs || ' pares como saldo inicial', r);
  RETURN f360.cutover_json(c.id, r) || jsonb_build_object('ok', true, 'replayed', false);
END $$;

CREATE FUNCTION public.f360_get_cutover(p_cutover_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.location_cutovers;
BEGIN
  SELECT * INTO c FROM f360.location_cutovers WHERE id = p_cutover_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Corte no encontrado.'; END IF;
  r := f360.require_counter(c.location_id);
  RETURN f360.cutover_json(c.id, r);
END $$;

-- ── Existing writers: refuse during a cutover ────────────────────────────────
-- (receipts/transfers already refuse legacy locations; this makes the rule explicit and future-proof)
CREATE OR REPLACE FUNCTION f360.assert_ledger_location(p_location uuid) RETURNS f360.locations
LANGUAGE plpgsql STABLE AS $$
DECLARE l f360.locations;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = p_location AND status = 'active';
  IF l.id IS NULL OR l.type = 'transit' THEN RAISE EXCEPTION 'Elige una ubicación válida.'; END IF;
  IF f360.location_in_cutover(l.id) THEN RAISE EXCEPTION '% está en corte de inventario: no se puede mover mercancía hasta terminar.', l.name; END IF;
  IF l.ledger_authority <> 'f360' THEN
    RAISE EXCEPTION '% todavía lleva su inventario en el sistema anterior. Se podrá operar aquí cuando se migre.', l.name;
  END IF;
  RETURN l;
END $$;

-- C2 evidence is frozen once a location is migrated or in cutover (proposals / reviews refused).
CREATE FUNCTION f360.guard_legacy_map() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE loc uuid := coalesce(NEW.location_id, OLD.location_id);
BEGIN
  IF EXISTS (SELECT 1 FROM f360.locations WHERE id = loc AND ledger_authority = 'f360') THEN
    RAISE EXCEPTION 'Esta ubicación ya se migró: su mapeo quedó como evidencia y no se modifica.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER legacy_inventory_map_guard BEFORE INSERT OR UPDATE OR DELETE ON f360.legacy_inventory_map FOR EACH ROW EXECUTE FUNCTION f360.guard_legacy_map();

-- ── C3.2: the store sale, both branches ──────────────────────────────────────
ALTER TABLE public.offline_sale_items ADD COLUMN variant_id uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT;
ALTER TABLE public.offline_sales ADD COLUMN sale_event_id uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT;
CREATE TRIGGER offline_sales_client_guard BEFORE INSERT ON public.offline_sales FOR EACH ROW EXECUTE FUNCTION public.offline_sales_client_guard();

CREATE OR REPLACE FUNCTION public.f360_record_store_sale(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text,
  p_payment_reference text DEFAULT NULL, p_customer_qr text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations; seller_name text; seller_role text; prior public.offline_sales; sale public.offline_sales;
  li jsonb; k text; v_id uuid; v_qty int; ci record; v_total numeric := 0; n int := 0; v_code text; card public.loyalty_cards;
  loy jsonb; lines_for_loyalty jsonb := '[]'; items_compat jsonb := '[]'; req jsonb := '{}'; is_f360 boolean; v_event uuid;
BEGIN
  -- 1 · WHO and WHERE come from the server: authenticated seller + active shift at an assigned location
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF f360.location_in_cutover(l.id) THEN RAISE EXCEPTION '% está en corte de inventario: no se puede vender hasta terminar el conteo.', l.name; END IF;
  is_f360 := l.ledger_authority = 'f360';
  IF NOT is_f360 AND l.legacy_channel_id IS NULL THEN RAISE EXCEPTION 'Esta ubicación no tiene inventario del sistema anterior.'; END IF;
  SELECT display_name, role INTO seller_name, seller_role FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;

  -- 2 · idempotency (double tap / retry): the same key returns the same sale
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la venta.'; END IF;
  SELECT * INTO prior FROM public.offline_sales WHERE idempotency_key = p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.seller_auth_user_id IS DISTINCT FROM s.auth_user_id THEN RAISE EXCEPTION 'Llave de venta repetida.'; END IF;
    RETURN jsonb_build_object('ok', true, 'replayed', true, 'sale_id', prior.id, 'code', CASE WHEN prior.claimed_at IS NULL THEN prior.code END,
      'total', prior.total, 'points', prior.points_earned, 'self_sale', prior.self_sale, 'claimed', prior.claimed_at IS NOT NULL);
  END IF;

  -- 3 · payment (D-PM)
  IF p_payment_method IS NULL OR p_payment_method NOT IN ('cash', 'card', 'transfer', 'other') THEN RAISE EXCEPTION 'Elige cómo pagó la clienta.'; END IF;
  IF p_payment_reference IS NOT NULL AND (length(p_payment_reference) > 64 OR p_payment_reference ~ '[0-9]{12,}') THEN
    RAISE EXCEPTION 'La referencia no puede contener números de tarjeta.';
  END IF;

  -- 4 · input: ONLY {channel_inventory_id | variant_id, quantity}. Any price/total/points/location/seller key is refused.
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 OR jsonb_array_length(p_lines) > 50 THEN
    RAISE EXCEPTION 'La venta necesita entre 1 y 50 productos.';
  END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    IF jsonb_typeof(li) <> 'object' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN (CASE WHEN is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END, 'quantity') THEN
        RAISE EXCEPTION 'Solo se aceptan producto y cantidad: el precio, la ubicación y la vendedora los pone el sistema (campo "%").', k;
      END IF;
    END LOOP;
    v_qty := (li->>'quantity')::int;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN RAISE EXCEPTION 'Cantidad no válida.'; END IF;
    v_id := (li->>CASE WHEN is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END)::uuid;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Falta el producto en una línea.'; END IF;
    req := jsonb_set(req, ARRAY[v_id::text], to_jsonb(coalesce((req->>v_id::text)::int, 0) + v_qty));   -- same product twice → summed
  END LOOP;

  IF is_f360 THEN
    -- ═══ F360 branch (C3): the single ledger is the stock; master price; never negative ═══
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(req) x LEFT JOIN f360.product_variants v ON v.id = x::uuid AND v.status = 'active' WHERE v.id IS NULL) THEN
      RAISE EXCEPTION 'Un producto no existe.';
    END IF;
    PERFORM 1 FROM f360.inventory_balances b WHERE b.location_id = l.id AND b.variant_id IN (SELECT x::uuid FROM jsonb_object_keys(req) x)
      ORDER BY b.variant_id FOR UPDATE;                                                             -- same lock order as transfers
    FOR ci IN SELECT v.id, v.sku, v.size_label, p.name AS product_name, c.name AS color, p.category_key,
                     coalesce(p.sale_price, p.regular_price) AS price, CASE WHEN p.sale_price IS NOT NULL THEN 'f360_master_sale_price' ELSE 'f360_master_price' END AS price_source,
                     coalesce(b.on_hand, 0) AS on_hand, (req->>v.id::text)::int AS qty
              FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
              LEFT JOIN f360.inventory_balances b ON b.variant_id = v.id AND b.location_id = l.id
              WHERE v.id IN (SELECT x::uuid FROM jsonb_object_keys(req) x) ORDER BY v.id LOOP
      IF ci.on_hand < ci.qty THEN
        RAISE EXCEPTION 'No hay existencia suficiente de % % % (quedan %).', ci.product_name, ci.color, ci.size_label, ci.on_hand;
      END IF;
      IF ci.price IS NULL THEN RAISE EXCEPTION '% no tiene precio en Fuxia 360: no se puede vender.', ci.product_name; END IF;
      v_total := v_total + ci.price * ci.qty;
    END LOOP;
  ELSE
    -- ═══ Legacy branch (S0.3, unchanged): lock the legacy stock rows; every row must belong to THIS shift's channel ═══
    FOR ci IN SELECT * FROM public.channel_inventory WHERE id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY id FOR UPDATE LOOP
      IF ci.channel_id IS DISTINCT FROM l.legacy_channel_id THEN RAISE EXCEPTION 'Un producto no pertenece a tu tienda.'; END IF;
    END LOOP;
    IF (SELECT count(*) FROM public.channel_inventory WHERE id IN (SELECT (jsonb_object_keys(req))::uuid)) <> (SELECT count(*) FROM jsonb_object_keys(req)) THEN
      RAISE EXCEPTION 'Un producto no existe.';
    END IF;
    FOR ci IN SELECT c.*, (req->>c.id::text)::int AS qty FROM public.channel_inventory c WHERE c.id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY c.id LOOP
      IF coalesce(ci.stock, 0) - coalesce(ci.sold, 0) < ci.qty THEN
        RAISE EXCEPTION 'No hay existencia suficiente de % % % (quedan %). Pide un ajuste de inventario.', ci.product_name, coalesce(ci.color, ''), coalesce(ci.size, ''),
          greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0);
      END IF;
      v_total := v_total + ci.price * ci.qty;                                                 -- authoritative legacy price (D-P2)
    END LOOP;
  END IF;

  -- 5 · the sale (claim code from a CSPRNG)
  LOOP
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.offline_sales WHERE code = v_code);
  END LOOP;
  INSERT INTO public.offline_sales (code, channel_id, staff_id, customer_phone, customer_id, items, total, points_earned,
      idempotency_key, seller_auth_user_id, location_id, session_id, payment_method, payment_reference, price_source, created_by_rpc)
    VALUES (v_code, CASE WHEN is_f360 THEN NULL ELSE l.legacy_channel_id END, NULL, NULL, NULL, '[]', v_total, 0,
      p_idempotency_key, s.auth_user_id, l.id, s.id, p_payment_method, nullif(btrim(p_payment_reference), ''),
      CASE WHEN is_f360 THEN 'f360_master_price' ELSE 'legacy_channel_inventory' END, true)
    RETURNING * INTO sale;

  IF is_f360 THEN
    INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
      VALUES ('SALE', p_idempotency_key, s.auth_user_id, coalesce(seller_name, 'Vendedora'), coalesce(seller_role, 'seller'), 'Venta en ' || l.name, 'offline_sale', sale.id::text)
      RETURNING id INTO v_event;
    FOR ci IN SELECT v.id, v.sku, v.size_label, p.name AS product_name, c.name AS color, p.category_key,
                     coalesce(p.sale_price, p.regular_price) AS price, CASE WHEN p.sale_price IS NOT NULL THEN 'f360_master_sale_price' ELSE 'f360_master_price' END AS price_source,
                     (req->>v.id::text)::int AS qty
              FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
              WHERE v.id IN (SELECT x::uuid FROM jsonb_object_keys(req) x) ORDER BY v.id LOOP
      n := n + 1;
      INSERT INTO public.offline_sale_items (sale_id, line_no, channel_inventory_id, variant_id, sku, product_name, size, color, quantity, unit_price, line_total, price_source)
        VALUES (sale.id, n, NULL, ci.id, ci.sku, ci.product_name, ci.size_label, ci.color, ci.qty, ci.price, ci.price * ci.qty, ci.price_source);
      PERFORM f360.ledger_move(v_event, ci.id, l.id, NULL, ci.qty);                             -- never negative (guarded update)
      lines_for_loyalty := lines_for_loyalty || jsonb_build_object('sku', ci.sku, 'product_name', ci.product_name, 'size', ci.size_label,
        'color', ci.color, 'category', ci.category_key, 'quantity', ci.qty, 'unit_price', ci.price);
      items_compat := items_compat || jsonb_build_object('variant_id', ci.id, 'product_name', ci.product_name, 'size', ci.size_label, 'color', ci.color,
        'quantity', ci.qty, 'unit_price', ci.price);
    END LOOP;
    UPDATE public.offline_sales SET sale_event_id = v_event WHERE id = sale.id RETURNING * INTO sale;
  ELSE
    FOR ci IN SELECT c.*, (req->>c.id::text)::int AS qty FROM public.channel_inventory c WHERE c.id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY c.id LOOP
      n := n + 1;
      INSERT INTO public.offline_sale_items (sale_id, line_no, channel_inventory_id, sku, product_name, size, color, quantity, unit_price, line_total, price_source)
        VALUES (sale.id, n, ci.id, ci.sku, ci.product_name, ci.size, ci.color, ci.qty, ci.price, ci.price * ci.qty, 'legacy_channel_inventory');
      UPDATE public.channel_inventory SET sold = coalesce(sold, 0) + ci.qty, updated_at = now() WHERE id = ci.id;   -- relative, under the lock
      lines_for_loyalty := lines_for_loyalty || jsonb_build_object('channel_inventory_id', ci.id, 'sku', ci.sku, 'product_name', ci.product_name,
        'size', ci.size, 'color', ci.color, 'quantity', ci.qty, 'unit_price', ci.price);
      items_compat := items_compat || jsonb_build_object('inventory_id', ci.id, 'product_name', ci.product_name, 'size', ci.size, 'color', ci.color,
        'quantity', ci.qty, 'unit_price', ci.price);   -- same shape the existing app screens read
    END LOOP;
  END IF;

  -- 6 · customer (optional, never required to discount stock). Unknown QR → the WHOLE sale is refused (rollback).
  IF nullif(btrim(p_customer_qr), '') IS NOT NULL THEN
    SELECT * INTO card FROM public.loyalty_cards WHERE qr_code = btrim(p_customer_qr);
    IF card.id IS NULL THEN RAISE EXCEPTION 'No encontramos esa tarjeta de clienta. Vuelve a escanear o registra la venta sin clienta.'; END IF;
    loy := public.loyalty_apply(card.id, lines_for_loyalty, v_total, 'store', 'offline_sale', sale.id::text, 'offline_sale:' || sale.id,
      jsonb_build_object('type', 'seller', 'auth_user_id', s.auth_user_id, 'name', seller_name, 'location_id', l.id, 'session_id', s.id));
    UPDATE public.offline_sales SET customer_id = card.customer_id, claimed_at = now(), items = items_compat,
      points_earned = coalesce((loy->>'points')::int, 0), self_sale = coalesce((loy->>'self_sale')::boolean, false),
      loyalty_transaction_id = nullif(loy->>'transaction_id', '')::uuid
      WHERE id = sale.id RETURNING * INTO sale;
  ELSE
    UPDATE public.offline_sales SET items = items_compat WHERE id = sale.id RETURNING * INTO sale;
  END IF;

  RETURN jsonb_build_object('ok', true, 'replayed', false, 'sale_id', sale.id, 'code', CASE WHEN sale.claimed_at IS NULL THEN sale.code END,
    'total', sale.total, 'lines', n, 'points', sale.points_earned, 'self_sale', sale.self_sale, 'claimed', sale.claimed_at IS NOT NULL,
    'location', l.name, 'seller', seller_name, 'payment_method', sale.payment_method, 'ledger', CASE WHEN is_f360 THEN 'f360' ELSE 'legacy' END);
END $$;

-- What the seller can sell at her shift's location (the app's product list): f360 → ledger + master price; legacy → channel_inventory.
CREATE FUNCTION public.f360_shift_catalog(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations;
BEGIN
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF l.ledger_authority = 'f360' THEN
    RETURN jsonb_build_object('location', l.name, 'ledger', 'f360', 'in_cutover', false, 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'variant_id', v.id, 'product_name', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
        'price', coalesce(p.sale_price, p.regular_price), 'available', b.on_hand) ORDER BY p.name, c.sort, v.size_label), '[]'::jsonb)
      FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id WHERE b.location_id = l.id AND b.on_hand > 0));
  END IF;
  RETURN jsonb_build_object('location', l.name, 'ledger', 'legacy', 'in_cutover', f360.location_in_cutover(l.id), 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'channel_inventory_id', ci.id, 'product_name', ci.product_name, 'color', ci.color, 'size', ci.size, 'sku', ci.sku, 'price', ci.price,
      'available', greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0)) ORDER BY ci.product_name, ci.color, ci.size), '[]'::jsonb)
    FROM public.channel_inventory ci WHERE ci.channel_id = l.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0));
END $$;

-- One fact per sale for Customer 360 / Growth: both ledgers, one row per sale, source says which.
CREATE OR REPLACE VIEW f360.store_sale_facts AS
  SELECT s.id AS sale_id, CASE WHEN s.sale_event_id IS NOT NULL THEN 'store_f360' ELSE 'store_legacy' END AS source, s.location_id,
         s.channel_id AS legacy_channel_id, s.seller_auth_user_id, s.customer_id,
         s.total, s.payment_method, s.price_source, s.self_sale, s.points_earned, s.claimed_at, s.created_at,
         (SELECT coalesce(sum(i.quantity), 0) FROM public.offline_sale_items i WHERE i.sale_id = s.id) AS units
  FROM public.offline_sales s WHERE s.created_by_rpc;
REVOKE ALL ON f360.store_sale_facts FROM PUBLIC, anon, authenticated;

-- ── Grants ──────────────────────────────────────────────────────────────────
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_start_cutover(uuid, uuid, text), public.f360_cutover_count(uuid, jsonb), public.f360_cutover_finish_count(uuid),
  public.f360_cutover_verify(uuid, jsonb), public.f360_cancel_cutover(uuid, text), public.f360_complete_cutover(uuid, uuid), public.f360_get_cutover(uuid),
  public.f360_shift_catalog(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_start_cutover(uuid, uuid, text), public.f360_cutover_count(uuid, jsonb), public.f360_cutover_finish_count(uuid),
  public.f360_cutover_verify(uuid, jsonb), public.f360_cancel_cutover(uuid, text), public.f360_complete_cutover(uuid, uuid), public.f360_get_cutover(uuid),
  public.f360_shift_catalog(text) TO authenticated, service_role;
