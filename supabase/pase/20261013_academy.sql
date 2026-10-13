-- Fuxia Academy · PRODUCCIÓN · aplicar (Mario 2026-10-13: "si sale"; P0-6 cerrado antes). Cuerpos = las 4 migraciones 20261030000100–0400, idénticas al repo:
--   20261030000100_f360_approval_registry.sql sha256 210c5f5647585f0c…
--   20261030000200_f360_academy_a1.sql sha256 38690bcc532ae8ec…
--   20261030000300_f360_academy_pilot_seed.sql sha256 c50eb4251ad9f4f3…
--   20261030000400_f360_academy_open_sellers.sql sha256 6849b5d1618821fa…
-- Permisos: Carolina = editora + aprobadora de contenido (publicar ventas, políticas, retirar); Mario = admin + editor + aprobador (políticas, retirar).
-- Ningún curso se publica aquí. Reversión: supabase/pase/20261013_academy_reversion.sql
BEGIN;
DO $$ BEGIN
  IF to_regnamespace('f360_academy') IS NOT NULL OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version LIKE '20261030%')
    THEN RAISE EXCEPTION 'ACADEMY PRE: Academy ya existe'; END IF;
  IF (SELECT md5(pg_get_functiondef('f360.can_approve(text,uuid)'::regprocedure))) <> '565a9163f96b40b17895b2cbdd1b1729' THEN RAISE EXCEPTION 'ACADEMY PRE: f360.can_approve distinta a lo revisado'; END IF;
  IF (SELECT count(*) FROM f360.user_roles WHERE role = 'owner' AND display_name IN ('Carolina', 'Mario Silva')) <> 2 THEN RAISE EXCEPTION 'ACADEMY PRE: dueñas distintas a lo revisado'; END IF;
END $$;
-- >>> 20261030000100_f360_approval_registry
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

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261030000100', 'f360_approval_registry', ARRAY[$m$-- Fuxia 360 · Shared approval registry (Mario 2026-10-11: "registro compartido de aprobaciones en f360"; Academy is its first user).
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
  f360.approval_cancel(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;$m$]);
-- >>> 20261030000200_f360_academy_a1
-- Fuxia Academy · A1 — learning engine for Sales Academy (Mario 2026-10-11: "A1 exclusivamente en staging, alcance controlado").
-- STAGING FIRST. ADDITIVE: own schema f360_academy + public.f360_academy_* RPCs. Depends on 20261030000100 (approval registry).
-- Design: docs/fuxia360/academy/00_FUXIA_ACADEMY_DISENO.md (§3–§5, §9.4, §10, §12) · A1 conditions:
--   · NO real seller access while P0-6 is open: settings.learner_access_enabled is false and a CHECK forbids true — only a reviewed
--     migration can lift it (after P0-6 is fixed). Learners in A1 = people with an explicit 'tester' grant, loaded per environment.
--   · NO certificates, NO points, NO rewards: no tables for them; settings flags are false with CHECKs.
--   · Authentication is untouched. Learners get NO privileged permission: they read published Sales content and write only their
--     own progress / practice answers, server-graded.
--   · Sales and Executive strictly separated: every learner RPC filters school = 'sales'; no executive RPC exists in A1.
--   · Product facts are NEVER stored as course text: lessons reference products by immutable code; on submission the validated
--     public knowledge (f360.product_knowledge_public) is frozen into a snapshot that is part of the approved hash (§9.4).
--   · Publication = shared registry (academy_content.publish_sales, aal2; self-approval only for ordinary product content).
-- Rollback: supabase/rollbacks/20261030000200_f360_academy_a1.down.sql

DO $$ BEGIN
  IF to_regclass('f360.approval_requests') IS NULL THEN RAISE EXCEPTION 'ABORT: falta 20261030000100 (registro de aprobaciones)'; END IF;
END $$;

CREATE SCHEMA f360_academy;
REVOKE ALL ON SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;

-- ── Settings (A1 gates) ──────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.settings (
  id                     boolean PRIMARY KEY DEFAULT true CHECK (id),
  learner_access_enabled boolean NOT NULL DEFAULT false,
  certificates_enabled   boolean NOT NULL DEFAULT false,
  points_enabled         boolean NOT NULL DEFAULT false,
  redemptions_enabled    boolean NOT NULL DEFAULT false,
  note                   text NOT NULL DEFAULT 'A1: acceso real de vendedoras bloqueado mientras P0-6 siga abierto (Mario 2026-10-11).',
  CONSTRAINT a1_no_real_learners CHECK (NOT learner_access_enabled),   -- lifted only by a reviewed migration after P0-6
  CONSTRAINT a1_no_certificates  CHECK (NOT certificates_enabled),
  CONSTRAINT a1_no_points        CHECK (NOT points_enabled),
  CONSTRAINT a1_no_redemptions   CHECK (NOT redemptions_enabled)
);
INSERT INTO f360_academy.settings DEFAULT VALUES;

-- ── Educational roles (layer 1). Loaded per environment by a reviewed script. ────────────────────────────────────────────────
CREATE TABLE f360_academy.grants (
  auth_user_id    uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role            text NOT NULL CHECK (role IN ('tester', 'editor', 'admin', 'executive_learner')),
  display_name    text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 80),
  active          boolean NOT NULL DEFAULT true,
  granted_by_name text NOT NULL,
  evidence        text NOT NULL CHECK (length(btrim(evidence)) >= 5),
  granted_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at      timestamptz,
  PRIMARY KEY (auth_user_id, role)
);
COMMENT ON TABLE f360_academy.grants IS 'Academy educational roles (not Fuxia 360 roles, not approvals). tester = authorized test learner (A1).';
CREATE TABLE f360_academy.grant_changes (
  id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  op     text NOT NULL,
  before jsonb,
  after  jsonb
);
CREATE TRIGGER grant_changes_append_only BEFORE UPDATE OR DELETE ON f360_academy.grant_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE FUNCTION f360_academy.log_grant_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO f360_academy.grant_changes (op, before, after)
  VALUES (TG_OP, CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END, CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER grants_log AFTER INSERT OR UPDATE OR DELETE ON f360_academy.grants FOR EACH ROW EXECUTE FUNCTION f360_academy.log_grant_change();

-- ── Content (versioned; immutable once submitted) ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.courses (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school               text NOT NULL CHECK (school IN ('sales', 'executive')),
  key                  text NOT NULL UNIQUE CHECK (key ~ '^[a-z0-9-]{3,60}$'),
  title                text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  kind                 text NOT NULL CHECK (kind IN ('nivel', 'parte', 'microcert', 'programa', 'bienvenida')),   -- bienvenida = first-entry video
  level_key            text CHECK (level_key IN ('starter', 'product_expert', 'sales_pro', 'master')),
  sort                 int NOT NULL DEFAULT 0,
  published_version_id uuid,
  created_by_name      text NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE f360_academy.course_versions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id           uuid NOT NULL REFERENCES f360_academy.courses (id),
  version             int NOT NULL CHECK (version > 0),
  status              text NOT NULL DEFAULT 'borrador' CHECK (status IN ('borrador', 'en_revision', 'publicado', 'retirado')),
  title               text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  summary             text CHECK (summary IS NULL OR length(summary) <= 600),
  content_hash        text CHECK (content_hash IS NULL OR content_hash ~ '^[0-9a-f]{64}$'),
  approval_request_id uuid REFERENCES f360.approval_requests (id),
  created_by_name     text NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
  submitted_at        timestamptz,
  published_at        timestamptz,
  retired_at          timestamptz,
  UNIQUE (course_id, version)
);
CREATE UNIQUE INDEX course_versions_one_published ON f360_academy.course_versions (course_id) WHERE status = 'publicado';
CREATE UNIQUE INDEX course_versions_one_open ON f360_academy.course_versions (course_id) WHERE status IN ('borrador', 'en_revision');
ALTER TABLE f360_academy.courses ADD CONSTRAINT courses_published_version_fk FOREIGN KEY (published_version_id) REFERENCES f360_academy.course_versions (id);

CREATE TABLE f360_academy.lessons (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  key               text NOT NULL CHECK (key ~ '^[a-z0-9.-]{1,20}$'),
  position          int NOT NULL CHECK (position > 0),
  title             text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  minutes           int NOT NULL CHECK (minutes BETWEEN 1 AND 15),
  blocks            jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(blocks) = 'array'),
  product_codes     text[] NOT NULL DEFAULT '{}',
  product_snapshot  jsonb,                    -- frozen at submission from f360.product_knowledge_public (validated only)
  UNIQUE (course_version_id, key),
  UNIQUE (course_version_id, position)
);
CREATE TABLE f360_academy.items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  key               text NOT NULL CHECK (key ~ '^[A-Za-z0-9-]{2,40}$'),
  lesson_key        text,
  uses              text[] NOT NULL DEFAULT '{practica}' CHECK (uses <@ ARRAY['practica', 'examen'] AND cardinality(uses) > 0),
  area              text NOT NULL CHECK (area IN ('producto', 'tallas', 'cuidados', 'atencion', 'marca_politicas')),
  kind              text NOT NULL CHECK (kind IN ('opcion', 'vf', 'varias', 'ordenar')),
  prompt            text NOT NULL CHECK (length(btrim(prompt)) BETWEEN 5 AND 600),
  options           jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(options) = 'array'),
  answer            jsonb NOT NULL,           -- never returned to a learner
  explanation       text NOT NULL CHECK (length(btrim(explanation)) BETWEEN 3 AND 600),
  source            text NOT NULL CHECK (length(btrim(source)) >= 3),
  product_code      text,
  status            text NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'bloqueada')),
  UNIQUE (course_version_id, key)
);
CREATE TABLE f360_academy.review_comments (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  lesson_key        text,
  item_key          text,
  block_index       int,
  body              text NOT NULL CHECK (length(btrim(body)) BETWEEN 2 AND 1000),
  by_user           uuid NOT NULL,
  by_name           text NOT NULL,
  at                timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER review_comments_append_only BEFORE UPDATE OR DELETE ON f360_academy.review_comments FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Children of a version can be written only while the version is a draft. The version itself: content fixed once submitted.
CREATE FUNCTION f360_academy.guard_draft_child() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE st text;
BEGIN
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = coalesce(NEW.course_version_id, OLD.course_version_id);
  IF st IS DISTINCT FROM 'borrador' THEN RAISE EXCEPTION 'Esta versión ya no es borrador: no se puede cambiar su contenido.'; END IF;
  IF TG_OP = 'UPDATE' AND NEW.course_version_id IS DISTINCT FROM OLD.course_version_id THEN RAISE EXCEPTION 'No se puede mover contenido entre versiones.'; END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER lessons_draft_only BEFORE INSERT OR UPDATE OR DELETE ON f360_academy.lessons FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_draft_child();
CREATE TRIGGER items_draft_only BEFORE INSERT OR UPDATE OR DELETE ON f360_academy.items FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_draft_child();

CREATE FUNCTION f360_academy.guard_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Una versión de curso no se borra.'; END IF;
  IF (NEW.course_id, NEW.version, NEW.created_by_name, NEW.created_at) IS DISTINCT FROM (OLD.course_id, OLD.version, OLD.created_by_name, OLD.created_at) THEN
    RAISE EXCEPTION 'Estos datos de la versión no cambian.';
  END IF;
  IF OLD.status <> 'borrador' AND (NEW.title, NEW.summary) IS DISTINCT FROM (OLD.title, OLD.summary) THEN
    RAISE EXCEPTION 'Esta versión ya no es borrador: no se puede cambiar su contenido.';
  END IF;
  IF OLD.status IN ('publicado', 'en_revision') AND NEW.content_hash IS DISTINCT FROM OLD.content_hash AND NEW.status <> 'borrador' THEN
    RAISE EXCEPTION 'La huella de una versión enviada no cambia.';
  END IF;
  IF NEW.status <> OLD.status AND NOT ((OLD.status = 'borrador' AND NEW.status = 'en_revision')
      OR (OLD.status = 'en_revision' AND NEW.status IN ('borrador', 'publicado'))
      OR (OLD.status = 'publicado' AND NEW.status = 'retirado')) THEN
    RAISE EXCEPTION 'Transición de versión no permitida: % → %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER course_versions_guard BEFORE UPDATE OR DELETE ON f360_academy.course_versions FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_version();

-- ── Learner progress (own rows only, through RPCs) ───────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.enrollments (
  auth_user_id      uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  course_id         uuid NOT NULL REFERENCES f360_academy.courses (id),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  location_id       uuid REFERENCES f360.locations (id),       -- store at enrollment (reports)
  enrolled_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at      timestamptz,
  PRIMARY KEY (auth_user_id, course_id)
);
CREATE TABLE f360_academy.lesson_progress (
  auth_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  lesson_id    uuid NOT NULL REFERENCES f360_academy.lessons (id),
  card_index   int NOT NULL DEFAULT 0 CHECK (card_index >= 0),
  status       text NOT NULL DEFAULT 'en_curso' CHECK (status IN ('en_curso', 'completada')),
  started_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  PRIMARY KEY (auth_user_id, lesson_id)
);
CREATE TABLE f360_academy.attempts (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  auth_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  item_id      uuid NOT NULL REFERENCES f360_academy.items (id),
  kind         text NOT NULL DEFAULT 'practica' CHECK (kind = 'practica'),   -- A1: practice only (no exam, no certificate)
  answer       jsonb NOT NULL,
  correct      boolean NOT NULL,
  at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX attempts_user_idx ON f360_academy.attempts (auth_user_id, at DESC);
CREATE TRIGGER attempts_append_only BEFORE UPDATE OR DELETE ON f360_academy.attempts FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE TABLE f360_academy.admin_events (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_user uuid,
  by_name text NOT NULL,
  action  text NOT NULL,
  ref     text,
  detail  jsonb NOT NULL DEFAULT '{}'
);
CREATE TRIGGER admin_events_append_only BEFORE UPDATE OR DELETE ON f360_academy.admin_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ── Access (layer 2) ─────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION f360_academy.has_grant(p_uid uuid, p_role text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT p_uid IS NOT NULL AND EXISTS (SELECT 1 FROM f360_academy.grants WHERE auth_user_id = p_uid AND role = p_role AND active) $$;

-- Sales learner state: 'ok' (tester, or active seller when access is enabled) | 'bloqueado' (active seller, access disabled: P0-6) | 'none'
CREATE FUNCTION f360_academy.sales_access(p_uid uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE
    WHEN p_uid IS NULL THEN 'none'
    WHEN f360_academy.has_grant(p_uid, 'tester') THEN 'ok'
    WHEN EXISTS (SELECT 1 FROM f360.sellers s WHERE s.auth_user_id = p_uid AND s.status = 'activa')
      THEN CASE WHEN (SELECT learner_access_enabled FROM f360_academy.settings WHERE id) THEN 'ok' ELSE 'bloqueado' END
    ELSE 'none' END $$;

CREATE FUNCTION f360_academy.is_editor(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_academy.has_grant(p_uid, 'editor') OR f360_academy.has_grant(p_uid, 'admin') $$;
CREATE FUNCTION f360_academy.is_content_approver(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360.can_approve_op('academy_content', 'publish_sales', p_uid) OR f360.can_approve_op('academy_content', 'publish_sales_policy', p_uid) $$;
CREATE FUNCTION f360_academy.is_staff(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_academy.is_editor(p_uid) OR f360_academy.is_content_approver(p_uid) $$;
CREATE FUNCTION f360_academy.caller_name(p_uid uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT display_name FROM f360_academy.grants WHERE auth_user_id = p_uid AND active ORDER BY granted_at LIMIT 1),
                  (SELECT display_name FROM f360.user_roles WHERE auth_user_id = p_uid), 'Usuario') $$;

CREATE FUNCTION f360_academy.denied() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object('ok', false, 'error', 'No disponible.') $$;

-- ── Content helpers ──────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Validated product facts for one code (NULL when the model is not active or its knowledge is not validated).
CREATE FUNCTION f360_academy.product_card(p_code text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN f360.product_knowledge_public(p.id) IS NOT NULL THEN jsonb_build_object(
    'code', p.code, 'name', p.name, 'category', p.category_key,
    'photo', f360.product_primary_image(p.id),
    'sizes', (SELECT jsonb_agg(s.label ORDER BY s.sort) FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT jsonb_agg(jsonb_build_object('name', c.name, 'photo', f360.color_primary_image(c.id)) ORDER BY c.sort, c.created_at)
               FROM f360.product_colors c WHERE c.product_id = p.id),
    'knowledge', f360.product_knowledge_public(p.id)) END
  FROM f360.products p WHERE p.code = p_code AND p.status = 'active' $$;

CREATE FUNCTION f360_academy.valid_blocks(p jsonb) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE b jsonb;
BEGIN
  IF jsonb_typeof(p) <> 'array' OR jsonb_array_length(p) = 0 OR jsonb_array_length(p) > 40 THEN RETURN 'Una lección necesita entre 1 y 40 tarjetas.'; END IF;
  FOR b IN SELECT * FROM jsonb_array_elements(p) LOOP
    IF jsonb_typeof(b) <> 'object' OR NOT (b->>'type' = ANY (ARRAY['texto', 'ficha', 'ficha_talla', 'pendiente', 'politica', 'video'])) THEN RETURN 'Tipo de tarjeta no válido.'; END IF;
    -- a video is a static file of the app, bound to its exact bytes by sha256 (part of the approved hash)
    IF b->>'type' = 'video' AND (coalesce(b->>'src', '') !~ '^/academy/[a-z0-9._-]+\.mp4$' OR coalesce(b->>'sha256', '') !~ '^[0-9a-f]{64}$'
        OR length(btrim(coalesce(b->>'source', ''))) < 3) THEN RETURN 'Una tarjeta de video necesita archivo, huella sha256 y fuente.'; END IF;
    IF b->>'type' IN ('texto', 'pendiente', 'politica') AND length(btrim(coalesce(b->>'text', ''))) NOT BETWEEN 2 AND 600 THEN RETURN 'Cada tarjeta de texto lleva entre 2 y 600 caracteres.'; END IF;
    IF b->>'type' IN ('texto', 'politica') AND length(btrim(coalesce(b->>'source', ''))) < 3 THEN RETURN 'Cada tarjeta de texto lleva su etiqueta de fuente.'; END IF;
    IF b->>'type' IN ('ficha', 'ficha_talla') AND coalesce(b->>'code', '') !~ '^[A-Z0-9-]{2,60}$' THEN RETURN 'Una tarjeta de ficha necesita el código del modelo.'; END IF;
  END LOOP;
  RETURN NULL;
END $$;

-- Canonical content of a version → sha256. Everything an approval covers is in here (texts, product snapshot, questions + answers).
CREATE FUNCTION f360_academy.version_hash(p_version uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object(
    'course', (SELECT c.key FROM f360_academy.courses c WHERE c.id = v.course_id), 'version', v.version, 'title', v.title, 'summary', v.summary,
    'lessons', coalesce((SELECT jsonb_agg(jsonb_build_object('key', l.key, 'position', l.position, 'title', l.title, 'minutes', l.minutes,
                 'blocks', l.blocks, 'products', to_jsonb(l.product_codes), 'snapshot', l.product_snapshot) ORDER BY l.position)
               FROM f360_academy.lessons l WHERE l.course_version_id = v.id), '[]'),
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object('key', i.key, 'lesson', i.lesson_key, 'uses', to_jsonb(i.uses), 'area', i.area,
                 'kind', i.kind, 'prompt', i.prompt, 'options', i.options, 'answer', i.answer, 'explanation', i.explanation,
                 'source', i.source, 'product', i.product_code, 'status', i.status) ORDER BY i.key)
               FROM f360_academy.items i WHERE i.course_version_id = v.id), '[]'))::text, 'UTF8')), 'hex')
  FROM f360_academy.course_versions v WHERE v.id = p_version $$;

-- Learner-safe item (no answer).
CREATE FUNCTION f360_academy.item_public(i f360_academy.items) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('id', i.id, 'key', i.key, 'kind', i.kind, 'area', i.area, 'prompt', i.prompt, 'options', i.options) $$;

-- Server-side grading. answer shapes: opcion {"choice":"b"} · vf {"value":true} · varias {"choices":[..]} · ordenar {"order":[..]}
CREATE FUNCTION f360_academy.grade(i f360_academy.items, p_answer jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE i.kind
    WHEN 'opcion' THEN (p_answer->>'choice') IS NOT NULL AND (p_answer->>'choice') = (i.answer->>'choice')
    WHEN 'vf'     THEN jsonb_typeof(p_answer->'value') = 'boolean' AND (p_answer->'value') = (i.answer->'value')
    WHEN 'varias' THEN jsonb_typeof(p_answer->'choices') = 'array'
      AND (SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM jsonb_array_elements_text(p_answer->'choices') x)
        = (SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM jsonb_array_elements_text(i.answer->'choices') x)
    WHEN 'ordenar' THEN jsonb_typeof(p_answer->'order') = 'array' AND (p_answer->'order') = (i.answer->'order')
    ELSE false END $$;

-- The version a learner sees for a course: her pinned enrollment, else the published one.
CREATE FUNCTION f360_academy.learner_version(p_uid uuid, p_course uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT e.course_version_id FROM f360_academy.enrollments e WHERE e.auth_user_id = p_uid AND e.course_id = p_course),
                  (SELECT c.published_version_id FROM f360_academy.courses c WHERE c.id = p_course)) $$;

CREATE FUNCTION f360_academy.render_lesson(l f360_academy.lessons, p_live boolean) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', l.id, 'key', l.key, 'position', l.position, 'title', l.title, 'minutes', l.minutes, 'blocks', l.blocks,
    'products', CASE WHEN p_live THEN coalesce((SELECT jsonb_object_agg(c, coalesce(f360_academy.product_card(c), 'null'::jsonb)) FROM unnest(l.product_codes) c), '{}')
                     ELSE coalesce(l.product_snapshot, '{}') END) $$;

-- ── Learner RPCs ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_academy_me() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('ok', true, 'sales', f360_academy.sales_access(auth.uid()),
    'editor', f360_academy.is_editor(auth.uid()), 'approver', f360_academy.is_content_approver(auth.uid()),
    'admin', f360_academy.has_grant(auth.uid(), 'admin'), 'aal', coalesce(auth.jwt()->>'aal', ''),
    'name', f360_academy.caller_name(auth.uid()),
    'gates', (SELECT jsonb_build_object('learner_access_enabled', learner_access_enabled, 'certificates_enabled', certificates_enabled,
                'points_enabled', points_enabled, 'redemptions_enabled', redemptions_enabled, 'note', note) FROM f360_academy.settings WHERE id)) $$;

CREATE FUNCTION public.f360_academy_home() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'courses', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', c.id, 'key', c.key, 'title', v.title, 'summary', v.summary, 'kind', c.kind, 'version', v.version,
      'enrolled', EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_id = c.id),
      'lessons', (SELECT jsonb_agg(jsonb_build_object('id', l.id, 'key', l.key, 'title', l.title, 'minutes', l.minutes, 'cards', jsonb_array_length(l.blocks),
                    'status', coalesce(p.status, 'pendiente'), 'card_index', coalesce(p.card_index, 0)) ORDER BY l.position)
                  FROM f360_academy.lessons l LEFT JOIN f360_academy.lesson_progress p ON p.lesson_id = l.id AND p.auth_user_id = uid
                  WHERE l.course_version_id = v.id)) ORDER BY c.sort, c.title)
    FROM f360_academy.courses c JOIN f360_academy.course_versions v ON v.id = f360_academy.learner_version(uid, c.id)
    WHERE c.school = 'sales' AND v.status IN ('publicado', 'retirado')), '[]'));
