-- Fuxia 360 · PRODUCCIÓN · 20261024000200_f360_intel_inputs VERBATIM (Mario 2026-10-27: "pasa todo a produccion" / "de acuerdo").
-- Plan: docs/fuxia360/intelligence/I5_PLAN_PRODUCCION.md (earn-in: strategy-board/SB_EARNIN_DELIVERY.md). En staging desde oct.
-- Reversión: supabase/rollbacks/20261024000200_f360_intel_inputs.down.sql
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261024000200') THEN RAISE EXCEPTION 'PRE: 20261024000200 ya está'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261024000100') THEN RAISE EXCEPTION 'PRE: falta 20261024000100'; END IF;
END $$;
-- Fuxia 360 · I1a Centro de Inteligencia — INPUTS (Mario 2026-10-11, decisiones 2–4, aprobado para STAGING). ADDITIVE.
-- Builds on the board finance foundation (20261015000200/0300) and S-G0 product cost (20261014000400); nothing is copied.
--   2 · PRESUPUESTO: f360_board.budget_versions/lines already version (DRAFT → APPROVED frozen with content hash → SUPERSEDED).
--       Adds: change reason, Carolina's commercial validation, RPCs to draft / set lines / validate / approve / list.
--       Capture may be delegated (board FINANCIAL member or a finance preparer with can_budget); APPROVAL = scope 'budget' in
--       f360.approval_scopes (Mario). Approving supersedes the previous approved version of the same year; originals are kept.
--   · METAS: f360_board.goals — versioned targets (append-only; a change = a new version with reason). The $300,000 MXN monthly
--       ecommerce-MX goal is DATA, registered per environment by Mario's decision (not seeded here). Setting a goal = scope 'budget'.
--   3 · COSTOS: f360.product_cost_versions.cost_basis (generated from source): owner_estimate / other = 'estimated';
--       supplier_invoice / production_order / accounting = 'confirmed'. Validation state = status (proposed / approved / rejected).
--       Nothing else changes (Carolina is an owner: she proposes and approves through the existing RPCs).
--   4 · CIERRE (contadora): f360_board.finance_preparers — a LIMITED capability (not a board member, not an owner): capture and void
--       her own monthly-close amounts while the month is OPEN/REOPENED, and capture financial commitments. She never sees the
--       strategy, customers or users. Approval stays with the board (existing f360_board_close_entries_approve: who captures ≠ who
--       approves) — Mario or Carolina. Commitments: f360_board.financial_commitments (immutable) + events (paid / cancelled /
--       corrected / approved), every change with who, when and why.
-- Rollback: supabase/rollbacks/20261024000200_f360_intel_inputs.down.sql

-- ══ 2 · Presupuesto ═══════════════════════════════════════════════════════════════════════════════════════════════════════
ALTER TABLE f360_board.budget_versions
  ADD COLUMN change_reason                 text CHECK (change_reason IS NULL OR length(btrim(change_reason)) BETWEEN 5 AND 500),
  ADD COLUMN commercial_validated_by       uuid,
  ADD COLUMN commercial_validated_by_name  text,
  ADD COLUMN commercial_validated_at       timestamptz,
  ADD COLUMN commercial_validation_note    text CHECK (commercial_validation_note IS NULL OR length(commercial_validation_note) <= 500);

-- ══ 4 · Contadora (finance preparer) ══════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE f360_board.finance_preparers (
  auth_user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name    text NOT NULL,
  can_close       boolean NOT NULL DEFAULT true,
  can_budget      boolean NOT NULL DEFAULT false,
  active          boolean NOT NULL DEFAULT true,
  granted_at      timestamptz NOT NULL DEFAULT now(),
  granted_by_name text NOT NULL,
  evidence        text NOT NULL,           -- how the identity was verified (same rule as board_members)
  note            text
);
COMMENT ON TABLE f360_board.finance_preparers IS 'I1: limited finance capture (contadora). Not a board member: no strategy, no PII, no users. Loaded by a reviewed script.';

