-- Track C · Transfers with inventory "En camino" (design: docs/fuxia360/ops/TRACK_C_TRANSFERS.md, D-T1). STAGING. Additive.
--
--   requested ──(Preparar y enviar)──▶ in_transit ──(Confirmar recepción)──▶ received
--       │                                                   └────────────▶ with_difference ──(Resolver)──▶ closed
--       └──(Cancelar)──▶ cancelled
--
-- * ONE ledger: every stock change is an f360.inventory_events + f360.inventory_movements pair (no new ledger).
--   Send = TRANSFER origin → "En camino"; receive = TRANSFER "En camino" → destination;
--   gap resolution = RETURN "En camino" → origin, or WRITE_OFF out of "En camino" (mandatory reason).
-- * "En camino" is ONE system location (type 'transit'): never sellable, never assignable, never a receipt/sale location,
--   never counted as available. Lists show it apart ("En camino"), never mixed into available stock.
-- * A request does NOT reserve stock. Stock is validated and committed at send, under row locks (never negative).
-- * Only locations whose ledger_authority = 'f360' take part (legacy locations are refused; no channel_inventory writes).
-- * Identity/role/location assignment come from auth.uid() and f360 tables, re-checked live on every call.
-- * Every transition is idempotent (key), atomic, and audited append-only in f360.transfer_changes.
--   Transfers and lines cannot be deleted or edited retroactively (guard triggers).
-- Rollback: supabase/rollbacks/20261003000100_f360_transfers.down.sql

-- ── "En camino": the system transit location ────────────────────────────────
ALTER TABLE f360.locations DROP CONSTRAINT locations_type_check;
ALTER TABLE f360.locations ADD CONSTRAINT locations_type_check
  CHECK (type IN ('warehouse', 'receiving', 'store', 'bazaar', 'workshop', 'other', 'transit'));
CREATE UNIQUE INDEX locations_single_transit ON f360.locations ((true)) WHERE type = 'transit';
ALTER TABLE f360.locations ADD CONSTRAINT locations_transit_not_sellable CHECK (type <> 'transit' OR (sellable = false AND legacy_channel_id IS NULL AND ledger_authority = 'f360'));
INSERT INTO f360.locations (name, type, status, is_authoritative, sales_sync_pending, ledger_authority, sellable, sort)
  VALUES ('En camino', 'transit', 'active', false, false, 'f360', false, 9999);

CREATE FUNCTION f360.transit_location() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT id FROM f360.locations WHERE type = 'transit' $$;

-- Operable locations never include "En camino" (receipts, sales, shifts, assignments).
CREATE OR REPLACE FUNCTION f360.assert_ledger_location(p_location uuid) RETURNS f360.locations
LANGUAGE plpgsql STABLE AS $$
DECLARE l f360.locations;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = p_location AND status = 'active';
  IF l.id IS NULL OR l.type = 'transit' THEN RAISE EXCEPTION 'Elige una ubicación válida.'; END IF;
  IF l.ledger_authority <> 'f360' THEN
    RAISE EXCEPTION '% todavía lleva su inventario en el sistema anterior. Se podrá operar aquí cuando se migre.', l.name;
  END IF;
  RETURN l;
END $$;

CREATE OR REPLACE FUNCTION f360.require_location(p_location uuid) RETURNS f360.user_roles
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  IF NOT EXISTS (SELECT 1 FROM f360.locations WHERE id = p_location AND status = 'active' AND type <> 'transit') THEN RAISE EXCEPTION 'Ubicación no válida.'; END IF;
  IF r.role IN ('owner', 'operator') THEN RETURN r; END IF;
  IF r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = p_location AND a.active) THEN
    RETURN r;
  END IF;
  RAISE EXCEPTION 'No tienes asignada esta ubicación.' USING ERRCODE = 'insufficient_privilege';
END $$;

-- Nobody can be assigned to "En camino" (so no shift, no sale, no receipt can ever happen there).
CREATE FUNCTION f360.reject_transit_assignment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM f360.locations WHERE id = NEW.location_id AND type = 'transit') THEN
    RAISE EXCEPTION '"En camino" no es una ubicación donde se pueda trabajar.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER location_assignments_no_transit BEFORE INSERT OR UPDATE ON f360.location_assignments
  FOR EACH ROW EXECUTE FUNCTION f360.reject_transit_assignment();

-- ── Transfers ───────────────────────────────────────────────────────────────
CREATE SEQUENCE f360.transfer_number_seq;
CREATE TABLE f360.transfers (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number             text NOT NULL UNIQUE DEFAULT 'T-' || lpad(nextval('f360.transfer_number_seq')::text, 6, '0'),
  from_location_id   uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  to_location_id     uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  status             text NOT NULL DEFAULT 'requested'
                       CHECK (status IN ('requested', 'cancelled', 'in_transit', 'received', 'with_difference', 'closed')),
  note               text,
  requested_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  requested_by_name  text NOT NULL,
  requested_by_role  text NOT NULL,
  requested_at       timestamptz NOT NULL DEFAULT now(),
  sent_by_name       text,  sent_at timestamptz,  send_event_id uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT,
  received_by_name   text,  received_at timestamptz,  receive_event_id uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT,
  cancelled_by_name  text,  cancelled_at timestamptz,
  closed_by_name     text,  closed_at timestamptz,
  CHECK (from_location_id <> to_location_id)
);
CREATE INDEX transfers_status_idx ON f360.transfers (status, requested_at DESC);
CREATE INDEX transfers_to_idx ON f360.transfers (to_location_id);
CREATE INDEX transfers_from_idx ON f360.transfers (from_location_id);

CREATE TABLE f360.transfer_lines (
  transfer_id        uuid NOT NULL REFERENCES f360.transfers(id) ON DELETE RESTRICT,
  variant_id         uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  requested_qty      integer NOT NULL CHECK (requested_qty > 0),
  sent_qty           integer CHECK (sent_qty >= 0),
  received_qty       integer CHECK (received_qty >= 0),
  returned_qty       integer NOT NULL DEFAULT 0 CHECK (returned_qty >= 0),
  written_off_qty    integer NOT NULL DEFAULT 0 CHECK (written_off_qty >= 0),
  PRIMARY KEY (transfer_id, variant_id),
  CHECK (sent_qty IS NULL OR sent_qty <= requested_qty),
  CHECK (received_qty IS NULL OR (sent_qty IS NOT NULL AND received_qty <= sent_qty)),
  CHECK (coalesce(received_qty, 0) + returned_qty + written_off_qty <= coalesce(sent_qty, 0))
);