END $$;

CREATE FUNCTION public.f360_academy_lesson(p_lesson uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; v f360_academy.course_versions; c f360_academy.courses; loc uuid;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = l.course_version_id;
  SELECT * INTO c FROM f360_academy.courses WHERE id = v.course_id;
  IF l.id IS NULL OR c.school <> 'sales' OR v.id IS DISTINCT FROM f360_academy.learner_version(uid, c.id) OR v.status NOT IN ('publicado', 'retirado') THEN
    RETURN f360_academy.denied();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_academy.enrollments WHERE auth_user_id = uid AND course_id = c.id) THEN
    SELECT location_id INTO loc FROM f360.location_assignments WHERE auth_user_id = uid AND active ORDER BY granted_at DESC LIMIT 1;
    INSERT INTO f360_academy.enrollments (auth_user_id, course_id, course_version_id, location_id) VALUES (uid, c.id, v.id, loc);
  END IF;
  INSERT INTO f360_academy.lesson_progress (auth_user_id, lesson_id) VALUES (uid, l.id) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('ok', true, 'course', jsonb_build_object('id', c.id, 'title', v.title),
    'lesson', f360_academy.render_lesson(l, false),
    'progress', (SELECT jsonb_build_object('card_index', card_index, 'status', status) FROM f360_academy.lesson_progress WHERE auth_user_id = uid AND lesson_id = l.id),
    'practice', coalesce((SELECT jsonb_agg(f360_academy.item_public(i) ORDER BY i.key) FROM f360_academy.items i
                          WHERE i.course_version_id = v.id AND i.lesson_key = l.key AND 'practica' = ANY (i.uses) AND i.status = 'ok'), '[]'),
    'next', (SELECT n.id FROM f360_academy.lessons n WHERE n.course_version_id = v.id AND n.position > l.position ORDER BY n.position LIMIT 1));
END $$;

CREATE FUNCTION public.f360_academy_progress_save(p_lesson uuid, p_card int, p_done boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; n int;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  IF l.id IS NULL OR NOT EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_version_id = l.course_version_id) THEN
    RETURN f360_academy.denied();
  END IF;
  n := jsonb_array_length(l.blocks);
  IF p_card IS NULL OR p_card < 0 OR p_card > n THEN RETURN jsonb_build_object('ok', false, 'error', 'Tarjeta no válida.'); END IF;
  INSERT INTO f360_academy.lesson_progress AS p (auth_user_id, lesson_id, card_index, status, completed_at)
  VALUES (uid, l.id, p_card, CASE WHEN coalesce(p_done, false) THEN 'completada' ELSE 'en_curso' END, CASE WHEN coalesce(p_done, false) THEN clock_timestamp() END)
  ON CONFLICT (auth_user_id, lesson_id) DO UPDATE SET card_index = EXCLUDED.card_index, updated_at = clock_timestamp(),
    status = CASE WHEN p.status = 'completada' OR coalesce(p_done, false) THEN 'completada' ELSE 'en_curso' END,
    completed_at = coalesce(p.completed_at, EXCLUDED.completed_at);
  UPDATE f360_academy.enrollments e SET completed_at = clock_timestamp()
   WHERE e.auth_user_id = uid AND e.course_version_id = l.course_version_id AND e.completed_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM f360_academy.lessons x LEFT JOIN f360_academy.lesson_progress q ON q.lesson_id = x.id AND q.auth_user_id = uid
                      WHERE x.course_version_id = l.course_version_id AND coalesce(q.status, '') <> 'completada');
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_answer(p_item uuid, p_answer jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); i f360_academy.items; ok boolean;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO i FROM f360_academy.items WHERE id = p_item;
  IF i.id IS NULL OR i.status <> 'ok' OR NOT ('practica' = ANY (i.uses))
     OR NOT EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_version_id = i.course_version_id) THEN
    RETURN f360_academy.denied();
  END IF;
  IF p_answer IS NULL OR jsonb_typeof(p_answer) <> 'object' OR length(p_answer::text) > 2000 THEN RETURN jsonb_build_object('ok', false, 'error', 'Respuesta no válida.'); END IF;
  ok := f360_academy.grade(i, p_answer);
  INSERT INTO f360_academy.attempts (auth_user_id, item_id, answer, correct) VALUES (uid, i.id, p_answer, ok);
  RETURN jsonb_build_object('ok', true, 'correct', ok, 'explanation', i.explanation, 'source', i.source, 'answer', i.answer);   -- practice: show the right answer after answering
END $$;

CREATE FUNCTION public.f360_academy_fichas() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'fichas', coalesce((
    SELECT jsonb_agg(card ORDER BY card->>'name') FROM (
      SELECT DISTINCT ON (s.key) s.value AS card
      FROM f360_academy.courses c
      JOIN f360_academy.lessons l ON l.course_version_id = f360_academy.learner_version(uid, c.id)
      JOIN f360_academy.course_versions v ON v.id = l.course_version_id AND v.status IN ('publicado', 'retirado'),
      LATERAL jsonb_each(coalesce(l.product_snapshot, '{}')) s
      WHERE c.school = 'sales' AND jsonb_typeof(s.value) = 'object') x), '[]'));
END $$;

-- ── Content administration RPCs (editor / approver) ──────────────────────────────────────────────────────────────────────────
CREATE FUNCTION f360_academy.admin_log(p_uid uuid, p_action text, p_ref text, p_detail jsonb DEFAULT '{}') RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  INSERT INTO f360_academy.admin_events (by_user, by_name, action, ref, detail) VALUES (p_uid, f360_academy.caller_name(p_uid), p_action, p_ref, coalesce(p_detail, '{}')) $$;

CREATE FUNCTION public.f360_academy_admin_overview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'me', public.f360_academy_me(), 'courses', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', c.id, 'key', c.key, 'title', c.title, 'school', c.school, 'kind', c.kind,
      'published_version_id', c.published_version_id,
      'versions', (SELECT jsonb_agg(jsonb_build_object('id', v.id, 'version', v.version, 'status', v.status, 'title', v.title,
          'lessons', (SELECT count(*) FROM f360_academy.lessons l WHERE l.course_version_id = v.id),
          'items', (SELECT count(*) FROM f360_academy.items i WHERE i.course_version_id = v.id),
          'comments', (SELECT count(*) FROM f360_academy.review_comments r WHERE r.course_version_id = v.id),
          'request', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'operation', r.operation, 'requested_by', r.requested_by_name,
                        'requested_at', r.requested_at, 'expires_at', r.expires_at, 'decided_by', r.decided_by_name, 'self_approval', r.self_approval)
                      FROM f360.approval_requests r WHERE r.id = v.approval_request_id),
          -- §9.4: a published snapshot whose product knowledge was re-validated since → needs review
          'stale_products', CASE WHEN v.status = 'publicado' THEN (SELECT coalesce(jsonb_agg(DISTINCT s.key), '[]') FROM f360_academy.lessons l,
              LATERAL jsonb_each(coalesce(l.product_snapshot, '{}')) s
              WHERE l.course_version_id = v.id AND (s.value->'knowledge'->>'version') IS DISTINCT FROM (f360_academy.product_card(s.key)->'knowledge'->>'version')) END
        ) ORDER BY v.version DESC) FROM f360_academy.course_versions v WHERE v.course_id = c.id)
    ) ORDER BY c.school, c.sort, c.title) FROM f360_academy.courses c), '[]'),
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action, 'by', e.by_name, 'reason', e.reason, 'self', e.self_approval,
                  'aal', e.aal, 'operation', r.operation, 'version', r.object_version) ORDER BY e.id DESC)
                FROM (SELECT * FROM f360.approval_events ORDER BY id DESC LIMIT 400) e JOIN f360.approval_requests r ON r.id = e.request_id
                WHERE r.scope LIKE 'academy\_%'), '[]'));
END $$;

CREATE FUNCTION public.f360_academy_admin_version(p_version uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions;
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version;
  IF v.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true,
    'version', jsonb_build_object('id', v.id, 'version', v.version, 'status', v.status, 'title', v.title, 'summary', v.summary,
      'course', (SELECT jsonb_build_object('id', c.id, 'key', c.key, 'school', c.school) FROM f360_academy.courses c WHERE c.id = v.course_id),
      'hash', v.content_hash, 'current_hash', f360_academy.version_hash(v.id)),
    'lessons', coalesce((SELECT jsonb_agg(f360_academy.render_lesson(l, v.status = 'borrador') ORDER BY l.position) FROM f360_academy.lessons l WHERE l.course_version_id = v.id), '[]'),
    'items', coalesce((SELECT jsonb_agg(to_jsonb(i) - 'course_version_id' ORDER BY i.key) FROM f360_academy.items i WHERE i.course_version_id = v.id), '[]'),
    'comments', coalesce((SELECT jsonb_agg(jsonb_build_object('lesson', r.lesson_key, 'item', r.item_key, 'block', r.block_index, 'body', r.body, 'by', r.by_name, 'at', r.at) ORDER BY r.id)
                          FROM f360_academy.review_comments r WHERE r.course_version_id = v.id), '[]'),
    'request', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'operation', r.operation, 'requested_by', r.requested_by_name, 'reason', r.reason,
                  'requested_at', r.requested_at, 'expires_at', r.expires_at, 'hash', r.object_hash,
                  'events', (SELECT jsonb_agg(jsonb_build_object('action', e.action, 'by', e.by_name, 'reason', e.reason, 'at', e.at, 'aal', e.aal, 'self', e.self_approval) ORDER BY e.id)
                             FROM f360.approval_events e WHERE e.request_id = r.id))
                FROM f360.approval_requests r WHERE r.id = v.approval_request_id),
    'can_edit', f360_academy.is_editor(uid) AND v.status = 'borrador',
    'can_decide', v.status = 'en_revision' AND f360_academy.is_content_approver(uid));
