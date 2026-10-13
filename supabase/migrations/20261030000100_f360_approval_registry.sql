-- Fuxia 360 · Shared approval registry (Mario 2026-10-11: "registro compartido de aprobaciones en f360"; Academy is its first user).
-- STAGING FIRST. ADDITIVE. Design: docs/fuxia360/academy/00_FUXIA_ACADEMY_DISENO.md §4.1 (requirements 1–7, conditions §4.1.8).
--
--   · f360.approval_scopes / f360.can_approve / store_discount: NOT altered. The only change is to WIDEN the scope CHECK with
--     academy_content, academy_points, academy_rewards — guarded: aborts unless the live CHECK is exactly the expected set.
--   · f360.approval_operations      catalog of operations per scope (sensitive, aal2, self-approval, max age). Migration-only.
--   · f360.approval_scope_operations permission PER OPERATION inside a scope (requirement 1). Existing scopes don't use it.
--   · f360.approval_requests        one request bound to object kind + id + version + sha256 hash (requirement 4).
--   · f360.approval_events          append-only history: requested/approved/rejected/cancelled/invalidated/expired/consumed (req. 3).
--   · f360.approval_request/decide/consume/cancel — the ONLY writers (SECURITY DEFINER, not callable by clients). Module RPCs call
--     them with the caller they derived from auth.uid(). decide enforces requester ≠ approver for sensitive operations, beneficiary
--     ≠ requester/approver, aal2, can_approve_op, expiry (database clock) and hash equality; consume is single-use.
--   · The existing fx_rate / budget / close / store_discount flows do NOT read or write this registry and need no change.
-- Rollback: supabase/rollbacks/20261030000100_f360_approval_registry.down.sql

-- ── 1. Widen the scope CHECK (guarded) ────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE def text; vals text[];
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO def FROM pg_constraint c
   WHERE c.conrelid = 'f360.approval_scopes'::regclass AND c.conname = 'approval_scopes_scope_check';
  IF def IS NULL THEN RAISE EXCEPTION 'ABORT: f360.approval_scopes_scope_check no existe (¿falta 20261023000200?)'; END IF;
  SELECT array_agg(m[1] ORDER BY m[1]) INTO vals FROM regexp_matches(def, '''([a-z_]+)''', 'g') m;
  IF vals IS DISTINCT FROM ARRAY['budget', 'close', 'fx_rate', 'store_discount'] THEN
    RAISE EXCEPTION 'ABORT: el CHECK vigente de approval_scopes es % (se esperaba budget, close, fx_rate, store_discount). Coordinar con la otra sesión antes de aplicar.', vals;
  END IF;
END $$;
ALTER TABLE f360.approval_scopes DROP CONSTRAINT approval_scopes_scope_check;
ALTER TABLE f360.approval_scopes ADD CONSTRAINT approval_scopes_scope_check
  CHECK (scope IN ('fx_rate', 'budget', 'close', 'store_discount', 'academy_content', 'academy_points', 'academy_rewards'));

-- ── 2. Operation catalog + per-operation permission ──────────────────────────────────────────────────────────────────────────
CREATE TABLE f360.approval_operations (
  scope               text NOT NULL CHECK (scope ~ '^[a-z_]{2,40}$'),
  operation           text NOT NULL CHECK (operation ~ '^[a-z_]{3,40}$'),
  label               text NOT NULL,
  sensitive           boolean NOT NULL,            -- true = requester ≠ approver, reason required
  requires_aal2       boolean NOT NULL,
  allow_self_approval boolean NOT NULL DEFAULT false,
  max_age_days        int NOT NULL CHECK (max_age_days BETWEEN 1 AND 90),
  PRIMARY KEY (scope, operation),
  CONSTRAINT approval_operations_sensitive_no_self CHECK (NOT (sensitive AND allow_self_approval))
);
COMMENT ON TABLE f360.approval_operations IS 'Operations per approval scope and their rules. Changed only by a reviewed migration.';
INSERT INTO f360.approval_operations (scope, operation, label, sensitive, requires_aal2, allow_self_approval, max_age_days) VALUES
  ('academy_content', 'publish_sales',        'Publicar contenido ordinario de producto (Sales)',           false, true, true,  14),
  ('academy_content', 'publish_sales_policy', 'Publicar contenido con políticas o criterios de certificación', true, true, false, 14),
  ('academy_content', 'publish_executive',    'Publicar contenido de la Escuela Ejecutiva',                  true, true, false, 14),
  ('academy_content', 'retire',               'Retirar un curso publicado',                                  true, true, false, 14),
  ('academy_points',  'rule_version',         'Activar una versión de reglas de XP y puntos',                true, true, false, 14),
  ('academy_points',  'manual_adjust',        'Ajuste manual de puntos',                                     true, true, false, 7),
  ('academy_points',  'certificate_revoke',   'Revocar un certificado',                                      true, true, false, 7),
  ('academy_rewards', 'catalog_item',         'Activar o cambiar un premio del catálogo',                    true, true, false, 14),
  ('academy_rewards', 'redemptions_enable',   'Encender canjes reales',                                      true, true, false, 7),
  ('academy_rewards', 'redemption',           'Aprobar un canje',                                            true, true, false, 7);