-- Append-only audit of EVERY transition: who, when, from→to status, origin, destination, variants and quantities.
CREATE TABLE f360.transfer_changes (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  transfer_id        uuid NOT NULL REFERENCES f360.transfers(id) ON DELETE RESTRICT,
  idempotency_key    uuid NOT NULL UNIQUE,
  action             text NOT NULL CHECK (action IN ('request', 'cancel', 'send', 'receive', 'resolve')),
  from_status        text,
  to_status          text NOT NULL,
  from_location_id   uuid NOT NULL,
  from_location_name text NOT NULL,
  to_location_id     uuid NOT NULL,
  to_location_name   text NOT NULL,
  lines              jsonb NOT NULL,        -- [{variant_id, label, quantity, (action)}]
  reason             text,
  event_ids          uuid[] NOT NULL DEFAULT '{}',
  actor_auth_user_id uuid,
  actor_name         text NOT NULL,
  actor_role         text NOT NULL,
  at                 timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX transfer_changes_transfer_idx ON f360.transfer_changes (transfer_id, id);
CREATE TRIGGER transfer_changes_append_only BEFORE UPDATE OR DELETE ON f360.transfer_changes
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- No retroactive edits: identity fields are frozen, status only moves forward, quantities are set once / only grow.
CREATE FUNCTION f360.guard_transfer() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Una transferencia no se puede borrar.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NEW.id <> OLD.id OR NEW.number <> OLD.number OR NEW.from_location_id <> OLD.from_location_id OR NEW.to_location_id <> OLD.to_location_id
     OR NEW.requested_by IS DISTINCT FROM OLD.requested_by OR NEW.requested_by_name <> OLD.requested_by_name OR NEW.requested_at <> OLD.requested_at
     OR NEW.note IS DISTINCT FROM OLD.note
     OR (OLD.sent_at IS NOT NULL AND (NEW.sent_at IS DISTINCT FROM OLD.sent_at OR NEW.send_event_id IS DISTINCT FROM OLD.send_event_id OR NEW.sent_by_name IS DISTINCT FROM OLD.sent_by_name))
     OR (OLD.received_at IS NOT NULL AND (NEW.received_at IS DISTINCT FROM OLD.received_at OR NEW.receive_event_id IS DISTINCT FROM OLD.receive_event_id OR NEW.received_by_name IS DISTINCT FROM OLD.received_by_name))
  THEN RAISE EXCEPTION 'Una transferencia no se puede editar.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NEW.status <> OLD.status AND NOT (
       (OLD.status = 'requested' AND NEW.status IN ('cancelled', 'in_transit'))
    OR (OLD.status = 'in_transit' AND NEW.status IN ('received', 'with_difference'))
    OR (OLD.status = 'with_difference' AND NEW.status = 'closed'))
  THEN RAISE EXCEPTION 'Cambio de estado no permitido (% → %).', OLD.status, NEW.status USING ERRCODE = 'insufficient_privilege'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER transfers_guard BEFORE UPDATE OR DELETE ON f360.transfers FOR EACH ROW EXECUTE FUNCTION f360.guard_transfer();

CREATE FUNCTION f360.guard_transfer_line() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Una transferencia no se puede borrar.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NEW.transfer_id <> OLD.transfer_id OR NEW.variant_id <> OLD.variant_id OR NEW.requested_qty <> OLD.requested_qty
     OR (OLD.sent_qty IS NOT NULL AND NEW.sent_qty IS DISTINCT FROM OLD.sent_qty)
     OR (OLD.received_qty IS NOT NULL AND NEW.received_qty IS DISTINCT FROM OLD.received_qty)
     OR NEW.returned_qty < OLD.returned_qty OR NEW.written_off_qty < OLD.written_off_qty
  THEN RAISE EXCEPTION 'Una transferencia no se puede editar.' USING ERRCODE = 'insufficient_privilege'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER transfer_lines_guard BEFORE UPDATE OR DELETE ON f360.transfer_lines FOR EACH ROW EXECUTE FUNCTION f360.guard_transfer_line();

REVOKE ALL ON f360.transfers, f360.transfer_lines, f360.transfer_changes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE f360.transfer_number_seq FROM PUBLIC, anon, authenticated;

-- ── Ledger helper: one movement + both balances, never negative ──────────────
-- Caller must already hold the FOR UPDATE lock on the source balance row(s) (taken in variant order).
CREATE FUNCTION f360.ledger_move(p_event uuid, p_variant uuid, p_from uuid, p_to uuid, p_qty int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_left int;
BEGIN
  IF p_qty <= 0 THEN RETURN; END IF;
  INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity) VALUES (p_event, p_variant, p_from, p_to, p_qty);
  IF p_from IS NOT NULL THEN
    UPDATE f360.inventory_balances SET on_hand = on_hand - p_qty, last_event_id = p_event, updated_at = now()
      WHERE variant_id = p_variant AND location_id = p_from AND on_hand >= p_qty RETURNING on_hand INTO v_left;
    IF v_left IS NULL THEN
      RAISE EXCEPTION 'No hay suficientes pares de % en %.', f360.variant_label(p_variant), (SELECT name FROM f360.locations WHERE id = p_from);
    END IF;
  END IF;
  IF p_to IS NOT NULL THEN
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand, last_event_id, updated_at) VALUES (p_variant, p_to, p_qty, p_event, now())
      ON CONFLICT (variant_id, location_id) DO UPDATE SET on_hand = f360.inventory_balances.on_hand + EXCLUDED.on_hand, last_event_id = p_event, updated_at = now();
  END IF;
END $$;

-- ── Read model ──────────────────────────────────────────────────────────────
-- Caller may see this transfer: owner/operator/viewer all; seller only with an ACTIVE assignment at origin or destination.
CREATE FUNCTION f360.can_see_transfer(r f360.user_roles, t f360.transfers) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT r.role IN ('owner', 'operator', 'viewer')
      OR (r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.active
                                        AND a.location_id IN (t.from_location_id, t.to_location_id)))
$$;