END $$;

CREATE FUNCTION public.f360_academy_lesson_save(p_lesson uuid, p_title text, p_minutes int, p_blocks jsonb, p_product_codes text[]) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; bad text; st text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = l.course_version_id;
  IF l.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF st <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión ya no es borrador. Crea una nueva versión para editar.'); END IF;
  bad := f360_academy.valid_blocks(p_blocks);
  IF bad IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', bad); END IF;
  IF length(btrim(coalesce(p_title, ''))) NOT BETWEEN 3 AND 120 OR coalesce(p_minutes, 0) NOT BETWEEN 1 AND 15 THEN RETURN jsonb_build_object('ok', false, 'error', 'Revisa el título y los minutos.'); END IF;
  UPDATE f360_academy.lessons SET title = btrim(p_title), minutes = p_minutes, blocks = p_blocks,
    product_codes = coalesce((SELECT array_agg(DISTINCT upper(btrim(c))) FROM unnest(p_product_codes) c WHERE btrim(c) <> ''), '{}'), product_snapshot = NULL
  WHERE id = l.id;
  PERFORM f360_academy.admin_log(uid, 'lesson_save', l.id::text, jsonb_build_object('key', l.key));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_item_save(p_item uuid, p_fields jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); i f360_academy.items; st text; f jsonb := coalesce(p_fields, '{}'); bad text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO i FROM f360_academy.items WHERE id = p_item;
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = i.course_version_id;
  IF i.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF st <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión ya no es borrador.'); END IF;
  SELECT string_agg(k, ', ') INTO bad FROM jsonb_object_keys(f) k WHERE k <> ALL (ARRAY['prompt', 'options', 'answer', 'explanation', 'source', 'status']);
  IF bad IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Campos no permitidos: ' || bad); END IF;
  BEGIN
    UPDATE f360_academy.items SET
      prompt = coalesce(f->>'prompt', prompt), options = coalesce(f->'options', options), answer = coalesce(f->'answer', answer),
      explanation = coalesce(f->>'explanation', explanation), source = coalesce(f->>'source', source), status = coalesce(f->>'status', status)
    WHERE id = i.id;
  EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Revisa los datos de la pregunta.');
  END;
  PERFORM f360_academy.admin_log(uid, 'item_save', i.id::text, jsonb_build_object('key', i.key, 'fields', (SELECT jsonb_agg(k) FROM jsonb_object_keys(f) k)));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_comment(p_version uuid, p_lesson_key text, p_item_key text, p_block int, p_body text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) OR NOT EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE id = p_version) THEN RETURN f360_academy.denied(); END IF;
  IF length(btrim(coalesce(p_body, ''))) NOT BETWEEN 2 AND 1000 THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe el comentario.'); END IF;
  INSERT INTO f360_academy.review_comments (course_version_id, lesson_key, item_key, block_index, body, by_user, by_name)
  VALUES (p_version, p_lesson_key, p_item_key, p_block, btrim(p_body), uid, f360_academy.caller_name(uid));
  RETURN jsonb_build_object('ok', true);
END $$;

-- New draft = copy of the latest version (published or not), version + 1.
CREATE FUNCTION public.f360_academy_new_draft(p_course uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); src f360_academy.course_versions; nv uuid;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  IF EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE course_id = p_course AND status IN ('borrador', 'en_revision')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ya hay un borrador o una versión en revisión de este curso.');
  END IF;
  SELECT * INTO src FROM f360_academy.course_versions WHERE course_id = p_course ORDER BY version DESC LIMIT 1;
  IF src.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  INSERT INTO f360_academy.course_versions (course_id, version, title, summary, created_by_name)
  VALUES (p_course, src.version + 1, src.title, src.summary, f360_academy.caller_name(uid)) RETURNING id INTO nv;
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes)
  SELECT nv, key, position, title, minutes, blocks, product_codes FROM f360_academy.lessons WHERE course_version_id = src.id;
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code, status)
  SELECT nv, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code, status FROM f360_academy.items WHERE course_version_id = src.id;
  PERFORM f360_academy.admin_log(uid, 'new_draft', nv::text, jsonb_build_object('from', src.version));
  RETURN jsonb_build_object('ok', true, 'id', nv);
END $$;

-- Submit: validate, freeze validated product snapshots, hash, open the approval request.
CREATE FUNCTION public.f360_academy_submit(p_version uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions; c f360_academy.courses; l record; missing text; h text; rid uuid; op text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version FOR UPDATE;
  SELECT * INTO c FROM f360_academy.courses WHERE id = v.course_id;
  IF v.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF c.school <> 'sales' THEN RETURN jsonb_build_object('ok', false, 'error', 'La Escuela Ejecutiva no se publica en A1.'); END IF;
  IF v.status <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo un borrador se envía a revisión.'); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe qué cambió o por qué se envía.'); END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_academy.lessons WHERE course_version_id = v.id) THEN RETURN jsonb_build_object('ok', false, 'error', 'El curso no tiene lecciones.'); END IF;
  SELECT string_agg(l2.key, ', ') INTO missing FROM f360_academy.lessons l2
   WHERE l2.course_version_id = v.id AND EXISTS (SELECT 1 FROM jsonb_array_elements(l2.blocks) b WHERE b->>'type' = 'pendiente');
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Hay tarjetas pendientes de Carolina en: ' || missing || '.'); END IF;
  SELECT string_agg(i.key, ', ') INTO missing FROM f360_academy.items i
   WHERE i.course_version_id = v.id AND i.status = 'ok' AND (length(btrim(i.explanation)) < 3 OR length(btrim(i.source)) < 3);
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Preguntas sin explicación o fuente: ' || missing || '.'); END IF;
  -- every block that names a model must point to a code listed in its lesson, and every listed model must have validated knowledge
  FOR l IN SELECT * FROM f360_academy.lessons WHERE course_version_id = v.id LOOP
    SELECT string_agg(b->>'code', ', ') INTO missing FROM jsonb_array_elements(l.blocks) b
     WHERE b->>'type' IN ('ficha', 'ficha_talla') AND NOT ((b->>'code') = ANY (l.product_codes));
    IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', format('En %s hay fichas que no están en su lista de modelos: %s.', l.key, missing)); END IF;
    SELECT string_agg(x, ', ') INTO missing FROM unnest(l.product_codes) x WHERE f360_academy.product_card(x) IS NULL;
    IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', format('En %s hay modelos sin ficha validada o inactivos: %s.', l.key, missing)); END IF;
    UPDATE f360_academy.lessons SET product_snapshot = coalesce((SELECT jsonb_object_agg(x, f360_academy.product_card(x)) FROM unnest(product_codes) x), '{}')
     WHERE id = l.id;
  END LOOP;
  SELECT string_agg(i.key, ', ') INTO missing FROM f360_academy.items i
   WHERE i.course_version_id = v.id AND i.product_code IS NOT NULL AND f360_academy.product_card(i.product_code) IS NULL;
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Preguntas sobre modelos sin ficha validada: ' || missing || '.'); END IF;
  op := CASE WHEN EXISTS (SELECT 1 FROM f360_academy.lessons l3, jsonb_array_elements(l3.blocks) b WHERE l3.course_version_id = v.id AND b->>'type' = 'politica')
             THEN 'publish_sales_policy' ELSE 'publish_sales' END;
  h := f360_academy.version_hash(v.id);
  rid := f360.approval_request('academy_content', op, 'academy.course_version', v.id, v.version, h, NULL,
    jsonb_build_object('course', c.key, 'title', v.title, 'lessons', (SELECT count(*) FROM f360_academy.lessons WHERE course_version_id = v.id)),
    p_reason, uid, f360_academy.caller_name(uid));
  UPDATE f360_academy.course_versions SET status = 'en_revision', content_hash = h, approval_request_id = rid, submitted_at = clock_timestamp() WHERE id = v.id;
  PERFORM f360_academy.admin_log(uid, 'submit', v.id::text, jsonb_build_object('request', rid, 'operation', op, 'hash', h));
  RETURN jsonb_build_object('ok', true, 'request_id', rid, 'operation', op, 'hash', h);
END $$;

-- Decide (approver, aal2). Approve → consume + publish in the same transaction. Reject → back to draft (new request on resubmit).
CREATE FUNCTION public.f360_academy_decide(p_version uuid, p_approve boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions; r f360.approval_requests; d jsonb; h text; nm text;
BEGIN
  IF NOT f360_academy.is_content_approver(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'en_revision' OR v.approval_request_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión no está en revisión.'); END IF;
  SELECT * INTO r FROM f360.approval_requests WHERE id = v.approval_request_id;
  nm := f360_academy.caller_name(uid);
  h := f360_academy.version_hash(v.id);
  d := f360.approval_decide(r.id, coalesce(p_approve, false), h, uid, nm, p_reason);
  IF NOT (d->>'ok')::boolean THEN
    IF (SELECT status FROM f360.approval_requests WHERE id = r.id) IN ('invalidated', 'expired') THEN
      UPDATE f360_academy.course_versions SET status = 'borrador', content_hash = NULL WHERE id = v.id;
    END IF;
    RETURN d;
  END IF;
  IF d->>'status' = 'rejected' THEN
    UPDATE f360_academy.course_versions SET status = 'borrador', content_hash = NULL WHERE id = v.id;
    PERFORM f360_academy.admin_log(uid, 'reject', v.id::text, jsonb_build_object('request', r.id));
    RETURN jsonb_build_object('ok', true, 'status', 'rechazado');
  END IF;
  IF NOT f360.approval_consume(r.id, 'academy_content', r.operation, 'academy.course_version', v.id, v.version, h, uid, nm) THEN
    RAISE EXCEPTION 'La aprobación no se pudo usar (cambió o venció).';
  END IF;
  UPDATE f360_academy.course_versions SET status = 'retirado', retired_at = clock_timestamp() WHERE course_id = v.course_id AND status = 'publicado';
  UPDATE f360_academy.course_versions SET status = 'publicado', published_at = clock_timestamp() WHERE id = v.id;
  UPDATE f360_academy.courses SET published_version_id = v.id WHERE id = v.course_id;
  PERFORM f360_academy.admin_log(uid, 'publish', v.id::text, jsonb_build_object('request', r.id, 'self_approval', d->'self_approval'));
  RETURN jsonb_build_object('ok', true, 'status', 'publicado', 'self_approval', d->'self_approval');
END $$;

-- Individual progress per learner and store (staff only).
CREATE FUNCTION public.f360_academy_team() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'learners', coalesce((
    SELECT jsonb_agg(jsonb_build_object('name', f360_academy.caller_name(e.auth_user_id),
      'store', (SELECT name FROM f360.locations WHERE id = e.location_id), 'course', v.title, 'version', v.version,
      'enrolled_at', e.enrolled_at, 'completed_at', e.completed_at,
      'lessons_total', (SELECT count(*) FROM f360_academy.lessons l WHERE l.course_version_id = v.id),
      'lessons_done', (SELECT count(*) FROM f360_academy.lesson_progress p JOIN f360_academy.lessons l ON l.id = p.lesson_id
                        WHERE p.auth_user_id = e.auth_user_id AND l.course_version_id = v.id AND p.status = 'completada'),
      'practice', (SELECT jsonb_build_object('answered', count(*), 'correct', count(*) FILTER (WHERE a.correct)) FROM f360_academy.attempts a
                    JOIN f360_academy.items i ON i.id = a.item_id WHERE a.auth_user_id = e.auth_user_id AND i.course_version_id = v.id),
      'tester', f360_academy.has_grant(e.auth_user_id, 'tester')) ORDER BY e.enrolled_at)
    FROM f360_academy.enrollments e JOIN f360_academy.course_versions v ON v.id = e.course_version_id
    JOIN f360_academy.courses c ON c.id = e.course_id WHERE c.school = 'sales'), '[]'));
END $$;

-- ── Privileges ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT format('%I.%I', schemaname, tablename) FROM pg_tables WHERE schemaname = 'f360_academy' LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_academy_me(), public.f360_academy_home(), public.f360_academy_lesson(uuid),
  public.f360_academy_progress_save(uuid, int, boolean), public.f360_academy_answer(uuid, jsonb), public.f360_academy_fichas(),
  public.f360_academy_admin_overview(), public.f360_academy_admin_version(uuid), public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]),
  public.f360_academy_item_save(uuid, jsonb), public.f360_academy_comment(uuid, text, text, int, text), public.f360_academy_new_draft(uuid),
  public.f360_academy_submit(uuid, text), public.f360_academy_decide(uuid, boolean, text), public.f360_academy_team() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_academy_me(), public.f360_academy_home(), public.f360_academy_lesson(uuid),
  public.f360_academy_progress_save(uuid, int, boolean), public.f360_academy_answer(uuid, jsonb), public.f360_academy_fichas(),
  public.f360_academy_admin_overview(), public.f360_academy_admin_version(uuid), public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]),
  public.f360_academy_item_save(uuid, jsonb), public.f360_academy_comment(uuid, text, text, int, text), public.f360_academy_new_draft(uuid),
  public.f360_academy_submit(uuid, text), public.f360_academy_decide(uuid, boolean, text), public.f360_academy_team() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261030000200', 'f360_academy_a1', ARRAY[$m$-- Fuxia Academy · A1 — learning engine for Sales Academy (Mario 2026-10-11: "A1 exclusivamente en staging, alcance controlado").
-- STAGING FIRST. ADDITIVE: own schema f360_academy + public.f360_academy_* RPCs. Depends on 20261030000100 (approval registry).
-- Design: docs/fuxia360/academy/00_FUXIA_ACADEMY_DISENO.md (§3–§5, §9.4, §10, §12) · A1 conditions:
--   · NO real seller access while P0-6 is open: settings.learner_access_enabled is false and a CHECK forbids true — only a reviewed
--     migration can lift it (after P0-6 is fixed). Learners in A1 = people with an explicit 'tester' grant, loaded per environment.
--   · NO certificates, NO points, NO rewards: no tables for them; settings flags are false with CHECKs.
--   · Authentication is untouched. Learners get NO privileged permission: they read published Sales content and write only their
--     own progress / practice answers, server-graded.
--   · Sales and Executive strictly separated: every learner RPC filters school = 'sales'; no executive RPC exists in A1.
--   · Product facts are NEVER stored as course text: lessons reference products by immutable code; on submission the validated
--     public knowledge (f360.product_knowledge_public) is frozen into a snapshot that is part of the approved hash (§9.4).
--   · Publication = shared registry (academy_content.publish_sales, aal2; self-approval only for ordinary product content).
-- Rollback: supabase/rollbacks/20261030000200_f360_academy_a1.down.sql

DO $$ BEGIN
  IF to_regclass('f360.approval_requests') IS NULL THEN RAISE EXCEPTION 'ABORT: falta 20261030000100 (registro de aprobaciones)'; END IF;
END $$;

CREATE SCHEMA f360_academy;
REVOKE ALL ON SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;

-- ── Settings (A1 gates) ──────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.settings (
  id                     boolean PRIMARY KEY DEFAULT true CHECK (id),
  learner_access_enabled boolean NOT NULL DEFAULT false,
  certificates_enabled   boolean NOT NULL DEFAULT false,
  points_enabled         boolean NOT NULL DEFAULT false,
  redemptions_enabled    boolean NOT NULL DEFAULT false,
  note                   text NOT NULL DEFAULT 'A1: acceso real de vendedoras bloqueado mientras P0-6 siga abierto (Mario 2026-10-11).',
  CONSTRAINT a1_no_real_learners CHECK (NOT learner_access_enabled),   -- lifted only by a reviewed migration after P0-6
  CONSTRAINT a1_no_certificates  CHECK (NOT certificates_enabled),
  CONSTRAINT a1_no_points        CHECK (NOT points_enabled),
  CONSTRAINT a1_no_redemptions   CHECK (NOT redemptions_enabled)
);
INSERT INTO f360_academy.settings DEFAULT VALUES;