-- uid of the caller if allowed for p_what ('close' | 'budget'): a FINANCIAL board member, or an active preparer with that flag.
-- Every call is written to f360_board.access_log (scope FINANCIAL) like the board gate.
CREATE FUNCTION f360_board.require_finance_capture(p_what text, p_rpc text, p_object_ref text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); why text; prep f360_board.finance_preparers;
BEGIN
  IF p_what NOT IN ('close', 'budget') THEN RAISE EXCEPTION 'f360_board gate misuse'; END IF;
  why := f360_board.member_denial(uid, 'FINANCIAL');
  IF why IS NOT NULL THEN
    SELECT * INTO prep FROM f360_board.finance_preparers WHERE auth_user_id = uid AND active;
    IF prep.auth_user_id IS NOT NULL AND ((p_what = 'close' AND prep.can_close) OR (p_what = 'budget' AND prep.can_budget)) THEN
      -- same second-factor rule as the board (f360_board.settings.require_aal2)
      why := CASE WHEN coalesce((SELECT require_aal2 FROM f360_board.settings WHERE id), false) AND coalesce(auth.jwt()->>'aal', '') <> 'aal2'
                  THEN 'mfa_required' END;
    END IF;
  END IF;
  INSERT INTO f360_board.access_log (auth_user_id, rpc, scope, outcome, reason, object_ref, params_hash, request_id)
    VALUES (uid, p_rpc, 'FINANCIAL', CASE WHEN why IS NULL THEN 'allowed' ELSE 'denied' END, why, left(p_object_ref, 200), NULL, f360_board.request_id());
  RETURN CASE WHEN why IS NULL THEN uid END;
END $$;

CREATE FUNCTION f360_board.capture_name(p_uid uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT display_name FROM f360_board.finance_preparers WHERE auth_user_id = p_uid), f360_board.member_name(p_uid)) $$;

-- ── budget RPCs ──────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_board_budget_draft(p_fiscal_year int, p_name text, p_reason text, p_copy_from uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_finance_capture('budget', 'f360_board_budget_draft', p_fiscal_year::text); src f360_board.budget_versions; v uuid;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_fiscal_year IS NULL OR p_fiscal_year NOT BETWEEN 2024 AND 2100 THEN RETURN jsonb_build_object('ok', false, 'error', 'Año no válido.'); END IF;
  IF length(btrim(coalesce(p_name, ''))) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Ponle un nombre al presupuesto.'); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica el motivo de esta versión.'); END IF;
  IF p_copy_from IS NOT NULL THEN
    SELECT * INTO src FROM f360_board.budget_versions WHERE id = p_copy_from;
    IF src.id IS NULL OR src.fiscal_year <> p_fiscal_year THEN RETURN jsonb_build_object('ok', false, 'error', 'La versión de origen no es de ese año.'); END IF;
  END IF;
  INSERT INTO f360_board.budget_versions (entity_key, fiscal_year, name, supersedes_id, created_by, created_by_name, change_reason)
    VALUES ('fuxia', p_fiscal_year, btrim(p_name), p_copy_from, uid, f360_board.capture_name(uid), btrim(p_reason)) RETURNING id INTO v;
  IF p_copy_from IS NOT NULL THEN
    INSERT INTO f360_board.budget_lines (version_id, period_month, metric_key, dim_market, dim_channel, dim_location_id, dim_category_key, currency, amount, note)
      SELECT v, period_month, metric_key, dim_market, dim_channel, dim_location_id, dim_category_key, currency, amount, note FROM f360_board.budget_lines WHERE version_id = p_copy_from;
  END IF;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_budget_draft', v::text, jsonb_build_object('year', p_fiscal_year));
  RETURN jsonb_build_object('ok', true, 'id', v);
END $$;