CREATE FUNCTION f360.transfer_json(p_id uuid, r f360.user_roles) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'number', t.number, 'status', t.status, 'note', t.note,
    'from', jsonb_build_object('id', lf.id, 'name', lf.name), 'to', jsonb_build_object('id', lt.id, 'name', lt.name),
    'requested_by_name', t.requested_by_name, 'requested_at', t.requested_at,
    'sent_by_name', t.sent_by_name, 'sent_at', t.sent_at, 'received_by_name', t.received_by_name, 'received_at', t.received_at,
    'cancelled_by_name', t.cancelled_by_name, 'cancelled_at', t.cancelled_at, 'closed_by_name', t.closed_by_name, 'closed_at', t.closed_at,
    'totals', (SELECT jsonb_build_object('requested', sum(l.requested_qty), 'sent', coalesce(sum(l.sent_qty), 0), 'received', coalesce(sum(l.received_qty), 0),
                 'returned', sum(l.returned_qty), 'written_off', sum(l.written_off_qty),
                 'outstanding', sum(coalesce(l.sent_qty, 0) - coalesce(l.received_qty, 0) - l.returned_qty - l.written_off_qty) FILTER (WHERE t.status IN ('with_difference', 'closed')))
               FROM f360.transfer_lines l WHERE l.transfer_id = t.id),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                 'variant_id', l.variant_id, 'product_id', p.id, 'product_name', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
                 'image_path', coalesce(f360.color_primary_image(c.id), f360.product_primary_image(p.id)),
                 'requested', l.requested_qty, 'sent', l.sent_qty, 'received', l.received_qty, 'returned', l.returned_qty, 'written_off', l.written_off_qty,
                 'outstanding', CASE WHEN t.status IN ('with_difference', 'closed') THEN coalesce(l.sent_qty, 0) - coalesce(l.received_qty, 0) - l.returned_qty - l.written_off_qty ELSE 0 END,
                 'available_at_origin', coalesce((SELECT b.on_hand FROM f360.inventory_balances b WHERE b.variant_id = l.variant_id AND b.location_id = t.from_location_id), 0))
                 ORDER BY p.name, c.sort, ps.sort), '[]'::jsonb)
               FROM f360.transfer_lines l JOIN f360.product_variants v ON v.id = l.variant_id JOIN f360.products p ON p.id = v.product_id
               JOIN f360.product_colors c ON c.id = v.color_id JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
               WHERE l.transfer_id = t.id),
    'history', (SELECT coalesce(jsonb_agg(jsonb_build_object('action', h.action, 'from_status', h.from_status, 'to_status', h.to_status,
                 'actor_name', h.actor_name, 'actor_role', h.actor_role, 'at', h.at, 'lines', h.lines, 'reason', h.reason) ORDER BY h.id), '[]'::jsonb)
               FROM f360.transfer_changes h WHERE h.transfer_id = t.id),
    'can', jsonb_build_object(
      'cancel', t.status = 'requested' AND (r.role IN ('owner', 'operator') OR (r.role = 'seller' AND t.requested_by = r.auth_user_id)),
      'send', t.status = 'requested' AND r.role IN ('owner', 'operator'),
      'receive', t.status = 'in_transit' AND (r.role IN ('owner', 'operator') OR (r.role = 'seller' AND EXISTS (
                   SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = t.to_location_id AND a.active))),
      'resolve', t.status = 'with_difference' AND r.role IN ('owner', 'operator')))
  FROM f360.transfers t JOIN f360.locations lf ON lf.id = t.from_location_id JOIN f360.locations lt ON lt.id = t.to_location_id
  WHERE t.id = p_id
$$;

-- Shared start of every transition: identity, idempotent replay, lock, visibility.
-- VOLATILE on purpose: after waiting on the key lock it must see the other call's committed row.
CREATE FUNCTION f360.transfer_replay(p_key uuid, p_transfer uuid, p_action text, r f360.user_roles) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE h f360.transfer_changes;
BEGIN
  IF p_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('f360.transfer:' || p_key::text, 0));
  SELECT * INTO h FROM f360.transfer_changes WHERE idempotency_key = p_key;
  IF h.id IS NULL THEN RETURN NULL; END IF;
  IF h.action <> p_action OR (p_transfer IS NOT NULL AND h.transfer_id <> p_transfer) OR h.actor_auth_user_id IS DISTINCT FROM r.auth_user_id THEN
    RAISE EXCEPTION 'Esa operación ya se registró con otros datos. Recarga la página.';
  END IF;
  RETURN f360.transfer_json(h.transfer_id, r) || jsonb_build_object('replayed', true);
END $$;

CREATE FUNCTION f360.transfer_audit(t f360.transfers, p_key uuid, p_action text, p_from_status text, p_lines jsonb, p_reason text, p_events uuid[], r f360.user_roles)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO f360.transfer_changes (transfer_id, idempotency_key, action, from_status, to_status, from_location_id, from_location_name,
      to_location_id, to_location_name, lines, reason, event_ids, actor_auth_user_id, actor_name, actor_role)
  SELECT t.id, p_key, p_action, p_from_status, t.status, t.from_location_id, lf.name, t.to_location_id, lt.name,
         coalesce(p_lines, '[]'::jsonb), p_reason, coalesce(p_events, '{}'), r.auth_user_id, r.display_name, r.role
  FROM f360.locations lf, f360.locations lt WHERE lf.id = t.from_location_id AND lt.id = t.to_location_id
$$;

-- Normalizes [{variant_id, quantity}] → one row per variant (duplicates summed), strict keys and quantities.
CREATE FUNCTION f360.transfer_qty_lines(p_lines jsonb, p_allow_zero boolean) RETURNS TABLE (variant_id uuid, quantity int)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE li jsonb; k text;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN RAISE EXCEPTION 'No hay pares en la transferencia.'; END IF;
  IF jsonb_array_length(p_lines) > 200 THEN RAISE EXCEPTION 'Demasiadas líneas en una transferencia.'; END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    IF jsonb_typeof(li) <> 'object' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN ('variant_id', 'quantity') THEN RAISE EXCEPTION 'Solo se aceptan talla y cantidad (campo "%").', k; END IF;
    END LOOP;
    IF coalesce(li->>'variant_id', '') !~ '^[0-9a-fA-F-]{36}$' THEN RAISE EXCEPTION 'Falta la talla en una línea.'; END IF;
    IF (li->>'quantity') !~ '^\d{1,5}$' THEN RAISE EXCEPTION 'Las cantidades deben ser números enteros, sin negativos.'; END IF;
    IF NOT p_allow_zero AND (li->>'quantity')::int = 0 THEN RAISE EXCEPTION 'Las cantidades deben ser mayores que cero.'; END IF;
  END LOOP;
  RETURN QUERY SELECT (x->>'variant_id')::uuid, sum((x->>'quantity')::int)::int FROM jsonb_array_elements(p_lines) x GROUP BY 1 ORDER BY 1;