-- ── Educational roles (layer 1). Loaded per environment by a reviewed script. ────────────────────────────────────────────────
CREATE TABLE f360_academy.grants (
  auth_user_id    uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role            text NOT NULL CHECK (role IN ('tester', 'editor', 'admin', 'executive_learner')),
  display_name    text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 80),
  active          boolean NOT NULL DEFAULT true,
  granted_by_name text NOT NULL,
  evidence        text NOT NULL CHECK (length(btrim(evidence)) >= 5),
  granted_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at      timestamptz,
  PRIMARY KEY (auth_user_id, role)
);
COMMENT ON TABLE f360_academy.grants IS 'Academy educational roles (not Fuxia 360 roles, not approvals). tester = authorized test learner (A1).';
CREATE TABLE f360_academy.grant_changes (
  id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  op     text NOT NULL,
  before jsonb,
  after  jsonb
);
CREATE TRIGGER grant_changes_append_only BEFORE UPDATE OR DELETE ON f360_academy.grant_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE FUNCTION f360_academy.log_grant_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO f360_academy.grant_changes (op, before, after)
  VALUES (TG_OP, CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END, CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER grants_log AFTER INSERT OR UPDATE OR DELETE ON f360_academy.grants FOR EACH ROW EXECUTE FUNCTION f360_academy.log_grant_change();

-- ── Content (versioned; immutable once submitted) ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.courses (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school               text NOT NULL CHECK (school IN ('sales', 'executive')),
  key                  text NOT NULL UNIQUE CHECK (key ~ '^[a-z0-9-]{3,60}$'),
  title                text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  kind                 text NOT NULL CHECK (kind IN ('nivel', 'parte', 'microcert', 'programa', 'bienvenida')),   -- bienvenida = first-entry video
  level_key            text CHECK (level_key IN ('starter', 'product_expert', 'sales_pro', 'master')),
  sort                 int NOT NULL DEFAULT 0,
  published_version_id uuid,
  created_by_name      text NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE f360_academy.course_versions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id           uuid NOT NULL REFERENCES f360_academy.courses (id),
  version             int NOT NULL CHECK (version > 0),
  status              text NOT NULL DEFAULT 'borrador' CHECK (status IN ('borrador', 'en_revision', 'publicado', 'retirado')),
  title               text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  summary             text CHECK (summary IS NULL OR length(summary) <= 600),
  content_hash        text CHECK (content_hash IS NULL OR content_hash ~ '^[0-9a-f]{64}$'),
  approval_request_id uuid REFERENCES f360.approval_requests (id),
  created_by_name     text NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
  submitted_at        timestamptz,
  published_at        timestamptz,
  retired_at          timestamptz,
  UNIQUE (course_id, version)
);
CREATE UNIQUE INDEX course_versions_one_published ON f360_academy.course_versions (course_id) WHERE status = 'publicado';
CREATE UNIQUE INDEX course_versions_one_open ON f360_academy.course_versions (course_id) WHERE status IN ('borrador', 'en_revision');
ALTER TABLE f360_academy.courses ADD CONSTRAINT courses_published_version_fk FOREIGN KEY (published_version_id) REFERENCES f360_academy.course_versions (id);

CREATE TABLE f360_academy.lessons (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  key               text NOT NULL CHECK (key ~ '^[a-z0-9.-]{1,20}$'),
  position          int NOT NULL CHECK (position > 0),
  title             text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 120),
  minutes           int NOT NULL CHECK (minutes BETWEEN 1 AND 15),
  blocks            jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(blocks) = 'array'),
  product_codes     text[] NOT NULL DEFAULT '{}',
  product_snapshot  jsonb,                    -- frozen at submission from f360.product_knowledge_public (validated only)
  UNIQUE (course_version_id, key),
  UNIQUE (course_version_id, position)
);
CREATE TABLE f360_academy.items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  key               text NOT NULL CHECK (key ~ '^[A-Za-z0-9-]{2,40}$'),
  lesson_key        text,
  uses              text[] NOT NULL DEFAULT '{practica}' CHECK (uses <@ ARRAY['practica', 'examen'] AND cardinality(uses) > 0),
  area              text NOT NULL CHECK (area IN ('producto', 'tallas', 'cuidados', 'atencion', 'marca_politicas')),
  kind              text NOT NULL CHECK (kind IN ('opcion', 'vf', 'varias', 'ordenar')),
  prompt            text NOT NULL CHECK (length(btrim(prompt)) BETWEEN 5 AND 600),
  options           jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(options) = 'array'),
  answer            jsonb NOT NULL,           -- never returned to a learner
  explanation       text NOT NULL CHECK (length(btrim(explanation)) BETWEEN 3 AND 600),
  source            text NOT NULL CHECK (length(btrim(source)) >= 3),
  product_code      text,
  status            text NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'bloqueada')),
  UNIQUE (course_version_id, key)
);
CREATE TABLE f360_academy.review_comments (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  lesson_key        text,
  item_key          text,
  block_index       int,
  body              text NOT NULL CHECK (length(btrim(body)) BETWEEN 2 AND 1000),
  by_user           uuid NOT NULL,
  by_name           text NOT NULL,
  at                timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER review_comments_append_only BEFORE UPDATE OR DELETE ON f360_academy.review_comments FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Children of a version can be written only while the version is a draft. The version itself: content fixed once submitted.
CREATE FUNCTION f360_academy.guard_draft_child() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE st text;
BEGIN
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = coalesce(NEW.course_version_id, OLD.course_version_id);
  IF st IS DISTINCT FROM 'borrador' THEN RAISE EXCEPTION 'Esta versión ya no es borrador: no se puede cambiar su contenido.'; END IF;
  IF TG_OP = 'UPDATE' AND NEW.course_version_id IS DISTINCT FROM OLD.course_version_id THEN RAISE EXCEPTION 'No se puede mover contenido entre versiones.'; END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER lessons_draft_only BEFORE INSERT OR UPDATE OR DELETE ON f360_academy.lessons FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_draft_child();
CREATE TRIGGER items_draft_only BEFORE INSERT OR UPDATE OR DELETE ON f360_academy.items FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_draft_child();

CREATE FUNCTION f360_academy.guard_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Una versión de curso no se borra.'; END IF;
  IF (NEW.course_id, NEW.version, NEW.created_by_name, NEW.created_at) IS DISTINCT FROM (OLD.course_id, OLD.version, OLD.created_by_name, OLD.created_at) THEN
    RAISE EXCEPTION 'Estos datos de la versión no cambian.';
  END IF;
  IF OLD.status <> 'borrador' AND (NEW.title, NEW.summary) IS DISTINCT FROM (OLD.title, OLD.summary) THEN
    RAISE EXCEPTION 'Esta versión ya no es borrador: no se puede cambiar su contenido.';
  END IF;
  IF OLD.status IN ('publicado', 'en_revision') AND NEW.content_hash IS DISTINCT FROM OLD.content_hash AND NEW.status <> 'borrador' THEN
    RAISE EXCEPTION 'La huella de una versión enviada no cambia.';
  END IF;
  IF NEW.status <> OLD.status AND NOT ((OLD.status = 'borrador' AND NEW.status = 'en_revision')
      OR (OLD.status = 'en_revision' AND NEW.status IN ('borrador', 'publicado'))
      OR (OLD.status = 'publicado' AND NEW.status = 'retirado')) THEN
    RAISE EXCEPTION 'Transición de versión no permitida: % → %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER course_versions_guard BEFORE UPDATE OR DELETE ON f360_academy.course_versions FOR EACH ROW EXECUTE FUNCTION f360_academy.guard_version();

-- ── Learner progress (own rows only, through RPCs) ───────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_academy.enrollments (
  auth_user_id      uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  course_id         uuid NOT NULL REFERENCES f360_academy.courses (id),
  course_version_id uuid NOT NULL REFERENCES f360_academy.course_versions (id),
  location_id       uuid REFERENCES f360.locations (id),       -- store at enrollment (reports)
  enrolled_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at      timestamptz,
  PRIMARY KEY (auth_user_id, course_id)
);
CREATE TABLE f360_academy.lesson_progress (
  auth_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  lesson_id    uuid NOT NULL REFERENCES f360_academy.lessons (id),
  card_index   int NOT NULL DEFAULT 0 CHECK (card_index >= 0),
  status       text NOT NULL DEFAULT 'en_curso' CHECK (status IN ('en_curso', 'completada')),
  started_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  PRIMARY KEY (auth_user_id, lesson_id)
);
CREATE TABLE f360_academy.attempts (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  auth_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  item_id      uuid NOT NULL REFERENCES f360_academy.items (id),
  kind         text NOT NULL DEFAULT 'practica' CHECK (kind = 'practica'),   -- A1: practice only (no exam, no certificate)
  answer       jsonb NOT NULL,
  correct      boolean NOT NULL,
  at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX attempts_user_idx ON f360_academy.attempts (auth_user_id, at DESC);
CREATE TRIGGER attempts_append_only BEFORE UPDATE OR DELETE ON f360_academy.attempts FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE TABLE f360_academy.admin_events (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_user uuid,
  by_name text NOT NULL,
  action  text NOT NULL,
  ref     text,
  detail  jsonb NOT NULL DEFAULT '{}'
);
CREATE TRIGGER admin_events_append_only BEFORE UPDATE OR DELETE ON f360_academy.admin_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ── Access (layer 2) ─────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION f360_academy.has_grant(p_uid uuid, p_role text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT p_uid IS NOT NULL AND EXISTS (SELECT 1 FROM f360_academy.grants WHERE auth_user_id = p_uid AND role = p_role AND active) $$;

-- Sales learner state: 'ok' (tester, or active seller when access is enabled) | 'bloqueado' (active seller, access disabled: P0-6) | 'none'
CREATE FUNCTION f360_academy.sales_access(p_uid uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE
    WHEN p_uid IS NULL THEN 'none'
    WHEN f360_academy.has_grant(p_uid, 'tester') THEN 'ok'
    WHEN EXISTS (SELECT 1 FROM f360.sellers s WHERE s.auth_user_id = p_uid AND s.status = 'activa')
      THEN CASE WHEN (SELECT learner_access_enabled FROM f360_academy.settings WHERE id) THEN 'ok' ELSE 'bloqueado' END
    ELSE 'none' END $$;

CREATE FUNCTION f360_academy.is_editor(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_academy.has_grant(p_uid, 'editor') OR f360_academy.has_grant(p_uid, 'admin') $$;
CREATE FUNCTION f360_academy.is_content_approver(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360.can_approve_op('academy_content', 'publish_sales', p_uid) OR f360.can_approve_op('academy_content', 'publish_sales_policy', p_uid) $$;
CREATE FUNCTION f360_academy.is_staff(p_uid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_academy.is_editor(p_uid) OR f360_academy.is_content_approver(p_uid) $$;
CREATE FUNCTION f360_academy.caller_name(p_uid uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT display_name FROM f360_academy.grants WHERE auth_user_id = p_uid AND active ORDER BY granted_at LIMIT 1),
                  (SELECT display_name FROM f360.user_roles WHERE auth_user_id = p_uid), 'Usuario') $$;

CREATE FUNCTION f360_academy.denied() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object('ok', false, 'error', 'No disponible.') $$;

-- ── Content helpers ──────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Validated product facts for one code (NULL when the model is not active or its knowledge is not validated).
CREATE FUNCTION f360_academy.product_card(p_code text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN f360.product_knowledge_public(p.id) IS NOT NULL THEN jsonb_build_object(
    'code', p.code, 'name', p.name, 'category', p.category_key,
    'photo', f360.product_primary_image(p.id),
    'sizes', (SELECT jsonb_agg(s.label ORDER BY s.sort) FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT jsonb_agg(jsonb_build_object('name', c.name, 'photo', f360.color_primary_image(c.id)) ORDER BY c.sort, c.created_at)
               FROM f360.product_colors c WHERE c.product_id = p.id),
    'knowledge', f360.product_knowledge_public(p.id)) END
  FROM f360.products p WHERE p.code = p_code AND p.status = 'active' $$;

CREATE FUNCTION f360_academy.valid_blocks(p jsonb) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE b jsonb;
BEGIN
  IF jsonb_typeof(p) <> 'array' OR jsonb_array_length(p) = 0 OR jsonb_array_length(p) > 40 THEN RETURN 'Una lección necesita entre 1 y 40 tarjetas.'; END IF;
  FOR b IN SELECT * FROM jsonb_array_elements(p) LOOP
    IF jsonb_typeof(b) <> 'object' OR NOT (b->>'type' = ANY (ARRAY['texto', 'ficha', 'ficha_talla', 'pendiente', 'politica', 'video'])) THEN RETURN 'Tipo de tarjeta no válido.'; END IF;
    -- a video is a static file of the app, bound to its exact bytes by sha256 (part of the approved hash)
    IF b->>'type' = 'video' AND (coalesce(b->>'src', '') !~ '^/academy/[a-z0-9._-]+\.mp4$' OR coalesce(b->>'sha256', '') !~ '^[0-9a-f]{64}$'
        OR length(btrim(coalesce(b->>'source', ''))) < 3) THEN RETURN 'Una tarjeta de video necesita archivo, huella sha256 y fuente.'; END IF;
    IF b->>'type' IN ('texto', 'pendiente', 'politica') AND length(btrim(coalesce(b->>'text', ''))) NOT BETWEEN 2 AND 600 THEN RETURN 'Cada tarjeta de texto lleva entre 2 y 600 caracteres.'; END IF;
    IF b->>'type' IN ('texto', 'politica') AND length(btrim(coalesce(b->>'source', ''))) < 3 THEN RETURN 'Cada tarjeta de texto lleva su etiqueta de fuente.'; END IF;
    IF b->>'type' IN ('ficha', 'ficha_talla') AND coalesce(b->>'code', '') !~ '^[A-Z0-9-]{2,60}$' THEN RETURN 'Una tarjeta de ficha necesita el código del modelo.'; END IF;
  END LOOP;
  RETURN NULL;
END $$;

-- Canonical content of a version → sha256. Everything an approval covers is in here (texts, product snapshot, questions + answers).
CREATE FUNCTION f360_academy.version_hash(p_version uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT encode(sha256(convert_to(jsonb_build_object(
    'course', (SELECT c.key FROM f360_academy.courses c WHERE c.id = v.course_id), 'version', v.version, 'title', v.title, 'summary', v.summary,
    'lessons', coalesce((SELECT jsonb_agg(jsonb_build_object('key', l.key, 'position', l.position, 'title', l.title, 'minutes', l.minutes,
                 'blocks', l.blocks, 'products', to_jsonb(l.product_codes), 'snapshot', l.product_snapshot) ORDER BY l.position)
               FROM f360_academy.lessons l WHERE l.course_version_id = v.id), '[]'),
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object('key', i.key, 'lesson', i.lesson_key, 'uses', to_jsonb(i.uses), 'area', i.area,
                 'kind', i.kind, 'prompt', i.prompt, 'options', i.options, 'answer', i.answer, 'explanation', i.explanation,
                 'source', i.source, 'product', i.product_code, 'status', i.status) ORDER BY i.key)
               FROM f360_academy.items i WHERE i.course_version_id = v.id), '[]'))::text, 'UTF8')), 'hex')
  FROM f360_academy.course_versions v WHERE v.id = p_version $$;

-- Learner-safe item (no answer).
CREATE FUNCTION f360_academy.item_public(i f360_academy.items) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('id', i.id, 'key', i.key, 'kind', i.kind, 'area', i.area, 'prompt', i.prompt, 'options', i.options) $$;

-- Server-side grading. answer shapes: opcion {"choice":"b"} · vf {"value":true} · varias {"choices":[..]} · ordenar {"order":[..]}
CREATE FUNCTION f360_academy.grade(i f360_academy.items, p_answer jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE i.kind
    WHEN 'opcion' THEN (p_answer->>'choice') IS NOT NULL AND (p_answer->>'choice') = (i.answer->>'choice')
    WHEN 'vf'     THEN jsonb_typeof(p_answer->'value') = 'boolean' AND (p_answer->'value') = (i.answer->'value')
    WHEN 'varias' THEN jsonb_typeof(p_answer->'choices') = 'array'
      AND (SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM jsonb_array_elements_text(p_answer->'choices') x)
        = (SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM jsonb_array_elements_text(i.answer->'choices') x)
    WHEN 'ordenar' THEN jsonb_typeof(p_answer->'order') = 'array' AND (p_answer->'order') = (i.answer->'order')
    ELSE false END $$;

-- The version a learner sees for a course: her pinned enrollment, else the published one.
CREATE FUNCTION f360_academy.learner_version(p_uid uuid, p_course uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT e.course_version_id FROM f360_academy.enrollments e WHERE e.auth_user_id = p_uid AND e.course_id = p_course),
                  (SELECT c.published_version_id FROM f360_academy.courses c WHERE c.id = p_course)) $$;

CREATE FUNCTION f360_academy.render_lesson(l f360_academy.lessons, p_live boolean) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', l.id, 'key', l.key, 'position', l.position, 'title', l.title, 'minutes', l.minutes, 'blocks', l.blocks,
    'products', CASE WHEN p_live THEN coalesce((SELECT jsonb_object_agg(c, coalesce(f360_academy.product_card(c), 'null'::jsonb)) FROM unnest(l.product_codes) c), '{}')
                     ELSE coalesce(l.product_snapshot, '{}') END) $$;

-- ── Learner RPCs ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_academy_me() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('ok', true, 'sales', f360_academy.sales_access(auth.uid()),
    'editor', f360_academy.is_editor(auth.uid()), 'approver', f360_academy.is_content_approver(auth.uid()),
    'admin', f360_academy.has_grant(auth.uid(), 'admin'), 'aal', coalesce(auth.jwt()->>'aal', ''),
    'name', f360_academy.caller_name(auth.uid()),
    'gates', (SELECT jsonb_build_object('learner_access_enabled', learner_access_enabled, 'certificates_enabled', certificates_enabled,
                'points_enabled', points_enabled, 'redemptions_enabled', redemptions_enabled, 'note', note) FROM f360_academy.settings WHERE id)) $$;

CREATE FUNCTION public.f360_academy_home() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'courses', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', c.id, 'key', c.key, 'title', v.title, 'summary', v.summary, 'kind', c.kind, 'version', v.version,
      'enrolled', EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_id = c.id),
      'lessons', (SELECT jsonb_agg(jsonb_build_object('id', l.id, 'key', l.key, 'title', l.title, 'minutes', l.minutes, 'cards', jsonb_array_length(l.blocks),
                    'status', coalesce(p.status, 'pendiente'), 'card_index', coalesce(p.card_index, 0)) ORDER BY l.position)
                  FROM f360_academy.lessons l LEFT JOIN f360_academy.lesson_progress p ON p.lesson_id = l.id AND p.auth_user_id = uid
                  WHERE l.course_version_id = v.id)) ORDER BY c.sort, c.title)
    FROM f360_academy.courses c JOIN f360_academy.course_versions v ON v.id = f360_academy.learner_version(uid, c.id)
    WHERE c.school = 'sales' AND v.status IN ('publicado', 'retirado')), '[]'));