-- Replaces ALL lines of a DRAFT (the line trigger refuses any change once approved). Lines = monthly revenue budget by market ×
-- channel in the market's currency: [{"month":"2026-11-01","market":"MX","channel":"online","amount":300000,"note":"…"}].
CREATE FUNCTION public.f360_board_budget_lines_set(p_version uuid, p_lines jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_finance_capture('budget', 'f360_board_budget_lines_set', p_version::text); v f360_board.budget_versions;
  x jsonb; i int := 0; cur text; m date;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO v FROM f360_board.budget_versions WHERE id = p_version FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'DRAFT' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo se editan borradores.'); END IF;
  IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) > 2000 THEN RETURN jsonb_build_object('ok', false, 'error', 'Líneas no válidas.'); END IF;
  FOR x IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    i := i + 1;
    cur := CASE x->>'market' WHEN 'MX' THEN 'MXN' WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' END;
    IF cur IS NULL OR x->>'channel' NOT IN ('online', 'store') OR (x->>'month') !~ '^\d{4}-\d{2}-01$'
       OR (x->>'amount') !~ '^\d+(\.\d{1,2})?$' THEN RETURN jsonb_build_object('ok', false, 'error', format('Línea %s no válida (mes, mercado MX/CO/ROW, canal online/store, monto).', i)); END IF;
    m := (x->>'month')::date;
    IF extract(year FROM m) <> v.fiscal_year THEN RETURN jsonb_build_object('ok', false, 'error', format('Línea %s: el mes no es del año %s.', i, v.fiscal_year)); END IF;
  END LOOP;
  DELETE FROM f360_board.budget_lines WHERE version_id = p_version;
  INSERT INTO f360_board.budget_lines (version_id, period_month, metric_key, dim_market, dim_channel, currency, amount, note)
    SELECT p_version, (y->>'month')::date, 'revenue_net_product', y->>'market', y->>'channel',
           CASE y->>'market' WHEN 'MX' THEN 'MXN' WHEN 'CO' THEN 'COP' ELSE 'USD' END, (y->>'amount')::numeric, nullif(btrim(coalesce(y->>'note', '')), '')
    FROM jsonb_array_elements(p_lines) y;
  -- any change after a commercial validation invalidates it (Carolina validates what is approved, not an earlier draft)
  UPDATE f360_board.budget_versions SET commercial_validated_by = NULL, commercial_validated_by_name = NULL, commercial_validated_at = NULL,
         commercial_validation_note = NULL WHERE id = p_version AND commercial_validated_at IS NOT NULL;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_budget_lines_set', p_version::text, jsonb_build_object('lines', i));
  RETURN jsonb_build_object('ok', true, 'lines', i);
END $$;

