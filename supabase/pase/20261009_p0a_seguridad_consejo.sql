-- Fuxia 360 · pase P0A — Security / Strategy & Board foundation (SB0 + D13 + Board MFA)
-- PREPARED 2026-10-08 by the pre-production gate (docs/fuxia360/PRE_PRODUCTION_GATE_S-G0_SB0.md). NOT RUN. Apply ONLY with
-- scripts/f360/prod_sql.sh after Mario's explicit written approval of THIS gate (it dry-runs with ROLLBACK first).
-- Contents: the committed migrations 20261015000100, 20261015000200, 20261015000300, 20261015000400, 20261016000100 verbatim, in order, each with its schema_migrations row.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE key = 'woo_production' AND is_production) THEN
    RAISE EXCEPTION 'ABORT: this pase is for PRODUCTION only (woo_production target missing)';
  END IF;
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20261015000100', '20261015000200', '20261015000300', '20261015000400', '20261016000100')) THEN
    RAISE EXCEPTION 'ABORT: part of this gate is already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261013000700') THEN RAISE EXCEPTION 'ABORT: prerequisite 20261013000700 missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261010000100') THEN RAISE EXCEPTION 'ABORT: prerequisite 20261010000100 missing'; END IF;
  IF to_regnamespace('f360_board') IS NOT NULL THEN RAISE EXCEPTION 'ABORT: schema f360_board already exists'; END IF;
  IF to_regprocedure('extensions.digest(text, text)') IS NULL THEN RAISE EXCEPTION 'ABORT: pgcrypto (extensions.digest) missing'; END IF;
END $$;

-- ════════ 20261015000100_f360_board_sb0_access.sql ════════
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

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261015000100', 'f360_board_sb0_access', '{}');

-- ════════ 20261015000200_f360_board_sb0_finance_foundation.sql ════════
-- Fuxia 360 · Strategy & Board · SB0.2 — FINANCE FOUNDATION (needs 20261015000100).
-- Spec: 13_DATA_MODEL.md §2–3 & §11, 02_CEO_COCKPIT.md §3, 03_FORECAST_MODEL.md §1. Mario 2026-10-08: D9, D11, monthly close.
-- ADDITIVE, all inside f360_board. What exists after this file:
--   reporting_entities     the management scope 'fuxia' (NOT a legal entity). Legal entities (MX/CO) are supported by the
--                          model but NOT populated (D9 pending). Cali = casa matriz, PENDING BUSINESS CONFIRMATION, not inserted.
--   fiscal_periods         D11 calendar fiscal year (Jan 1 → Dec 31): 12 months + 4 quarters + 1 year per year (2026, 2027 seeded).
--                          Month status OPEN → UNDER_REVIEW → CLOSED → REOPENED → UNDER_REVIEW …; quarter/year roll up.
--   fiscal_period_events   append-only history of every status change (who, when, why, close version).
--   close_accounts         catalog of what a manual close may capture (COGS, OPEX by category, cash, tax). NO amounts.
--                          Marketing spend is NOT here: S-G0 owns marketing spend (single source of truth).
--   monthly_close_entries  manual close amounts with source + evidence + who captured + who approved (≠ capturer).
--                          Correction = void + new (pattern f360.historical_sales); never UPDATE an amount; never DELETE.
--   monthly_close_log      append-only log of every capture / approval / void.
--   close_actual_snapshots frozen photo of the close at each CLOSE (close_version), append-only.
--   metric_catalog         one vocabulary for cockpit/gates/valuation: definition, unit, source, availability TODAY.
--   budget_* / forecast_*  versioned foundation (no data, no write RPCs until SB1/SB2): approved/published versions are
--                          frozen by trigger; publishing a forecast writes an immutable snapshot.
-- Nothing here invents a number: missing sources are reported as DATA_INCOMPLETE. f360.fx_rates and
-- f360.product_cost_versions belong to the S-G0 sprint and are only REFERENCED by name (metric_catalog.depends_on).
-- Rollback: supabase/rollbacks/20261015000200_f360_board_sb0_finance_foundation.down.sql

-- ══ 1 · Reporting entities ═══════════════════════════════════════════════════
CREATE TABLE f360_board.reporting_entities (
  key                  text PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9_]*$'),
  name                 text NOT NULL,
  kind                 text NOT NULL CHECK (kind IN ('MANAGEMENT', 'LEGAL_ENTITY')),
  country              text CHECK (country IN ('MX', 'CO')),
  functional_currency  text NOT NULL REFERENCES f360.currencies(code),
  status               text NOT NULL CHECK (status IN ('ACTIVE', 'PENDING_BUSINESS_CONFIRMATION', 'INACTIVE')),
  note                 text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by_name      text NOT NULL
);
ALTER TABLE f360_board.reporting_entities ENABLE ROW LEVEL SECURITY;
INSERT INTO f360_board.reporting_entities (key, name, kind, country, functional_currency, status, note, created_by_name) VALUES
  ('fuxia', 'Fuxia Ballerinas · gestión (todo lo que opera Fuxia 360)', 'MANAGEMENT', NULL, 'MXN', 'ACTIVE',
   'Alcance de gestión, no entidad legal. Entidades legales MX/CO: pendientes (D9). Cali = casa matriz (suegra de Mario), fuera de Fuxia 360 (D7), PENDING BUSINESS CONFIRMATION — no se registra.',
   'migration 20261015000200');

-- ══ 2 · Fiscal periods (D11: calendar year) ══════════════════════════════════
CREATE TABLE f360_board.fiscal_periods (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key         text NOT NULL REFERENCES f360_board.reporting_entities(key),
  kind               text NOT NULL CHECK (kind IN ('MONTH', 'QUARTER', 'YEAR')),
  fiscal_year        int  NOT NULL CHECK (fiscal_year BETWEEN 2024 AND 2100),
  period_no          int  NOT NULL,
  period_start       date NOT NULL,
  period_end         date NOT NULL,                       -- inclusive
  status             text CHECK (status IN ('OPEN', 'UNDER_REVIEW', 'CLOSED', 'REOPENED')),  -- months only; quarter/year roll up
  close_version      int  NOT NULL DEFAULT 0,             -- +1 at every CLOSE
  submitted_by       uuid,                                -- who sent it to UNDER_REVIEW last
  status_changed_at  timestamptz,
  status_changed_by  uuid,
  exception_note     text,                                -- why it was closed with DATA_INCOMPLETE components
  UNIQUE (entity_key, kind, fiscal_year, period_no),
  CHECK ((kind = 'MONTH' AND period_no BETWEEN 1 AND 12) OR (kind = 'QUARTER' AND period_no BETWEEN 1 AND 4) OR (kind = 'YEAR' AND period_no = 1)),
  CHECK (period_start = make_date(fiscal_year, CASE kind WHEN 'MONTH' THEN period_no WHEN 'QUARTER' THEN (period_no - 1) * 3 + 1 ELSE 1 END, 1)),
  CHECK (period_end = (period_start + CASE kind WHEN 'MONTH' THEN interval '1 month' WHEN 'QUARTER' THEN interval '3 months' ELSE interval '1 year' END - interval '1 day')::date),
  CHECK ((kind = 'MONTH') = (status IS NOT NULL))
);
ALTER TABLE f360_board.fiscal_periods ENABLE ROW LEVEL SECURITY;

CREATE TABLE f360_board.fiscal_period_events (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  period_id      uuid NOT NULL REFERENCES f360_board.fiscal_periods(id),
  at             timestamptz NOT NULL DEFAULT clock_timestamp(),
  from_status    text, to_status text NOT NULL,
  close_version  int NOT NULL,
  by_user        uuid,
  by_name        text NOT NULL,
  reason         text,
  db_user        text NOT NULL DEFAULT current_user
);
ALTER TABLE f360_board.fiscal_period_events ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER fiscal_period_events_append_only BEFORE UPDATE OR DELETE ON f360_board.fiscal_period_events
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Periods never change shape, are never deleted, and only move along the allowed status graph; every move is logged
-- (also a direct DB update, not only the RPC). Reason comes from the RPC via the transaction-local GUC f360_board.reason.
CREATE FUNCTION f360_board.on_period_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Un periodo fiscal no se borra.'; END IF;
  IF (NEW.entity_key, NEW.kind, NEW.fiscal_year, NEW.period_no, NEW.period_start, NEW.period_end)
     IS DISTINCT FROM (OLD.entity_key, OLD.kind, OLD.fiscal_year, OLD.period_no, OLD.period_start, OLD.period_end) THEN
    RAISE EXCEPTION 'Un periodo fiscal no cambia de fechas.';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT ((OLD.status, NEW.status) IN (('OPEN', 'UNDER_REVIEW'), ('REOPENED', 'UNDER_REVIEW'), ('UNDER_REVIEW', 'OPEN'),
                                         ('UNDER_REVIEW', 'CLOSED'), ('CLOSED', 'REOPENED'))) THEN
      RAISE EXCEPTION 'Cambio de estado no permitido: % → %.', OLD.status, NEW.status;
    END IF;
    IF NEW.status = 'CLOSED' AND NEW.close_version <> OLD.close_version + 1 THEN RAISE EXCEPTION 'Cada cierre crea una versión nueva.'; END IF;
    IF NEW.status <> 'CLOSED' AND NEW.close_version <> OLD.close_version THEN RAISE EXCEPTION 'La versión de cierre solo cambia al cerrar.'; END IF;
    INSERT INTO f360_board.fiscal_period_events (period_id, from_status, to_status, close_version, by_user, by_name, reason)
      VALUES (NEW.id, OLD.status, NEW.status, NEW.close_version, auth.uid(),
              CASE WHEN auth.uid() IS NULL THEN 'sistema (' || current_user || ')' ELSE f360_board.member_name(auth.uid()) END,
              nullif(current_setting('f360_board.reason', true), ''));
  ELSIF NEW.close_version <> OLD.close_version THEN
    RAISE EXCEPTION 'La versión de cierre solo cambia al cerrar.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER fiscal_periods_guard BEFORE UPDATE OR DELETE ON f360_board.fiscal_periods
  FOR EACH ROW EXECUTE FUNCTION f360_board.on_period_change();

CREATE FUNCTION f360_board.ensure_fiscal_year(p_entity text, p_year int) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE n int;
BEGIN
  INSERT INTO f360_board.fiscal_periods (entity_key, kind, fiscal_year, period_no, period_start, period_end, status)
  SELECT p_entity, k.kind, p_year, k.no, k.s, (k.s + k.len - interval '1 day')::date, CASE WHEN k.kind = 'MONTH' THEN 'OPEN' END
  FROM (SELECT 'MONTH' kind, m no, make_date(p_year, m, 1) s, interval '1 month' len FROM generate_series(1, 12) m
        UNION ALL SELECT 'QUARTER', q, make_date(p_year, (q - 1) * 3 + 1, 1), interval '3 months' FROM generate_series(1, 4) q
        UNION ALL SELECT 'YEAR', 1, make_date(p_year, 1, 1), interval '1 year') k
  ON CONFLICT (entity_key, kind, fiscal_year, period_no) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
