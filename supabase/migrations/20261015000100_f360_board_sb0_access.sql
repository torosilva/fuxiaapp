-- Fuxia 360 · Strategy & Board · SB0.1 — ACCESS FOUNDATION (Mario 2026-10-08, decisions D10/D10B/D11/D12/D13).
-- Spec: docs/fuxia360/strategy-board/01_ACCESS_MODEL.md, 13_DATA_MODEL.md §0–1, 14_SECURITY_MODEL.md §3.
-- ADDITIVE: new schema f360_board + public.f360_board_* RPCs. Nothing in f360/public is changed by this file.
--
-- Who gets in: an EXPLICIT PERSON ALLOWLIST (f360_board.board_members, keyed by auth.users.id), AND the person must still be
-- f360.user_roles.role = 'owner' (defence in depth). NOT the generic owner role alone (staging has a technical owner,
-- Adrián, who must not see the Board), never display_name / user_metadata / app_metadata / customers.role / phone.
-- Membership rows are NOT inserted by this migration: they are environment-specific auth ids, inserted by a separate,
-- reviewed script by verified id (staging: supabase/staging/sb0_board_members_staging.sql; production: approved pase).
--
-- Denials are LOGGED AND KEPT: a RAISE would roll back its own log row (lesson of 20261001000200_f360_s02_persist_denials),
-- so the gate RETURNS NULL on denial after writing the log, and every public RPC answers {ok:false,"No disponible."}
-- without data. Successful access ('allowed') and sensitive writes ('write') are logged in the same append-only table.
-- Rollback: supabase/rollbacks/20261015000100_f360_board_sb0_access.down.sql

CREATE SCHEMA f360_board;
REVOKE ALL ON SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
-- Nobody but the database owner touches f360_board directly; clients only reach SECURITY DEFINER public.f360_board_* RPCs.

-- ══ 1 · Allowlist ════════════════════════════════════════════════════════════
CREATE FUNCTION f360_board.valid_scopes() RETURNS text[] LANGUAGE sql IMMUTABLE AS
$$ SELECT ARRAY['OPERATIONAL', 'FINANCIAL', 'BOARD', 'CAP_TABLE', 'VALUATION', 'INVESTOR_ROOM']::text[] $$;

CREATE TABLE f360_board.board_members (
  auth_user_id     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  person_key       text UNIQUE CHECK (person_key ~ '^[A-Z][A-Z_]*$'),  -- stable governance identity (e.g. MARIO) for conflict-of-interest rules; set only by reviewed script
  display_name     text NOT NULL,                                        -- label only; NEVER used for authorization
  scopes           text[] NOT NULL CHECK (cardinality(scopes) > 0 AND scopes <@ f360_board.valid_scopes()),
  active           boolean NOT NULL DEFAULT true,
  granted_at       timestamptz NOT NULL DEFAULT now(),
  granted_by_name  text NOT NULL,
  evidence         text NOT NULL,                                        -- how the auth id was verified (audit)
  note             text
);
ALTER TABLE f360_board.board_members ENABLE ROW LEVEL SECURITY;

CREATE TABLE f360_board.board_member_changes (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  auth_user_id  uuid NOT NULL,
  action        text NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  before        jsonb,
  after         jsonb,
  db_user       text NOT NULL DEFAULT current_user,
  jwt_sub       uuid
);
ALTER TABLE f360_board.board_member_changes ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER board_member_changes_append_only BEFORE UPDATE OR DELETE ON f360_board.board_member_changes
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE FUNCTION f360_board.on_member_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO f360_board.board_member_changes (auth_user_id, action, before, after, jwt_sub)
    VALUES (coalesce(NEW.auth_user_id, OLD.auth_user_id), TG_OP,
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END, CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END, auth.uid());
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER board_members_audit AFTER INSERT OR UPDATE OR DELETE ON f360_board.board_members
  FOR EACH ROW EXECUTE FUNCTION f360_board.on_member_change();