CREATE FUNCTION public.f360_board_budget_validate(p_version uuid, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_budget_validate', p_version::text);
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  UPDATE f360_board.budget_versions SET commercial_validated_by = uid, commercial_validated_by_name = f360_board.member_name(uid),
         commercial_validated_at = now(), commercial_validation_note = nullif(btrim(coalesce(p_note, '')), '')
   WHERE id = p_version AND status = 'DRAFT' AND EXISTS (SELECT 1 FROM f360_board.budget_lines WHERE version_id = p_version);
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'Borrador no encontrado o sin líneas.'); END IF;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_budget_validate', p_version::text);
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE FUNCTION public.f360_board_budget_approve(p_version uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_budget_approve', p_version::text); v f360_board.budget_versions; prev uuid[];
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF NOT f360.can_approve('budget', uid) THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo quien aprueba presupuestos puede aprobarlo.'); END IF;
  SELECT * INTO v FROM f360_board.budget_versions WHERE id = p_version FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'DRAFT' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo se aprueban borradores.'); END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_board.budget_lines WHERE version_id = p_version) THEN RETURN jsonb_build_object('ok', false, 'error', 'El presupuesto no tiene líneas.'); END IF;
  IF v.commercial_validated_at IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Falta la validación comercial (Carolina).'); END IF;
  SELECT array_agg(id) INTO prev FROM f360_board.budget_versions WHERE entity_key = v.entity_key AND fiscal_year = v.fiscal_year AND status = 'APPROVED';
  UPDATE f360_board.budget_versions SET status = 'SUPERSEDED' WHERE id = ANY (coalesce(prev, '{}'));
  UPDATE f360_board.budget_versions SET status = 'APPROVED', approved_at = now(), approved_by = ARRAY[uid] WHERE id = p_version;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_budget_approve', p_version::text, jsonb_build_object('superseded', prev));
  RETURN jsonb_build_object('ok', true, 'superseded', to_jsonb(coalesce(prev, '{}')));
END $$;

CREATE FUNCTION public.f360_board_budgets(p_fiscal_year int) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_finance_capture('budget', 'f360_board_budgets', p_fiscal_year::text);
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'can_approve', f360.can_approve('budget', uid), 'versions', (
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'status', v.status, 'reason', v.change_reason, 'supersedes', v.supersedes_id,
             'created_by', v.created_by_name, 'created_at', v.created_at, 'approved_at', v.approved_at,
             'approved_by', (SELECT string_agg(f360_board.member_name(a), ', ') FROM unnest(v.approved_by) a),
             'validated_by', v.commercial_validated_by_name, 'validated_at', v.commercial_validated_at, 'validation_note', v.commercial_validation_note,
             'content_hash', v.content_hash,
             'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object('month', l.period_month, 'market', l.dim_market, 'channel', l.dim_channel,
                         'currency', l.currency, 'amount', l.amount, 'note', l.note) ORDER BY l.period_month, l.dim_market, l.dim_channel), '[]')
                       FROM f360_board.budget_lines l WHERE l.version_id = v.id)) ORDER BY v.created_at DESC), '[]')
    FROM f360_board.budget_versions v WHERE v.fiscal_year = p_fiscal_year));
END $$;

-- ══ Metas (versioned targets) ═════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE f360_board.goals (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_key       text NOT NULL CHECK (goal_key ~ '^[a-z][a-z0-9_]*$'),
  label          text NOT NULL CHECK (length(btrim(label)) BETWEEN 3 AND 120),
  metric_key     text NOT NULL REFERENCES f360_board.metric_catalog(metric_key),
  dim_market     text CHECK (dim_market IN ('MX', 'CO', 'ROW')),
  dim_channel    text CHECK (dim_channel IN ('online', 'store')),
  currency       text NOT NULL REFERENCES f360.currencies(code),
  amount         numeric(14,2) NOT NULL CHECK (amount > 0),
  grain          text NOT NULL DEFAULT 'month' CHECK (grain = 'month'),
  effective_from date NOT NULL CHECK (effective_from = date_trunc('month', effective_from)::date),
  reason         text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 500),
  supersedes_id  uuid REFERENCES f360_board.goals(id),
  set_by         uuid NOT NULL,
  set_by_name    text NOT NULL,
  set_at         timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX goals_key_idx ON f360_board.goals (goal_key, effective_from DESC, set_at DESC);
COMMENT ON TABLE f360_board.goals IS 'I1: versioned business targets (e.g. ecommerce MX $300,000 MXN/month). Append-only; the newest version per key and month wins.';
CREATE TRIGGER goals_append_only BEFORE UPDATE OR DELETE ON f360_board.goals FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- the goal in force for a key and month (newest version with effective_from ≤ month)
CREATE FUNCTION f360_board.goal_for(p_goal_key text, p_month date) RETURNS f360_board.goals LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT * FROM f360_board.goals WHERE goal_key = p_goal_key AND effective_from <= date_trunc('month', p_month)::date
  ORDER BY effective_from DESC, set_at DESC LIMIT 1 $$;