SELECT f360_board.ensure_fiscal_year('fuxia', 2026), f360_board.ensure_fiscal_year('fuxia', 2027);

-- ══ 3 · Close accounts (catalog only — no amounts) ═══════════════════════════
CREATE TABLE f360_board.close_accounts (
  account_key    text PRIMARY KEY CHECK (account_key ~ '^[a-z][a-z0-9_]*$'),
  label          text NOT NULL,
  component      text NOT NULL CHECK (component IN ('cogs', 'opex', 'cash', 'tax')),
  balance_kind   text NOT NULL CHECK (balance_kind IN ('FLOW', 'BALANCE')),   -- FLOW = during the month; BALANCE = at month end
  allow_negative boolean NOT NULL DEFAULT false,
  sort           int NOT NULL,
  active         boolean NOT NULL DEFAULT true
);
ALTER TABLE f360_board.close_accounts ENABLE ROW LEVEL SECURITY;
INSERT INTO f360_board.close_accounts (account_key, label, component, balance_kind, allow_negative, sort) VALUES
  ('cogs',           'Costo de lo vendido del mes (COGS)',          'cogs', 'FLOW',    false, 10),
  ('opex_rent',      'Renta de tiendas y oficina',                  'opex', 'FLOW',    false, 20),
  ('opex_payroll',   'Nómina y honorarios',                         'opex', 'FLOW',    false, 21),
  ('opex_tech',      'Tecnología y software',                       'opex', 'FLOW',    false, 22),
  ('opex_logistics', 'Envíos y logística',                          'opex', 'FLOW',    false, 23),
  ('opex_other',     'Otros gastos de operación',                   'opex', 'FLOW',    false, 24),
  ('cash_bank',      'Saldo en bancos al cierre',                   'cash', 'BALANCE', true,  30),
  ('cash_on_hand',   'Efectivo en tiendas al cierre',               'cash', 'BALANCE', false, 31),
  ('tax_paid',       'Impuestos pagados en el mes (si aplica)',     'tax',  'FLOW',    false, 40);

-- ══ 4 · Monthly close entries (void + new; who captured, who approved) ══════
CREATE TABLE f360_board.monthly_close_entries (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id          uuid NOT NULL REFERENCES f360_board.fiscal_periods(id),
  account_key        text NOT NULL REFERENCES f360_board.close_accounts(account_key),
  dimension_key      text NOT NULL DEFAULT '' CHECK (dimension_key ~ '^[a-z0-9_:-]*$'),  -- e.g. a bank account alias; '' = total
  amount             numeric(14,2) NOT NULL,
  currency           text NOT NULL REFERENCES f360.currencies(code),
  source             text NOT NULL CHECK (length(btrim(source)) >= 3),   -- "estado de cuenta BBVA sep", "factura proveedor X"
  evidence_ref       text,                                               -- document reference (private bucket comes in SB6)
  note               text,
  status             text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'voided')),
  captured_by        uuid NOT NULL,
  captured_by_name   text NOT NULL,
  captured_at        timestamptz NOT NULL DEFAULT now(),
  approved_by        uuid,
  approved_by_name   text,
  approved_at        timestamptz,
  void_reason        text,
  voided_by          uuid,
  voided_at          timestamptz,
  idempotency_key    uuid NOT NULL UNIQUE,
  CHECK (approved_by IS NULL OR approved_by <> captured_by),
  CHECK ((status = 'voided') = (voided_at IS NOT NULL AND void_reason IS NOT NULL))
);
ALTER TABLE f360_board.monthly_close_entries ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX monthly_close_entries_one_active ON f360_board.monthly_close_entries (period_id, account_key, dimension_key, currency) WHERE status = 'active';

CREATE TABLE f360_board.monthly_close_log (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  entry_id   uuid NOT NULL,
  period_id  uuid NOT NULL,
  action     text NOT NULL CHECK (action IN ('capture', 'approve', 'void')),
  by_user    uuid,
  by_name    text NOT NULL,
  snapshot   jsonb NOT NULL
);
ALTER TABLE f360_board.monthly_close_log ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER monthly_close_log_append_only BEFORE UPDATE OR DELETE ON f360_board.monthly_close_log
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Entries: insert/void only while the month is OPEN/REOPENED; approve only before CLOSED; amounts never edited; no DELETE.
CREATE FUNCTION f360_board.on_close_entry() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360_board.fiscal_periods; act text;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Este historial no se puede modificar (f360_board.monthly_close_entries)'; END IF;
  SELECT * INTO p FROM f360_board.fiscal_periods WHERE id = NEW.period_id;
  IF p.kind <> 'MONTH' THEN RAISE EXCEPTION 'El cierre se captura por mes.'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'active' OR NEW.approved_by IS NOT NULL THEN RAISE EXCEPTION 'Una captura nueva nace activa y sin aprobar.'; END IF;
    IF p.status NOT IN ('OPEN', 'REOPENED') THEN RAISE EXCEPTION 'El mes está en revisión o cerrado: para cambiarlo hay que regresarlo o reabrirlo.'; END IF;
    act := 'capture';
  ELSE
    IF (NEW.id, NEW.period_id, NEW.account_key, NEW.dimension_key, NEW.amount, NEW.currency, NEW.source, NEW.evidence_ref, NEW.note,
        NEW.captured_by, NEW.captured_by_name, NEW.captured_at, NEW.idempotency_key)
       IS DISTINCT FROM (OLD.id, OLD.period_id, OLD.account_key, OLD.dimension_key, OLD.amount, OLD.currency, OLD.source, OLD.evidence_ref, OLD.note,
        OLD.captured_by, OLD.captured_by_name, OLD.captured_at, OLD.idempotency_key) THEN
      RAISE EXCEPTION 'Un monto capturado no se edita: anúlalo y captura uno nuevo.';
    END IF;
    IF OLD.status = 'voided' THEN RAISE EXCEPTION 'Una captura anulada no cambia.'; END IF;
    IF NEW.status = 'voided' THEN
      IF p.status NOT IN ('OPEN', 'REOPENED') THEN RAISE EXCEPTION 'El mes está en revisión o cerrado: para anular hay que regresarlo o reabrirlo.'; END IF;
      IF (NEW.approved_by, NEW.approved_at) IS DISTINCT FROM (OLD.approved_by, OLD.approved_at) THEN RAISE EXCEPTION 'Anular y aprobar son pasos distintos.'; END IF;
      act := 'void';
    ELSIF OLD.approved_by IS NULL AND NEW.approved_by IS NOT NULL THEN
      IF p.status = 'CLOSED' THEN RAISE EXCEPTION 'El mes está cerrado.'; END IF;
      act := 'approve';
    ELSE
      RAISE EXCEPTION 'Cambio no permitido en una captura de cierre.';
    END IF;
  END IF;
  INSERT INTO f360_board.monthly_close_log (entry_id, period_id, action, by_user, by_name, snapshot)
    VALUES (NEW.id, NEW.period_id, act, auth.uid(),
            CASE WHEN auth.uid() IS NULL THEN 'sistema (' || current_user || ')' ELSE f360_board.member_name(auth.uid()) END, to_jsonb(NEW));
  RETURN NEW;
END $$;
CREATE TRIGGER monthly_close_entries_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.monthly_close_entries
  FOR EACH ROW EXECUTE FUNCTION f360_board.on_close_entry();

