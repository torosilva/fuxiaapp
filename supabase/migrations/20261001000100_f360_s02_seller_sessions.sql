-- Fuxia 360 · S0.2 — Authenticated seller session, built ON Track C · C1 (roles + location_assignments). STAGING.
-- The server derives EVERYTHING: identity = auth.uid(); role = f360.user_roles; authorized locations =
-- f360.location_assignments; active shift location = the session. Never staff.channel_id, customers.role, phone,
-- user_metadata, a public/legacy PIN, or a location sent by the client.
--
--   f360.seller_credentials   PIN hash (bcrypt via pgcrypto) + failure counters. The PIN is never stored or returned.
--   f360.seller_sessions      one active shift per person: token HASH, location, absolute + idle expiry, revocation
--   f360.seller_auth_events   append-only: every attempt/lock/unlock/PIN set/shift start-end/revocation (person + location)
--   f360.seller_params()      the security parameters — RECOMMENDED values, pending approval (docs/fuxia360/ops/S0_2_SELLER_SESSION.md)
--   f360.require_seller_session(token, location_claim)  what every future OPERATE call uses (C3 sale, transfers, receipts)
-- READ stays role-based (a seller reads stock of every location); OPERATE needs a valid session at an ASSIGNED location.
-- Rollback: supabase/rollbacks/20261001000100_f360_s02_seller_sessions.down.sql

CREATE FUNCTION f360.seller_params() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'pin_length', 4,                    -- Q2 (approved)
    'max_consecutive_failures', 5,      -- RECOMMENDED: then a temporary lock
    'lock_minutes', 15,                 -- RECOMMENDED: temporary lock length
    'hard_lock_failures_24h', 10,       -- RECOMMENDED: then locked until an owner/operator unlocks
    'session_hours', 12,                -- RECOMMENDED: absolute shift length
    'idle_minutes', 120                 -- RECOMMENDED: inactivity expiry
  )
$$;

CREATE TABLE f360.seller_credentials (
  auth_user_id     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  pin_hash         text NOT NULL CHECK (pin_hash LIKE '$2%'),     -- bcrypt only; never plaintext
  pin_set_at       timestamptz NOT NULL DEFAULT now(),
  pin_set_by_name  text NOT NULL,
  failed_attempts  integer NOT NULL DEFAULT 0,
  locked_until     timestamptz,
  hard_locked      boolean NOT NULL DEFAULT false
);

CREATE TABLE f360.seller_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  location_id   uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  token_hash    text NOT NULL UNIQUE,                               -- sha256 of the token; the token itself is never stored
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  revoked_at    timestamptz,
  revoke_reason text
);
CREATE UNIQUE INDEX seller_sessions_one_active ON f360.seller_sessions (auth_user_id) WHERE revoked_at IS NULL;
CREATE INDEX seller_sessions_location_idx ON f360.seller_sessions (location_id) WHERE revoked_at IS NULL;

CREATE TABLE f360.seller_auth_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  auth_user_id  uuid,                  -- no FK: audit survives the removal of synthetic fixtures / users
  person_name   text,
  location_id   uuid,
  location_name text,
  event         text NOT NULL,         -- shift_start | bad_pin | locked | hard_locked | blocked_locked | not_assigned | not_seller
                                       -- | no_pin | pin_set | unlock | shift_end | revoked | location_mismatch | expired
  detail        jsonb,
  at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX seller_auth_events_user_idx ON f360.seller_auth_events (auth_user_id, at DESC);