CREATE FUNCTION public.f360_board_goal_set(p_goal_key text, p_label text, p_market text, p_channel text, p_amount numeric,
  p_effective_from date, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_goal_set', p_goal_key); prev f360_board.goals; v uuid;
  cur text := CASE p_market WHEN 'MX' THEN 'MXN' WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' END;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF NOT f360.can_approve('budget', uid) THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo quien aprueba presupuestos define metas.'); END IF;
  IF coalesce(p_goal_key, '') !~ '^[a-z][a-z0-9_]*$' OR cur IS NULL OR p_channel NOT IN ('online', 'store') OR p_amount IS NULL OR p_amount <= 0
     OR p_effective_from IS NULL OR length(btrim(coalesce(p_reason, ''))) < 5 OR length(btrim(coalesce(p_label, ''))) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Meta no válida (clave, nombre, mercado, canal, monto, desde, motivo).');
  END IF;
  prev := f360_board.goal_for(p_goal_key, p_effective_from);
  INSERT INTO f360_board.goals (goal_key, label, metric_key, dim_market, dim_channel, currency, amount, effective_from, reason, supersedes_id, set_by, set_by_name)
    VALUES (p_goal_key, btrim(p_label), 'revenue_net_product', p_market, p_channel, cur, round(p_amount, 2), date_trunc('month', p_effective_from)::date,
            btrim(p_reason), prev.id, uid, f360_board.member_name(uid)) RETURNING id INTO v;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_goal_set', v::text, jsonb_build_object('key', p_goal_key, 'amount', p_amount));
  RETURN jsonb_build_object('ok', true, 'id', v, 'supersedes', prev.id);
END $$;

CREATE FUNCTION public.f360_board_goals() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_goals');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'can_set', f360.can_approve('budget', uid), 'goals', (
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'key', goal_key, 'label', label, 'market', dim_market, 'channel', dim_channel, 'currency', currency,
             'amount', amount, 'from', effective_from, 'reason', reason, 'by', set_by_name, 'at', set_at, 'supersedes', supersedes_id)
             ORDER BY goal_key, effective_from DESC, set_at DESC), '[]') FROM f360_board.goals));
END $$;

-- ══ 3 · Costo estimado vs confirmado ══════════════════════════════════════════════════════════════════════════════════════
ALTER TABLE f360.product_cost_versions ADD COLUMN cost_basis text GENERATED ALWAYS AS
  (CASE WHEN source IN ('supplier_invoice', 'production_order', 'accounting') THEN 'confirmed' ELSE 'estimated' END) STORED;
COMMENT ON COLUMN f360.product_cost_versions.cost_basis IS 'I1 (Mario 2026-10-11): estimated (owner_estimate, other) vs confirmed (invoice, production order, accounting). Derived from source; never typed.';
CREATE OR REPLACE VIEW f360.product_cost_effective AS
  SELECT c.id, c.product_id, c.variant_id, c.market, c.cost_amount, c.currency, c.effective_from, c.effective_to, c.source,
         c.created_by_name, c.approved_by_name, c.approved_at, c.cost_basis
  FROM f360.product_cost_versions c WHERE c.status = 'approved';

-- ══ 4 · Cierre: captura de la contadora ═══════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.f360_close_prep_context() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_finance_capture('close', 'f360_close_prep_context');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'me', f360_board.capture_name(uid),
    'accounts', (SELECT coalesce(jsonb_agg(jsonb_build_object('key', account_key, 'label', label, 'component', component, 'kind', balance_kind,
                   'allow_negative', allow_negative) ORDER BY sort), '[]') FROM f360_board.close_accounts WHERE active),
    'periods', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'month', p.period_start, 'status', p.status,
                  'entries', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'account', e.account_key, 'dimension', e.dimension_key, 'amount', e.amount,
                                'currency', e.currency, 'source', e.source, 'evidence', e.evidence_ref, 'note', e.note, 'status', e.status,
                                'captured_by', e.captured_by_name, 'captured_at', e.captured_at, 'mine', e.captured_by = uid,
                                'approved_by', e.approved_by_name, 'approved_at', e.approved_at, 'void_reason', e.void_reason) ORDER BY e.captured_at), '[]')
                              FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id)) ORDER BY p.period_start DESC), '[]')
                FROM f360_board.fiscal_periods p WHERE p.kind = 'MONTH' AND p.period_start <= now() AND p.period_start >= (now() - interval '13 months')),
    'commitments', (SELECT coalesce(jsonb_agg(c ORDER BY c->>'due_date'), '[]') FROM f360_board.commitments_current_json() c));