-- ══ 5 · Close snapshots (append-only) ════════════════════════════════════════
CREATE TABLE f360_board.close_actual_snapshots (
  period_id      uuid NOT NULL REFERENCES f360_board.fiscal_periods(id),
  close_version  int NOT NULL CHECK (close_version >= 1),
  taken_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  taken_by       uuid,
  taken_by_name  text NOT NULL,
  approved_by    uuid,            -- the member who closed
  prepared_by    uuid,            -- the member who sent it to review
  payload        jsonb NOT NULL,  -- readiness per component + entry totals by account/currency
  content_hash   text NOT NULL,
  PRIMARY KEY (period_id, close_version)
);
ALTER TABLE f360_board.close_actual_snapshots ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER close_actual_snapshots_append_only BEFORE UPDATE OR DELETE ON f360_board.close_actual_snapshots
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ══ 6 · Metric catalog (one vocabulary; availability as audited 2026-10-08, 02_CEO_COCKPIT.md §2) ══
CREATE TABLE f360_board.metric_catalog (
  metric_key           text PRIMARY KEY CHECK (metric_key ~ '^[a-z][a-z0-9_]*$'),
  label                text NOT NULL,
  definition           text NOT NULL,
  unit                 text NOT NULL CHECK (unit IN ('money', 'count', 'ratio', 'pct', 'units')),
  source_kind          text NOT NULL CHECK (source_kind IN ('G1', 'CLOSE', 'DERIVED', 'GROWTH', 'LEDGER', 'CRM')),
  source_ref           text NOT NULL,
  depends_on           text[] NOT NULL DEFAULT '{}',
  availability         text NOT NULL CHECK (availability IN ('AVAILABLE', 'PARTIAL', 'MISSING')),
  availability_reason  text NOT NULL,
  sort                 int NOT NULL
);
ALTER TABLE f360_board.metric_catalog ENABLE ROW LEVEL SECURITY;
INSERT INTO f360_board.metric_catalog (metric_key, label, definition, unit, source_kind, source_ref, depends_on, availability, availability_reason, sort) VALUES
 ('revenue_net_product', 'Venta neta de producto', 'Producto cobrado − cupones − reembolsos de producto, pedidos countable, en moneda original. IVA no separado (D4 / definición de ingresos de S-G0).', 'money', 'G1', 'f360.commerce_orders.net_product + f360.historical_sales_active', ARRAY['revenue definitions (S-G0)'], 'PARTIAL', 'Ventas legacy de public.offline_sales fuera de G1; salud del canal de producción invisible (C5/F9).', 10),
 ('revenue_gross_product', 'Venta bruta de producto', 'Subtotal de producto antes de cupones (Woo items_subtotal; tienda line_total).', 'money', 'G1', 'f360.commerce_orders.product_gross', ARRAY['revenue definitions (S-G0)'], 'PARTIAL', 'Mismos huecos que la venta neta.', 11),
 ('orders', 'Pedidos', 'Pedidos countable (online + tienda). Los resúmenes históricos no tienen número de pedidos.', 'count', 'G1', 'f360.commerce_orders', '{}', 'AVAILABLE', 'Medido en G1.', 20),
 ('aov', 'Ticket promedio', 'Venta neta de producto ÷ pedidos, por moneda.', 'money', 'DERIVED', 'revenue_net_product / orders', '{}', 'PARTIAL', 'Hereda los huecos de la venta.', 21),
 ('units', 'Pares vendidos', 'Unidades de producto en pedidos countable + pares de resúmenes históricos.', 'units', 'G1', 'f360.commerce_order_lines + f360.historical_sales_active', '{}', 'PARTIAL', 'Hereda los huecos de la venta.', 22),
 ('new_customers', 'Clientas nuevas', 'Primera compra identificada en el periodo.', 'count', 'CRM', 'f360.commerce_orders.loyalty_customer_id/woo_customer_id', '{}', 'PARTIAL', 'Pedidos invitados sin identidad.', 30),
 ('repeat_customers', 'Clientas recurrentes', 'Clientas identificadas con ≥ 2 pedidos countable en la ventana.', 'count', 'CRM', 'f360.commerce_orders', '{}', 'PARTIAL', 'Depende de identidad.', 31),
 ('repeat_rate', 'Tasa de recompra', 'Recurrentes ÷ compradoras identificadas (denominador explícito).', 'pct', 'DERIVED', 'repeat_customers / identified buyers', '{}', 'PARTIAL', 'Depende de identidad.', 32),
 ('cogs', 'Costo de lo vendido', 'Costo de producto de lo vendido. Hoy solo por captura de cierre (cuenta cogs); calculado cuando exista costo unitario.', 'money', 'CLOSE', 'f360_board.monthly_close_entries[cogs]', ARRAY['f360.product_cost_versions (S-G0)'], 'MISSING', 'No hay costo en ninguna tabla; sin capturas de cierre.', 40),
 ('gross_profit', 'Utilidad bruta', 'Venta neta de producto − COGS, mismo mes y moneda.', 'money', 'DERIVED', 'revenue_net_product − cogs', '{}', 'MISSING', 'Requiere COGS.', 41),
 ('gross_margin', 'Margen bruto', 'Utilidad bruta ÷ venta neta de producto.', 'pct', 'DERIVED', 'gross_profit / revenue_net_product', '{}', 'MISSING', 'Requiere COGS.', 42),
 ('opex', 'Gastos de operación', 'Suma de cuentas opex_* del cierre del mes.', 'money', 'CLOSE', 'f360_board.monthly_close_entries[opex_*]', '{}', 'MISSING', 'Sin capturas de cierre.', 50),
 ('ebitda', 'EBITDA', 'Utilidad bruta − OPEX; solo si ambos del mismo mes están cerrados.', 'money', 'DERIVED', 'gross_profit − opex', '{}', 'MISSING', 'Requiere COGS y OPEX.', 51),
 ('cash', 'Caja', 'Saldos de caja/bancos al cierre por moneda (cuentas cash_*).', 'money', 'CLOSE', 'f360_board.monthly_close_entries[cash_*]', '{}', 'MISSING', 'Sin capturas de cierre.', 60),
 ('inventory_units', 'Inventario en pares', 'Pares en ubicaciones vendibles/bodega, sin tránsito.', 'units', 'LEDGER', 'f360.inventory_balances', '{}', 'AVAILABLE', 'Ledger F360 (saldo vivo, no foto de fin de mes).', 70),
 ('inventory_value_cost', 'Inventario a costo', 'Pares × costo unitario vigente.', 'money', 'DERIVED', 'inventory_units × unit cost', ARRAY['f360.product_cost_versions (S-G0)'], 'MISSING', 'Sin costo unitario.', 71),
 ('inventory_value_retail', 'Inventario a precio de venta', 'Pares × precio de venta (NO es costo).', 'money', 'LEDGER', 'f360.inventory_balances × f360.products.regular_price', '{}', 'AVAILABLE', 'Igual que el panel ejecutivo (rótulo "a precio de venta").', 72),
 ('marketing_spend', 'Gasto de marketing', 'Gasto pagado por canal.', 'money', 'GROWTH', 'marketing spend facts (S-G0)', ARRAY['marketing spend (S-G0)'], 'MISSING', 'Lo publica S-G0; Strategy no lo captura (una sola fuente).', 80),
 ('cac_blended', 'CAC combinado', 'Gasto de marketing ÷ clientas nuevas del periodo.', 'money', 'DERIVED', 'marketing_spend / new_customers', ARRAY['marketing spend (S-G0)'], 'MISSING', 'Requiere gasto.', 81),
 ('roas', 'ROAS', 'Venta atribuida first-party ÷ gasto pagado (nunca el ROAS de la plataforma).', 'ratio', 'DERIVED', 'attributed revenue / paid spend', ARRAY['marketing spend (S-G0)', 'measurement health (S-G0)'], 'MISSING', 'Requiere gasto y atribución.', 82),
 ('mer', 'MER', 'Venta total ÷ gasto de marketing total.', 'ratio', 'DERIVED', 'revenue_net_product / marketing_spend', ARRAY['marketing spend (S-G0)'], 'MISSING', 'Requiere gasto.', 83),
 ('tax_paid', 'Impuestos pagados', 'Impuestos pagados del mes (si aplica), captura de cierre.', 'money', 'CLOSE', 'f360_board.monthly_close_entries[tax_paid]', '{}', 'MISSING', 'Sin capturas de cierre.', 90);

-- ══ 7 · Budget & forecast foundation (versioned; frozen once approved/published) ══
CREATE TABLE f360_board.budget_versions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key       text NOT NULL REFERENCES f360_board.reporting_entities(key),
  fiscal_year      int NOT NULL CHECK (fiscal_year BETWEEN 2024 AND 2100),
  name             text NOT NULL,
  number_class     text NOT NULL DEFAULT 'BUDGET' CHECK (number_class = 'BUDGET'),
  status           text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'APPROVED', 'SUPERSEDED')),
  supersedes_id    uuid REFERENCES f360_board.budget_versions(id),
  decision_id      uuid,                      -- FK added with the decision log (20261015000300)
  created_by       uuid, created_by_name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  approved_at      timestamptz, approved_by uuid[],
  content_hash     text
);
CREATE TABLE f360_board.budget_lines (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id       uuid NOT NULL REFERENCES f360_board.budget_versions(id),
  period_month     date NOT NULL CHECK (period_month = date_trunc('month', period_month)::date),
  metric_key       text NOT NULL REFERENCES f360_board.metric_catalog(metric_key),
  dim_market       text CHECK (dim_market IN ('MX', 'CO', 'ROW')),
  dim_channel      text CHECK (dim_channel IN ('online', 'store', 'historical_summary')),
  dim_location_id  uuid REFERENCES f360.locations(id),
  dim_category_key text REFERENCES f360.categories(key),
  currency         text NOT NULL REFERENCES f360.currencies(code),
  amount           numeric(14,2) NOT NULL,
  note             text
);
CREATE TABLE f360_board.forecast_versions (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key              text NOT NULL REFERENCES f360_board.reporting_entities(key),
  name                    text NOT NULL,
  number_class            text NOT NULL DEFAULT 'FORECAST' CHECK (number_class = 'FORECAST'),
  window_start            date NOT NULL CHECK (window_start = date_trunc('month', window_start)::date),
  horizon_months          int NOT NULL DEFAULT 18 CHECK (horizon_months BETWEEN 1 AND 60),
  status                  text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'SUPERSEDED')),
  based_on_close_version  int,
  supersedes_id           uuid REFERENCES f360_board.forecast_versions(id),
  created_by uuid, created_by_name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz, published_by uuid,
  content_hash            text
);
CREATE TABLE f360_board.forecast_lines (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id       uuid NOT NULL REFERENCES f360_board.forecast_versions(id),
  period_month     date NOT NULL CHECK (period_month = date_trunc('month', period_month)::date),
  metric_key       text NOT NULL REFERENCES f360_board.metric_catalog(metric_key),
  method           text NOT NULL CHECK (method IN ('ECOM_FUNNEL', 'PAID_ACQ', 'RETAIL_TX', 'CUSTOMER_BASE', 'MANUAL', 'INVENTORY_CHAIN')),
  role             text NOT NULL DEFAULT 'total' CHECK (role IN ('total', 'decomposition')),
  dim_market       text CHECK (dim_market IN ('MX', 'CO', 'ROW')),
  dim_channel      text CHECK (dim_channel IN ('online', 'store', 'historical_summary')),
  dim_location_id  uuid REFERENCES f360.locations(id),
  dim_category_key text REFERENCES f360.categories(key),
  currency         text NOT NULL REFERENCES f360.currencies(code),
  amount           numeric(14,2),
  drivers          jsonb NOT NULL DEFAULT '{}',
  note             text,
  CHECK (method <> 'MANUAL' OR length(btrim(coalesce(note, ''))) > 0)
);
CREATE TABLE f360_board.forecast_snapshots (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  version_id    uuid NOT NULL REFERENCES f360_board.forecast_versions(id),
  taken_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  reason        text NOT NULL,
  payload       jsonb NOT NULL,
  content_hash  text NOT NULL
);
ALTER TABLE f360_board.budget_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.budget_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.forecast_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.forecast_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.forecast_snapshots ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER forecast_snapshots_append_only BEFORE UPDATE OR DELETE ON f360_board.forecast_snapshots
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Versions: content is frozen outside DRAFT; only forward status moves; only DRAFT versions may be deleted.
CREATE FUNCTION f360_board.on_version_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE frozen text := CASE TG_TABLE_NAME WHEN 'budget_versions' THEN 'APPROVED' ELSE 'PUBLISHED' END;
  o jsonb := to_jsonb(OLD); n jsonb; lines jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN RAISE EXCEPTION 'Una versión % no se borra.', OLD.status; END IF;
    RETURN OLD;
  END IF;
  n := to_jsonb(NEW);
  IF OLD.status <> 'DRAFT' THEN
    -- only allowed: frozen → SUPERSEDED, nothing else changes
    IF NOT (OLD.status = frozen AND NEW.status = 'SUPERSEDED' AND (o - 'status') = (n - 'status')) THEN
      RAISE EXCEPTION 'Esta versión ya está %: no se modifica (crea una versión nueva).', OLD.status;
    END IF;
  ELSIF NEW.status NOT IN ('DRAFT', frozen) THEN
    RAISE EXCEPTION 'Un borrador solo puede pasar a %.', frozen;
  ELSIF NEW.status = frozen THEN
    IF TG_TABLE_NAME = 'budget_versions' THEN
      SELECT coalesce(jsonb_agg(to_jsonb(l) - 'id' ORDER BY l.period_month, l.metric_key, l.currency, l.id), '[]') INTO lines FROM f360_board.budget_lines l WHERE l.version_id = NEW.id;
      NEW.content_hash := encode(extensions.digest(lines::text, 'sha256'), 'hex');
    ELSE
      SELECT coalesce(jsonb_agg(to_jsonb(l) - 'id' ORDER BY l.period_month, l.metric_key, l.currency, l.id), '[]') INTO lines FROM f360_board.forecast_lines l WHERE l.version_id = NEW.id;
      NEW.content_hash := encode(extensions.digest(lines::text, 'sha256'), 'hex');
      INSERT INTO f360_board.forecast_snapshots (version_id, reason, payload, content_hash)
        VALUES (NEW.id, 'publish', jsonb_build_object('version', to_jsonb(NEW) - 'content_hash', 'lines', lines), NEW.content_hash);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER budget_versions_guard BEFORE UPDATE OR DELETE ON f360_board.budget_versions FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_change();