END $$;

-- ── Transitions ─────────────────────────────────────────────────────────────
-- Internal send (used by f360_send_transfer and by "request + send" in one step). Locks transfer, then origin balances in
-- variant order; any line short → the whole send fails and nothing moves.
CREATE FUNCTION f360.transfer_do_send(p_key uuid, p_transfer uuid, p_lines jsonb, r f360.user_roles) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t f360.transfers; v_transit uuid := f360.transit_location(); v_event uuid; x record; v_total int := 0; v_audit jsonb := '[]';
BEGIN
  SELECT * INTO t FROM f360.transfers WHERE id = p_transfer FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Transferencia no encontrada.'; END IF;
  IF t.status <> 'requested' THEN RAISE EXCEPTION 'La transferencia % ya no está pendiente de envío (%).', t.number, t.status; END IF;
  PERFORM f360.assert_ledger_location(t.from_location_id);
  PERFORM f360.assert_ledger_location(t.to_location_id);

  -- quantities to send: explicit lines (≤ requested; 0 allowed) or, if omitted, exactly what was requested
  CREATE TEMP TABLE IF NOT EXISTS pg_temp.t_send (variant_id uuid PRIMARY KEY, quantity int) ON COMMIT DROP;
  DELETE FROM pg_temp.t_send;
  IF p_lines IS NULL THEN
    INSERT INTO pg_temp.t_send SELECT l.variant_id, l.requested_qty FROM f360.transfer_lines l WHERE l.transfer_id = t.id;
  ELSE
    INSERT INTO pg_temp.t_send SELECT * FROM f360.transfer_qty_lines(p_lines, true);
    IF EXISTS (SELECT 1 FROM pg_temp.t_send s LEFT JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE l.variant_id IS NULL) THEN
      RAISE EXCEPTION 'Solo se pueden enviar tallas que están en la solicitud.';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_temp.t_send s JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE s.quantity > l.requested_qty) THEN
      RAISE EXCEPTION 'No puedes enviar más pares de los solicitados.';
    END IF;
    INSERT INTO pg_temp.t_send SELECT l.variant_id, 0 FROM f360.transfer_lines l WHERE l.transfer_id = t.id ON CONFLICT DO NOTHING;
  END IF;
  IF (SELECT coalesce(sum(quantity), 0) FROM pg_temp.t_send) = 0 THEN RAISE EXCEPTION 'Escribe al menos un par para enviar.'; END IF;

  -- lock origin balances in variant order (same order as every other stock writer → no deadlocks), then validate all
  PERFORM 1 FROM f360.inventory_balances b JOIN pg_temp.t_send s ON s.variant_id = b.variant_id
    WHERE b.location_id = t.from_location_id AND s.quantity > 0 ORDER BY b.variant_id FOR UPDATE OF b;
  FOR x IN SELECT s.variant_id, s.quantity, coalesce(b.on_hand, 0) AS on_hand FROM pg_temp.t_send s
           LEFT JOIN f360.inventory_balances b ON b.variant_id = s.variant_id AND b.location_id = t.from_location_id
           WHERE s.quantity > 0 ORDER BY s.variant_id LOOP
    IF x.on_hand < x.quantity THEN
      RAISE EXCEPTION 'No hay suficientes pares de % en % (hay %, quieres enviar %). No se envió nada.',
        f360.variant_label(x.variant_id), (SELECT name FROM f360.locations WHERE id = t.from_location_id), x.on_hand, x.quantity;
    END IF;
  END LOOP;

  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
    VALUES ('TRANSFER', p_key, r.auth_user_id, r.display_name, r.role, 'Enviado · ' || t.number, 'transfer', t.number) RETURNING id INTO v_event;
  FOR x IN SELECT * FROM pg_temp.t_send ORDER BY variant_id LOOP
    PERFORM f360.ledger_move(v_event, x.variant_id, t.from_location_id, v_transit, x.quantity);
    UPDATE f360.transfer_lines SET sent_qty = x.quantity WHERE transfer_id = t.id AND variant_id = x.variant_id;
    v_total := v_total + x.quantity;
    v_audit := v_audit || jsonb_build_object('variant_id', x.variant_id, 'label', f360.variant_label(x.variant_id), 'quantity', x.quantity);
  END LOOP;
  UPDATE f360.transfers SET status = 'in_transit', sent_by_name = r.display_name, sent_at = now(), send_event_id = v_event WHERE id = t.id;
  SELECT * INTO t FROM f360.transfers WHERE id = t.id;
  PERFORM f360.transfer_audit(t, p_key, 'send', 'requested', v_audit, NULL, ARRAY[v_event], r);
END $$;