END $$;

CREATE FUNCTION public.f360_close_prep_entry_add(p_idempotency_key uuid, p_period_id uuid, p_account_key text, p_amount numeric,
  p_currency text, p_source text, p_evidence_ref text DEFAULT NULL, p_note text DEFAULT NULL, p_dimension_key text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_finance_capture('close', 'f360_close_prep_entry_add', p_period_id::text);
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
              nullif(btrim(p_note), ''), uid, f360_board.capture_name(uid), p_idempotency_key)
      RETURNING * INTO e;
  EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Ya hay un monto activo para esa cuenta y moneda: anúlalo primero.');
    WHEN foreign_key_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Mes no encontrado.');
    WHEN raise_exception OR check_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'No se pudo guardar: ' || SQLERRM);
  END;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_close_prep_entry_add', e.id::text, jsonb_build_object('period', p_period_id, 'account', a.account_key));
  RETURN jsonb_build_object('ok', true, 'id', e.id);
END $$;

-- a preparer voids only her OWN, not yet approved capture (with a reason); board members keep f360_board_close_entry_void
CREATE FUNCTION public.f360_close_prep_entry_void(p_entry_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_finance_capture('close', 'f360_close_prep_entry_void', p_entry_id::text);
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica por qué se anula.'); END IF;
  BEGIN
    UPDATE f360_board.monthly_close_entries SET status = 'voided', void_reason = btrim(p_reason), voided_by = uid, voided_at = now()
      WHERE id = p_entry_id AND status = 'active' AND captured_by = uid AND approved_by IS NULL;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo anulas tus capturas que aún no se aprueban.'); END IF;
  EXCEPTION WHEN raise_exception THEN RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_close_prep_entry_void', p_entry_id::text);
  RETURN jsonb_build_object('ok', true);
END $$;

-- ── compromisos financieros ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360_board.financial_commitments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind             text NOT NULL CHECK (kind IN ('proveedor', 'produccion', 'renta', 'nomina', 'impuestos', 'credito', 'servicios', 'otro')),
  counterparty     text NOT NULL CHECK (length(btrim(counterparty)) BETWEEN 2 AND 120),   -- company / concept, never a customer
  description      text CHECK (description IS NULL OR length(description) <= 300),
  due_date         date NOT NULL,
  amount           numeric(14,2) NOT NULL CHECK (amount > 0 AND amount < 1e12),
  currency         text NOT NULL REFERENCES f360.currencies(code),
  recurrence       text NOT NULL DEFAULT 'una_vez' CHECK (recurrence IN ('una_vez', 'mensual')),
  source           text NOT NULL CHECK (length(btrim(source)) >= 3),
  evidence_ref     text,
  corrects_id      uuid REFERENCES f360_board.financial_commitments(id),
  captured_by      uuid NOT NULL,
  captured_by_name text NOT NULL,
  captured_at      timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER financial_commitments_append_only BEFORE UPDATE OR DELETE ON f360_board.financial_commitments FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TABLE f360_board.financial_commitment_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  commitment_id uuid NOT NULL REFERENCES f360_board.financial_commitments(id),
  action        text NOT NULL CHECK (action IN ('approved', 'paid', 'cancelled', 'corrected')),
  reason        text,
  by_uid        uuid NOT NULL,
  by_name       text NOT NULL,
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT fce_reason CHECK (action = 'approved' OR length(btrim(coalesce(reason, ''))) >= 5)
);
CREATE TRIGGER financial_commitment_events_append_only BEFORE UPDATE OR DELETE ON f360_board.financial_commitment_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
COMMENT ON TABLE f360_board.financial_commitments IS 'I1: upcoming payments (suppliers, production, rent, payroll, taxes, credit). Immutable; corrections = new row (corrects_id) + event.';