-- ══ 2 · Module settings (singleton; changed only by reviewed migration; every change audited) ══
CREATE TABLE f360_board.settings (
  id                              boolean PRIMARY KEY DEFAULT true CHECK (id),
  require_aal2                    boolean NOT NULL DEFAULT false,  -- D2 (MFA) pending: when true the gate demands an aal2 JWT
  close_requires_second_member    boolean NOT NULL DEFAULT true,   -- D5 default: the member who closes ≠ the one who sent to review
  decision_requires_other_member  boolean NOT NULL DEFAULT true,   -- D5 default: a decision is approved by a member other than its proposer
  fiscal_year_start_month         int NOT NULL DEFAULT 1 CHECK (fiscal_year_start_month = 1),  -- D11: Jan 1 → Dec 31 (only value supported)
  timezone                        text NOT NULL DEFAULT 'America/Mexico_City' CHECK (timezone = 'America/Mexico_City'),
  updated_at                      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE f360_board.settings ENABLE ROW LEVEL SECURITY;
INSERT INTO f360_board.settings DEFAULT VALUES;

CREATE TABLE f360_board.settings_changes (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  before    jsonb, after jsonb,
  db_user   text NOT NULL DEFAULT current_user
);
ALTER TABLE f360_board.settings_changes ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER settings_changes_append_only BEFORE UPDATE OR DELETE ON f360_board.settings_changes
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE FUNCTION f360_board.on_settings_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'La configuración del consejo no se borra.'; END IF;
  INSERT INTO f360_board.settings_changes (before, after) VALUES (to_jsonb(OLD), to_jsonb(NEW));
  RETURN NEW;
END $$;
CREATE TRIGGER settings_audit BEFORE UPDATE OR DELETE ON f360_board.settings FOR EACH ROW EXECUTE FUNCTION f360_board.on_settings_change();

-- ══ 3 · Access log (allowed / denied / write) — append-only ══════════════════
CREATE TABLE f360_board.access_log (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  auth_user_id  uuid,                               -- may be a non-member (denied attempts); NULL = no session
  rpc           text NOT NULL,
  scope         text NOT NULL,
  outcome       text NOT NULL CHECK (outcome IN ('allowed', 'denied', 'write')),
  reason        text,                               -- denied: no_session | not_member | inactive | missing_scope | not_owner | mfa_required
  object_ref    text,                               -- id of the object read/written, never its content
  params_hash   text,                               -- sha256 of the parameters, never the values
  request_id    text,
  actor_kind    text NOT NULL DEFAULT 'human' CHECK (actor_kind IN ('human', 'ai_analyst'))
);
ALTER TABLE f360_board.access_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX access_log_at_idx ON f360_board.access_log (at DESC);
CREATE TRIGGER access_log_append_only BEFORE UPDATE OR DELETE ON f360_board.access_log
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE FUNCTION f360_board.request_id() RETURNS text
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE h text := current_setting('request.headers', true);
BEGIN
  IF h IS NULL OR h = '' THEN RETURN NULL; END IF;
  RETURN left(coalesce(h::jsonb->>'x-request-id', h::jsonb->>'cf-ray'), 120);
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;

CREATE FUNCTION f360_board.params_hash(p jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, pg_temp AS
$$ SELECT CASE WHEN p IS NULL THEN NULL ELSE encode(extensions.digest(p::text, 'sha256'), 'hex') END $$;

-- Pure membership check for the CALLER (no logging). NULL = authorized; otherwise the denial reason.
-- 'ANY' = any active member (used by f360_board_me / nav); otherwise the scope must be granted.
CREATE FUNCTION f360_board.member_denial(p_uid uuid, p_scope text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE m f360_board.board_members; s f360_board.settings;
BEGIN
  IF p_uid IS NULL THEN RETURN 'no_session'; END IF;
  SELECT * INTO m FROM f360_board.board_members WHERE auth_user_id = p_uid;
  IF m.auth_user_id IS NULL THEN RETURN 'not_member'; END IF;
  IF NOT m.active THEN RETURN 'inactive'; END IF;
  IF p_scope <> 'ANY' AND NOT (p_scope = ANY (m.scopes)) THEN RETURN 'missing_scope'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = p_uid AND r.role = 'owner') THEN RETURN 'not_owner'; END IF;
  SELECT * INTO s FROM f360_board.settings WHERE id;
  IF coalesce(s.require_aal2, false) AND coalesce(auth.jwt()->>'aal', '') <> 'aal2' THEN RETURN 'mfa_required'; END IF;
  RETURN NULL;
END $$;

-- THE GATE. First statement of every public.f360_board_* RPC. Identity = auth.uid() from the verified JWT only.
-- Returns the member's uid, or NULL after logging the denial (the caller then returns f360_board.denied()).
CREATE FUNCTION f360_board.require_board_member(p_scope text, p_rpc text, p_object_ref text DEFAULT NULL, p_params jsonb DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); why text;
BEGIN
  IF p_scope IS NULL OR NOT (p_scope = 'ANY' OR p_scope = ANY (f360_board.valid_scopes())) OR coalesce(p_rpc, '') = '' THEN
    RAISE EXCEPTION 'f360_board gate misuse';   -- programming error, never a user path
  END IF;
  why := f360_board.member_denial(uid, p_scope);
  INSERT INTO f360_board.access_log (auth_user_id, rpc, scope, outcome, reason, object_ref, params_hash, request_id)
    VALUES (uid, p_rpc, p_scope, CASE WHEN why IS NULL THEN 'allowed' ELSE 'denied' END, why, left(p_object_ref, 200),
            f360_board.params_hash(p_params), f360_board.request_id());
  RETURN CASE WHEN why IS NULL THEN uid END;
END $$;

-- Sensitive business write (after the write succeeded, same transaction).
CREATE FUNCTION f360_board.log_write(p_uid uuid, p_scope text, p_rpc text, p_object_ref text, p_params jsonb DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  INSERT INTO f360_board.access_log (auth_user_id, rpc, scope, outcome, object_ref, params_hash, request_id)
  VALUES (p_uid, p_rpc, p_scope, 'write', left(p_object_ref, 200), f360_board.params_hash(p_params), f360_board.request_id())
$$;

-- Generic answer to any denied call: reveals nothing (not even that the module exists).
CREATE FUNCTION f360_board.denied() RETURNS jsonb LANGUAGE sql IMMUTABLE AS
$$ SELECT jsonb_build_object('ok', false, 'error', 'No disponible.') $$;

CREATE FUNCTION f360_board.member_name(p_uid uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT display_name FROM f360_board.board_members WHERE auth_user_id = p_uid),
                  (SELECT display_name FROM f360.user_roles WHERE auth_user_id = p_uid), 'Sin nombre')
$$;

-- ══ 4 · Public RPCs ══════════════════════════════════════════════════════════
-- Who am I in the Board (any active member). Also lists the members (id + label) for conflict-of-interest workflows.
CREATE FUNCTION public.f360_board_me() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('ANY', 'f360_board_me'); m f360_board.board_members; s f360_board.settings;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO m FROM f360_board.board_members WHERE auth_user_id = uid;
  SELECT * INTO s FROM f360_board.settings WHERE id;
  RETURN jsonb_build_object('ok', true,
    'me', jsonb_build_object('auth_user_id', m.auth_user_id, 'display_name', m.display_name, 'scopes', to_jsonb(m.scopes), 'person_key', m.person_key),
    'members', (SELECT jsonb_agg(jsonb_build_object('auth_user_id', b.auth_user_id, 'display_name', b.display_name, 'person_key', b.person_key) ORDER BY b.display_name)
                FROM f360_board.board_members b WHERE b.active),
    'settings', jsonb_build_object('require_aal2', s.require_aal2, 'close_requires_second_member', s.close_requires_second_member,
                                   'decision_requires_other_member', s.decision_requires_other_member,
                                   'fiscal_year', 'calendar (Jan 1 → Dec 31)', 'timezone', s.timezone));
END $$;

-- Navigation hint ONLY: is the caller an active member? Returns a boolean about the caller, no data, not logged (it is
-- rendered on every page; the real check is f360_board_me + the gate on every Board RPC).
CREATE FUNCTION public.f360_board_nav_visible() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_board.member_denial(auth.uid(), 'ANY') IS NULL
$$;

-- Access log for the members (who, when, what RPC, allowed/denied/write). Labels only; no e-mails, no parameters.
CREATE FUNCTION public.f360_board_access_log(p_days int DEFAULT 30) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE d int := greatest(1, least(coalesce(p_days, 30), 365));
  uid uuid := f360_board.require_board_member('BOARD', 'f360_board_access_log', NULL, jsonb_build_object('days', d));
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'days', d,
    'summary', (SELECT jsonb_build_object(
        'allowed', count(*) FILTER (WHERE outcome = 'allowed'), 'denied', count(*) FILTER (WHERE outcome = 'denied'),
        'writes', count(*) FILTER (WHERE outcome = 'write'),
        'denied_non_members', count(*) FILTER (WHERE outcome = 'denied' AND NOT EXISTS (SELECT 1 FROM f360_board.board_members b WHERE b.auth_user_id = l.auth_user_id))
      ) FROM f360_board.access_log l WHERE l.at > now() - make_interval(days => d)),
    'rows', coalesce((SELECT jsonb_agg(x ORDER BY (x->>'id')::bigint DESC) FROM (
        SELECT jsonb_build_object('id', l.id, 'at', l.at, 'who', CASE WHEN l.auth_user_id IS NULL THEN 'Sin sesión' ELSE f360_board.member_name(l.auth_user_id) END,
                 'member', EXISTS (SELECT 1 FROM f360_board.board_members b WHERE b.auth_user_id = l.auth_user_id),
                 'rpc', l.rpc, 'scope', l.scope, 'outcome', l.outcome, 'reason', l.reason, 'object_ref', l.object_ref) x
        FROM f360_board.access_log l WHERE l.at > now() - make_interval(days => d) ORDER BY l.id DESC LIMIT 200) q), '[]'::jsonb));
END $$;

-- ══ 5 · Grants ═══════════════════════════════════════════════════════════════
REVOKE ALL ON ALL TABLES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_board_me(), public.f360_board_nav_visible(), public.f360_board_access_log(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_me(), public.f360_board_nav_visible(), public.f360_board_access_log(int) TO authenticated;