-- Solicitar (and, for owner/operator with p_send_now, send in the same transaction). No stock effect when only requested.
CREATE FUNCTION public.f360_request_transfer(p_idempotency_key uuid, p_from_location_id uuid, p_to_location_id uuid, p_lines jsonb,
  p_note text DEFAULT NULL, p_send_now boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; prior jsonb; t f360.transfers; x record; v_audit jsonb := '[]';
BEGIN
  r := f360.require_role('viewer');
  prior := f360.transfer_replay(p_idempotency_key, NULL, 'request', r);
  IF prior IS NOT NULL THEN RETURN prior; END IF;
  IF r.role = 'viewer' THEN RAISE EXCEPTION 'Tu cuenta no tiene permiso para esta acción.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF p_from_location_id IS NULL OR p_to_location_id IS NULL THEN RAISE EXCEPTION 'Elige origen y destino.'; END IF;
  IF p_from_location_id = p_to_location_id THEN RAISE EXCEPTION 'El origen y el destino deben ser distintos.'; END IF;
  PERFORM f360.assert_ledger_location(p_from_location_id);
  PERFORM f360.assert_ledger_location(p_to_location_id);
  IF r.role = 'seller' THEN
    IF p_send_now THEN RAISE EXCEPTION 'Solo operación puede enviar mercancía.' USING ERRCODE = 'insufficient_privilege'; END IF;
    IF NOT EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.active
                   AND a.location_id IN (p_from_location_id, p_to_location_id)) THEN
      RAISE EXCEPTION 'Solo puedes pedir mercancía para una ubicación que tienes asignada.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  INSERT INTO f360.transfers (from_location_id, to_location_id, note, requested_by, requested_by_name, requested_by_role)
    VALUES (p_from_location_id, p_to_location_id, nullif(btrim(p_note), ''), r.auth_user_id, r.display_name, r.role) RETURNING * INTO t;
  FOR x IN SELECT * FROM f360.transfer_qty_lines(p_lines, false) LOOP
    IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = x.variant_id AND status = 'active') THEN RAISE EXCEPTION 'Una de las tallas no es válida.'; END IF;
    INSERT INTO f360.transfer_lines (transfer_id, variant_id, requested_qty) VALUES (t.id, x.variant_id, x.quantity);
    v_audit := v_audit || jsonb_build_object('variant_id', x.variant_id, 'label', f360.variant_label(x.variant_id), 'quantity', x.quantity);
  END LOOP;
  PERFORM f360.transfer_audit(t, p_idempotency_key, 'request', NULL, v_audit, NULL, NULL, r);

  IF p_send_now THEN
    IF r.role NOT IN ('owner', 'operator') THEN RAISE EXCEPTION 'Solo operación puede enviar mercancía.' USING ERRCODE = 'insufficient_privilege'; END IF;
    -- the send gets its own derived key (request key → send key), so a replay of the request replays both
    PERFORM f360.transfer_do_send(md5('send:' || p_idempotency_key::text)::uuid, t.id, NULL, r);
  END IF;
  RETURN f360.transfer_json(t.id, r) || jsonb_build_object('replayed', false);
END $$;