CREATE TRIGGER seller_auth_events_append_only BEFORE UPDATE OR DELETE ON f360.seller_auth_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE FUNCTION f360.log_seller(p_user uuid, p_location uuid, p_event text, p_detail jsonb DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
  INSERT INTO f360.seller_auth_events (auth_user_id, person_name, location_id, location_name, event, detail)
  VALUES (p_user, (SELECT display_name FROM f360.user_roles WHERE auth_user_id = p_user), p_location,
          (SELECT name FROM f360.locations WHERE id = p_location), p_event, p_detail)
$$;

CREATE FUNCTION f360.token_hash(p_token text) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT encode(extensions.digest(p_token, 'sha256'), 'hex') $$;

-- Revokes active sessions (all of a person, or only at one location). Used on role/assignment changes.
CREATE FUNCTION f360.revoke_seller_sessions(p_user uuid, p_location uuid, p_reason text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  WITH r AS (
    UPDATE f360.seller_sessions SET revoked_at = now(), revoke_reason = p_reason
    WHERE auth_user_id = p_user AND revoked_at IS NULL AND (p_location IS NULL OR location_id = p_location) RETURNING location_id)
  SELECT count(*) INTO n FROM r;
  IF n > 0 THEN PERFORM f360.log_seller(p_user, p_location, 'revoked', jsonb_build_object('reason', p_reason, 'sessions', n)); END IF;
  RETURN n;
END $$;

-- ── The OPERATE gate for every future seller operation ──────────────────────
-- Re-checks LIVE state on every call (so a revocation is effective immediately even without the session being
-- revoked): session belongs to the caller, not revoked/expired/idle, role still allows operating, assignment still
-- active, location still active + sellable. A client-sent location must equal the session's; otherwise refused.
CREATE FUNCTION f360.require_seller_session(p_token text, p_location_claim uuid DEFAULT NULL) RETURNS f360.seller_sessions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; r f360.user_roles; prm jsonb := f360.seller_params(); uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Inicia sesión con tu cuenta.' USING ERRCODE = 'insufficient_privilege'; END IF;
  SELECT * INTO s FROM f360.seller_sessions WHERE token_hash = f360.token_hash(coalesce(p_token, '')) FOR UPDATE;
  IF s.id IS NULL OR s.auth_user_id <> uid THEN RAISE EXCEPTION 'Tu turno no es válido. Vuelve a iniciar turno.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF s.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'Tu turno terminó (%). Vuelve a iniciar turno.', coalesce(s.revoke_reason, 'cerrado') USING ERRCODE = 'insufficient_privilege'; END IF;
  IF s.expires_at <= now() OR s.last_seen_at + make_interval(mins => (prm->>'idle_minutes')::int) <= now() THEN
    UPDATE f360.seller_sessions SET revoked_at = now(), revoke_reason = 'vencido' WHERE id = s.id;
    PERFORM f360.log_seller(uid, s.location_id, 'expired', NULL);
    RAISE EXCEPTION 'Tu turno venció. Vuelve a iniciar turno con tu PIN.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO r FROM f360.user_roles WHERE auth_user_id = uid;
  IF r.role IS NULL OR r.role NOT IN ('seller', 'operator', 'owner')
     OR (r.role = 'seller' AND NOT EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = uid AND a.location_id = s.location_id AND a.active))
     OR NOT EXISTS (SELECT 1 FROM f360.locations l WHERE l.id = s.location_id AND l.status = 'active' AND l.sellable) THEN
    UPDATE f360.seller_sessions SET revoked_at = now(), revoke_reason = 'acceso retirado' WHERE id = s.id;
    PERFORM f360.log_seller(uid, s.location_id, 'revoked', jsonb_build_object('reason', 'acceso retirado'));
    RAISE EXCEPTION 'Ya no tienes acceso a esta ubicación.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_location_claim IS NOT NULL AND p_location_claim <> s.location_id THEN
    PERFORM f360.log_seller(uid, s.location_id, 'location_mismatch', jsonb_build_object('claimed', p_location_claim));
    RAISE EXCEPTION 'Esa ubicación no es la de tu turno.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE f360.seller_sessions SET last_seen_at = now() WHERE id = s.id RETURNING * INTO s;
  RETURN s;
END $$;

-- ── Owner/operator: set or reset a PIN (shown once by the caller's UI, never retrievable), unlock ──
CREATE FUNCTION public.f360_set_seller_pin(p_auth_user_id uuid, p_pin text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; prm jsonb := f360.seller_params();
BEGIN
  r := f360.require_role('owner');
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_auth_user_id AND role IN ('seller', 'operator', 'owner')) THEN
    RAISE EXCEPTION 'Esa persona no tiene un rol que pueda iniciar turno.';
  END IF;
  IF p_pin IS NULL OR p_pin !~ ('^[0-9]{' || (prm->>'pin_length') || '}$') THEN RAISE EXCEPTION 'El PIN debe tener % dígitos.', prm->>'pin_length'; END IF;
  INSERT INTO f360.seller_credentials (auth_user_id, pin_hash, pin_set_by_name) VALUES (p_auth_user_id, extensions.crypt(p_pin, extensions.gen_salt('bf', 10)), r.display_name)
    ON CONFLICT (auth_user_id) DO UPDATE SET pin_hash = EXCLUDED.pin_hash, pin_set_at = now(), pin_set_by_name = EXCLUDED.pin_set_by_name,
      failed_attempts = 0, locked_until = NULL, hard_locked = false;
  PERFORM f360.revoke_seller_sessions(p_auth_user_id, NULL, 'PIN cambiado');
  PERFORM f360.log_seller(p_auth_user_id, NULL, 'pin_set', jsonb_build_object('by', r.display_name));
  RETURN jsonb_build_object('ok', true);   -- never the PIN, never the hash
END $$;

CREATE FUNCTION public.f360_unlock_seller(p_auth_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('operator');
  UPDATE f360.seller_credentials SET failed_attempts = 0, locked_until = NULL, hard_locked = false WHERE auth_user_id = p_auth_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Esa persona no tiene PIN.'; END IF;
  PERFORM f360.log_seller(p_auth_user_id, NULL, 'unlock', jsonb_build_object('by', r.display_name));
  RETURN jsonb_build_object('ok', true);
END $$;

-- ── The seller: start / check / end a shift ─────────────────────────────────
CREATE FUNCTION public.f360_start_seller_shift(p_location_id uuid, p_pin text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); r f360.user_roles; c f360.seller_credentials; l f360.locations; prm jsonb := f360.seller_params();
  fails24 int; token text; sess f360.seller_sessions;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Inicia sesión con tu cuenta para iniciar turno.' USING ERRCODE = 'insufficient_privilege'; END IF;
  SELECT * INTO r FROM f360.user_roles WHERE auth_user_id = uid;
  IF r.role IS NULL OR r.role NOT IN ('seller', 'operator', 'owner') THEN
    PERFORM f360.log_seller(uid, p_location_id, 'not_seller', NULL);
    RAISE EXCEPTION 'Esta cuenta no puede iniciar turno de venta.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO l FROM f360.locations WHERE id = p_location_id AND status = 'active' AND sellable;
  IF l.id IS NULL OR (r.role = 'seller' AND NOT EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = uid AND a.location_id = p_location_id AND a.active)) THEN
    PERFORM f360.log_seller(uid, p_location_id, 'not_assigned', NULL);   -- checked BEFORE the PIN: no attempt consumed, nothing learned
    RAISE EXCEPTION 'No tienes asignada esa ubicación.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO c FROM f360.seller_credentials WHERE auth_user_id = uid FOR UPDATE;
  IF c.auth_user_id IS NULL THEN
    PERFORM f360.log_seller(uid, p_location_id, 'no_pin', NULL);
    RAISE EXCEPTION 'Todavía no tienes PIN. Pídele a Carolina o Mario que te lo asignen.';
  END IF;
  IF c.hard_locked OR (c.locked_until IS NOT NULL AND c.locked_until > now()) THEN
    PERFORM f360.log_seller(uid, p_location_id, 'blocked_locked', jsonb_build_object('until', c.locked_until, 'hard', c.hard_locked));
    RAISE EXCEPTION '%', CASE WHEN c.hard_locked THEN 'Tu PIN está bloqueado. Pide que lo desbloqueen.'
                              ELSE format('Demasiados intentos. Intenta de nuevo en %s minutos.', ceil(extract(epoch FROM c.locked_until - now()) / 60)) END
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_pin IS NULL OR extensions.crypt(p_pin, c.pin_hash) <> c.pin_hash THEN
    SELECT count(*) + 1 INTO fails24 FROM f360.seller_auth_events WHERE auth_user_id = uid AND event = 'bad_pin' AND at > now() - interval '24 hours';
    UPDATE f360.seller_credentials SET failed_attempts = failed_attempts + 1,
      locked_until = CASE WHEN failed_attempts + 1 >= (prm->>'max_consecutive_failures')::int THEN now() + make_interval(mins => (prm->>'lock_minutes')::int) ELSE locked_until END,
      hard_locked = fails24 >= (prm->>'hard_lock_failures_24h')::int
      WHERE auth_user_id = uid RETURNING * INTO c;
    PERFORM f360.log_seller(uid, p_location_id, 'bad_pin', jsonb_build_object('consecutive', c.failed_attempts, 'last_24h', fails24));
    IF c.hard_locked THEN PERFORM f360.log_seller(uid, p_location_id, 'hard_locked', NULL);
    ELSIF c.locked_until > now() THEN PERFORM f360.log_seller(uid, p_location_id, 'locked', jsonb_build_object('until', c.locked_until)); END IF;
    -- COMMIT the counters and the audit (RETURN, don't RAISE: a RAISE would roll them back)
    RETURN jsonb_build_object('ok', false, 'error', CASE WHEN c.hard_locked THEN 'Tu PIN quedó bloqueado. Pide que lo desbloqueen.'
      WHEN c.locked_until > now() THEN format('PIN incorrecto. Bloqueado por %s minutos.', prm->>'lock_minutes')
      ELSE format('PIN incorrecto. Te quedan %s intentos.', (prm->>'max_consecutive_failures')::int - c.failed_attempts) END);
  END IF;
  UPDATE f360.seller_credentials SET failed_attempts = 0, locked_until = NULL WHERE auth_user_id = uid;
  -- one active shift per person: changing location = closing the previous shift (recommended behavior)
  PERFORM f360.revoke_seller_sessions(uid, NULL, 'nuevo turno');
  token := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO f360.seller_sessions (auth_user_id, location_id, token_hash, expires_at)
    VALUES (uid, l.id, f360.token_hash(token), now() + make_interval(hours => (prm->>'session_hours')::int)) RETURNING * INTO sess;
  PERFORM f360.log_seller(uid, l.id, 'shift_start', jsonb_build_object('session', sess.id));
  RETURN jsonb_build_object('ok', true, 'token', token, 'expires_at', sess.expires_at, 'idle_minutes', (prm->>'idle_minutes')::int,
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'legacy_channel_id', l.legacy_channel_id, 'ledger_authority', l.ledger_authority),
    'person', r.display_name);
END $$;

-- Session status for the app (also the heartbeat). Any location in the request must match the shift.
CREATE FUNCTION public.f360_seller_session(p_token text, p_location_claim uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations;
BEGIN
  s := f360.require_seller_session(p_token, p_location_claim);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  RETURN jsonb_build_object('ok', true, 'person', (SELECT display_name FROM f360.user_roles WHERE auth_user_id = s.auth_user_id),
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'legacy_channel_id', l.legacy_channel_id, 'ledger_authority', l.ledger_authority),
    'expires_at', s.expires_at, 'last_seen_at', s.last_seen_at);
END $$;

CREATE FUNCTION public.f360_end_seller_shift(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions;
BEGIN
  SELECT * INTO s FROM f360.seller_sessions WHERE token_hash = f360.token_hash(coalesce(p_token, '')) AND auth_user_id = auth.uid() AND revoked_at IS NULL;
  IF s.id IS NOT NULL THEN
    UPDATE f360.seller_sessions SET revoked_at = now(), revoke_reason = 'turno cerrado' WHERE id = s.id;
    PERFORM f360.log_seller(s.auth_user_id, s.location_id, 'shift_end', NULL);
  END IF;
  RETURN jsonb_build_object('ok', true);
END $$;

-- ── Immediate revocation hooks on the C1 RPCs ───────────────────────────────
CREATE FUNCTION f360.on_assignment_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT NEW.active THEN PERFORM f360.revoke_seller_sessions(NEW.auth_user_id, NEW.location_id, 'asignación retirada'); END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER location_assignments_revoke_sessions AFTER UPDATE OF active ON f360.location_assignments
  FOR EACH ROW WHEN (OLD.active AND NOT NEW.active) EXECUTE FUNCTION f360.on_assignment_change();

CREATE FUNCTION f360.on_role_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN PERFORM f360.revoke_seller_sessions(OLD.auth_user_id, NULL, 'rol retirado'); RETURN OLD; END IF;
  IF NEW.role NOT IN ('seller', 'operator', 'owner') THEN PERFORM f360.revoke_seller_sessions(NEW.auth_user_id, NULL, 'rol cambiado'); END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER user_roles_revoke_sessions AFTER UPDATE OF role OR DELETE ON f360.user_roles
  FOR EACH ROW EXECUTE FUNCTION f360.on_role_change();

-- Owner/operator view of seller audit
CREATE FUNCTION public.f360_seller_audit(p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('at', at, 'person', person_name, 'location', location_name, 'event', event, 'detail', detail) ORDER BY id DESC), '[]')
    FROM (SELECT * FROM f360.seller_auth_events ORDER BY id DESC LIMIT least(greatest(p_limit, 1), 500)) e);
END $$;

-- ── Grants ──────────────────────────────────────────────────────────────────
REVOKE ALL ON f360.seller_credentials, f360.seller_sessions, f360.seller_auth_events FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.f360_set_seller_pin(uuid, text), public.f360_unlock_seller(uuid), public.f360_start_seller_shift(uuid, text),
  public.f360_seller_session(text, uuid), public.f360_end_seller_shift(text), public.f360_seller_audit(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_set_seller_pin(uuid, text), public.f360_unlock_seller(uuid), public.f360_start_seller_shift(uuid, text),
  public.f360_seller_session(text, uuid), public.f360_end_seller_shift(text), public.f360_seller_audit(integer) TO authenticated, service_role;