END $$;

CREATE FUNCTION public.f360_academy_lesson(p_lesson uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; v f360_academy.course_versions; c f360_academy.courses; loc uuid;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = l.course_version_id;
  SELECT * INTO c FROM f360_academy.courses WHERE id = v.course_id;
  IF l.id IS NULL OR c.school <> 'sales' OR v.id IS DISTINCT FROM f360_academy.learner_version(uid, c.id) OR v.status NOT IN ('publicado', 'retirado') THEN
    RETURN f360_academy.denied();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_academy.enrollments WHERE auth_user_id = uid AND course_id = c.id) THEN
    SELECT location_id INTO loc FROM f360.location_assignments WHERE auth_user_id = uid AND active ORDER BY granted_at DESC LIMIT 1;
    INSERT INTO f360_academy.enrollments (auth_user_id, course_id, course_version_id, location_id) VALUES (uid, c.id, v.id, loc);
  END IF;
  INSERT INTO f360_academy.lesson_progress (auth_user_id, lesson_id) VALUES (uid, l.id) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('ok', true, 'course', jsonb_build_object('id', c.id, 'title', v.title),
    'lesson', f360_academy.render_lesson(l, false),
    'progress', (SELECT jsonb_build_object('card_index', card_index, 'status', status) FROM f360_academy.lesson_progress WHERE auth_user_id = uid AND lesson_id = l.id),
    'practice', coalesce((SELECT jsonb_agg(f360_academy.item_public(i) ORDER BY i.key) FROM f360_academy.items i
                          WHERE i.course_version_id = v.id AND i.lesson_key = l.key AND 'practica' = ANY (i.uses) AND i.status = 'ok'), '[]'),
    'next', (SELECT n.id FROM f360_academy.lessons n WHERE n.course_version_id = v.id AND n.position > l.position ORDER BY n.position LIMIT 1));
END $$;

CREATE FUNCTION public.f360_academy_progress_save(p_lesson uuid, p_card int, p_done boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; n int;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  IF l.id IS NULL OR NOT EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_version_id = l.course_version_id) THEN
    RETURN f360_academy.denied();
  END IF;
  n := jsonb_array_length(l.blocks);
  IF p_card IS NULL OR p_card < 0 OR p_card > n THEN RETURN jsonb_build_object('ok', false, 'error', 'Tarjeta no válida.'); END IF;
  INSERT INTO f360_academy.lesson_progress AS p (auth_user_id, lesson_id, card_index, status, completed_at)
  VALUES (uid, l.id, p_card, CASE WHEN coalesce(p_done, false) THEN 'completada' ELSE 'en_curso' END, CASE WHEN coalesce(p_done, false) THEN clock_timestamp() END)
  ON CONFLICT (auth_user_id, lesson_id) DO UPDATE SET card_index = EXCLUDED.card_index, updated_at = clock_timestamp(),
    status = CASE WHEN p.status = 'completada' OR coalesce(p_done, false) THEN 'completada' ELSE 'en_curso' END,
    completed_at = coalesce(p.completed_at, EXCLUDED.completed_at);
  UPDATE f360_academy.enrollments e SET completed_at = clock_timestamp()
   WHERE e.auth_user_id = uid AND e.course_version_id = l.course_version_id AND e.completed_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM f360_academy.lessons x LEFT JOIN f360_academy.lesson_progress q ON q.lesson_id = x.id AND q.auth_user_id = uid
                      WHERE x.course_version_id = l.course_version_id AND coalesce(q.status, '') <> 'completada');
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_answer(p_item uuid, p_answer jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); i f360_academy.items; ok boolean;
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO i FROM f360_academy.items WHERE id = p_item;
  IF i.id IS NULL OR i.status <> 'ok' OR NOT ('practica' = ANY (i.uses))
     OR NOT EXISTS (SELECT 1 FROM f360_academy.enrollments e WHERE e.auth_user_id = uid AND e.course_version_id = i.course_version_id) THEN
    RETURN f360_academy.denied();
  END IF;
  IF p_answer IS NULL OR jsonb_typeof(p_answer) <> 'object' OR length(p_answer::text) > 2000 THEN RETURN jsonb_build_object('ok', false, 'error', 'Respuesta no válida.'); END IF;
  ok := f360_academy.grade(i, p_answer);
  INSERT INTO f360_academy.attempts (auth_user_id, item_id, answer, correct) VALUES (uid, i.id, p_answer, ok);
  RETURN jsonb_build_object('ok', true, 'correct', ok, 'explanation', i.explanation, 'source', i.source, 'answer', i.answer);   -- practice: show the right answer after answering
END $$;

CREATE FUNCTION public.f360_academy_fichas() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF f360_academy.sales_access(uid) <> 'ok' THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'fichas', coalesce((
    SELECT jsonb_agg(card ORDER BY card->>'name') FROM (
      SELECT DISTINCT ON (s.key) s.value AS card
      FROM f360_academy.courses c
      JOIN f360_academy.lessons l ON l.course_version_id = f360_academy.learner_version(uid, c.id)
      JOIN f360_academy.course_versions v ON v.id = l.course_version_id AND v.status IN ('publicado', 'retirado'),
      LATERAL jsonb_each(coalesce(l.product_snapshot, '{}')) s
      WHERE c.school = 'sales' AND jsonb_typeof(s.value) = 'object') x), '[]'));
END $$;

-- ── Content administration RPCs (editor / approver) ──────────────────────────────────────────────────────────────────────────
CREATE FUNCTION f360_academy.admin_log(p_uid uuid, p_action text, p_ref text, p_detail jsonb DEFAULT '{}') RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  INSERT INTO f360_academy.admin_events (by_user, by_name, action, ref, detail) VALUES (p_uid, f360_academy.caller_name(p_uid), p_action, p_ref, coalesce(p_detail, '{}')) $$;

CREATE FUNCTION public.f360_academy_admin_overview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'me', public.f360_academy_me(), 'courses', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', c.id, 'key', c.key, 'title', c.title, 'school', c.school, 'kind', c.kind,
      'published_version_id', c.published_version_id,
      'versions', (SELECT jsonb_agg(jsonb_build_object('id', v.id, 'version', v.version, 'status', v.status, 'title', v.title,
          'lessons', (SELECT count(*) FROM f360_academy.lessons l WHERE l.course_version_id = v.id),
          'items', (SELECT count(*) FROM f360_academy.items i WHERE i.course_version_id = v.id),
          'comments', (SELECT count(*) FROM f360_academy.review_comments r WHERE r.course_version_id = v.id),
          'request', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'operation', r.operation, 'requested_by', r.requested_by_name,
                        'requested_at', r.requested_at, 'expires_at', r.expires_at, 'decided_by', r.decided_by_name, 'self_approval', r.self_approval)
                      FROM f360.approval_requests r WHERE r.id = v.approval_request_id),
          -- §9.4: a published snapshot whose product knowledge was re-validated since → needs review
          'stale_products', CASE WHEN v.status = 'publicado' THEN (SELECT coalesce(jsonb_agg(DISTINCT s.key), '[]') FROM f360_academy.lessons l,
              LATERAL jsonb_each(coalesce(l.product_snapshot, '{}')) s
              WHERE l.course_version_id = v.id AND (s.value->'knowledge'->>'version') IS DISTINCT FROM (f360_academy.product_card(s.key)->'knowledge'->>'version')) END
        ) ORDER BY v.version DESC) FROM f360_academy.course_versions v WHERE v.course_id = c.id)
    ) ORDER BY c.school, c.sort, c.title) FROM f360_academy.courses c), '[]'),
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action, 'by', e.by_name, 'reason', e.reason, 'self', e.self_approval,
                  'aal', e.aal, 'operation', r.operation, 'version', r.object_version) ORDER BY e.id DESC)
                FROM (SELECT * FROM f360.approval_events ORDER BY id DESC LIMIT 400) e JOIN f360.approval_requests r ON r.id = e.request_id
                WHERE r.scope LIKE 'academy\_%'), '[]'));
END $$;

CREATE FUNCTION public.f360_academy_admin_version(p_version uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions;
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version;
  IF v.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true,
    'version', jsonb_build_object('id', v.id, 'version', v.version, 'status', v.status, 'title', v.title, 'summary', v.summary,
      'course', (SELECT jsonb_build_object('id', c.id, 'key', c.key, 'school', c.school) FROM f360_academy.courses c WHERE c.id = v.course_id),
      'hash', v.content_hash, 'current_hash', f360_academy.version_hash(v.id)),
    'lessons', coalesce((SELECT jsonb_agg(f360_academy.render_lesson(l, v.status = 'borrador') ORDER BY l.position) FROM f360_academy.lessons l WHERE l.course_version_id = v.id), '[]'),
    'items', coalesce((SELECT jsonb_agg(to_jsonb(i) - 'course_version_id' ORDER BY i.key) FROM f360_academy.items i WHERE i.course_version_id = v.id), '[]'),
    'comments', coalesce((SELECT jsonb_agg(jsonb_build_object('lesson', r.lesson_key, 'item', r.item_key, 'block', r.block_index, 'body', r.body, 'by', r.by_name, 'at', r.at) ORDER BY r.id)
                          FROM f360_academy.review_comments r WHERE r.course_version_id = v.id), '[]'),
    'request', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'operation', r.operation, 'requested_by', r.requested_by_name, 'reason', r.reason,
                  'requested_at', r.requested_at, 'expires_at', r.expires_at, 'hash', r.object_hash,
                  'events', (SELECT jsonb_agg(jsonb_build_object('action', e.action, 'by', e.by_name, 'reason', e.reason, 'at', e.at, 'aal', e.aal, 'self', e.self_approval) ORDER BY e.id)
                             FROM f360.approval_events e WHERE e.request_id = r.id))
                FROM f360.approval_requests r WHERE r.id = v.approval_request_id),
    'can_edit', f360_academy.is_editor(uid) AND v.status = 'borrador',
    'can_decide', v.status = 'en_revision' AND f360_academy.is_content_approver(uid));
END $$;

CREATE FUNCTION public.f360_academy_lesson_save(p_lesson uuid, p_title text, p_minutes int, p_blocks jsonb, p_product_codes text[]) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); l f360_academy.lessons; bad text; st text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO l FROM f360_academy.lessons WHERE id = p_lesson;
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = l.course_version_id;
  IF l.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF st <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión ya no es borrador. Crea una nueva versión para editar.'); END IF;
  bad := f360_academy.valid_blocks(p_blocks);
  IF bad IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', bad); END IF;
  IF length(btrim(coalesce(p_title, ''))) NOT BETWEEN 3 AND 120 OR coalesce(p_minutes, 0) NOT BETWEEN 1 AND 15 THEN RETURN jsonb_build_object('ok', false, 'error', 'Revisa el título y los minutos.'); END IF;
  UPDATE f360_academy.lessons SET title = btrim(p_title), minutes = p_minutes, blocks = p_blocks,
    product_codes = coalesce((SELECT array_agg(DISTINCT upper(btrim(c))) FROM unnest(p_product_codes) c WHERE btrim(c) <> ''), '{}'), product_snapshot = NULL
  WHERE id = l.id;
  PERFORM f360_academy.admin_log(uid, 'lesson_save', l.id::text, jsonb_build_object('key', l.key));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_item_save(p_item uuid, p_fields jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); i f360_academy.items; st text; f jsonb := coalesce(p_fields, '{}'); bad text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO i FROM f360_academy.items WHERE id = p_item;
  SELECT status INTO st FROM f360_academy.course_versions WHERE id = i.course_version_id;
  IF i.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF st <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión ya no es borrador.'); END IF;
  SELECT string_agg(k, ', ') INTO bad FROM jsonb_object_keys(f) k WHERE k <> ALL (ARRAY['prompt', 'options', 'answer', 'explanation', 'source', 'status']);
  IF bad IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Campos no permitidos: ' || bad); END IF;
  BEGIN
    UPDATE f360_academy.items SET
      prompt = coalesce(f->>'prompt', prompt), options = coalesce(f->'options', options), answer = coalesce(f->'answer', answer),
      explanation = coalesce(f->>'explanation', explanation), source = coalesce(f->>'source', source), status = coalesce(f->>'status', status)
    WHERE id = i.id;
  EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Revisa los datos de la pregunta.');
  END;
  PERFORM f360_academy.admin_log(uid, 'item_save', i.id::text, jsonb_build_object('key', i.key, 'fields', (SELECT jsonb_agg(k) FROM jsonb_object_keys(f) k)));
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_academy_comment(p_version uuid, p_lesson_key text, p_item_key text, p_block int, p_body text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) OR NOT EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE id = p_version) THEN RETURN f360_academy.denied(); END IF;
  IF length(btrim(coalesce(p_body, ''))) NOT BETWEEN 2 AND 1000 THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe el comentario.'); END IF;
  INSERT INTO f360_academy.review_comments (course_version_id, lesson_key, item_key, block_index, body, by_user, by_name)
  VALUES (p_version, p_lesson_key, p_item_key, p_block, btrim(p_body), uid, f360_academy.caller_name(uid));
  RETURN jsonb_build_object('ok', true);
END $$;

-- New draft = copy of the latest version (published or not), version + 1.
CREATE FUNCTION public.f360_academy_new_draft(p_course uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); src f360_academy.course_versions; nv uuid;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  IF EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE course_id = p_course AND status IN ('borrador', 'en_revision')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ya hay un borrador o una versión en revisión de este curso.');
  END IF;
  SELECT * INTO src FROM f360_academy.course_versions WHERE course_id = p_course ORDER BY version DESC LIMIT 1;
  IF src.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  INSERT INTO f360_academy.course_versions (course_id, version, title, summary, created_by_name)
  VALUES (p_course, src.version + 1, src.title, src.summary, f360_academy.caller_name(uid)) RETURNING id INTO nv;
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes)
  SELECT nv, key, position, title, minutes, blocks, product_codes FROM f360_academy.lessons WHERE course_version_id = src.id;
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code, status)
  SELECT nv, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code, status FROM f360_academy.items WHERE course_version_id = src.id;
  PERFORM f360_academy.admin_log(uid, 'new_draft', nv::text, jsonb_build_object('from', src.version));
  RETURN jsonb_build_object('ok', true, 'id', nv);