CREATE FUNCTION public.f360_cancel_transfer(p_idempotency_key uuid, p_transfer_id uuid, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; prior jsonb; t f360.transfers;
BEGIN
  r := f360.require_role('viewer');
  prior := f360.transfer_replay(p_idempotency_key, p_transfer_id, 'cancel', r);
  IF prior IS NOT NULL THEN RETURN prior; END IF;
  SELECT * INTO t FROM f360.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF t.id IS NULL OR NOT f360.can_see_transfer(r, t) THEN RAISE EXCEPTION 'Transferencia no encontrada.'; END IF;
  IF NOT (r.role IN ('owner', 'operator') OR (r.role = 'seller' AND t.requested_by = r.auth_user_id)) THEN
    RAISE EXCEPTION 'Tu cuenta no tiene permiso para esta acción.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF t.status <> 'requested' THEN RAISE EXCEPTION 'Solo se puede cancelar una transferencia que no se ha enviado.'; END IF;
  UPDATE f360.transfers SET status = 'cancelled', cancelled_by_name = r.display_name, cancelled_at = now() WHERE id = t.id RETURNING * INTO t;
  PERFORM f360.transfer_audit(t, p_idempotency_key, 'cancel', 'requested', '[]', nullif(btrim(p_reason), ''), NULL, r);
  RETURN f360.transfer_json(t.id, r) || jsonb_build_object('replayed', false);
END $$;

-- Preparar y enviar: owner/operator only. p_lines NULL = send what was requested; otherwise per-variant (≤ requested).
CREATE FUNCTION public.f360_send_transfer(p_idempotency_key uuid, p_transfer_id uuid, p_lines jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; prior jsonb;
BEGIN
  r := f360.require_role('viewer');
  prior := f360.transfer_replay(p_idempotency_key, p_transfer_id, 'send', r);
  IF prior IS NOT NULL THEN RETURN prior; END IF;
  IF r.role NOT IN ('owner', 'operator') THEN RAISE EXCEPTION 'Solo operación puede enviar mercancía.' USING ERRCODE = 'insufficient_privilege'; END IF;
  PERFORM f360.transfer_do_send(p_idempotency_key, p_transfer_id, p_lines, r);
  RETURN f360.transfer_json(p_transfer_id, r) || jsonb_build_object('replayed', false);
END $$;

-- Confirmar recepción: seller assigned to the DESTINATION, operator, owner. p_lines NULL = everything sent arrived.
-- Received < sent on any line → with_difference; the missing pairs STAY in "En camino", identified, until resolved.
CREATE FUNCTION public.f360_receive_transfer(p_idempotency_key uuid, p_transfer_id uuid, p_lines jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; prior jsonb; t f360.transfers; v_transit uuid := f360.transit_location(); v_event uuid; x record;
        v_total int := 0; v_short boolean := false; v_audit jsonb := '[]';
BEGIN
  r := f360.require_role('viewer');
  prior := f360.transfer_replay(p_idempotency_key, p_transfer_id, 'receive', r);
  IF prior IS NOT NULL THEN RETURN prior; END IF;
  SELECT * INTO t FROM f360.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF t.id IS NULL OR NOT f360.can_see_transfer(r, t) THEN RAISE EXCEPTION 'Transferencia no encontrada.'; END IF;
  IF r.role = 'viewer' THEN RAISE EXCEPTION 'Tu cuenta no tiene permiso para esta acción.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF r.role = 'seller' THEN PERFORM f360.require_location(t.to_location_id); END IF;   -- live: a revoked assignment fails here
  IF t.status <> 'in_transit' THEN RAISE EXCEPTION 'La transferencia % no está en camino (%).', t.number, t.status; END IF;
  PERFORM f360.assert_ledger_location(t.to_location_id);

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.t_recv (variant_id uuid PRIMARY KEY, quantity int) ON COMMIT DROP;
  DELETE FROM pg_temp.t_recv;
  IF p_lines IS NULL THEN
    INSERT INTO pg_temp.t_recv SELECT l.variant_id, l.sent_qty FROM f360.transfer_lines l WHERE l.transfer_id = t.id;
  ELSE
    INSERT INTO pg_temp.t_recv SELECT * FROM f360.transfer_qty_lines(p_lines, true);
    IF EXISTS (SELECT 1 FROM pg_temp.t_recv s LEFT JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE l.variant_id IS NULL) THEN
      RAISE EXCEPTION 'Esa talla no viene en esta transferencia.';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_temp.t_recv s JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id WHERE s.quantity > l.sent_qty) THEN
      RAISE EXCEPTION 'No puedes recibir más pares de los que se enviaron.';
    END IF;
    INSERT INTO pg_temp.t_recv SELECT l.variant_id, 0 FROM f360.transfer_lines l WHERE l.transfer_id = t.id ON CONFLICT DO NOTHING;
  END IF;

  PERFORM 1 FROM f360.inventory_balances b JOIN pg_temp.t_recv s ON s.variant_id = b.variant_id
    WHERE b.location_id = v_transit AND s.quantity > 0 ORDER BY b.variant_id FOR UPDATE OF b;
  IF (SELECT coalesce(sum(quantity), 0) FROM pg_temp.t_recv) > 0 THEN
    INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
      VALUES ('TRANSFER', p_idempotency_key, r.auth_user_id, r.display_name, r.role, 'Recibido · ' || t.number, 'transfer', t.number) RETURNING id INTO v_event;
  END IF;
  FOR x IN SELECT s.variant_id, s.quantity, l.sent_qty FROM pg_temp.t_recv s JOIN f360.transfer_lines l ON l.transfer_id = t.id AND l.variant_id = s.variant_id ORDER BY s.variant_id LOOP
    IF x.quantity > 0 THEN PERFORM f360.ledger_move(v_event, x.variant_id, v_transit, t.to_location_id, x.quantity); END IF;
    UPDATE f360.transfer_lines SET received_qty = x.quantity WHERE transfer_id = t.id AND variant_id = x.variant_id;
    v_total := v_total + x.quantity;
    v_short := v_short OR x.quantity < coalesce(x.sent_qty, 0);
    v_audit := v_audit || jsonb_build_object('variant_id', x.variant_id, 'label', f360.variant_label(x.variant_id), 'sent', x.sent_qty, 'quantity', x.quantity);
  END LOOP;
  UPDATE f360.transfers SET status = CASE WHEN v_short THEN 'with_difference' ELSE 'received' END,
      received_by_name = r.display_name, received_at = now(), receive_event_id = v_event WHERE id = t.id RETURNING * INTO t;
  PERFORM f360.transfer_audit(t, p_idempotency_key, 'receive', 'in_transit', v_audit, NULL, CASE WHEN v_event IS NULL THEN NULL ELSE ARRAY[v_event] END, r);
  RETURN f360.transfer_json(t.id, r) || jsonb_build_object('replayed', false);
END $$;

-- Resolver diferencia: owner/operator. Per variant: 'return' (back to origin) or 'write_off' (baja/ajuste), mandatory reason.
-- Only the outstanding (missing) quantity can be resolved; it may be done in several steps. When nothing is outstanding → closed.
CREATE FUNCTION public.f360_resolve_transfer_difference(p_idempotency_key uuid, p_transfer_id uuid, p_lines jsonb, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; prior jsonb; t f360.transfers; v_transit uuid := f360.transit_location(); li jsonb; k text;
        v_variant uuid; v_qty int; v_action text; v_left int; v_ret uuid; v_wo uuid; v_audit jsonb := '[]'; v_events uuid[] := '{}';
BEGIN
  r := f360.require_role('viewer');
  prior := f360.transfer_replay(p_idempotency_key, p_transfer_id, 'resolve', r);
  IF prior IS NOT NULL THEN RETURN prior; END IF;
  IF r.role NOT IN ('owner', 'operator') THEN RAISE EXCEPTION 'Solo operación puede resolver una diferencia.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT * INTO t FROM f360.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Transferencia no encontrada.'; END IF;
  IF t.status <> 'with_difference' THEN RAISE EXCEPTION 'La transferencia % no tiene diferencias pendientes.', t.number; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN RAISE EXCEPTION 'Indica qué pasó con los pares faltantes.'; END IF;

  PERFORM 1 FROM f360.inventory_balances b WHERE b.location_id = v_transit
    AND b.variant_id IN (SELECT (x->>'variant_id')::uuid FROM jsonb_array_elements(p_lines) x) ORDER BY b.variant_id FOR UPDATE;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) ORDER BY value->>'variant_id' LOOP
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN ('variant_id', 'quantity', 'action') THEN RAISE EXCEPTION 'Campo no permitido (%).', k; END IF;
    END LOOP;
    v_variant := (li->>'variant_id')::uuid; v_action := li->>'action';
    IF (li->>'quantity') !~ '^\d{1,5}$' OR (li->>'quantity')::int = 0 THEN RAISE EXCEPTION 'Las cantidades deben ser mayores que cero.'; END IF;
    v_qty := (li->>'quantity')::int;
    IF v_action NOT IN ('return', 'write_off') THEN RAISE EXCEPTION 'Elige: regresar al origen o dar de baja.'; END IF;
    SELECT coalesce(sent_qty, 0) - coalesce(received_qty, 0) - returned_qty - written_off_qty INTO v_left
      FROM f360.transfer_lines WHERE transfer_id = t.id AND variant_id = v_variant FOR UPDATE;
    IF v_left IS NULL THEN RAISE EXCEPTION 'Esa talla no viene en esta transferencia.'; END IF;
    IF v_qty > v_left THEN RAISE EXCEPTION 'Solo faltan % pares de %.', v_left, f360.variant_label(v_variant); END IF;
    IF v_action = 'return' THEN
      IF v_ret IS NULL THEN
        INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
          VALUES ('RETURN', p_idempotency_key, r.auth_user_id, r.display_name, r.role, 'Regresa al origen · ' || t.number || ' · ' || btrim(p_reason), 'transfer', t.number) RETURNING id INTO v_ret;
        v_events := v_events || v_ret;
      END IF;
      PERFORM f360.ledger_move(v_ret, v_variant, v_transit, t.from_location_id, v_qty);
      UPDATE f360.transfer_lines SET returned_qty = returned_qty + v_qty WHERE transfer_id = t.id AND variant_id = v_variant;
    ELSE
      IF v_wo IS NULL THEN
        INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
          VALUES ('WRITE_OFF', md5('write_off:' || p_idempotency_key::text)::uuid, r.auth_user_id, r.display_name, r.role, 'Baja · ' || t.number || ' · ' || btrim(p_reason), 'transfer', t.number) RETURNING id INTO v_wo;
        v_events := v_events || v_wo;
      END IF;
      PERFORM f360.ledger_move(v_wo, v_variant, v_transit, NULL, v_qty);
      UPDATE f360.transfer_lines SET written_off_qty = written_off_qty + v_qty WHERE transfer_id = t.id AND variant_id = v_variant;
    END IF;
    v_audit := v_audit || jsonb_build_object('variant_id', v_variant, 'label', f360.variant_label(v_variant), 'quantity', v_qty, 'action', v_action);
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM f360.transfer_lines WHERE transfer_id = t.id AND coalesce(sent_qty, 0) - coalesce(received_qty, 0) - returned_qty - written_off_qty > 0) THEN
    UPDATE f360.transfers SET status = 'closed', closed_by_name = r.display_name, closed_at = now() WHERE id = t.id RETURNING * INTO t;
  END IF;
  PERFORM f360.transfer_audit(t, p_idempotency_key, 'resolve', 'with_difference', v_audit, btrim(p_reason), v_events, r);
  RETURN f360.transfer_json(t.id, r) || jsonb_build_object('replayed', false);
END $$;

-- Lists. p_view: requested | in_transit | received | with_difference | all. Sellers see only their locations' transfers.
CREATE FUNCTION public.f360_list_transfers(p_view text DEFAULT 'all', p_limit int DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object(
    'items', (SELECT coalesce(jsonb_agg(f360.transfer_json(x.id, r) - 'history' ORDER BY x.requested_at DESC), '[]'::jsonb) FROM (
        SELECT t.id, t.requested_at FROM f360.transfers t
        WHERE f360.can_see_transfer(r, t)
          AND (coalesce(p_view, 'all') = 'all'
               OR (p_view = 'received' AND t.status IN ('received', 'closed'))
               OR (p_view = 'requested' AND t.status IN ('requested', 'cancelled'))
               OR t.status = p_view)
        ORDER BY t.requested_at DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 300))) x),
    'counts', (SELECT jsonb_build_object(
        'requested', count(*) FILTER (WHERE t.status = 'requested'),
        'in_transit', count(*) FILTER (WHERE t.status = 'in_transit'),
        'with_difference', count(*) FILTER (WHERE t.status = 'with_difference'))
      FROM f360.transfers t WHERE f360.can_see_transfer(r, t)));