CREATE TRIGGER forecast_versions_guard BEFORE UPDATE OR DELETE ON f360_board.forecast_versions FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_change();

-- Lines: only while the parent version is DRAFT.
CREATE FUNCTION f360_board.on_version_line_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE st text; vid uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.version_id ELSE NEW.version_id END;
BEGIN
  IF TG_TABLE_NAME = 'budget_lines' THEN SELECT status INTO st FROM f360_board.budget_versions WHERE id = vid;
  ELSE SELECT status INTO st FROM f360_board.forecast_versions WHERE id = vid; END IF;
  IF st IS DISTINCT FROM 'DRAFT' THEN RAISE EXCEPTION 'La versión está %: sus líneas no se modifican.', st; END IF;
  IF TG_OP = 'UPDATE' AND NEW.version_id <> OLD.version_id THEN RAISE EXCEPTION 'Una línea no cambia de versión.'; END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER budget_lines_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.budget_lines FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_line_change();
CREATE TRIGGER forecast_lines_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.forecast_lines FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_line_change();

-- ══ 8 · Close readiness (what a close consolidates; missing source → DATA_INCOMPLETE, never a number) ══
CREATE FUNCTION f360_board.close_readiness(p_period_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE opex_n int; has_cogs boolean; has_cash boolean; has_tax boolean;
BEGIN
  SELECT count(DISTINCT e.account_key) FILTER (WHERE a.component = 'opex'), bool_or(a.component = 'cogs'), bool_or(a.component = 'cash'), bool_or(a.component = 'tax')
    INTO opex_n, has_cogs, has_cash, has_tax
    FROM f360_board.monthly_close_entries e JOIN f360_board.close_accounts a USING (account_key)
    WHERE e.period_id = p_period_id AND e.status = 'active';
  RETURN jsonb_build_array(
    jsonb_build_object('component', 'sales', 'status', 'DATA_INCOMPLETE', 'source', 'G1 Commerce Facts + historical_sales (SB1)',
                       'reason', 'Aún no conectado (SB1). Definición de ingresos: S-G0 / D4.'),
    jsonb_build_object('component', 'cogs', 'status', CASE WHEN coalesce(has_cogs, false) THEN 'AVAILABLE' ELSE 'DATA_INCOMPLETE' END,
                       'source', 'Captura de cierre (cogs); costo unitario de S-G0 cuando exista', 'reason', CASE WHEN coalesce(has_cogs, false) THEN NULL ELSE 'Sin captura de COGS.' END),
    jsonb_build_object('component', 'gross_profit', 'status', 'DATA_INCOMPLETE', 'source', 'Derivado: ventas − COGS', 'reason', 'Requiere ventas conectadas (SB1) y COGS.'),
    jsonb_build_object('component', 'opex', 'status', CASE WHEN coalesce(opex_n, 0) = 0 THEN 'DATA_INCOMPLETE' WHEN opex_n < (SELECT count(*) FROM f360_board.close_accounts WHERE component = 'opex' AND active) THEN 'PARTIAL' ELSE 'AVAILABLE' END,
                       'source', 'Captura de cierre (opex_*)', 'captured_categories', coalesce(opex_n, 0),
                       'reason', CASE WHEN coalesce(opex_n, 0) = 0 THEN 'Sin capturas de OPEX.' END),
    jsonb_build_object('component', 'marketing_spend', 'status', 'DATA_INCOMPLETE', 'source', 'Gasto de marketing de S-G0', 'reason', 'Lo publica S-G0; aún no conectado.'),
    jsonb_build_object('component', 'cash', 'status', CASE WHEN coalesce(has_cash, false) THEN 'AVAILABLE' ELSE 'DATA_INCOMPLETE' END,
                       'source', 'Captura de cierre (cash_*)', 'reason', CASE WHEN coalesce(has_cash, false) THEN NULL ELSE 'Sin saldo de caja.' END),
    jsonb_build_object('component', 'inventory', 'status', 'DATA_INCOMPLETE', 'source', 'Ledger F360 (pares) + costo S-G0',
                       'reason', 'Foto de inventario a fin de mes aún no conectada (SB1); valor a costo requiere costo unitario.'),
    jsonb_build_object('component', 'tax', 'status', CASE WHEN coalesce(has_tax, false) THEN 'AVAILABLE' ELSE 'DATA_INCOMPLETE' END,
                       'source', 'Captura de cierre (tax_paid), si aplica', 'reason', CASE WHEN coalesce(has_tax, false) THEN NULL ELSE 'Sin captura (si aplica).' END));
END $$;

-- ══ 9 · Public RPCs (FINANCIAL scope) ════════════════════════════════════════
-- Periods of a fiscal year with month statuses and the quarter/year roll-up.
CREATE FUNCTION public.f360_board_periods(p_year int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE y int := coalesce(p_year, extract(year FROM (now() AT TIME ZONE 'America/Mexico_City'))::int);
  uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_periods', y::text);
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'fiscal_year', y, 'rule', 'Año fiscal calendario: 1 de enero → 31 de diciembre (D11).',
    'months', coalesce((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'month', p.period_no, 'start', p.period_start, 'end', p.period_end,
               'status', p.status, 'close_version', p.close_version, 'exception_note', p.exception_note,
               'entries', (SELECT count(*) FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id AND e.status = 'active'),
               'pending_approval', (SELECT count(*) FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id AND e.status = 'active' AND e.approved_by IS NULL))
             ORDER BY p.period_no) FROM f360_board.fiscal_periods p WHERE p.entity_key = 'fuxia' AND p.kind = 'MONTH' AND p.fiscal_year = y), '[]'),
    'rollups', coalesce((SELECT jsonb_agg(jsonb_build_object('kind', r.kind, 'no', r.period_no, 'start', r.period_start, 'end', r.period_end,
               'months_closed', (SELECT count(*) FROM f360_board.fiscal_periods m WHERE m.entity_key = r.entity_key AND m.kind = 'MONTH' AND m.period_start BETWEEN r.period_start AND r.period_end AND m.status = 'CLOSED'),
               'months_total', (SELECT count(*) FROM f360_board.fiscal_periods m WHERE m.entity_key = r.entity_key AND m.kind = 'MONTH' AND m.period_start BETWEEN r.period_start AND r.period_end),
               'status', CASE WHEN NOT EXISTS (SELECT 1 FROM f360_board.fiscal_periods m WHERE m.entity_key = r.entity_key AND m.kind = 'MONTH' AND m.period_start BETWEEN r.period_start AND r.period_end AND m.status <> 'CLOSED') THEN 'CLOSED' ELSE 'OPEN' END)
             ORDER BY r.kind DESC, r.period_no) FROM f360_board.fiscal_periods r WHERE r.entity_key = 'fuxia' AND r.kind IN ('QUARTER', 'YEAR') AND r.fiscal_year = y), '[]'));
END $$;

-- One month's close: entries (with who captured/approved), readiness, history, snapshots.
CREATE FUNCTION public.f360_board_close_get(p_period_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_get', p_period_id::text); p f360_board.fiscal_periods;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO p FROM f360_board.fiscal_periods WHERE id = p_period_id AND kind = 'MONTH';
  IF p.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Mes no encontrado.'); END IF;
  RETURN jsonb_build_object('ok', true,
    'period', jsonb_build_object('id', p.id, 'year', p.fiscal_year, 'month', p.period_no, 'start', p.period_start, 'end', p.period_end, 'status', p.status,
                                 'close_version', p.close_version, 'submitted_by', f360_board.member_name(p.submitted_by), 'submitted_by_me', p.submitted_by = uid,
                                 'exception_note', p.exception_note),
    'accounts', (SELECT jsonb_agg(jsonb_build_object('key', a.account_key, 'label', a.label, 'component', a.component, 'balance_kind', a.balance_kind, 'allow_negative', a.allow_negative) ORDER BY a.sort)
                 FROM f360_board.close_accounts a WHERE a.active),
    'currencies', (SELECT jsonb_agg(code ORDER BY code) FROM f360.currencies),
    'entries', coalesce((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'account_key', e.account_key, 'dimension_key', e.dimension_key, 'amount', e.amount, 'currency', e.currency,
                 'source', e.source, 'evidence_ref', e.evidence_ref, 'note', e.note, 'status', e.status,
                 'captured_by', e.captured_by_name, 'captured_by_me', e.captured_by = uid, 'captured_at', e.captured_at,
                 'approved_by', e.approved_by_name, 'approved_at', e.approved_at, 'void_reason', e.void_reason, 'voided_at', e.voided_at)
                 ORDER BY e.status, e.captured_at) FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id), '[]'),
    'readiness', f360_board.close_readiness(p.id),
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('at', v.at, 'from', v.from_status, 'to', v.to_status, 'version', v.close_version, 'by', v.by_name, 'reason', v.reason) ORDER BY v.id)
                 FROM f360_board.fiscal_period_events v WHERE v.period_id = p.id), '[]'),
    'snapshots', coalesce((SELECT jsonb_agg(jsonb_build_object('version', s.close_version, 'taken_at', s.taken_at, 'by', s.taken_by_name, 'hash', s.content_hash) ORDER BY s.close_version)
                 FROM f360_board.close_actual_snapshots s WHERE s.period_id = p.id), '[]'));
END $$;

-- Capture one manual close amount (sensitive write; idempotent by key; server validates account, currency, sign, state).
CREATE FUNCTION public.f360_board_close_entry_add(p_idempotency_key uuid, p_period_id uuid, p_account_key text, p_amount numeric,
  p_currency text, p_source text, p_evidence_ref text DEFAULT NULL, p_note text DEFAULT NULL, p_dimension_key text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_entry_add', p_period_id::text,
    jsonb_build_object('k', p_idempotency_key, 'a', p_account_key, 'amt', p_amount, 'c', p_currency));
  a f360_board.close_accounts; e f360_board.monthly_close_entries;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Falta la llave de idempotencia.'); END IF;
  SELECT * INTO e FROM f360_board.monthly_close_entries WHERE idempotency_key = p_idempotency_key;
  IF e.id IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'replayed', true, 'id', e.id); END IF;
  SELECT * INTO a FROM f360_board.close_accounts WHERE account_key = p_account_key AND active;
  IF a.account_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Cuenta de cierre no válida.'); END IF;
  IF p_amount IS NULL OR (p_amount < 0 AND NOT a.allow_negative) OR p_amount <> round(p_amount, 2) OR abs(p_amount) >= 1e12 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Monto no válido.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.currencies WHERE code = p_currency) THEN RETURN jsonb_build_object('ok', false, 'error', 'Moneda no válida.'); END IF;
  IF length(btrim(coalesce(p_source, ''))) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Indica la fuente (p. ej. "estado de cuenta BBVA").'); END IF;
  BEGIN
    INSERT INTO f360_board.monthly_close_entries (period_id, account_key, dimension_key, amount, currency, source, evidence_ref, note,
                                                  captured_by, captured_by_name, idempotency_key)
      VALUES (p_period_id, a.account_key, lower(coalesce(p_dimension_key, '')), p_amount, p_currency, btrim(p_source), nullif(btrim(p_evidence_ref), ''),
              nullif(btrim(p_note), ''), uid, f360_board.member_name(uid), p_idempotency_key)
      RETURNING * INTO e;
  EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Ya hay un monto activo para esa cuenta y moneda: anúlalo primero.');
    WHEN foreign_key_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Mes no encontrado.');
    WHEN raise_exception OR check_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'No se pudo guardar: ' || SQLERRM);
  END;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_close_entry_add', e.id::text, jsonb_build_object('period', p_period_id, 'account', a.account_key));
  RETURN jsonb_build_object('ok', true, 'id', e.id);