END $$;

-- Submit: validate, freeze validated product snapshots, hash, open the approval request.
CREATE FUNCTION public.f360_academy_submit(p_version uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions; c f360_academy.courses; l record; missing text; h text; rid uuid; op text;
BEGIN
  IF NOT f360_academy.is_editor(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version FOR UPDATE;
  SELECT * INTO c FROM f360_academy.courses WHERE id = v.course_id;
  IF v.id IS NULL THEN RETURN f360_academy.denied(); END IF;
  IF c.school <> 'sales' THEN RETURN jsonb_build_object('ok', false, 'error', 'La Escuela Ejecutiva no se publica en A1.'); END IF;
  IF v.status <> 'borrador' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo un borrador se envía a revisión.'); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe qué cambió o por qué se envía.'); END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_academy.lessons WHERE course_version_id = v.id) THEN RETURN jsonb_build_object('ok', false, 'error', 'El curso no tiene lecciones.'); END IF;
  SELECT string_agg(l2.key, ', ') INTO missing FROM f360_academy.lessons l2
   WHERE l2.course_version_id = v.id AND EXISTS (SELECT 1 FROM jsonb_array_elements(l2.blocks) b WHERE b->>'type' = 'pendiente');
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Hay tarjetas pendientes de Carolina en: ' || missing || '.'); END IF;
  SELECT string_agg(i.key, ', ') INTO missing FROM f360_academy.items i
   WHERE i.course_version_id = v.id AND i.status = 'ok' AND (length(btrim(i.explanation)) < 3 OR length(btrim(i.source)) < 3);
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Preguntas sin explicación o fuente: ' || missing || '.'); END IF;
  -- every block that names a model must point to a code listed in its lesson, and every listed model must have validated knowledge
  FOR l IN SELECT * FROM f360_academy.lessons WHERE course_version_id = v.id LOOP
    SELECT string_agg(b->>'code', ', ') INTO missing FROM jsonb_array_elements(l.blocks) b
     WHERE b->>'type' IN ('ficha', 'ficha_talla') AND NOT ((b->>'code') = ANY (l.product_codes));
    IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', format('En %s hay fichas que no están en su lista de modelos: %s.', l.key, missing)); END IF;
    SELECT string_agg(x, ', ') INTO missing FROM unnest(l.product_codes) x WHERE f360_academy.product_card(x) IS NULL;
    IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', format('En %s hay modelos sin ficha validada o inactivos: %s.', l.key, missing)); END IF;
    UPDATE f360_academy.lessons SET product_snapshot = coalesce((SELECT jsonb_object_agg(x, f360_academy.product_card(x)) FROM unnest(product_codes) x), '{}')
     WHERE id = l.id;
  END LOOP;
  SELECT string_agg(i.key, ', ') INTO missing FROM f360_academy.items i
   WHERE i.course_version_id = v.id AND i.product_code IS NOT NULL AND f360_academy.product_card(i.product_code) IS NULL;
  IF missing IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Preguntas sobre modelos sin ficha validada: ' || missing || '.'); END IF;
  op := CASE WHEN EXISTS (SELECT 1 FROM f360_academy.lessons l3, jsonb_array_elements(l3.blocks) b WHERE l3.course_version_id = v.id AND b->>'type' = 'politica')
             THEN 'publish_sales_policy' ELSE 'publish_sales' END;
  h := f360_academy.version_hash(v.id);
  rid := f360.approval_request('academy_content', op, 'academy.course_version', v.id, v.version, h, NULL,
    jsonb_build_object('course', c.key, 'title', v.title, 'lessons', (SELECT count(*) FROM f360_academy.lessons WHERE course_version_id = v.id)),
    p_reason, uid, f360_academy.caller_name(uid));
  UPDATE f360_academy.course_versions SET status = 'en_revision', content_hash = h, approval_request_id = rid, submitted_at = clock_timestamp() WHERE id = v.id;
  PERFORM f360_academy.admin_log(uid, 'submit', v.id::text, jsonb_build_object('request', rid, 'operation', op, 'hash', h));
  RETURN jsonb_build_object('ok', true, 'request_id', rid, 'operation', op, 'hash', h);
END $$;

-- Decide (approver, aal2). Approve → consume + publish in the same transaction. Reject → back to draft (new request on resubmit).
CREATE FUNCTION public.f360_academy_decide(p_version uuid, p_approve boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); v f360_academy.course_versions; r f360.approval_requests; d jsonb; h text; nm text;
BEGIN
  IF NOT f360_academy.is_content_approver(uid) THEN RETURN f360_academy.denied(); END IF;
  SELECT * INTO v FROM f360_academy.course_versions WHERE id = p_version FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'en_revision' OR v.approval_request_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta versión no está en revisión.'); END IF;
  SELECT * INTO r FROM f360.approval_requests WHERE id = v.approval_request_id;
  nm := f360_academy.caller_name(uid);
  h := f360_academy.version_hash(v.id);
  d := f360.approval_decide(r.id, coalesce(p_approve, false), h, uid, nm, p_reason);
  IF NOT (d->>'ok')::boolean THEN
    IF (SELECT status FROM f360.approval_requests WHERE id = r.id) IN ('invalidated', 'expired') THEN
      UPDATE f360_academy.course_versions SET status = 'borrador', content_hash = NULL WHERE id = v.id;
    END IF;
    RETURN d;
  END IF;
  IF d->>'status' = 'rejected' THEN
    UPDATE f360_academy.course_versions SET status = 'borrador', content_hash = NULL WHERE id = v.id;
    PERFORM f360_academy.admin_log(uid, 'reject', v.id::text, jsonb_build_object('request', r.id));
    RETURN jsonb_build_object('ok', true, 'status', 'rechazado');
  END IF;
  IF NOT f360.approval_consume(r.id, 'academy_content', r.operation, 'academy.course_version', v.id, v.version, h, uid, nm) THEN
    RAISE EXCEPTION 'La aprobación no se pudo usar (cambió o venció).';
  END IF;
  UPDATE f360_academy.course_versions SET status = 'retirado', retired_at = clock_timestamp() WHERE course_id = v.course_id AND status = 'publicado';
  UPDATE f360_academy.course_versions SET status = 'publicado', published_at = clock_timestamp() WHERE id = v.id;
  UPDATE f360_academy.courses SET published_version_id = v.id WHERE id = v.course_id;
  PERFORM f360_academy.admin_log(uid, 'publish', v.id::text, jsonb_build_object('request', r.id, 'self_approval', d->'self_approval'));
  RETURN jsonb_build_object('ok', true, 'status', 'publicado', 'self_approval', d->'self_approval');
END $$;

-- Individual progress per learner and store (staff only).
CREATE FUNCTION public.f360_academy_team() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF NOT f360_academy.is_staff(uid) THEN RETURN f360_academy.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'learners', coalesce((
    SELECT jsonb_agg(jsonb_build_object('name', f360_academy.caller_name(e.auth_user_id),
      'store', (SELECT name FROM f360.locations WHERE id = e.location_id), 'course', v.title, 'version', v.version,
      'enrolled_at', e.enrolled_at, 'completed_at', e.completed_at,
      'lessons_total', (SELECT count(*) FROM f360_academy.lessons l WHERE l.course_version_id = v.id),
      'lessons_done', (SELECT count(*) FROM f360_academy.lesson_progress p JOIN f360_academy.lessons l ON l.id = p.lesson_id
                        WHERE p.auth_user_id = e.auth_user_id AND l.course_version_id = v.id AND p.status = 'completada'),
      'practice', (SELECT jsonb_build_object('answered', count(*), 'correct', count(*) FILTER (WHERE a.correct)) FROM f360_academy.attempts a
                    JOIN f360_academy.items i ON i.id = a.item_id WHERE a.auth_user_id = e.auth_user_id AND i.course_version_id = v.id),
      'tester', f360_academy.has_grant(e.auth_user_id, 'tester')) ORDER BY e.enrolled_at)
    FROM f360_academy.enrollments e JOIN f360_academy.course_versions v ON v.id = e.course_version_id
    JOIN f360_academy.courses c ON c.id = e.course_id WHERE c.school = 'sales'), '[]'));
END $$;

-- ── Privileges ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$ DECLARE t text; BEGIN
  FOR t IN SELECT format('%I.%I', schemaname, tablename) FROM pg_tables WHERE schemaname = 'f360_academy' LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_academy FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_academy_me(), public.f360_academy_home(), public.f360_academy_lesson(uuid),
  public.f360_academy_progress_save(uuid, int, boolean), public.f360_academy_answer(uuid, jsonb), public.f360_academy_fichas(),
  public.f360_academy_admin_overview(), public.f360_academy_admin_version(uuid), public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]),
  public.f360_academy_item_save(uuid, jsonb), public.f360_academy_comment(uuid, text, text, int, text), public.f360_academy_new_draft(uuid),
  public.f360_academy_submit(uuid, text), public.f360_academy_decide(uuid, boolean, text), public.f360_academy_team() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_academy_me(), public.f360_academy_home(), public.f360_academy_lesson(uuid),
  public.f360_academy_progress_save(uuid, int, boolean), public.f360_academy_answer(uuid, jsonb), public.f360_academy_fichas(),
  public.f360_academy_admin_overview(), public.f360_academy_admin_version(uuid), public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]),
  public.f360_academy_item_save(uuid, jsonb), public.f360_academy_comment(uuid, text, text, int, text), public.f360_academy_new_draft(uuid),
  public.f360_academy_submit(uuid, text), public.f360_academy_decide(uuid, boolean, text), public.f360_academy_team() TO authenticated;$m$]);