CREATE VIEW f360_board.commitments_current AS
SELECT c.*,
  CASE WHEN EXISTS (SELECT 1 FROM f360_board.financial_commitment_events e WHERE e.commitment_id = c.id AND e.action = 'corrected') THEN 'corregido'
       WHEN EXISTS (SELECT 1 FROM f360_board.financial_commitment_events e WHERE e.commitment_id = c.id AND e.action = 'cancelled') THEN 'cancelado'
       WHEN EXISTS (SELECT 1 FROM f360_board.financial_commitment_events e WHERE e.commitment_id = c.id AND e.action = 'paid') THEN 'pagado'
       ELSE 'pendiente' END AS state,
  (SELECT e.by_name FROM f360_board.financial_commitment_events e WHERE e.commitment_id = c.id AND e.action = 'approved' ORDER BY e.at LIMIT 1) AS approved_by_name,
  (SELECT e.at FROM f360_board.financial_commitment_events e WHERE e.commitment_id = c.id AND e.action = 'approved' ORDER BY e.at LIMIT 1) AS approved_at
FROM f360_board.financial_commitments c;

CREATE FUNCTION f360_board.commitments_current_json() RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', id, 'kind', kind, 'counterparty', counterparty, 'description', description, 'due_date', due_date, 'amount', amount,
           'currency', currency, 'recurrence', recurrence, 'source', source, 'evidence', evidence_ref, 'corrects', corrects_id, 'state', state,
           'captured_by', captured_by_name, 'captured_at', captured_at, 'approved_by', approved_by_name, 'approved_at', approved_at)
  FROM f360_board.commitments_current WHERE state IN ('pendiente', 'pagado') AND (state = 'pendiente' OR due_date >= current_date - 60) $$;

CREATE FUNCTION public.f360_finance_commitment_add(p_kind text, p_counterparty text, p_description text, p_due_date date, p_amount numeric,
  p_currency text, p_recurrence text, p_source text, p_evidence_ref text DEFAULT NULL, p_corrects uuid DEFAULT NULL, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_finance_capture('close', 'f360_finance_commitment_add', p_counterparty); v uuid; st text;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_kind NOT IN ('proveedor', 'produccion', 'renta', 'nomina', 'impuestos', 'credito', 'servicios', 'otro') OR length(btrim(coalesce(p_counterparty, ''))) < 2
     OR p_due_date IS NULL OR p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR coalesce(p_recurrence, 'una_vez') NOT IN ('una_vez', 'mensual')
     OR length(btrim(coalesce(p_source, ''))) < 3 OR NOT EXISTS (SELECT 1 FROM f360.currencies WHERE code = p_currency) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Compromiso no válido (tipo, a quién, fecha, monto, moneda, fuente).');
  END IF;
  IF p_corrects IS NOT NULL THEN
    SELECT state INTO st FROM f360_board.commitments_current WHERE id = p_corrects;
    IF st IS NULL OR st <> 'pendiente' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo se corrige un compromiso pendiente.'); END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica la corrección.'); END IF;
  END IF;
  INSERT INTO f360_board.financial_commitments (kind, counterparty, description, due_date, amount, currency, recurrence, source, evidence_ref, corrects_id,
                                                captured_by, captured_by_name)
    VALUES (p_kind, btrim(p_counterparty), nullif(btrim(coalesce(p_description, '')), ''), p_due_date, p_amount, p_currency, coalesce(p_recurrence, 'una_vez'),
            btrim(p_source), nullif(btrim(coalesce(p_evidence_ref, '')), ''), p_corrects, uid, f360_board.capture_name(uid)) RETURNING id INTO v;
  IF p_corrects IS NOT NULL THEN
    INSERT INTO f360_board.financial_commitment_events (commitment_id, action, reason, by_uid, by_name)
      VALUES (p_corrects, 'corrected', btrim(p_reason) || ' → ' || v::text, uid, f360_board.capture_name(uid));
  END IF;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_finance_commitment_add', v::text);
  RETURN jsonb_build_object('ok', true, 'id', v);