END $$;

-- Void a capture (correction = void + new). Reason required.
CREATE FUNCTION public.f360_board_close_entry_void(p_entry_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_entry_void', p_entry_id::text);
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica por qué se anula.'); END IF;
  BEGIN
    UPDATE f360_board.monthly_close_entries SET status = 'voided', void_reason = btrim(p_reason), voided_by = uid, voided_at = now()
      WHERE id = p_entry_id AND status = 'active';
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'Captura no encontrada o ya anulada.'); END IF;
  EXCEPTION WHEN raise_exception THEN RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_close_entry_void', p_entry_id::text);
  RETURN jsonb_build_object('ok', true);
END $$;

-- Approve every pending capture of the month that the caller did NOT capture (who captures ≠ who approves).
CREATE FUNCTION public.f360_board_close_entries_approve(p_period_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_entries_approve', p_period_id::text); n int; own int;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  BEGIN
    UPDATE f360_board.monthly_close_entries SET approved_by = uid, approved_by_name = f360_board.member_name(uid), approved_at = now()
      WHERE period_id = p_period_id AND status = 'active' AND approved_by IS NULL AND captured_by <> uid;
    GET DIAGNOSTICS n = ROW_COUNT;
  EXCEPTION WHEN raise_exception THEN RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
  SELECT count(*) INTO own FROM f360_board.monthly_close_entries WHERE period_id = p_period_id AND status = 'active' AND approved_by IS NULL AND captured_by = uid;
  IF n > 0 THEN PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_close_entries_approve', p_period_id::text, jsonb_build_object('approved', n)); END IF;
  RETURN jsonb_build_object('ok', true, 'approved', n, 'pending_own', own,
    'note', CASE WHEN own > 0 THEN 'Tus propias capturas las aprueba otra persona del consejo.' END);
END $$;

-- Move a month along OPEN → UNDER_REVIEW → CLOSED (→ REOPENED → UNDER_REVIEW …). Closing freezes a snapshot.
CREATE FUNCTION public.f360_board_period_transition(p_period_id uuid, p_to_status text, p_reason text DEFAULT NULL, p_exception_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_period_transition', p_period_id::text, jsonb_build_object('to', p_to_status));
  p f360_board.fiscal_periods; s f360_board.settings; ready jsonb; incomplete int; totals jsonb; payload jsonb; pending int;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO s FROM f360_board.settings WHERE id;
  SELECT * INTO p FROM f360_board.fiscal_periods WHERE id = p_period_id AND kind = 'MONTH' FOR UPDATE;
  IF p.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Mes no encontrado.'); END IF;
  IF p_to_status = 'REOPENED' AND length(btrim(coalesce(p_reason, ''))) < 10 THEN RETURN jsonb_build_object('ok', false, 'error', 'Reabrir un mes cerrado requiere un motivo claro.'); END IF;
  IF p_to_status = 'OPEN' AND length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica qué falta corregir.'); END IF;
  IF p_to_status = 'CLOSED' THEN
    IF p.status <> 'UNDER_REVIEW' THEN RETURN jsonb_build_object('ok', false, 'error', 'Primero hay que mandar el mes a revisión.'); END IF;
    IF s.close_requires_second_member AND p.submitted_by = uid THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Otra persona del consejo debe aprobar el cierre.');
    END IF;
    SELECT count(*) INTO pending FROM f360_board.monthly_close_entries WHERE period_id = p.id AND status = 'active' AND approved_by IS NULL;
    IF pending > 0 THEN RETURN jsonb_build_object('ok', false, 'error', format('Hay %s capturas sin aprobar.', pending)); END IF;
    ready := f360_board.close_readiness(p.id);
    SELECT count(*) INTO incomplete FROM jsonb_array_elements(ready) x WHERE x->>'status' <> 'AVAILABLE';
    IF incomplete > 0 AND length(btrim(coalesce(p_exception_note, ''))) < 10 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Faltan datos (DATA INCOMPLETE): para cerrar así, escribe la excepción.', 'readiness', ready);
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('account', account_key, 'currency', currency, 'amount', total) ORDER BY account_key, currency), '[]') INTO totals
      FROM (SELECT account_key, currency, sum(amount) total FROM f360_board.monthly_close_entries WHERE period_id = p.id AND status = 'active' GROUP BY 1, 2) t;
    payload := jsonb_build_object('period', jsonb_build_object('year', p.fiscal_year, 'month', p.period_no), 'close_version', p.close_version + 1,
      'readiness', ready, 'entry_totals', totals, 'exception_note', nullif(btrim(p_exception_note), ''),
      'entries', (SELECT coalesce(jsonb_agg(to_jsonb(e) - 'idempotency_key' ORDER BY e.id), '[]') FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id AND e.status = 'active'));
  END IF;
  PERFORM set_config('f360_board.reason', coalesce(btrim(p_reason), ''), true);
  BEGIN
    UPDATE f360_board.fiscal_periods SET status = p_to_status,
        close_version = CASE WHEN p_to_status = 'CLOSED' THEN close_version + 1 ELSE close_version END,
        submitted_by = CASE WHEN p_to_status = 'UNDER_REVIEW' THEN uid ELSE submitted_by END,
        exception_note = CASE WHEN p_to_status = 'CLOSED' THEN nullif(btrim(p_exception_note), '') ELSE exception_note END,
        status_changed_at = now(), status_changed_by = uid
      WHERE id = p.id;
  EXCEPTION WHEN raise_exception OR check_violation THEN RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
  PERFORM set_config('f360_board.reason', '', true);
  IF p_to_status = 'CLOSED' THEN   -- after the status change succeeded: the frozen photo of this close version
    INSERT INTO f360_board.close_actual_snapshots (period_id, close_version, taken_by, taken_by_name, approved_by, prepared_by, payload, content_hash)
      VALUES (p.id, p.close_version + 1, uid, f360_board.member_name(uid), uid, p.submitted_by, payload, encode(extensions.digest(payload::text, 'sha256'), 'hex'));
  END IF;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_period_transition', p.id::text, jsonb_build_object('from', p.status, 'to', p_to_status));
  RETURN jsonb_build_object('ok', true, 'status', p_to_status, 'close_version', CASE WHEN p_to_status = 'CLOSED' THEN p.close_version + 1 ELSE p.close_version END);
END $$;

-- The metric vocabulary with today's availability (no values).
CREATE FUNCTION public.f360_board_metric_catalog() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_metric_catalog');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'metrics', (SELECT jsonb_agg(to_jsonb(m) - 'sort' ORDER BY m.sort) FROM f360_board.metric_catalog m));
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_board_periods(int), public.f360_board_close_get(uuid),
  public.f360_board_close_entry_add(uuid, uuid, text, numeric, text, text, text, text, text), public.f360_board_close_entry_void(uuid, text),
  public.f360_board_close_entries_approve(uuid), public.f360_board_period_transition(uuid, text, text, text), public.f360_board_metric_catalog() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_periods(int), public.f360_board_close_get(uuid),
  public.f360_board_close_entry_add(uuid, uuid, text, numeric, text, text, text, text, text), public.f360_board_close_entry_void(uuid, text),
  public.f360_board_close_entries_approve(uuid), public.f360_board_period_transition(uuid, text, text, text), public.f360_board_metric_catalog() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261015000200', 'f360_board_sb0_finance_foundation', '{}');

-- ════════ 20261015000300_f360_board_sb0_governance_plan.sql ════════
-- Fuxia 360 · Strategy & Board · SB0.3 — DECISION LOG WITH CONFLICT OF INTEREST (D10B) + PLAN 2027 MAPPING (D12).
-- Needs 20261015000100 and 20261015000200. Spec: 08_BOARD_GOVERNANCE.md §2, 07_CAPITAL_OWNERSHIP.md §3, 05_FIVE_YEAR_PLAN.md §1–2.
-- ADDITIVE, inside f360_board (+ public.f360_board_* RPCs). f360.growth_* tables are READ, never changed.
--
-- D10B (Mario 2026-10-08) — workflow support only, no final legal rules:
--   · decisions carry RELATED PARTY / CONFLICT OF INTEREST flags and the interested members;
--   · conflict kinds MARIO_INVESTMENT / MARIO_OWNERSHIP / MARIO_TECH_CONTRIBUTION / MARIO_COMPENSATION make the member with
--     person_key = 'MARIO' (board_members, set by reviewed script by auth id — never by name) an interested party automatically;
--   · interested members are RECUSED (recorded) and their approve/reject attempts are refused (and recorded);
--   · approval is valid only from a non-interested member → "APPROVED BY OTHER MEMBER". Mario can never be the sole approver
--     of a Mario-related decision; Carolina can be the independent approver.
--   · D5 default (settings.decision_requires_other_member): ordinary decisions are approved by a member other than the proposer.
-- Immutability: after APPROVED/REJECTED the content is frozen by trigger; the only later change is → SUPERSEDED by a newer
-- approved decision (supersedes_id). DELETE always refused. Revisions while PROPOSED and every event are append-only.
--
-- D12 Plan 2027: the existing B4 North Star (f360.growth_plans, prod 2027 = MXN 15,000,000) is the INITIAL SOURCE.
-- To avoid two parallel plans, the Board plan year 2027 is a LINKED row (linked_source = 'f360.growth_plans'): its amount is
-- read live from growth_plans (the only editable place until a Board plan is approved — D8), with its full history from
-- f360.growth_plan_changes; the import itself is preserved as revision 1 (value + history at import time). Label: DRAFT
-- MANAGEMENT TARGET (not forecast, not actual). The five-year draft targets (2028–2031) are NOT loaded here (spec: SB3, by
-- the owners in the UI).
-- Rollback: supabase/rollbacks/20261015000300_f360_board_sb0_governance_plan.down.sql

-- ══ 1 · Decisions ═══════════════════════════════════════════════════════════
CREATE SEQUENCE f360_board.decision_number_seq;