CREATE TABLE f360.approval_scope_operations (
  scope         text NOT NULL,
  auth_user_id  uuid NOT NULL,
  operation     text NOT NULL,
  added_by_name text NOT NULL,
  added_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  note          text CHECK (note IS NULL OR length(note) <= 300),
  PRIMARY KEY (scope, auth_user_id, operation),
  FOREIGN KEY (scope, auth_user_id) REFERENCES f360.approval_scopes (scope, auth_user_id) ON DELETE CASCADE,
  FOREIGN KEY (scope, operation) REFERENCES f360.approval_operations (scope, operation)
);
COMMENT ON TABLE f360.approval_scope_operations IS 'Per-operation approval permission inside a scope. Loaded per environment by a reviewed script; empty = nobody.';

CREATE FUNCTION f360.can_approve_op(p_scope text, p_operation text, p_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT p_user IS NOT NULL AND f360.can_approve(p_scope, p_user)
     AND EXISTS (SELECT 1 FROM f360.approval_scope_operations o WHERE o.scope = p_scope AND o.operation = p_operation AND o.auth_user_id = p_user) $$;

-- ── 3. Requests + append-only events ─────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360.approval_requests (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope             text NOT NULL,
  operation         text NOT NULL,
  object_kind       text NOT NULL CHECK (object_kind ~ '^[a-z_.]{3,60}$'),
  object_id         uuid NOT NULL,
  object_version    int  NOT NULL CHECK (object_version > 0),
  object_hash       text NOT NULL CHECK (object_hash ~ '^[0-9a-f]{64}$'),
  beneficiary_user  uuid,
  summary           jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(summary) = 'object'),
  requested_by      uuid NOT NULL,
  requested_by_name text NOT NULL,
  reason            text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 500),
  requested_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at        timestamptz NOT NULL,
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled', 'invalidated', 'expired', 'consumed')),
  decided_by        uuid,
  decided_by_name   text,
  decided_at        timestamptz,
  self_approval     boolean NOT NULL DEFAULT false,
  consumed_at       timestamptz,
  FOREIGN KEY (scope, operation) REFERENCES f360.approval_operations (scope, operation),
  CHECK (expires_at > requested_at)
);
CREATE UNIQUE INDEX approval_requests_one_open ON f360.approval_requests (scope, operation, object_kind, object_id, object_version)
  WHERE status IN ('pending', 'approved');
CREATE INDEX approval_requests_object_idx ON f360.approval_requests (object_kind, object_id, requested_at DESC);
COMMENT ON TABLE f360.approval_requests IS 'Shared approval registry: one request per object version + hash. Status changes only through f360.approval_* functions; every change is an event.';