-- >>> 20261030000300_f360_academy_pilot_seed
-- Fuxia Academy · A1 seed: course "Fuxia Starter · Parte 1 (Producto Ballerinas)", version 1 as a DRAFT (Mario 2026-10-11: pilot with Paula,
-- Byl, Mafalda Studs, Leather Loafers, Sueco cucarrón). Content = A0 documents (docs/fuxia360/academy/a0/02 and 04), NOT yet approved by
-- Carolina: it can only reach learners after she publishes it in the platform (academy_content.publish_sales, aal2).
-- Product facts are NOT written here: lessons list product CODES; the validated knowledge is frozen at submission (§9.4). Question
-- items about a model carry its code; submission refuses them if that model's knowledge is not validated.
-- Idempotent (skips if the course exists). Rollback: supabase/rollbacks/20261030000300_f360_academy_pilot_seed.down.sql
DO $$
DECLARE c uuid; v uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM f360_academy.courses WHERE key = 'starter-ballerinas-parte-1') THEN RETURN; END IF;
  INSERT INTO f360_academy.courses (school, key, title, kind, level_key, sort, created_by_name)
  VALUES ('sales', 'starter-ballerinas-parte-1', 'Fuxia Starter · Parte 1 (Producto Ballerinas)', 'parte', 'starter', 1, 'migración 20261030000300') RETURNING id INTO c;
  INSERT INTO f360_academy.course_versions (course_id, version, title, summary, created_by_name)
  VALUES (c, 1, 'Fuxia Starter · Parte 1 (Producto Ballerinas)',
    'Piloto: 7 microlecciones y 5 modelos (Paula, Byl, Mafalda Studs, Leather Loafers, Sueco cucarrón). Sin certificado ni puntos en A1.',
    'migración 20261030000300') RETURNING id INTO v;
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '2.0', 1, 'Cómo leer una ficha', 3, $j$[{"type": "texto", "text": "Cada modelo tiene una ficha con su foto, tallas, colores y lo que Carolina validó sobre él.", "source": "[CATÁLOGO]"}, {"type": "texto", "text": "Validada significa que Carolina la revisó. Solo lo validado se le dice a la clienta. Si algo dice pendiente, no lo inventes: \"Lo confirmo y te aviso\".", "source": "[SISTEMA]"}, {"type": "texto", "text": "Ajuste de talla: si conviene la talla habitual. Entre dos tallas: cuál elegir si duda.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Horma: cómoda, normal o ajustada. Ancho: angosto, normal o amplio. Punta: redonda, almendrada, puntuda, cuadrada o abierta.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Materiales: exterior, forro y suela, tal como los escribió Carolina. Comodidad: su nota sobre cómo se siente. Cuidados: cómo cuidarlos.", "source": "[SISTEMA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '2.p', 2, 'Cinco modelos para empezar', 8, $j$[{"type": "texto", "text": "Vas a conocer 5 modelos. En cada uno fíjate en tres cosas: cómo queda la talla, la horma y la punta.", "source": "[PEDAGOGÍA]"}, {"type": "ficha", "code": "PAULA"}, {"type": "ficha", "code": "BALLERINAS-BYL-PUNTUDO"}, {"type": "ficha", "code": "MAFALDA-TACHES"}, {"type": "ficha", "code": "LEATHER-LOAFERS"}, {"type": "ficha", "code": "SUECO-CUCARRON"}, {"type": "texto", "text": "Antes de recomendar un modelo, abre su ficha: ahí está lo que Carolina validó.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY['PAULA', 'BALLERINAS-BYL-PUNTUDO', 'MAFALDA-TACHES', 'LEATHER-LOAFERS', 'SUECO-CUCARRON']::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '3.1', 3, 'Las tallas de las Ballerinas', 3, $j$[{"type": "texto", "text": "Las Ballerinas de este curso vienen en tallas 35, 36, 37, 38, 39 y 40.", "source": "[CATÁLOGO]"}, {"type": "texto", "text": "Son tallas enteras: no hay medias tallas en estos modelos.", "source": "[CATÁLOGO]"}, {"type": "texto", "text": "Si la clienta te dice su talla en otra escala (\"7\", \"US 6\"), no conviertas de memoria: pregúntale su talla en 35–40 o pruébale.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Antes de ofrecer una talla, revisa el inventario en Fuxia 360. El inventario cambia cada día.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '3.2', 4, 'Talla exacta, chica o grande', 4, $j$[{"type": "texto", "text": "Cada modelo dice en su ficha cómo queda la talla.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Talla exacta: recomienda su talla habitual.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Talla chica: sigue la nota de Carolina de ese modelo. Mira estos dos ejemplos.", "source": "[SISTEMA]"}, {"type": "ficha_talla", "code": "PAULA"}, {"type": "ficha_talla", "code": "SUECO-CUCARRON"}, {"type": "texto", "text": "Entre dos tallas: la ficha dice si conviene \"la mayor\" o \"la menor\". Sigue lo que diga la ficha de ese modelo.", "source": "[SISTEMA]"}, {"type": "ficha_talla", "code": "MAFALDA-TACHES"}, {"type": "ficha_talla", "code": "LEATHER-LOAFERS"}]$j$::jsonb, ARRAY['PAULA', 'SUECO-CUCARRON', 'MAFALDA-TACHES', 'LEATHER-LOAFERS']::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '3.3', 5, 'Cómo preguntar y probar la talla', 3, $j$[{"type": "texto", "text": "Pregunta: \"¿Qué talla usas normalmente?\" y \"¿Cómo te gusta sentir el zapato: justo o con espacio?\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Con su respuesta, revisa en la ficha el ajuste del modelo y confirma en el inventario que esté su talla.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Dale a probar. Pídele que camine unos pasos. Pregunta: \"¿Dónde lo sientes justo?\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Si queda justo, ofrece la otra talla o un modelo con otra horma. No prometas que \"se va a aflojar\".", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '5.1', 6, 'Recibir y descubrir', 4, $j$[{"type": "texto", "text": "Saluda con calma y déjala mirar unos segundos. \"Hola, bienvenida. Si quieres probarte alguno, aquí estoy.\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Cuando se interese, pregunta para qué los busca: diario, oficina, evento, viaje.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Pregunta su talla habitual y cómo le gusta sentir el zapato.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Escucha más de lo que hablas. Lo que te diga decide qué le muestras.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '5.2', 7, 'Presentar 2 o 3 opciones', 4, $j$[{"type": "texto", "text": "Elige 2 o 3 modelos según lo que te dijo. No muestres todo el catálogo.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Presenta cada uno con un dato de su ficha unido a lo que ella busca. Ejemplo genérico: \"Buscas comodidad todo el día; este tiene horma cómoda.\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "No digas \"es el más vendido\" ni \"se acaba hoy\" si no lo sabes.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Si duda entre dos, pregúntale cuál sintió más cómodo y para qué lo usará más.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A01', '2.0', ARRAY['practica', 'examen'], 'producto', 'opcion', '¿Qué significa que la ficha de un modelo diga "validada"?', $j$[{"id": "a", "text": "Que el modelo tiene inventario"}, {"id": "b", "text": "Que Carolina revisó y aprobó esa información"}, {"id": "c", "text": "Que el modelo está en oferta"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Solo la información validada por Carolina se enseña y se le dice a la clienta.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A05', '2.0', ARRAY['practica', 'examen'], 'producto', 'opcion', '¿Qué valores puede tener la punta en una ficha?', $j$[{"id": "a", "text": "Redonda, almendrada, puntuda, cuadrada o abierta"}, {"id": "b", "text": "Chica, mediana o grande"}, {"id": "c", "text": "Cómoda, normal o ajustada"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Son las opciones de la ficha. "Cómoda / normal / ajustada" es la horma.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A06', NULL, ARRAY['examen'], 'producto', 'opcion', '¿Qué valores puede tener la horma en una ficha?', $j$[{"id": "a", "text": "Angosta, normal o amplia"}, {"id": "b", "text": "Cómoda, normal o ajustada"}, {"id": "c", "text": "Exacta, chica o grande"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, '"Angosto / normal / amplio" es el ancho; "exacta / chica / grande" es el ajuste de talla.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-PAULA-HP', '2.p', ARRAY['practica', 'examen'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Paula?', $j$[{"id": "a", "text": "Horma cómoda, punta cuadrada"}, {"id": "b", "text": "Horma normal, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta redonda"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v2 · 2026-10-08]', 'PAULA');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-PAULA-TALLA', '3.2', ARRAY['practica', 'examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Paula. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Su ficha es "Talla chica": "Te recomendamos pedir una talla mas".', '[FICHA v2 · 2026-10-08]', 'PAULA');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-BYL-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Byl?', $j$[{"id": "a", "text": "Horma cómoda, punta cuadrada"}, {"id": "b", "text": "Horma normal, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta redonda"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v1 · 2026-10-08]', 'BALLERINAS-BYL-PUNTUDO');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-BYL-TALLA', NULL, ARRAY['examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Byl. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Su ficha es "Talla exacta": "Te recomendamos pedir tu talla habitual."', '[FICHA v1 · 2026-10-08]', 'BALLERINAS-BYL-PUNTUDO');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-MAFALDA-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Mafalda Studs?', $j$[{"id": "a", "text": "Horma normal, punta cuadrada"}, {"id": "b", "text": "Horma cómoda, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta redonda"}]$j$::jsonb, $j${"choice": "c"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v3 · 2026-10-08]', 'MAFALDA-TACHES');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-MAFALDA-TALLA', NULL, ARRAY['examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Mafalda Studs. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Su ficha es "Talla exacta": "Te recomendamos pedir tu talla habitual." Entre dos tallas: la menor.', '[FICHA v3 · 2026-10-08]', 'MAFALDA-TACHES');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-LOAFERS-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Leather Loafers?', $j$[{"id": "a", "text": "Horma normal, punta redonda"}, {"id": "b", "text": "Horma cómoda, punta cuadrada"}, {"id": "c", "text": "Horma cómoda, punta puntuda"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v4 · 2026-10-08]', 'LEATHER-LOAFERS');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-LOAFERS-TALLA', NULL, ARRAY['examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Leather Loafers. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Su ficha es "Talla exacta": "Te recomendamos pedir tu talla habitual."', '[FICHA v4 · 2026-10-08]', 'LEATHER-LOAFERS');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-SUECO-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Sueco cucarrón?', $j$[{"id": "a", "text": "Horma cómoda, punta redonda"}, {"id": "b", "text": "Horma normal, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta cuadrada"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v1 · 2026-10-08]', 'SUECO-CUCARRON');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-SUECO-TALLA', '3.2', ARRAY['practica', 'examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Sueco cucarrón. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Su ficha es "Talla chica": "Te recomendamos pedir una talla mas".', '[FICHA v1 · 2026-10-08]', 'SUECO-CUCARRON');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A07', '3.1', ARRAY['practica', 'examen'], 'tallas', 'opcion', '¿En qué tallas vienen las Ballerinas de este curso?', $j$[{"id": "a", "text": "22 a 27"}, {"id": "b", "text": "35 a 40"}, {"id": "c", "text": "5 a 10"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Vienen del 35 al 40.', '[CATÁLOGO]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A09', '3.1', ARRAY['practica'], 'tallas', 'opcion', 'Una clienta dice que en otra marca usa "talla 7". ¿Qué haces?', $j$[{"id": "a", "text": "Le conviertes la talla de memoria"}, {"id": "b", "text": "Le preguntas su talla en escala 35–40 o le pruebas el modelo"}, {"id": "c", "text": "Le das la 37 porque es la más común"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'No hacemos conversiones de memoria. Preguntamos o probamos.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A10', NULL, ARRAY['examen'], 'tallas', 'vf', 'Las Ballerinas de este curso tienen medias tallas, por ejemplo 37.5.', $j$[]$j$::jsonb, $j${"value": false}$j$::jsonb, 'Vienen en tallas enteras del 35 al 40.', '[CATÁLOGO]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A11', '3.2', ARRAY['practica', 'examen'], 'tallas', 'opcion', 'Un modelo dice "Talla exacta". ¿Qué le recomiendas a la clienta?', $j$[{"id": "a", "text": "Una talla más"}, {"id": "b", "text": "Su talla habitual"}, {"id": "c", "text": "Una talla menos"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, '"Talla exacta" = pedir la talla habitual.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A12', '3.2', ARRAY['practica', 'examen'], 'tallas', 'opcion', 'La ficha dice "¿Entre dos tallas? Elige la mayor." Una clienta duda entre 37 y 38. ¿Cuál le sugieres probar primero?', $j$[{"id": "a", "text": "37"}, {"id": "b", "text": "38"}, {"id": "c", "text": "Cualquiera"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'La ficha de ese modelo indica la mayor.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A17', '3.3', ARRAY['practica'], 'tallas', 'ordenar', 'Ordena los pasos.', $j$[{"id": "1", "text": "Le preguntas su talla habitual"}, {"id": "2", "text": "Revisas en la ficha el ajuste del modelo"}, {"id": "3", "text": "Revisas que esa talla esté en inventario"}, {"id": "4", "text": "Le das a probar"}]$j$::jsonb, $j${"order": ["1", "2", "3", "4"]}$j$::jsonb, 'Primero preguntar, luego ficha, luego inventario y al final probar.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A19', '3.3', ARRAY['practica'], 'tallas', 'vf', 'Si el par le aprieta un poco, le digo que "se va a aflojar" para cerrar la venta.', $j$[]$j$::jsonb, $j${"value": false}$j$::jsonb, 'No prometemos ajustes que la ficha no dice. Si queda justo, se prueba otra talla o modelo.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A25', '5.1', ARRAY['practica', 'examen'], 'atencion', 'opcion', '¿Cuál pregunta te ayuda más a recomendar bien?', $j$[{"id": "a", "text": "\"¿Te gustan?\""}, {"id": "b", "text": "\"¿Para qué ocasión o uso los buscas?\""}, {"id": "c", "text": "\"¿Vienes por la promoción?\""}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'El uso y la ocasión guían la recomendación.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A26', '5.1', ARRAY['practica'], 'atencion', 'varias', 'Elige las 3 preguntas de descubrimiento recomendadas.', $j$[{"id": "uso", "text": "Uso u ocasión"}, {"id": "talla", "text": "Talla habitual"}, {"id": "sentir", "text": "Cómo prefiere sentir el zapato"}, {"id": "ingreso", "text": "Cuánto gana al mes"}]$j$::jsonb, $j${"choices": ["sentir", "talla", "uso"]}$j$::jsonb, 'Uso, talla y cómo le gusta sentir el zapato. Cuánto gana no se pregunta.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A29', '5.2', ARRAY['practica', 'examen'], 'atencion', 'opcion', '¿Cuántas opciones conviene presentar al inicio?', $j$[{"id": "a", "text": "Una"}, {"id": "b", "text": "Dos o tres, elegidas por lo que te dijo"}, {"id": "c", "text": "Todas las del catálogo"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Menos opciones, mejor elegidas, facilitan decidir.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A30', '5.2', ARRAY['practica'], 'atencion', 'opcion', '¿Cómo presentas un modelo?', $j$[{"id": "a", "text": "\"Está muy bonito\""}, {"id": "b", "text": "Conectas un dato de la ficha con lo que ella pidió"}, {"id": "c", "text": "\"Es el más vendido\" (sin saberlo)"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Dato validado + necesidad de la clienta.', '[PEDAGOGÍA]', NULL);
  -- First-entry welcome video (Mario 2026-10-11: "Bienvenida a Fuxia Academy", para vendedoras). DRAFT until Carolina publishes it.
  IF NOT EXISTS (SELECT 1 FROM f360_academy.courses WHERE key = 'bienvenida-academy') THEN
    INSERT INTO f360_academy.courses (school, key, title, kind, sort, created_by_name)
    VALUES ('sales', 'bienvenida-academy', 'Bienvenida a Fuxia Academy', 'bienvenida', 0, 'migración 20261030000300') RETURNING id INTO c;
    INSERT INTO f360_academy.course_versions (course_id, version, title, summary, created_by_name)
    VALUES (c, 1, 'Bienvenida a Fuxia Academy', 'Video de 60 s que ve cada vendedora la primera vez que entra.', 'migración 20261030000300') RETURNING id INTO v;
    INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '0.1', 1, 'Bienvenida a Fuxia Academy', 1,
      $j$[{"type": "video", "src": "/academy/bienvenida-720.mp4", "poster": "/academy/bienvenida-poster.jpg", "sha256": "586603c1b17c5430bd73242f7004a7297df31e23925b859bf4939233e8edabdf", "text": "Bienvenida a Fuxia Academy", "source": "[VIDEO BIENVENIDA · guion tools/video/academy/GUION_BIENVENIDA.md]"}]$j$::jsonb, '{}');
  END IF;
END $$;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261030000300', 'f360_academy_pilot_seed', ARRAY[$m$-- Fuxia Academy · A1 seed: course "Fuxia Starter · Parte 1 (Producto Ballerinas)", version 1 as a DRAFT (Mario 2026-10-11: pilot with Paula,
-- Byl, Mafalda Studs, Leather Loafers, Sueco cucarrón). Content = A0 documents (docs/fuxia360/academy/a0/02 and 04), NOT yet approved by
-- Carolina: it can only reach learners after she publishes it in the platform (academy_content.publish_sales, aal2).
-- Product facts are NOT written here: lessons list product CODES; the validated knowledge is frozen at submission (§9.4). Question
-- items about a model carry its code; submission refuses them if that model's knowledge is not validated.
-- Idempotent (skips if the course exists). Rollback: supabase/rollbacks/20261030000300_f360_academy_pilot_seed.down.sql
DO $$
DECLARE c uuid; v uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM f360_academy.courses WHERE key = 'starter-ballerinas-parte-1') THEN RETURN; END IF;
  INSERT INTO f360_academy.courses (school, key, title, kind, level_key, sort, created_by_name)
  VALUES ('sales', 'starter-ballerinas-parte-1', 'Fuxia Starter · Parte 1 (Producto Ballerinas)', 'parte', 'starter', 1, 'migración 20261030000300') RETURNING id INTO c;
  INSERT INTO f360_academy.course_versions (course_id, version, title, summary, created_by_name)
  VALUES (c, 1, 'Fuxia Starter · Parte 1 (Producto Ballerinas)',
    'Piloto: 7 microlecciones y 5 modelos (Paula, Byl, Mafalda Studs, Leather Loafers, Sueco cucarrón). Sin certificado ni puntos en A1.',
    'migración 20261030000300') RETURNING id INTO v;
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '2.0', 1, 'Cómo leer una ficha', 3, $j$[{"type": "texto", "text": "Cada modelo tiene una ficha con su foto, tallas, colores y lo que Carolina validó sobre él.", "source": "[CATÁLOGO]"}, {"type": "texto", "text": "Validada significa que Carolina la revisó. Solo lo validado se le dice a la clienta. Si algo dice pendiente, no lo inventes: \"Lo confirmo y te aviso\".", "source": "[SISTEMA]"}, {"type": "texto", "text": "Ajuste de talla: si conviene la talla habitual. Entre dos tallas: cuál elegir si duda.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Horma: cómoda, normal o ajustada. Ancho: angosto, normal o amplio. Punta: redonda, almendrada, puntuda, cuadrada o abierta.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Materiales: exterior, forro y suela, tal como los escribió Carolina. Comodidad: su nota sobre cómo se siente. Cuidados: cómo cuidarlos.", "source": "[SISTEMA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '2.p', 2, 'Cinco modelos para empezar', 8, $j$[{"type": "texto", "text": "Vas a conocer 5 modelos. En cada uno fíjate en tres cosas: cómo queda la talla, la horma y la punta.", "source": "[PEDAGOGÍA]"}, {"type": "ficha", "code": "PAULA"}, {"type": "ficha", "code": "BALLERINAS-BYL-PUNTUDO"}, {"type": "ficha", "code": "MAFALDA-TACHES"}, {"type": "ficha", "code": "LEATHER-LOAFERS"}, {"type": "ficha", "code": "SUECO-CUCARRON"}, {"type": "texto", "text": "Antes de recomendar un modelo, abre su ficha: ahí está lo que Carolina validó.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY['PAULA', 'BALLERINAS-BYL-PUNTUDO', 'MAFALDA-TACHES', 'LEATHER-LOAFERS', 'SUECO-CUCARRON']::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '3.1', 3, 'Las tallas de las Ballerinas', 3, $j$[{"type": "texto", "text": "Las Ballerinas de este curso vienen en tallas 35, 36, 37, 38, 39 y 40.", "source": "[CATÁLOGO]"}, {"type": "texto", "text": "Son tallas enteras: no hay medias tallas en estos modelos.", "source": "[CATÁLOGO]"}, {"type": "texto", "text": "Si la clienta te dice su talla en otra escala (\"7\", \"US 6\"), no conviertas de memoria: pregúntale su talla en 35–40 o pruébale.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Antes de ofrecer una talla, revisa el inventario en Fuxia 360. El inventario cambia cada día.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '3.2', 4, 'Talla exacta, chica o grande', 4, $j$[{"type": "texto", "text": "Cada modelo dice en su ficha cómo queda la talla.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Talla exacta: recomienda su talla habitual.", "source": "[SISTEMA]"}, {"type": "texto", "text": "Talla chica: sigue la nota de Carolina de ese modelo. Mira estos dos ejemplos.", "source": "[SISTEMA]"}, {"type": "ficha_talla", "code": "PAULA"}, {"type": "ficha_talla", "code": "SUECO-CUCARRON"}, {"type": "texto", "text": "Entre dos tallas: la ficha dice si conviene \"la mayor\" o \"la menor\". Sigue lo que diga la ficha de ese modelo.", "source": "[SISTEMA]"}, {"type": "ficha_talla", "code": "MAFALDA-TACHES"}, {"type": "ficha_talla", "code": "LEATHER-LOAFERS"}]$j$::jsonb, ARRAY['PAULA', 'SUECO-CUCARRON', 'MAFALDA-TACHES', 'LEATHER-LOAFERS']::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '3.3', 5, 'Cómo preguntar y probar la talla', 3, $j$[{"type": "texto", "text": "Pregunta: \"¿Qué talla usas normalmente?\" y \"¿Cómo te gusta sentir el zapato: justo o con espacio?\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Con su respuesta, revisa en la ficha el ajuste del modelo y confirma en el inventario que esté su talla.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Dale a probar. Pídele que camine unos pasos. Pregunta: \"¿Dónde lo sientes justo?\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Si queda justo, ofrece la otra talla o un modelo con otra horma. No prometas que \"se va a aflojar\".", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '5.1', 6, 'Recibir y descubrir', 4, $j$[{"type": "texto", "text": "Saluda con calma y déjala mirar unos segundos. \"Hola, bienvenida. Si quieres probarte alguno, aquí estoy.\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Cuando se interese, pregunta para qué los busca: diario, oficina, evento, viaje.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Pregunta su talla habitual y cómo le gusta sentir el zapato.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Escucha más de lo que hablas. Lo que te diga decide qué le muestras.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '5.2', 7, 'Presentar 2 o 3 opciones', 4, $j$[{"type": "texto", "text": "Elige 2 o 3 modelos según lo que te dijo. No muestres todo el catálogo.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Presenta cada uno con un dato de su ficha unido a lo que ella busca. Ejemplo genérico: \"Buscas comodidad todo el día; este tiene horma cómoda.\"", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "No digas \"es el más vendido\" ni \"se acaba hoy\" si no lo sabes.", "source": "[PEDAGOGÍA]"}, {"type": "texto", "text": "Si duda entre dos, pregúntale cuál sintió más cómodo y para qué lo usará más.", "source": "[PEDAGOGÍA]"}]$j$::jsonb, ARRAY[]::text[]);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A01', '2.0', ARRAY['practica', 'examen'], 'producto', 'opcion', '¿Qué significa que la ficha de un modelo diga "validada"?', $j$[{"id": "a", "text": "Que el modelo tiene inventario"}, {"id": "b", "text": "Que Carolina revisó y aprobó esa información"}, {"id": "c", "text": "Que el modelo está en oferta"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Solo la información validada por Carolina se enseña y se le dice a la clienta.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A05', '2.0', ARRAY['practica', 'examen'], 'producto', 'opcion', '¿Qué valores puede tener la punta en una ficha?', $j$[{"id": "a", "text": "Redonda, almendrada, puntuda, cuadrada o abierta"}, {"id": "b", "text": "Chica, mediana o grande"}, {"id": "c", "text": "Cómoda, normal o ajustada"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Son las opciones de la ficha. "Cómoda / normal / ajustada" es la horma.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A06', NULL, ARRAY['examen'], 'producto', 'opcion', '¿Qué valores puede tener la horma en una ficha?', $j$[{"id": "a", "text": "Angosta, normal o amplia"}, {"id": "b", "text": "Cómoda, normal o ajustada"}, {"id": "c", "text": "Exacta, chica o grande"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, '"Angosto / normal / amplio" es el ancho; "exacta / chica / grande" es el ajuste de talla.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-PAULA-HP', '2.p', ARRAY['practica', 'examen'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Paula?', $j$[{"id": "a", "text": "Horma cómoda, punta cuadrada"}, {"id": "b", "text": "Horma normal, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta redonda"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v2 · 2026-10-08]', 'PAULA');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-PAULA-TALLA', '3.2', ARRAY['practica', 'examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Paula. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Su ficha es "Talla chica": "Te recomendamos pedir una talla mas".', '[FICHA v2 · 2026-10-08]', 'PAULA');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-BYL-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Byl?', $j$[{"id": "a", "text": "Horma cómoda, punta cuadrada"}, {"id": "b", "text": "Horma normal, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta redonda"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v1 · 2026-10-08]', 'BALLERINAS-BYL-PUNTUDO');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-BYL-TALLA', NULL, ARRAY['examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Byl. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Su ficha es "Talla exacta": "Te recomendamos pedir tu talla habitual."', '[FICHA v1 · 2026-10-08]', 'BALLERINAS-BYL-PUNTUDO');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-MAFALDA-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Mafalda Studs?', $j$[{"id": "a", "text": "Horma normal, punta cuadrada"}, {"id": "b", "text": "Horma cómoda, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta redonda"}]$j$::jsonb, $j${"choice": "c"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v3 · 2026-10-08]', 'MAFALDA-TACHES');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-MAFALDA-TALLA', NULL, ARRAY['examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Mafalda Studs. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Su ficha es "Talla exacta": "Te recomendamos pedir tu talla habitual." Entre dos tallas: la menor.', '[FICHA v3 · 2026-10-08]', 'MAFALDA-TACHES');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-LOAFERS-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Leather Loafers?', $j$[{"id": "a", "text": "Horma normal, punta redonda"}, {"id": "b", "text": "Horma cómoda, punta cuadrada"}, {"id": "c", "text": "Horma cómoda, punta puntuda"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v4 · 2026-10-08]', 'LEATHER-LOAFERS');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-LOAFERS-TALLA', NULL, ARRAY['examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Leather Loafers. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Su ficha es "Talla exacta": "Te recomendamos pedir tu talla habitual."', '[FICHA v4 · 2026-10-08]', 'LEATHER-LOAFERS');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-SUECO-HP', '2.p', ARRAY['practica'], 'producto', 'opcion', '¿Qué horma y qué punta tiene el Sueco cucarrón?', $j$[{"id": "a", "text": "Horma cómoda, punta redonda"}, {"id": "b", "text": "Horma normal, punta puntuda"}, {"id": "c", "text": "Horma cómoda, punta cuadrada"}]$j$::jsonb, $j${"choice": "a"}$j$::jsonb, 'Así lo dice su ficha validada.', '[FICHA v1 · 2026-10-08]', 'SUECO-CUCARRON');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'B-SUECO-TALLA', '3.2', ARRAY['practica', 'examen'], 'producto', 'opcion', 'Una clienta que normalmente usa 37 quiere el Sueco cucarrón. En general, ¿qué le recomiendas?', $j$[{"id": "a", "text": "Su talla habitual"}, {"id": "b", "text": "Una talla más que su talla habitual"}, {"id": "c", "text": "Una talla menos que su talla habitual"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Su ficha es "Talla chica": "Te recomendamos pedir una talla mas".', '[FICHA v1 · 2026-10-08]', 'SUECO-CUCARRON');
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A07', '3.1', ARRAY['practica', 'examen'], 'tallas', 'opcion', '¿En qué tallas vienen las Ballerinas de este curso?', $j$[{"id": "a", "text": "22 a 27"}, {"id": "b", "text": "35 a 40"}, {"id": "c", "text": "5 a 10"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Vienen del 35 al 40.', '[CATÁLOGO]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A09', '3.1', ARRAY['practica'], 'tallas', 'opcion', 'Una clienta dice que en otra marca usa "talla 7". ¿Qué haces?', $j$[{"id": "a", "text": "Le conviertes la talla de memoria"}, {"id": "b", "text": "Le preguntas su talla en escala 35–40 o le pruebas el modelo"}, {"id": "c", "text": "Le das la 37 porque es la más común"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'No hacemos conversiones de memoria. Preguntamos o probamos.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A10', NULL, ARRAY['examen'], 'tallas', 'vf', 'Las Ballerinas de este curso tienen medias tallas, por ejemplo 37.5.', $j$[]$j$::jsonb, $j${"value": false}$j$::jsonb, 'Vienen en tallas enteras del 35 al 40.', '[CATÁLOGO]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A11', '3.2', ARRAY['practica', 'examen'], 'tallas', 'opcion', 'Un modelo dice "Talla exacta". ¿Qué le recomiendas a la clienta?', $j$[{"id": "a", "text": "Una talla más"}, {"id": "b", "text": "Su talla habitual"}, {"id": "c", "text": "Una talla menos"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, '"Talla exacta" = pedir la talla habitual.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A12', '3.2', ARRAY['practica', 'examen'], 'tallas', 'opcion', 'La ficha dice "¿Entre dos tallas? Elige la mayor." Una clienta duda entre 37 y 38. ¿Cuál le sugieres probar primero?', $j$[{"id": "a", "text": "37"}, {"id": "b", "text": "38"}, {"id": "c", "text": "Cualquiera"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'La ficha de ese modelo indica la mayor.', '[SISTEMA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A17', '3.3', ARRAY['practica'], 'tallas', 'ordenar', 'Ordena los pasos.', $j$[{"id": "1", "text": "Le preguntas su talla habitual"}, {"id": "2", "text": "Revisas en la ficha el ajuste del modelo"}, {"id": "3", "text": "Revisas que esa talla esté en inventario"}, {"id": "4", "text": "Le das a probar"}]$j$::jsonb, $j${"order": ["1", "2", "3", "4"]}$j$::jsonb, 'Primero preguntar, luego ficha, luego inventario y al final probar.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A19', '3.3', ARRAY['practica'], 'tallas', 'vf', 'Si el par le aprieta un poco, le digo que "se va a aflojar" para cerrar la venta.', $j$[]$j$::jsonb, $j${"value": false}$j$::jsonb, 'No prometemos ajustes que la ficha no dice. Si queda justo, se prueba otra talla o modelo.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A25', '5.1', ARRAY['practica', 'examen'], 'atencion', 'opcion', '¿Cuál pregunta te ayuda más a recomendar bien?', $j$[{"id": "a", "text": "\"¿Te gustan?\""}, {"id": "b", "text": "\"¿Para qué ocasión o uso los buscas?\""}, {"id": "c", "text": "\"¿Vienes por la promoción?\""}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'El uso y la ocasión guían la recomendación.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A26', '5.1', ARRAY['practica'], 'atencion', 'varias', 'Elige las 3 preguntas de descubrimiento recomendadas.', $j$[{"id": "uso", "text": "Uso u ocasión"}, {"id": "talla", "text": "Talla habitual"}, {"id": "sentir", "text": "Cómo prefiere sentir el zapato"}, {"id": "ingreso", "text": "Cuánto gana al mes"}]$j$::jsonb, $j${"choices": ["sentir", "talla", "uso"]}$j$::jsonb, 'Uso, talla y cómo le gusta sentir el zapato. Cuánto gana no se pregunta.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A29', '5.2', ARRAY['practica', 'examen'], 'atencion', 'opcion', '¿Cuántas opciones conviene presentar al inicio?', $j$[{"id": "a", "text": "Una"}, {"id": "b", "text": "Dos o tres, elegidas por lo que te dijo"}, {"id": "c", "text": "Todas las del catálogo"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Menos opciones, mejor elegidas, facilitan decidir.', '[PEDAGOGÍA]', NULL);
  INSERT INTO f360_academy.items (course_version_id, key, lesson_key, uses, area, kind, prompt, options, answer, explanation, source, product_code) VALUES (v, 'A30', '5.2', ARRAY['practica'], 'atencion', 'opcion', '¿Cómo presentas un modelo?', $j$[{"id": "a", "text": "\"Está muy bonito\""}, {"id": "b", "text": "Conectas un dato de la ficha con lo que ella pidió"}, {"id": "c", "text": "\"Es el más vendido\" (sin saberlo)"}]$j$::jsonb, $j${"choice": "b"}$j$::jsonb, 'Dato validado + necesidad de la clienta.', '[PEDAGOGÍA]', NULL);
  -- First-entry welcome video (Mario 2026-10-11: "Bienvenida a Fuxia Academy", para vendedoras). DRAFT until Carolina publishes it.
  IF NOT EXISTS (SELECT 1 FROM f360_academy.courses WHERE key = 'bienvenida-academy') THEN
    INSERT INTO f360_academy.courses (school, key, title, kind, sort, created_by_name)
    VALUES ('sales', 'bienvenida-academy', 'Bienvenida a Fuxia Academy', 'bienvenida', 0, 'migración 20261030000300') RETURNING id INTO c;
    INSERT INTO f360_academy.course_versions (course_id, version, title, summary, created_by_name)
    VALUES (c, 1, 'Bienvenida a Fuxia Academy', 'Video de 60 s que ve cada vendedora la primera vez que entra.', 'migración 20261030000300') RETURNING id INTO v;
    INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks, product_codes) VALUES (v, '0.1', 1, 'Bienvenida a Fuxia Academy', 1,
      $j$[{"type": "video", "src": "/academy/bienvenida-720.mp4", "poster": "/academy/bienvenida-poster.jpg", "sha256": "586603c1b17c5430bd73242f7004a7297df31e23925b859bf4939233e8edabdf", "text": "Bienvenida a Fuxia Academy", "source": "[VIDEO BIENVENIDA · guion tools/video/academy/GUION_BIENVENIDA.md]"}]$j$::jsonb, '{}');
  END IF;
END $$;$m$]);
-- >>> 20261030000400_f360_academy_open_sellers
-- Fuxia Academy · abre Sales Academy a las vendedoras reales (Mario 2026-10-13: "si sale", después de cerrar P0-6 en producción:
-- whatsapp-otp v77 + rotación de contraseñas, ver docs/fuxia360/security/D12_CIERRE_Y_P0-6_PRODUCCION.md).
-- Solo levanta la compuerta de acceso: una vendedora activa (f360.sellers.status = 'activa') ve los cursos PUBLICADOS.
-- Certificados, puntos y canjes siguen bloqueados por sus CHECK. Ningún curso se publica aquí: lo publica Carolina (2FA).
-- Rollback: supabase/rollbacks/20261030000400_f360_academy_open_sellers.down.sql
ALTER TABLE f360_academy.settings DROP CONSTRAINT a1_no_real_learners;
UPDATE f360_academy.settings
   SET learner_access_enabled = true,
       note = 'Vendedoras reales con acceso desde 2026-10-13 (P0-6 cerrado en producción). Certificados, puntos y canjes: bloqueados.'
 WHERE id;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261030000400', 'f360_academy_open_sellers', ARRAY[$m$-- Fuxia Academy · abre Sales Academy a las vendedoras reales (Mario 2026-10-13: "si sale", después de cerrar P0-6 en producción:
-- whatsapp-otp v77 + rotación de contraseñas, ver docs/fuxia360/security/D12_CIERRE_Y_P0-6_PRODUCCION.md).
-- Solo levanta la compuerta de acceso: una vendedora activa (f360.sellers.status = 'activa') ve los cursos PUBLICADOS.
-- Certificados, puntos y canjes siguen bloqueados por sus CHECK. Ningún curso se publica aquí: lo publica Carolina (2FA).
-- Rollback: supabase/rollbacks/20261030000400_f360_academy_open_sellers.down.sql
ALTER TABLE f360_academy.settings DROP CONSTRAINT a1_no_real_learners;
UPDATE f360_academy.settings
   SET learner_access_enabled = true,
       note = 'Vendedoras reales con acceso desde 2026-10-13 (P0-6 cerrado en producción). Certificados, puntos y canjes: bloqueados.'
 WHERE id;$m$]);
-- >>> permisos de Academy (cuentas reales por su rol de dueña)
DO $$
DECLARE caro uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner' AND display_name = 'Carolina');
        mario uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'owner' AND display_name = 'Mario Silva');
BEGIN
  INSERT INTO f360_academy.grants (auth_user_id, role, display_name, granted_by_name, evidence) VALUES
    (caro,  'editor', 'Carolina', 'Mario (2026-10-13)', 'Academy en producción: autoridad de contenido'),
    (mario, 'admin',  'Mario',    'Mario (2026-10-13)', 'Academy en producción'),
    (mario, 'editor', 'Mario',    'Mario (2026-10-13)', 'Academy en producción');
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name, note) VALUES
    ('academy_content', caro,  'Carolina', 'Mario (2026-10-13)', 'Autoridad de contenido de producto'),
    ('academy_content', mario, 'Mario',    'Mario (2026-10-13)', 'Segunda persona para políticas y retiros');
  INSERT INTO f360.approval_scope_operations (scope, auth_user_id, operation, added_by_name) VALUES
    ('academy_content', caro,  'publish_sales',        'Mario (2026-10-13)'),
    ('academy_content', caro,  'publish_sales_policy', 'Mario (2026-10-13)'),
    ('academy_content', caro,  'retire',               'Mario (2026-10-13)'),
    ('academy_content', mario, 'publish_sales_policy', 'Mario (2026-10-13)'),
    ('academy_content', mario, 'retire',               'Mario (2026-10-13)');
END $$;
DO $$ BEGIN
  IF NOT (SELECT learner_access_enabled AND NOT certificates_enabled AND NOT points_enabled AND NOT redemptions_enabled FROM f360_academy.settings WHERE id)
    THEN RAISE EXCEPTION 'ACADEMY POST: compuertas inesperadas'; END IF;
  IF (SELECT count(*) FROM f360_academy.grants) <> 3 OR (SELECT count(*) FROM f360.approval_scopes WHERE scope = 'academy_content') <> 2
     OR (SELECT count(*) FROM f360.approval_scope_operations WHERE scope = 'academy_content') <> 5 THEN RAISE EXCEPTION 'ACADEMY POST: permisos inesperados'; END IF;
  IF EXISTS (SELECT 1 FROM f360_academy.course_versions WHERE status = 'publicado') THEN RAISE EXCEPTION 'ACADEMY POST: hay un curso publicado'; END IF;
END $$;
COMMIT;