CREATE TABLE f360_board.decisions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number                text NOT NULL UNIQUE,                    -- D-2026-001
  decided_on            date,
  title                 text NOT NULL CHECK (length(btrim(title)) >= 3),
  context               text NOT NULL DEFAULT '',
  alternatives          jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(alternatives) = 'array'),
  decision              text NOT NULL CHECK (length(btrim(decision)) >= 3),
  financial_impact      jsonb CHECK (financial_impact IS NULL OR jsonb_typeof(financial_impact) = 'object'),
  status                text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED', 'APPROVED', 'REJECTED', 'DEFERRED', 'SUPERSEDED', 'WITHDRAWN')),
  conflict_kind         text NOT NULL DEFAULT 'NONE' CHECK (conflict_kind IN ('NONE', 'MARIO_INVESTMENT', 'MARIO_OWNERSHIP', 'MARIO_TECH_CONTRIBUTION',
                                                                                  'MARIO_COMPENSATION', 'OTHER_RELATED_PARTY')),
  related_party         boolean NOT NULL DEFAULT false,
  conflict_of_interest  boolean NOT NULL DEFAULT false,
  interested_members    uuid[] NOT NULL DEFAULT '{}',
  approval_basis        text CHECK (approval_basis IN ('OTHER_MEMBER', 'APPROVED_BY_OTHER_MEMBER_RELATED_PARTY')),
  approved_by           uuid[] NOT NULL DEFAULT '{}',
  approved_at           timestamptz,
  related_object        jsonb CHECK (related_object IS NULL OR jsonb_typeof(related_object) = 'object'),
  supersedes_id         uuid REFERENCES f360_board.decisions(id),
  superseded_by_id      uuid REFERENCES f360_board.decisions(id),
  revision              int NOT NULL DEFAULT 1,
  proposed_by           uuid NOT NULL,
  proposed_by_name      text NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  idempotency_key       uuid NOT NULL UNIQUE,
  CHECK ((conflict_kind <> 'NONE') = (related_party AND conflict_of_interest)),
  CHECK (NOT related_party OR cardinality(interested_members) > 0),
  CHECK (status <> 'APPROVED' OR (cardinality(approved_by) > 0 AND approval_basis IS NOT NULL)),
  CHECK (NOT (approved_by && interested_members))                 -- an interested member is never an approver
);
ALTER TABLE f360_board.decisions ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX decisions_one_successor ON f360_board.decisions (supersedes_id) WHERE supersedes_id IS NOT NULL AND status NOT IN ('REJECTED', 'WITHDRAWN');

CREATE TABLE f360_board.decision_revisions (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  decision_id   uuid NOT NULL REFERENCES f360_board.decisions(id),
  revision      int NOT NULL,
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_user       uuid, by_name text NOT NULL,
  payload       jsonb NOT NULL,
  content_hash  text NOT NULL,
  UNIQUE (decision_id, revision)
);
CREATE TABLE f360_board.decision_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  decision_id   uuid NOT NULL REFERENCES f360_board.decisions(id),
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  event         text NOT NULL CHECK (event IN ('PROPOSED', 'REVISED', 'RECUSED', 'APPROVAL_REFUSED_RECUSED', 'APPROVAL_REFUSED_PROPOSER',
                                               'APPROVED', 'REJECTED', 'DEFERRED', 'WITHDRAWN', 'SUPERSEDED')),
  by_user       uuid, by_name text NOT NULL,
  note          text
);
CREATE TABLE f360_board.decision_recusals (
  decision_id   uuid NOT NULL REFERENCES f360_board.decisions(id),
  auth_user_id  uuid NOT NULL,
  member_name   text NOT NULL,
  reason        text NOT NULL,
  recused_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (decision_id, auth_user_id)
);
ALTER TABLE f360_board.decision_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.decision_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.decision_recusals ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER decision_revisions_append_only BEFORE UPDATE OR DELETE ON f360_board.decision_revisions FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TRIGGER decision_events_append_only BEFORE UPDATE OR DELETE ON f360_board.decision_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TRIGGER decision_recusals_append_only BEFORE UPDATE OR DELETE ON f360_board.decision_recusals FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Content frozen after a final status; the conflict-of-interest facts never change; no DELETE.
CREATE FUNCTION f360_board.on_decision_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE o jsonb; n jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Este historial no se puede modificar (f360_board.decisions)'; END IF;
  IF (NEW.id, NEW.number, NEW.proposed_by, NEW.created_at, NEW.idempotency_key, NEW.conflict_kind, NEW.related_party, NEW.conflict_of_interest,
      NEW.interested_members, NEW.supersedes_id)
     IS DISTINCT FROM (OLD.id, OLD.number, OLD.proposed_by, OLD.created_at, OLD.idempotency_key, OLD.conflict_kind, OLD.related_party, OLD.conflict_of_interest,
      OLD.interested_members, OLD.supersedes_id) THEN
    RAISE EXCEPTION 'La identidad y el conflicto de interés de una decisión no cambian.';
  END IF;
  IF OLD.status IN ('APPROVED', 'REJECTED', 'SUPERSEDED', 'WITHDRAWN') THEN
    o := to_jsonb(OLD) - 'status' - 'superseded_by_id'; n := to_jsonb(NEW) - 'status' - 'superseded_by_id';
    IF NOT (OLD.status = 'APPROVED' AND NEW.status = 'SUPERSEDED' AND OLD.superseded_by_id IS NULL AND NEW.superseded_by_id IS NOT NULL AND o = n) THEN
      RAISE EXCEPTION 'Una decisión % no se modifica: crea una nueva que la sustituya.', OLD.status;
    END IF;
  ELSIF NEW.status = 'SUPERSEDED' OR NEW.superseded_by_id IS NOT NULL THEN
    RAISE EXCEPTION 'Solo una decisión aprobada puede ser sustituida.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER decisions_guard BEFORE UPDATE OR DELETE ON f360_board.decisions FOR EACH ROW EXECUTE FUNCTION f360_board.on_decision_change();

ALTER TABLE f360_board.budget_versions ADD CONSTRAINT budget_versions_decision_fk FOREIGN KEY (decision_id) REFERENCES f360_board.decisions(id);

CREATE FUNCTION f360_board.decision_event(p_id uuid, p_event text, p_uid uuid, p_note text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  INSERT INTO f360_board.decision_events (decision_id, event, by_user, by_name, note) VALUES (p_id, p_event, p_uid, f360_board.member_name(p_uid), p_note)
$$;

CREATE FUNCTION f360_board.decision_json(d f360_board.decisions, p_uid uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', d.id, 'number', d.number, 'title', d.title, 'context', d.context, 'alternatives', d.alternatives, 'decision', d.decision,
    'financial_impact', d.financial_impact, 'status', d.status, 'decided_on', d.decided_on, 'revision', d.revision,
    'conflict_kind', d.conflict_kind, 'related_party', d.related_party, 'conflict_of_interest', d.conflict_of_interest,
    'interested', (SELECT coalesce(jsonb_agg(f360_board.member_name(x)), '[]') FROM unnest(d.interested_members) x),
    'recused', (SELECT coalesce(jsonb_agg(r.member_name ORDER BY r.member_name), '[]') FROM f360_board.decision_recusals r WHERE r.decision_id = d.id),
    'i_am_recused', p_uid = ANY (d.interested_members),
    'approval_basis', d.approval_basis, 'approved_by', (SELECT coalesce(jsonb_agg(f360_board.member_name(x)), '[]') FROM unnest(d.approved_by) x),
    'approved_at', d.approved_at, 'proposed_by', d.proposed_by_name, 'proposed_by_me', d.proposed_by = p_uid,
    'supersedes', (SELECT s.number FROM f360_board.decisions s WHERE s.id = d.supersedes_id),
    'superseded_by', (SELECT s.number FROM f360_board.decisions s WHERE s.id = d.superseded_by_id), 'created_at', d.created_at)
$$;

-- Propose (sensitive write). For MARIO_* kinds the member with person_key MARIO is added as interested automatically.
CREATE FUNCTION public.f360_board_decision_propose(p_idempotency_key uuid, p_title text, p_decision text, p_context text DEFAULT '',
  p_conflict_kind text DEFAULT 'NONE', p_interested_members uuid[] DEFAULT '{}', p_financial_impact jsonb DEFAULT NULL,
  p_alternatives jsonb DEFAULT '[]', p_supersedes_id uuid DEFAULT NULL, p_related_object jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decision_propose', NULL,
    jsonb_build_object('k', p_idempotency_key, 'kind', p_conflict_kind, 'sup', p_supersedes_id));
  d f360_board.decisions; mario uuid; interested uuid[]; kind text := coalesce(p_conflict_kind, 'NONE'); x uuid; prev f360_board.decisions;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Falta la llave de idempotencia.'); END IF;
  SELECT * INTO d FROM f360_board.decisions WHERE idempotency_key = p_idempotency_key;
  IF d.id IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'replayed', true, 'decision', f360_board.decision_json(d, uid)); END IF;
  IF kind NOT IN ('NONE', 'MARIO_INVESTMENT', 'MARIO_OWNERSHIP', 'MARIO_TECH_CONTRIBUTION', 'MARIO_COMPENSATION', 'OTHER_RELATED_PARTY') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Tipo de conflicto no válido.');
  END IF;
  interested := ARRAY(SELECT DISTINCT unnest(coalesce(p_interested_members, '{}')));
  FOREACH x IN ARRAY interested LOOP
    IF NOT EXISTS (SELECT 1 FROM f360_board.board_members WHERE auth_user_id = x AND active) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Parte interesada no válida: debe ser miembro del consejo.');
    END IF;
  END LOOP;
  IF kind LIKE 'MARIO\_%' THEN
    SELECT auth_user_id INTO mario FROM f360_board.board_members WHERE person_key = 'MARIO';
    IF mario IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'No se puede registrar: falta identificar a Mario en el consejo (person_key).'); END IF;
    IF NOT (mario = ANY (interested)) THEN interested := interested || mario; END IF;
  ELSIF kind = 'OTHER_RELATED_PARTY' AND cardinality(interested) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Indica qué miembro tiene el interés.');
  ELSIF kind = 'NONE' AND cardinality(interested) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Si hay una parte interesada, marca el tipo de conflicto.');
  END IF;
  IF p_supersedes_id IS NOT NULL THEN
    SELECT * INTO prev FROM f360_board.decisions WHERE id = p_supersedes_id;
    IF prev.status IS DISTINCT FROM 'APPROVED' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo se sustituye una decisión aprobada.'); END IF;
  END IF;
  BEGIN
    INSERT INTO f360_board.decisions (number, title, context, alternatives, decision, financial_impact, conflict_kind, related_party, conflict_of_interest,
                                      interested_members, related_object, supersedes_id, proposed_by, proposed_by_name, idempotency_key)
      VALUES (format('D-%s-%s', extract(year FROM (now() AT TIME ZONE 'America/Mexico_City'))::int, lpad(nextval('f360_board.decision_number_seq')::text, 3, '0')),
              btrim(p_title), coalesce(btrim(p_context), ''), coalesce(p_alternatives, '[]'), btrim(p_decision), p_financial_impact, kind, kind <> 'NONE', kind <> 'NONE',
              interested, p_related_object, p_supersedes_id, uid, f360_board.member_name(uid), p_idempotency_key)
      RETURNING * INTO d;
  EXCEPTION WHEN check_violation OR unique_violation OR not_null_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Datos de la decisión incompletos o no válidos.');
  END;
  INSERT INTO f360_board.decision_revisions (decision_id, revision, by_user, by_name, payload, content_hash)
    VALUES (d.id, 1, uid, f360_board.member_name(uid), to_jsonb(d) - 'idempotency_key', encode(extensions.digest((to_jsonb(d) - 'idempotency_key')::text, 'sha256'), 'hex'));
  PERFORM f360_board.decision_event(d.id, 'PROPOSED', uid);
  FOREACH x IN ARRAY d.interested_members LOOP
    INSERT INTO f360_board.decision_recusals (decision_id, auth_user_id, member_name, reason)
      VALUES (d.id, x, f360_board.member_name(x), 'Parte relacionada / conflicto de interés: ' || kind);
    PERFORM f360_board.decision_event(d.id, 'RECUSED', x, kind);
  END LOOP;
  PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_propose', d.id::text, jsonb_build_object('kind', kind));
  RETURN jsonb_build_object('ok', true, 'decision', f360_board.decision_json(d, uid));