END $$;

CREATE FUNCTION public.f360_get_transfer(p_transfer_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.transfers;
BEGIN
  r := f360.require_role('viewer');
  SELECT * INTO t FROM f360.transfers WHERE id = p_transfer_id;
  IF t.id IS NULL OR NOT f360.can_see_transfer(r, t) THEN RAISE EXCEPTION 'Transferencia no encontrada.'; END IF;
  RETURN f360.transfer_json(t.id, r);
END $$;

-- Locations the caller may pick in "Mover inventario" (f360 ledger only; never "En camino"; sellers: their assignments
-- appear as 'mine'; every f360 location is listed so a seller can ask FROM the warehouse TO her store).
CREATE FUNCTION public.f360_transfer_locations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object('role', r.role, 'can_send', r.role IN ('owner', 'operator'), 'can_request', r.role IN ('owner', 'operator', 'seller'),
    'locations', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type,
        'mine', r.role IN ('owner', 'operator') OR EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = l.id AND a.active),
        'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id)) ORDER BY l.sort, l.name), '[]'::jsonb)
      FROM f360.locations l WHERE l.status = 'active' AND l.type <> 'transit' AND l.ledger_authority = 'f360'));
END $$;

-- ── Existing read surfaces: "En camino" is shown apart, never mixed into available stock ─────────
CREATE OR REPLACE FUNCTION public.f360_list_locations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'name', l.name, 'type', l.type, 'is_authoritative', l.is_authoritative,
      'sales_sync_pending', l.sales_sync_pending, 'ledger_authority', l.ledger_authority, 'sellable', l.sellable,
      'starts_on', l.starts_on, 'ends_on', l.ends_on,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id),
      'incoming', (SELECT coalesce(sum(tl.sent_qty), 0) FROM f360.transfers t JOIN f360.transfer_lines tl ON tl.transfer_id = t.id
                   WHERE t.to_location_id = l.id AND t.status = 'in_transit'))
      ORDER BY l.sort, l.name), '[]'::jsonb)
    FROM f360.locations l WHERE l.status = 'active' AND l.type <> 'transit');
END $$;

CREATE OR REPLACE FUNCTION public.f360_home() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object(
    'display_name', r.display_name, 'role', r.role,
    'locations', public.f360_list_locations(),
    'recent', public.f360_list_events(5, NULL, NULL),
    'product_count', (SELECT count(*) FROM f360.products WHERE status = 'active'),
    'available_pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b JOIN f360.locations l ON l.id = b.location_id
                        WHERE l.status = 'active' AND l.type <> 'transit'),
    'in_transit_pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = f360.transit_location()),
    'transfers', (SELECT jsonb_build_object('requested', count(*) FILTER (WHERE t.status = 'requested'),
                    'in_transit', count(*) FILTER (WHERE t.status = 'in_transit'), 'with_difference', count(*) FILTER (WHERE t.status = 'with_difference'))
                  FROM f360.transfers t WHERE f360.can_see_transfer(r, t)));
END $$;

CREATE OR REPLACE FUNCTION public.f360_my_locations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'sellable', l.sellable,
      'ledger_authority', l.ledger_authority) ORDER BY l.sort, l.name), '[]')
    FROM f360.locations l
    WHERE l.status = 'active' AND l.type <> 'transit' AND (
      r.role IN ('owner', 'operator')
      OR (r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = l.id AND a.active))));
END $$;