-- Core columns never change; status only moves forward along the allowed transitions; no deletes.
CREATE FUNCTION f360.approval_requests_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Este historial no se puede modificar (f360.approval_requests)'; END IF;
  IF (NEW.id, NEW.scope, NEW.operation, NEW.object_kind, NEW.object_id, NEW.object_version, NEW.object_hash, NEW.beneficiary_user,
      NEW.summary, NEW.requested_by, NEW.requested_by_name, NEW.reason, NEW.requested_at, NEW.expires_at)
     IS DISTINCT FROM
     (OLD.id, OLD.scope, OLD.operation, OLD.object_kind, OLD.object_id, OLD.object_version, OLD.object_hash, OLD.beneficiary_user,
      OLD.summary, OLD.requested_by, OLD.requested_by_name, OLD.reason, OLD.requested_at, OLD.expires_at) THEN
    RAISE EXCEPTION 'Una solicitud de aprobación no se puede editar.';
  END IF;
  IF NOT ((OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected', 'cancelled', 'invalidated', 'expired'))
       OR (OLD.status = 'approved' AND NEW.status IN ('consumed', 'invalidated', 'expired', 'cancelled'))) THEN
    RAISE EXCEPTION 'Transición no permitida: % → %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER approval_requests_guard BEFORE UPDATE OR DELETE ON f360.approval_requests FOR EACH ROW EXECUTE FUNCTION f360.approval_requests_guard();

CREATE TABLE f360.approval_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id    uuid NOT NULL REFERENCES f360.approval_requests (id),
  action        text NOT NULL CHECK (action IN ('requested', 'approved', 'rejected', 'cancelled', 'invalidated', 'expired', 'consumed')),
  by_user       uuid,
  by_name       text NOT NULL,
  reason        text CHECK (reason IS NULL OR length(reason) <= 500),
  aal           text,
  object_hash   text,
  self_approval boolean NOT NULL DEFAULT false,
  at            timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX approval_events_request_idx ON f360.approval_events (request_id, id);
CREATE TRIGGER approval_events_append_only BEFORE UPDATE OR DELETE ON f360.approval_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE FUNCTION f360.approval_event(p_request uuid, p_action text, p_by uuid, p_by_name text, p_reason text, p_hash text, p_self boolean DEFAULT false)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  INSERT INTO f360.approval_events (request_id, action, by_user, by_name, reason, aal, object_hash, self_approval)
  VALUES (p_request, p_action, p_by, coalesce(p_by_name, 'sistema'), left(p_reason, 500), coalesce(auth.jwt()->>'aal', ''), p_hash, p_self) $$;

-- ── 4. The only writers ───────────────────────────────────────────────────────────────────────────────────────────────────────
-- Create a request. p_by / p_by_name are the caller as derived by the calling module from auth.uid() (never from client input).
CREATE FUNCTION f360.approval_request(p_scope text, p_operation text, p_object_kind text, p_object_id uuid, p_object_version int,
  p_object_hash text, p_beneficiary uuid, p_summary jsonb, p_reason text, p_by uuid, p_by_name text) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE op f360.approval_operations; rid uuid;
BEGIN
  SELECT * INTO op FROM f360.approval_operations WHERE scope = p_scope AND operation = p_operation;
  IF op.scope IS NULL THEN RAISE EXCEPTION 'Operación de aprobación desconocida: %.%', p_scope, p_operation; END IF;
  IF p_by IS NULL THEN RAISE EXCEPTION 'Solicitud sin solicitante.'; END IF;
  INSERT INTO f360.approval_requests (scope, operation, object_kind, object_id, object_version, object_hash, beneficiary_user, summary,
    requested_by, requested_by_name, reason, expires_at)
  VALUES (p_scope, p_operation, p_object_kind, p_object_id, p_object_version, p_object_hash, p_beneficiary, coalesce(p_summary, '{}'),
    p_by, p_by_name, btrim(p_reason), clock_timestamp() + make_interval(days => op.max_age_days))
  RETURNING id INTO rid;
  PERFORM f360.approval_event(rid, 'requested', p_by, p_by_name, p_reason, p_object_hash);
  RETURN rid;
END $$;

-- Decide. p_current_hash = the hash the module recomputed from the object NOW. Never raises on a rule failure: answers {ok:false}.
CREATE FUNCTION f360.approval_decide(p_request uuid, p_approve boolean, p_current_hash text, p_by uuid, p_by_name text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.approval_requests; op f360.approval_operations; self boolean; why text := btrim(coalesce(p_reason, ''));
BEGIN
  SELECT * INTO r FROM f360.approval_requests WHERE id = p_request FOR UPDATE;
  IF r.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Solicitud no encontrada.'); END IF;
  IF r.status <> 'pending' THEN RETURN jsonb_build_object('ok', false, 'error', 'La solicitud ya no está pendiente (' || r.status || ').'); END IF;
  IF clock_timestamp() > r.expires_at THEN
    UPDATE f360.approval_requests SET status = 'expired' WHERE id = r.id;
    PERFORM f360.approval_event(r.id, 'expired', NULL, 'sistema', 'Venció antes de decidirse', r.object_hash);
    RETURN jsonb_build_object('ok', false, 'error', 'La solicitud venció. Hay que pedirla de nuevo.');
  END IF;
  SELECT * INTO op FROM f360.approval_operations WHERE scope = r.scope AND operation = r.operation;
  IF NOT f360.can_approve_op(r.scope, r.operation, p_by) THEN RETURN jsonb_build_object('ok', false, 'error', 'No tienes permiso para aprobar esta operación.'); END IF;
  IF op.requires_aal2 AND coalesce(auth.jwt()->>'aal', '') <> 'aal2' THEN RETURN jsonb_build_object('ok', false, 'error', 'mfa_required'); END IF;
  self := (p_by = r.requested_by);
  IF self AND NOT op.allow_self_approval THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta operación la debe decidir otra persona.'); END IF;
  IF r.beneficiary_user IS NOT NULL AND (p_by = r.beneficiary_user OR r.requested_by = r.beneficiary_user) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Nadie puede pedir ni aprobar algo a su favor.');
  END IF;
  IF (op.sensitive OR NOT p_approve) AND length(why) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe el motivo.'); END IF;
  IF p_approve THEN
    IF p_current_hash IS DISTINCT FROM r.object_hash THEN
      UPDATE f360.approval_requests SET status = 'invalidated' WHERE id = r.id;
      PERFORM f360.approval_event(r.id, 'invalidated', p_by, p_by_name, 'El objeto cambió después de enviarse', p_current_hash);
      RETURN jsonb_build_object('ok', false, 'error', 'El contenido cambió después de enviarse a revisión. Hay que enviarlo de nuevo.');
    END IF;
    UPDATE f360.approval_requests SET status = 'approved', decided_by = p_by, decided_by_name = p_by_name, decided_at = clock_timestamp(),
      self_approval = self WHERE id = r.id;
    PERFORM f360.approval_event(r.id, 'approved', p_by, p_by_name, nullif(why, ''), p_current_hash, self);
    RETURN jsonb_build_object('ok', true, 'status', 'approved', 'self_approval', self);
  END IF;
  UPDATE f360.approval_requests SET status = 'rejected', decided_by = p_by, decided_by_name = p_by_name, decided_at = clock_timestamp() WHERE id = r.id;
  PERFORM f360.approval_event(r.id, 'rejected', p_by, p_by_name, why, p_current_hash);
  RETURN jsonb_build_object('ok', true, 'status', 'rejected');
END $$;

-- Use an approval once. Everything must match; an expired approval cannot be used.
CREATE FUNCTION f360.approval_consume(p_request uuid, p_scope text, p_operation text, p_object_kind text, p_object_id uuid,
  p_object_version int, p_object_hash text, p_by uuid, p_by_name text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.approval_requests;
BEGIN
  SELECT * INTO r FROM f360.approval_requests WHERE id = p_request FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'approved' THEN RETURN false; END IF;
  IF clock_timestamp() > r.expires_at THEN
    UPDATE f360.approval_requests SET status = 'expired' WHERE id = r.id;
    PERFORM f360.approval_event(r.id, 'expired', NULL, 'sistema', 'Venció antes de usarse', r.object_hash);
    RETURN false;
  END IF;
  IF (r.scope, r.operation, r.object_kind, r.object_id, r.object_version, r.object_hash)
     IS DISTINCT FROM (p_scope, p_operation, p_object_kind, p_object_id, p_object_version, p_object_hash) THEN
    RETURN false;
  END IF;
  UPDATE f360.approval_requests SET status = 'consumed', consumed_at = clock_timestamp() WHERE id = r.id;
  PERFORM f360.approval_event(r.id, 'consumed', p_by, p_by_name, NULL, p_object_hash);
  RETURN true;
END $$;

-- The requester (or the module on her behalf) withdraws a pending/approved request.
CREATE FUNCTION f360.approval_cancel(p_request uuid, p_by uuid, p_by_name text, p_reason text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.approval_requests;
BEGIN
  SELECT * INTO r FROM f360.approval_requests WHERE id = p_request FOR UPDATE;
  IF r.id IS NULL OR r.status NOT IN ('pending', 'approved') THEN RETURN false; END IF;
  UPDATE f360.approval_requests SET status = 'cancelled' WHERE id = r.id;
  PERFORM f360.approval_event(r.id, 'cancelled', p_by, p_by_name, p_reason, r.object_hash);
  RETURN true;
END $$;

-- ── 5. Privileges: nothing here is reachable by clients ───────────────────────────────────────────────────────────────────────
ALTER TABLE f360.approval_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.approval_scope_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.approval_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.approval_operations, f360.approval_scope_operations, f360.approval_requests, f360.approval_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.approval_operations, f360.approval_scope_operations, f360.approval_requests, f360.approval_events TO service_role;
GRANT INSERT, DELETE ON f360.approval_scope_operations TO service_role;   -- per-environment loading of who approves which operation
REVOKE ALL ON FUNCTION f360.can_approve_op(text, text, uuid), f360.approval_requests_guard(),
  f360.approval_event(uuid, text, uuid, text, text, text, boolean),
  f360.approval_request(text, text, text, uuid, int, text, uuid, jsonb, text, uuid, text),
  f360.approval_decide(uuid, boolean, text, uuid, text, text),
  f360.approval_consume(uuid, text, text, text, uuid, int, text, uuid, text),
  f360.approval_cancel(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