END $$;

-- Revise a PROPOSED decision (proposer only). Every revision is kept (payload + hash).
CREATE FUNCTION public.f360_board_decision_revise(p_id uuid, p_title text, p_decision text, p_context text DEFAULT '',
  p_financial_impact jsonb DEFAULT NULL, p_alternatives jsonb DEFAULT '[]') RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decision_revise', p_id::text); d f360_board.decisions;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO d FROM f360_board.decisions WHERE id = p_id FOR UPDATE;
  IF d.id IS NULL OR d.status <> 'PROPOSED' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo se revisa una decisión propuesta.'); END IF;
  IF d.proposed_by <> uid THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo quien la propuso puede revisarla.'); END IF;
  BEGIN
    UPDATE f360_board.decisions SET title = btrim(p_title), decision = btrim(p_decision), context = coalesce(btrim(p_context), ''),
        financial_impact = p_financial_impact, alternatives = coalesce(p_alternatives, '[]'), revision = revision + 1
      WHERE id = p_id RETURNING * INTO d;
  EXCEPTION WHEN check_violation OR not_null_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Datos de la decisión incompletos o no válidos.');
  END;
  INSERT INTO f360_board.decision_revisions (decision_id, revision, by_user, by_name, payload, content_hash)
    VALUES (d.id, d.revision, uid, f360_board.member_name(uid), to_jsonb(d) - 'idempotency_key', encode(extensions.digest((to_jsonb(d) - 'idempotency_key')::text, 'sha256'), 'hex'));
  PERFORM f360_board.decision_event(d.id, 'REVISED', uid, 'revisión ' || d.revision);
  PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_revise', d.id::text);
  RETURN jsonb_build_object('ok', true, 'decision', f360_board.decision_json(d, uid));
END $$;

-- Approve / reject / defer / withdraw. Approve & reject: never by an interested (recused) member; ordinary decisions by a
-- member other than the proposer (D5 default). Refusals are RETURNED (not raised) so their event + log persist.
CREATE FUNCTION public.f360_board_decision_act(p_id uuid, p_action text, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decision_act', p_id::text, jsonb_build_object('action', p_action));
  d f360_board.decisions; s f360_board.settings; prev f360_board.decisions;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_action NOT IN ('APPROVE', 'REJECT', 'DEFER', 'WITHDRAW') THEN RETURN jsonb_build_object('ok', false, 'error', 'Acción no válida.'); END IF;
  SELECT * INTO s FROM f360_board.settings WHERE id;
  SELECT * INTO d FROM f360_board.decisions WHERE id = p_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Decisión no encontrada.'); END IF;
  IF d.status NOT IN ('PROPOSED', 'DEFERRED') THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta decisión ya no está abierta.'); END IF;
  IF p_action = 'WITHDRAW' THEN
    IF d.proposed_by <> uid THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo quien la propuso puede retirarla.'); END IF;
    UPDATE f360_board.decisions SET status = 'WITHDRAWN' WHERE id = d.id RETURNING * INTO d;
    PERFORM f360_board.decision_event(d.id, 'WITHDRAWN', uid, p_note);
  ELSE
    IF uid = ANY (d.interested_members) THEN
      PERFORM f360_board.decision_event(d.id, 'APPROVAL_REFUSED_RECUSED', uid, p_action);
      PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_act:refused_recused', d.id::text);
      RETURN jsonb_build_object('ok', false, 'recused', true,
        'error', 'Tienes un conflicto de interés en esta decisión (parte relacionada): debe resolverla otra persona del consejo.');
    END IF;
    IF p_action IN ('APPROVE', 'REJECT') AND NOT d.related_party AND s.decision_requires_other_member AND d.proposed_by = uid THEN
      PERFORM f360_board.decision_event(d.id, 'APPROVAL_REFUSED_PROPOSER', uid, p_action);
      PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_act:refused_proposer', d.id::text);
      RETURN jsonb_build_object('ok', false, 'error', 'Quien propone no aprueba: debe resolverla otra persona del consejo.');
    END IF;
    IF p_action = 'APPROVE' THEN
      UPDATE f360_board.decisions SET status = 'APPROVED', approved_by = ARRAY[uid], approved_at = now(),
          decided_on = (now() AT TIME ZONE 'America/Mexico_City')::date,
          approval_basis = CASE WHEN related_party THEN 'APPROVED_BY_OTHER_MEMBER_RELATED_PARTY' ELSE 'OTHER_MEMBER' END
        WHERE id = d.id RETURNING * INTO d;
      PERFORM f360_board.decision_event(d.id, 'APPROVED', uid, coalesce(p_note, d.approval_basis));
      IF d.supersedes_id IS NOT NULL THEN
        UPDATE f360_board.decisions SET status = 'SUPERSEDED', superseded_by_id = d.id WHERE id = d.supersedes_id AND status = 'APPROVED' RETURNING * INTO prev;
        IF prev.id IS NULL THEN RAISE EXCEPTION 'La decisión sustituida ya no está aprobada.'; END IF;
        PERFORM f360_board.decision_event(prev.id, 'SUPERSEDED', uid, 'por ' || d.number);
      END IF;
    ELSIF p_action = 'REJECT' THEN
      UPDATE f360_board.decisions SET status = 'REJECTED', decided_on = (now() AT TIME ZONE 'America/Mexico_City')::date WHERE id = d.id RETURNING * INTO d;
      PERFORM f360_board.decision_event(d.id, 'REJECTED', uid, p_note);
    ELSE
      UPDATE f360_board.decisions SET status = 'DEFERRED' WHERE id = d.id RETURNING * INTO d;
      PERFORM f360_board.decision_event(d.id, 'DEFERRED', uid, p_note);
    END IF;
  END IF;
  PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_act:' || lower(p_action), d.id::text);
  RETURN jsonb_build_object('ok', true, 'decision', f360_board.decision_json(d, uid));
END $$;

CREATE FUNCTION public.f360_board_decisions(p_limit int DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decisions');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'decisions', coalesce((SELECT jsonb_agg(f360_board.decision_json(d, uid) ORDER BY d.created_at DESC)
    FROM (SELECT * FROM f360_board.decisions ORDER BY created_at DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 500))) d), '[]'));
END $$;

-- ══ 2 · Plan versions (TARGETS) with the B4 Plan 2027 link ═══════════════════
CREATE TABLE f360_board.plan_versions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key       text NOT NULL REFERENCES f360_board.reporting_entities(key),
  name             text NOT NULL,
  horizon          text NOT NULL CHECK (horizon IN ('ANNUAL', 'FIVE_YEAR')),
  number_class     text NOT NULL DEFAULT 'TARGET' CHECK (number_class = 'TARGET'),
  target_label     text NOT NULL DEFAULT 'DRAFT MANAGEMENT TARGET' CHECK (target_label = 'DRAFT MANAGEMENT TARGET'),
  status           text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PROPOSED', 'APPROVED', 'SUPERSEDED')),
  origin           text NOT NULL CHECK (origin IN ('IMPORTED_B4', 'BOARD')),
  supersedes_id    uuid REFERENCES f360_board.plan_versions(id),
  decision_id      uuid REFERENCES f360_board.decisions(id),
  created_by       uuid, created_by_name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  note             text
);
CREATE TABLE f360_board.plan_years (
  version_id       uuid NOT NULL REFERENCES f360_board.plan_versions(id),
  year             int NOT NULL CHECK (year BETWEEN 2024 AND 2100),
  theme            text,
  revenue_target   numeric(14,2) CHECK (revenue_target > 0),       -- own value (Board plans); NULL when linked
  currency         text NOT NULL DEFAULT 'MXN' REFERENCES f360.currencies(code),
  linked_source    text CHECK (linked_source IN ('f360.growth_plans')),
  linked_key       text,
  assumptions      text,
  PRIMARY KEY (version_id, year),
  CHECK ((linked_source IS NULL) = (linked_key IS NULL)),
  CHECK (NOT (linked_source IS NOT NULL AND revenue_target IS NOT NULL))   -- one source per number: linked rows never copy the amount
);
CREATE TABLE f360_board.plan_revisions (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  version_id    uuid NOT NULL REFERENCES f360_board.plan_versions(id),
  revision      int NOT NULL,
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_user       uuid, by_name text NOT NULL,
  reason        text NOT NULL,
  payload       jsonb NOT NULL,
  content_hash  text NOT NULL,
  UNIQUE (version_id, revision)
);
ALTER TABLE f360_board.plan_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.plan_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.plan_revisions ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER plan_revisions_append_only BEFORE UPDATE OR DELETE ON f360_board.plan_revisions FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Plans: content frozen outside DRAFT (approved → only SUPERSEDED); never deleted once proposed; years only in DRAFT.
CREATE FUNCTION f360_board.on_plan_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE st text;
BEGIN
  IF TG_TABLE_NAME = 'plan_versions' THEN
    IF TG_OP = 'DELETE' THEN
      IF OLD.status <> 'DRAFT' OR EXISTS (SELECT 1 FROM f360_board.plan_revisions WHERE version_id = OLD.id) THEN RAISE EXCEPTION 'Un plan con historia no se borra.'; END IF;
      RETURN OLD;
    END IF;
    IF OLD.status <> 'DRAFT' AND NOT (
         (OLD.status = 'PROPOSED' AND NEW.status IN ('APPROVED', 'DRAFT')) OR (OLD.status = 'APPROVED' AND NEW.status = 'SUPERSEDED'))
       OR (OLD.status <> 'DRAFT' AND (to_jsonb(OLD) - 'status' - 'decision_id') <> (to_jsonb(NEW) - 'status' - 'decision_id')) THEN
      RAISE EXCEPTION 'Este plan ya está %: no se modifica (duplica a un borrador nuevo).', OLD.status;
    END IF;
    RETURN NEW;
  END IF;
  SELECT status INTO st FROM f360_board.plan_versions WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.version_id ELSE NEW.version_id END;
  IF st IS DISTINCT FROM 'DRAFT' THEN RAISE EXCEPTION 'El plan está %: sus años no se modifican.', st; END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER plan_versions_guard BEFORE UPDATE OR DELETE ON f360_board.plan_versions FOR EACH ROW EXECUTE FUNCTION f360_board.on_plan_change();