END $$;

-- paid / cancelled (preparer or board, with reason); approved (board FINANCIAL only, never the person who captured it)
CREATE FUNCTION public.f360_finance_commitment_event(p_id uuid, p_action text, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid; c f360_board.commitments_current;
BEGIN
  IF p_action = 'approved' THEN uid := f360_board.require_board_member('FINANCIAL', 'f360_finance_commitment_event', p_id::text);
  ELSE uid := f360_board.require_finance_capture('close', 'f360_finance_commitment_event', p_id::text); END IF;
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO c FROM f360_board.commitments_current WHERE id = p_id;
  IF c.id IS NULL OR c.state <> 'pendiente' THEN RETURN jsonb_build_object('ok', false, 'error', 'Compromiso no encontrado o ya no está pendiente.'); END IF;
  IF p_action NOT IN ('approved', 'paid', 'cancelled') THEN RETURN jsonb_build_object('ok', false, 'error', 'Acción no válida.'); END IF;
  IF p_action = 'approved' AND (c.captured_by = uid OR c.approved_at IS NOT NULL) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Lo aprueba otra persona del consejo, una sola vez.');
  END IF;
  IF p_action <> 'approved' AND length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica el motivo.'); END IF;
  INSERT INTO f360_board.financial_commitment_events (commitment_id, action, reason, by_uid, by_name)
    VALUES (p_id, p_action, nullif(btrim(coalesce(p_reason, '')), ''), uid, f360_board.capture_name(uid));
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_finance_commitment_event', p_id::text, jsonb_build_object('action', p_action));
  RETURN jsonb_build_object('ok', true);
END $$;

-- ── grants ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE f360_board.finance_preparers ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.financial_commitments ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.financial_commitment_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360_board.finance_preparers, f360_board.goals, f360_board.financial_commitments, f360_board.financial_commitment_events,
  f360_board.commitments_current FROM PUBLIC, anon, authenticated, service_role;
-- SB0 convention: f360_board is deny-all, service_role included (only SECURITY DEFINER RPCs reach it). No Edge Function reads
-- these tables; an earlier draft granted them to service_role and test_sb0_access T0 caught it after the prod-ACL refresh.
REVOKE ALL ON FUNCTION f360_board.require_finance_capture(text, text, text), f360_board.capture_name(uuid), f360_board.goal_for(text, date),
  f360_board.commitments_current_json() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_board_budget_draft(int, text, text, uuid), public.f360_board_budget_lines_set(uuid, jsonb), public.f360_board_budget_validate(uuid, text),
  public.f360_board_budget_approve(uuid), public.f360_board_budgets(int), public.f360_board_goal_set(text, text, text, text, numeric, date, text), public.f360_board_goals(),
  public.f360_close_prep_context(), public.f360_close_prep_entry_add(uuid, uuid, text, numeric, text, text, text, text, text), public.f360_close_prep_entry_void(uuid, text),
  public.f360_finance_commitment_add(text, text, text, date, numeric, text, text, text, text, uuid, text), public.f360_finance_commitment_event(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_budget_draft(int, text, text, uuid), public.f360_board_budget_lines_set(uuid, jsonb), public.f360_board_budget_validate(uuid, text),
  public.f360_board_budget_approve(uuid), public.f360_board_budgets(int), public.f360_board_goal_set(text, text, text, text, numeric, date, text), public.f360_board_goals(),
  public.f360_close_prep_context(), public.f360_close_prep_entry_add(uuid, uuid, text, numeric, text, text, text, text, text), public.f360_close_prep_entry_void(uuid, text),
  public.f360_finance_commitment_add(text, text, text, date, numeric, text, text, text, text, uuid, text), public.f360_finance_commitment_event(uuid, text, text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261024000200', 'f360_intel_inputs', '{}');
COMMIT;