-- f360_inventory_by_location / f360_list_products / f360_get_product: same as today (P2.1) except "En camino" is excluded
-- from location stock and product totals, and shown apart as in_transit.
CREATE OR REPLACE FUNCTION public.f360_inventory_by_location(p_location_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(loc ORDER BY (loc->>'sort')::int, loc->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'sort', l.sort,
      'is_authoritative', l.is_authoritative, 'sales_sync_pending', l.sales_sync_pending,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id),
      'products', (SELECT coalesce(jsonb_agg(pr ORDER BY pr->>'name'), '[]'::jsonb) FROM (
          SELECT jsonb_build_object('id', p.id, 'name', p.name, 'image_path', f360.product_primary_image(p.id),
            'pairs', sum(b.on_hand),
            'colors', (SELECT jsonb_agg(jsonb_build_object('name', c2.name, 'hex', c2.hex,
                         'sizes', (SELECT jsonb_agg(jsonb_build_object('size', v3.size_label, 'on_hand', b3.on_hand) ORDER BY ps3.sort)
                                   FROM f360.inventory_balances b3 JOIN f360.product_variants v3 ON v3.id = b3.variant_id
                                   JOIN f360.product_sizes ps3 ON ps3.product_id = v3.product_id AND ps3.label = v3.size_label
                                   WHERE b3.location_id = l.id AND v3.color_id = c2.id AND b3.on_hand > 0))
                         ORDER BY c2.sort)
                       FROM f360.product_colors c2 WHERE c2.product_id = p.id AND EXISTS (
                         SELECT 1 FROM f360.inventory_balances b4 JOIN f360.product_variants v4 ON v4.id = b4.variant_id
                         WHERE b4.location_id = l.id AND v4.color_id = c2.id AND b4.on_hand > 0))) AS pr
          FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
          WHERE b.location_id = l.id AND b.on_hand > 0 GROUP BY p.id) q)) AS loc
    FROM f360.locations l WHERE l.status = 'active' AND l.type <> 'transit' AND (p_location_id IS NULL OR l.id = p_location_id)) s);
END $$;

CREATE OR REPLACE FUNCTION public.f360_list_products(p_query text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'last_activity') DESC NULLS LAST, x->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'name', p.name, 'code', p.code, 'category', cat.name, 'image_path', f360.product_primary_image(p.id),
      'regular_price', p.regular_price, 'sale_price', p.sale_price,
      'ready', (f360.product_readiness(p.id)->>'ready')::boolean,
      'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', c.name, 'hex', c.hex) ORDER BY c.sort, c.name), '[]'::jsonb)
                 FROM f360.product_colors c WHERE c.product_id = p.id),
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id <> f360.transit_location()),
      'in_transit', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id = f360.transit_location()),
      'last_activity', greatest(p.updated_at, (SELECT max(b.updated_at) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id))) AS x
    FROM f360.products p LEFT JOIN f360.categories cat ON cat.key = p.category_key
    WHERE p.status = 'active'
      AND (p_query IS NULL OR btrim(p_query) = '' OR p.name ILIKE '%' || btrim(p_query) || '%'
           OR EXISTS (SELECT 1 FROM f360.product_colors c WHERE c.product_id = p.id AND c.name ILIKE '%' || btrim(p_query) || '%'))
  ) s);
END $$;

CREATE OR REPLACE FUNCTION public.f360_get_product(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE result jsonb; online f360.locations; v_transit uuid := f360.transit_location();
BEGIN
  PERFORM f360.require_role('viewer');
  online := f360.online_location();
  SELECT jsonb_build_object(
    'id', p.id, 'name', p.name, 'code', p.code, 'codes_locked', p.codes_locked_at IS NOT NULL,
    'category', cat.name, 'category_key', p.category_key,
    'description', p.description, 'short_description', p.short_description,
    'regular_price', p.regular_price, 'sale_price', p.sale_price,
    'image_path', f360.product_primary_image(p.id),
    'readiness', f360.product_readiness(p.id),
    'online_location', CASE WHEN online.id IS NULL THEN NULL ELSE jsonb_build_object('id', online.id, 'name', online.name) END,
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]'::jsonb) FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'code', c.code, 'hex', c.hex, 'image_path', f360.color_primary_image(c.id),
        'media', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'path', m.storage_path) ORDER BY m.sort, m.created_at), '[]'::jsonb)
                  FROM f360.product_media m WHERE m.color_id = c.id),
        'variants', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'size', v.size_label, 'sku', v.sku) ORDER BY ps.sort), '[]'::jsonb)
                     FROM f360.product_variants v JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
                     WHERE v.color_id = c.id AND v.status = 'active'),
        'balances', (SELECT coalesce(jsonb_agg(jsonb_build_object('location_id', b.location_id, 'size', v.size_label, 'on_hand', b.on_hand)), '[]'::jsonb)
                     FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
                     WHERE v.color_id = c.id AND b.on_hand > 0 AND b.location_id <> v_transit),
        'in_transit', (SELECT coalesce(jsonb_agg(jsonb_build_object('size', v.size_label, 'on_hand', b.on_hand)), '[]'::jsonb)
                     FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
                     WHERE v.color_id = c.id AND b.on_hand > 0 AND b.location_id = v_transit))
        ORDER BY c.sort, c.created_at), '[]'::jsonb) FROM f360.product_colors c WHERE c.product_id = p.id),
    'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
              JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id <> v_transit),
    'in_transit', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
              JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id = v_transit))
  INTO result FROM f360.products p LEFT JOIN f360.categories cat ON cat.key = p.category_key WHERE p.id = p_product_id;
  IF result IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE = 'no_data_found'; END IF;
  RETURN result;
END $$;

-- ── Grants ──────────────────────────────────────────────────────────────────
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_request_transfer(uuid, uuid, uuid, jsonb, text, boolean), public.f360_cancel_transfer(uuid, uuid, text),
  public.f360_send_transfer(uuid, uuid, jsonb), public.f360_receive_transfer(uuid, uuid, jsonb),
  public.f360_resolve_transfer_difference(uuid, uuid, jsonb, text), public.f360_list_transfers(text, int), public.f360_get_transfer(uuid),
  public.f360_transfer_locations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_request_transfer(uuid, uuid, uuid, jsonb, text, boolean), public.f360_cancel_transfer(uuid, uuid, text),
  public.f360_send_transfer(uuid, uuid, jsonb), public.f360_receive_transfer(uuid, uuid, jsonb),
  public.f360_resolve_transfer_difference(uuid, uuid, jsonb, text), public.f360_list_transfers(text, int), public.f360_get_transfer(uuid),
  public.f360_transfer_locations() TO authenticated, service_role;