CREATE TRIGGER plan_years_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.plan_years FOR EACH ROW EXECUTE FUNCTION f360_board.on_plan_change();

-- Import the existing B4 Plan 2027 (if present in this database) as a LINKED draft target. History preserved in revision 1.
DO $$
DECLARE g f360.growth_plans; v uuid; payload jsonb;
BEGIN
  SELECT * INTO g FROM f360.growth_plans WHERE plan_year = 2027;
  IF g.plan_year IS NULL THEN RAISE NOTICE 'No B4 plan for 2027 in this database: nothing imported.'; RETURN; END IF;
  INSERT INTO f360_board.plan_versions (entity_key, name, horizon, origin, created_by_name, note)
    VALUES ('fuxia', 'Plan 2027 · North Star (desde Growth B4)', 'ANNUAL', 'IMPORTED_B4', 'migration 20261015000300',
            'Importado (D12, Mario 2026-10-08). El monto se lee en vivo de f360.growth_plans (única fuente editable hasta que un plan del consejo se apruebe, D8).')
    RETURNING id INTO v;
  INSERT INTO f360_board.plan_years (version_id, year, currency, linked_source, linked_key) VALUES (v, 2027, g.currency, 'f360.growth_plans', '2027');
  payload := jsonb_build_object('imported_from', 'f360.growth_plans', 'growth_plan', to_jsonb(g),
    'growth_scenarios', (SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.kind), '[]') FROM f360.growth_scenarios s WHERE s.plan_year = 2027),
    'history', (SELECT coalesce(jsonb_agg(to_jsonb(c) - 'by_user' ORDER BY c.id), '[]') FROM f360.growth_plan_changes c WHERE c.plan_year = 2027));
  INSERT INTO f360_board.plan_revisions (version_id, revision, by_name, reason, payload, content_hash)
    VALUES (v, 1, 'migration 20261015000300', 'Importación inicial del Plan 2027 de Growth B4 (D12)', payload, encode(extensions.digest(payload::text, 'sha256'), 'hex'));
END $$;

-- Plans with resolved targets: linked rows read growth_plans LIVE (+ its change history); always labelled DRAFT MANAGEMENT TARGET.
CREATE FUNCTION public.f360_board_plans() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_plans');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'label', 'DRAFT MANAGEMENT TARGET — no es pronóstico ni resultado real',
    'plans', coalesce((SELECT jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'horizon', v.horizon, 'status', v.status, 'origin', v.origin,
        'number_class', v.number_class, 'target_label', v.target_label, 'created_at', v.created_at, 'note', v.note,
        'revisions', (SELECT count(*) FROM f360_board.plan_revisions r WHERE r.version_id = v.id),
        'years', (SELECT coalesce(jsonb_agg(jsonb_build_object('year', y.year, 'theme', y.theme, 'currency', y.currency,
            'revenue_target', CASE WHEN y.linked_source = 'f360.growth_plans' THEN (SELECT g.north_star FROM f360.growth_plans g WHERE g.plan_year::text = y.linked_key) ELSE y.revenue_target END,
            'source', coalesce(y.linked_source, 'f360_board.plan_years'),
            'imported_value', (SELECT (r.payload->'growth_plan'->>'north_star')::numeric FROM f360_board.plan_revisions r WHERE r.version_id = v.id AND r.revision = 1),
            'source_history', CASE WHEN y.linked_source = 'f360.growth_plans' THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('what', c.what, 'before', c.before->'north_star',
                  'after', c.after->'north_star', 'by', c.by_name, 'at', c.at) ORDER BY c.id), '[]') FROM f360.growth_plan_changes c WHERE c.plan_year::text = y.linked_key AND c.what = 'north_star') END)
          ORDER BY y.year), '[]') FROM f360_board.plan_years y WHERE y.version_id = v.id))
      ORDER BY v.created_at) FROM f360_board.plan_versions v), '[]'));
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_board_decision_propose(uuid, text, text, text, text, uuid[], jsonb, jsonb, uuid, jsonb),
  public.f360_board_decision_revise(uuid, text, text, text, jsonb, jsonb), public.f360_board_decision_act(uuid, text, text),
  public.f360_board_decisions(int), public.f360_board_plans() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_decision_propose(uuid, text, text, text, text, uuid[], jsonb, jsonb, uuid, jsonb),
  public.f360_board_decision_revise(uuid, text, text, text, jsonb, jsonb), public.f360_board_decision_act(uuid, text, text),
  public.f360_board_decisions(int), public.f360_board_plans() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261015000300', 'f360_board_sb0_governance_plan', '{}');

-- ════════ 20261015000400_f360_d13_intent_reports_operator.sql ════════
-- Fuxia 360 · D13 (Mario 2026-10-08) — aggregate demand / product-intent reports need OPERATOR (or owner).
-- Finding F1 (docs/fuxia360/strategy-board/14_SECURITY_MODEL.md): role_rank gives seller = viewer = 1, so these RPCs gated
-- with require_role('viewer') were callable by any vendedora straight through PostgREST, even though the admin menu hides them:
--   f360_stock_demand(text)            demand without stock (waiting customers, made-to-order pairs)     — 20261010000700
--   f360_favorites_report(text,int)    favourites intent per model incl. units sold                       — 20261012000900
--   f360_review_summary(uuid)          review facts per product                                           — 20261011000100
--   f360_store_order(text)             store ranking by units sold (last 60 days, every channel)           — 20261012000700
-- (f360_growth_plan, the Board's Plan 2027 source, is already operator+ in the live definition — checked, not touched.)
-- Change: ONLY the gate literal require_role('viewer') → require_role('operator') inside each function, taken from the LIVE
-- definition of this database (so any later redefinition in production is preserved byte for byte otherwise). Signatures,
-- grants, owners and results are unchanged. Seller flows (shift, catalog, customer find/register, record_store_sale(_for),
-- reservations) do not call these functions and are untouched.
-- Rollback: supabase/rollbacks/20261015000400_f360_d13_intent_reports_operator.down.sql (inverse replacement).

DO $$
DECLARE f text; def text; n int;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.f360_stock_demand(text)', 'public.f360_favorites_report(text,integer)', 'public.f360_review_summary(uuid)',
                           'public.f360_store_order(text)'] LOOP
    def := pg_get_functiondef(f::regprocedure);
    n := (length(def) - length(replace(def, 'require_role(''viewer'')', ''))) / length('require_role(''viewer'')');
    IF n <> 1 THEN RAISE EXCEPTION 'D13: % has % viewer gates (expected exactly 1) — review by hand', f, n; END IF;
    EXECUTE replace(def, 'require_role(''viewer'')', 'require_role(''operator'')');
  END LOOP;
END $$;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261015000400', 'f360_d13_intent_reports_operator', '{}');

-- ════════ 20261016000100_f360_board_mfa_required.sql ════════
-- Fuxia 360 · Strategy & Board · MFA MANDATORY FOR THE BOARD ONLY (Mario 2026-10-08, pre-production gate decision 1).
-- Spec: docs/fuxia360/strategy-board/01_ACCESS_MODEL.md §3.4 (D2), 14_SECURITY_MODEL.md F12; report:
-- docs/fuxia360/PRE_PRODUCTION_GATE_S-G0_SB0.md §MFA.
--
-- What changes:
--   · f360_board.settings.require_aal2 = true (the switch SB0 already built; the change is written to settings_changes by the
--     existing audit trigger). From now on every public.f360_board_* RPC answers {ok:false,"No disponible."} — and logs
--     'denied' / reason 'mfa_required' — unless the caller's verified Supabase JWT carries aal = 'aal2' (a TOTP factor was
--     verified in THIS session). Identity still comes only from the JWT (auth.uid(), auth.jwt()->>'aal').
--   · public.f360_board_nav_visible(): a member who is only missing the second factor still SEES the menu entry, so she can
--     reach /estrategia and complete the challenge (before: the entry disappeared and the member could not get to MFA).
--   · public.f360_board_access_state(): 'ok' | 'mfa_required' | 'none' about the CALLER only (no data, no other person;
--     a non-member always gets 'none', exactly like nav_visible=false). The admin uses it to show the enroll / challenge screen.
-- What does NOT change: every other Fuxia 360 RPC (sales, inventory, CRM, Growth, Medición…) keeps working at aal1 —
-- nothing outside f360_board reads the aal claim. A member who has not enrolled MFA keeps the rest of the admin and the app.
-- Membership, scopes, owner requirement, approval rules and logging are untouched.
-- Rollback: supabase/rollbacks/20261016000100_f360_board_mfa_required.down.sql

UPDATE f360_board.settings SET require_aal2 = true, updated_at = now() WHERE id AND NOT require_aal2;

-- Navigation hint ONLY (never a security decision): active member, possibly still without the second factor.
CREATE OR REPLACE FUNCTION public.f360_board_nav_visible() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce(f360_board.member_denial(auth.uid(), 'ANY'), 'ok') IN ('ok', 'mfa_required')
$$;

-- The caller's own Board access state. member_denial checks MFA LAST, so 'mfa_required' implies: session, active member,
-- owner role — only the second factor is missing. Not logged (like nav_visible); the real gate logs every Board call.
CREATE FUNCTION public.f360_board_access_state() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE coalesce(f360_board.member_denial(auth.uid(), 'ANY'), 'ok')
           WHEN 'ok' THEN 'ok' WHEN 'mfa_required' THEN 'mfa_required' ELSE 'none' END
$$;

REVOKE ALL ON FUNCTION public.f360_board_access_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_access_state() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261016000100', 'f360_board_mfa_required', '{}');

DO $$ BEGIN
  IF (SELECT require_aal2 FROM f360_board.settings) IS NOT TRUE THEN RAISE EXCEPTION 'ABORT: Board MFA not on'; END IF;
  IF EXISTS (SELECT 1 FROM f360_board.board_members) THEN RAISE EXCEPTION 'ABORT: members must come from pase P0A2 only'; END IF;
  IF has_schema_privilege('authenticated', 'f360_board', 'USAGE') OR has_schema_privilege('anon', 'f360_board', 'USAGE') THEN RAISE EXCEPTION 'ABORT: f360_board reachable'; END IF;
END $$;
COMMIT;
