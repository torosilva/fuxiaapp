-- PRE-PRODUCTION GATE S-G0 / SB0 (Mario 2026-10-08) — database tests (STAGING ONLY). One transaction, ALWAYS rolled back.
-- Needs 20261014000100..0600, 20261015000100..0400, 20261016000100..0500 and the staging board membership.
-- Output: one row per check, PASS/FAIL | name | detail.  Run: psql "$STAGING_DB_URL" -X -A -t -f supabase/staging/test_preprod_gate.sql
-- Sections: A MFA board-only · B approval rules + conflict of interest · C equal board visibility · D FX documentation ·
-- E spend sources · F tax pending · G bazaar reconciliation (synthetic fixtures, 2025) · H legacy isolation + seller denials.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text DEFAULT '') RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status, name, detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_aal text DEFAULT 'aal2', p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
      ELSE json_build_object('sub', p_uid, 'role', p_role, 'aal', p_aal)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE); END;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.new_user(p_role text, p_name text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE u uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pp-' || u || '@test.invalid', '', now(), now(), now());
  IF p_role IS NOT NULL THEN INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (u, p_role, p_name, 'test_preprod_gate'); END IF;
  RETURN u;
END $$;
-- legacy POS sale (created_by_rpc = false), as the legacy app records it: items [{quantity, unit_price}], total = Σ
CREATE FUNCTION pg_temp.legacy_sale(p_channel uuid, p_day date, p_total numeric) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.offline_sales (code, channel_id, items, total, created_at)
  VALUES ('ZZPP-' || substr(md5(random()::text), 1, 8), p_channel, jsonb_build_array(jsonb_build_object('quantity', 1, 'unit_price', p_total)), p_total,
          (p_day + time '13:00') AT TIME ZONE 'America/Mexico_City')
  RETURNING id $$;

DO $$
DECLARE car uuid; mar uuid; adr uuid; seller uuid; oper uuid; r jsonb; r2 jsonb; q text; n int; d uuid; per uuid; e1 uuid; k text;
  reads text[]; calls text[]; t0 timestamptz := clock_timestamp(); fx1 uuid;
  ch_pue uuid; ch_tij uuid; ch_mer uuid; s_m1 uuid; s_m2 uuid; s_ld uuid; s_amb_edge uuid; s_amb_other uuid; s_un uuid;
  imp jsonb; c0 bigint; h0 bigint;
BEGIN
  SELECT auth_user_id INTO car FROM f360_board.board_members WHERE person_key = 'CAROLINA';
  SELECT auth_user_id INTO mar FROM f360_board.board_members WHERE person_key = 'MARIO';
  SELECT r.auth_user_id INTO adr FROM f360.user_roles r WHERE r.role = 'owner'
    AND NOT EXISTS (SELECT 1 FROM f360_board.board_members b WHERE b.auth_user_id = r.auth_user_id) LIMIT 1;
  IF adr IS NULL THEN adr := pg_temp.new_user('owner', 'Owner técnico (test)'); END IF;
  seller := pg_temp.new_user('seller', 'Vendedora PP'); oper := pg_temp.new_user('operator', 'Operación PP');
  PERFORM pg_temp.ok(car IS NOT NULL AND mar IS NOT NULL, 'fixture: Carolina + Mario board members (by person_key)', '');
  SELECT id INTO per FROM f360_board.fiscal_periods WHERE entity_key = 'fuxia' AND kind = 'MONTH' AND fiscal_year = 2026 AND period_no = 8;

  -- ═════ A · MFA mandatory for the Board only ═════
  PERFORM pg_temp.ok((SELECT require_aal2 FROM f360_board.settings), 'A0 settings.require_aal2 = true (20261016000100)', '');
  reads := ARRAY['SELECT public.f360_board_me()', 'SELECT public.f360_board_access_log(7)', 'SELECT public.f360_board_periods(2026)',
                 format('SELECT public.f360_board_close_get(%L)', per), 'SELECT public.f360_board_metric_catalog()',
                 'SELECT public.f360_board_decisions(10)', 'SELECT public.f360_board_plans()'];
  calls := reads || ARRAY[
    format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_rent'', 100, ''MXN'', ''prueba MFA'')', per),
    'SELECT public.f360_board_close_entry_void(gen_random_uuid(), ''motivo de prueba'')',
    format('SELECT public.f360_board_close_entries_approve(%L)', per),
    format('SELECT public.f360_board_period_transition(%L, ''UNDER_REVIEW'')', per),
    'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''t'', ''d'')',
    'SELECT public.f360_board_decision_revise(gen_random_uuid(), ''t'', ''d'')',
    'SELECT public.f360_board_decision_act(gen_random_uuid(), ''APPROVE'')'];
  FOREACH d IN ARRAY ARRAY[car, mar] LOOP
    n := 0;
    FOREACH q IN ARRAY calls LOOP
      r := pg_temp.as(d, q, 'aal1');
      IF r IS DISTINCT FROM f360_board.denied() THEN n := n + 1; RAISE NOTICE 'aal1 leak % %', q, r; END IF;
    END LOOP;
    PERFORM pg_temp.ok(n = 0, 'A1 member at aal1 (no MFA in session) → every Board RPC (' || cardinality(calls) || ') answers "No disponible." — ' || f360_board.member_name(d), n || ' leaks');
    PERFORM pg_temp.ok((pg_temp.as(d, 'SELECT to_jsonb(public.f360_board_nav_visible())', 'aal1'))::text = 'true'
      AND pg_temp.as(d, 'SELECT to_jsonb(public.f360_board_access_state())', 'aal1') = '"mfa_required"'::jsonb,
      'A2 member at aal1 still sees the menu entry and gets access_state = mfa_required (so she can reach the MFA screen) — ' || f360_board.member_name(d), '');
    n := 0;
    FOREACH q IN ARRAY reads LOOP
      IF NOT coalesce((pg_temp.as(d, q, 'aal2')->>'ok')::boolean, false) THEN n := n + 1; END IF;
    END LOOP;
    PERFORM pg_temp.ok(n = 0 AND pg_temp.as(d, 'SELECT to_jsonb(public.f360_board_access_state())', 'aal2') = '"ok"'::jsonb,
      'A3 member at aal2 reads all ' || cardinality(reads) || ' Board views; access_state = ok — ' || f360_board.member_name(d), n || ' refused');
  END LOOP;
  PERFORM pg_temp.ok((SELECT count(*) FROM f360_board.access_log WHERE at >= t0 AND auth_user_id IN (car, mar) AND outcome = 'denied' AND reason = 'mfa_required') >= 2 * cardinality(calls),
    'A4 every aal1 attempt is logged as denied / mfa_required', (SELECT count(*) FROM f360_board.access_log WHERE at >= t0 AND reason = 'mfa_required')::text);
  -- generic owner / seller / operator: nothing changes with or without MFA
  n := 0;
  FOREACH q IN ARRAY reads LOOP
    IF pg_temp.as(adr, q, 'aal2') IS DISTINCT FROM f360_board.denied() THEN n := n + 1; END IF;
    IF pg_temp.as(seller, q, 'aal2') IS DISTINCT FROM f360_board.denied() THEN n := n + 1; END IF;
    IF pg_temp.as(oper, q, 'aal2') IS DISTINCT FROM f360_board.denied() THEN n := n + 1; END IF;
  END LOOP;
  PERFORM pg_temp.ok(n = 0 AND pg_temp.as(adr, 'SELECT to_jsonb(public.f360_board_access_state())', 'aal2') = '"none"'::jsonb
    AND (pg_temp.as(adr, 'SELECT to_jsonb(public.f360_board_nav_visible())', 'aal2'))::text = 'false'
    AND (pg_temp.as(seller, 'SELECT to_jsonb(public.f360_board_nav_visible())', 'aal2'))::text = 'false',
    'A5 generic owner NOT on the allowlist, seller and operator are denied even WITH aal2; access_state none, no menu', n || ' leaks');
  r := pg_temp.as(NULL, 'SELECT to_jsonb(public.f360_board_access_state())', 'aal1', 'anon');
  PERFORM pg_temp.ok(r->>'sqlstate' = '42501', 'A6 anon cannot call f360_board_access_state', coalesce(r->>'sqlstate', r::text));
  -- the rest of Fuxia 360 keeps working at aal1 for the members (MFA not enrolled must not block operations)
  r := pg_temp.as(car, 'SELECT public.f360_measurement_health()', 'aal1');
  r2 := pg_temp.as(mar, 'SELECT public.f360_hist_sales_list(2026)', 'aal1');
  PERFORM pg_temp.ok(r ? 'sources' AND r2 ? 'items' AND NOT (pg_temp.as(car, 'SELECT to_jsonb(public.f360_growth_plan(2027))', 'aal1') ? 'error'),
    'A7 members at aal1 keep using the rest of Fuxia 360 (Medición, ventas históricas, Growth plan)', left(coalesce(r->>'error', r2->>'error', ''), 100));
  PERFORM pg_temp.ok(NOT (pg_temp.as(car, 'SELECT to_jsonb(public.f360_admin_customers(''zz-no-match-zz''))', 'aal1') ? 'error'),
    'A8 Carolina at aal1 still opens Clientas (PII viewer path unaffected by Board MFA)', '');

  -- ═════ B · approval rules + conflict of interest (members at aal2) ═════
  -- B1 capturer ≠ approver
  e1 := (pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_rent'', 25000, ''MXN'', ''renta agosto (prueba)'')', per))->>'id')::uuid;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entries_approve(%L)', per));
  PERFORM pg_temp.ok(e1 IS NOT NULL AND coalesce((r->>'approved')::int, 0) = 0 AND (SELECT approved_by FROM f360_board.monthly_close_entries WHERE id = e1) IS NULL,
    'B1 the member who captured cannot approve her own capture', r::text);
  r := pg_temp.as(mar, format('SELECT public.f360_board_close_entries_approve(%L)', per));
  PERFORM pg_temp.ok((r->>'approved')::int >= 1 AND (SELECT approved_by FROM f360_board.monthly_close_entries WHERE id = e1) = mar,
    'B1b the OTHER member approves it', r::text);
  -- B2 whoever sends to review ≠ whoever closes
  r := pg_temp.as(car, format('SELECT public.f360_board_period_transition(%L, ''UNDER_REVIEW'')', per));
  r2 := pg_temp.as(car, format('SELECT public.f360_board_period_transition(%L, ''CLOSED'', NULL, ''Excepción de prueba: datos incompletos'')', per));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND NOT coalesce((r2->>'ok')::boolean, false), 'B2 the member who sent the month to review cannot close it', coalesce(r2->>'error', ''));
  r2 := pg_temp.as(mar, format('SELECT public.f360_board_period_transition(%L, ''CLOSED'', NULL, ''Excepción de prueba: datos incompletos'')', per));
  PERFORM pg_temp.ok((r2->>'ok')::boolean, 'B2b the other member closes it (with a written DATA_INCOMPLETE exception)', coalesce(r2->>'error', r2::text));
  -- B3 proposer ≠ approver (ordinary decision)
  d := (pg_temp.as(car, 'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Decisión ordinaria PP'', ''Abrir bazar de prueba'')')->'decision'->>'id')::uuid;
  r := pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d));
  r2 := pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d));
  PERFORM pg_temp.ok(d IS NOT NULL AND NOT coalesce((r->>'ok')::boolean, true) AND (r2->>'ok')::boolean, 'B3 ordinary decision: proposer cannot approve; the other member can', coalesce(r->>'error', ''));
  -- B4 Mario is RELATED PARTY / RECUSED for each Mario-related kind; Carolina is the independent approver
  FOREACH k IN ARRAY ARRAY['MARIO_INVESTMENT', 'MARIO_OWNERSHIP', 'MARIO_TECH_CONTRIBUTION', 'MARIO_COMPENSATION'] LOOP
    FOREACH d IN ARRAY ARRAY[mar, car] LOOP     -- proposed by Mario, then by Carolina
      r := pg_temp.as(d, format('SELECT public.f360_board_decision_propose(gen_random_uuid(), %L, ''Decisión de prueba'', '''', %L)', 'PP ' || k, k));
      e1 := (r->'decision'->>'id')::uuid;
      r := pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', e1));
      r2 := pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''REJECT'')', e1));
      PERFORM pg_temp.ok(e1 IS NOT NULL AND (r->>'recused')::boolean AND NOT coalesce((r2->>'ok')::boolean, true)
        AND (SELECT related_party AND mar = ANY (interested_members) FROM f360_board.decisions WHERE id = e1)
        AND EXISTS (SELECT 1 FROM f360_board.decision_recusals WHERE decision_id = e1 AND auth_user_id = mar)
        AND (SELECT count(*) FROM f360_board.decision_events WHERE decision_id = e1 AND event = 'APPROVAL_REFUSED_RECUSED') = 2,
        'B4 ' || k || ' (proposed by ' || f360_board.member_name(d) || '): Mario RELATED PARTY + RECUSED, his approve/reject refused and recorded', coalesce(r::text, ''));
      r := pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', e1));
      PERFORM pg_temp.ok((r->>'ok')::boolean AND (SELECT approval_basis = 'APPROVED_BY_OTHER_MEMBER_RELATED_PARTY' AND approved_by = ARRAY[car] FROM f360_board.decisions WHERE id = e1),
        'B4b ' || k || ' (proposed by ' || f360_board.member_name(d) || '): Carolina approves as the independent member', coalesce(r->>'error', ''));
    END LOOP;
  END LOOP;
  e1 := (pg_temp.as(mar, 'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''PP directo'', ''Escritura directa de prueba'', '''', ''MARIO_INVESTMENT'')')->'decision'->>'id')::uuid;
  BEGIN
    UPDATE f360_board.decisions SET status = 'APPROVED', approved_by = ARRAY[mar], approved_at = now(), approval_basis = 'OTHER_MEMBER' WHERE id = e1;
    PERFORM pg_temp.ok(e1 IS NULL AND false, 'B5 table refuses Mario as approver of his own matter (direct write)');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(e1 IS NOT NULL AND SQLERRM ~* 'check constraint', 'B5 even a direct table write cannot make Mario the approver of a PROPOSED Mario-related decision', left(SQLERRM, 100)); END;

  -- ═════ C · Carolina and Mario SEE the same Board (differences only in write/approval authority) ═════
  PERFORM pg_temp.ok((SELECT bool_and(scopes @> f360_board.valid_scopes() AND f360_board.valid_scopes() @> scopes) FROM f360_board.board_members WHERE person_key IN ('CAROLINA', 'MARIO'))
    AND (SELECT count(*) FROM f360_board.board_members WHERE person_key IN ('CAROLINA', 'MARIO') AND active) = 2,
    'C1 both members hold ALL scopes (no per-person hidden section)', '');
  n := 0;
  FOREACH q IN ARRAY ARRAY['SELECT public.f360_board_periods(2026)', 'SELECT public.f360_board_metric_catalog()', 'SELECT public.f360_board_plans()',
                           format('SELECT public.f360_board_close_get(%L) #- ''{period,submitted_by_me}''', per)] LOOP
    r := pg_temp.as(car, q); r2 := pg_temp.as(mar, q);
    -- strip caller-relative flags (captured_by_me / mine / my_*) before comparing
    IF regexp_replace(r::text, '"(captured_by_me|submitted_by_me|mine|is_me)": (true|false|null)', '', 'g')
       IS DISTINCT FROM regexp_replace(r2::text, '"(captured_by_me|submitted_by_me|mine|is_me)": (true|false|null)', '', 'g') THEN n := n + 1; RAISE NOTICE 'C diff on %', q; END IF;
  END LOOP;
  r := pg_temp.as(car, 'SELECT public.f360_board_decisions(500)'); r2 := pg_temp.as(mar, 'SELECT public.f360_board_decisions(500)');
  PERFORM pg_temp.ok(n = 0 AND jsonb_array_length(r->'decisions') = jsonb_array_length(r2->'decisions')
    AND (SELECT array_agg(x->>'id' ORDER BY x->>'id') FROM jsonb_array_elements(r->'decisions') x) = (SELECT array_agg(x->>'id' ORDER BY x->>'id') FROM jsonb_array_elements(r2->'decisions') x),
    'C2 periods, close, metric catalog, plans and every decision are identical for Carolina and Mario', n || ' differing views');
  r := pg_temp.as(car, 'SELECT public.f360_board_access_log(1)'); r2 := pg_temp.as(mar, 'SELECT public.f360_board_access_log(1)');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'rows') e WHERE e->>'who' = f360_board.member_name(mar))
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r2->'rows') e WHERE e->>'who' = f360_board.member_name(car))
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'rows') e WHERE NOT (e->>'member')::boolean),
    'C3 access log: each member sees the other''s accesses and non-member attempts (one shared log)', '');

  -- ═════ D · FX: documented source, monthly, approval; no invented rate ═════
  r := pg_temp.as(oper, $q$SELECT public.f360_fx_rate_propose('USD', '2025-02-01', 20.31, 'Banxico FIX promedio mensual', NULL, '2025-03-02', 'MONTHLY_AVERAGE')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'D1 a rate without source reference is refused', coalesce(r->>'error', ''));
  r := pg_temp.as(oper, $q$SELECT public.f360_fx_rate_propose('USD', '2025-02-01', 20.31, 'Banxico FIX promedio mensual', 'https://www.banxico.org.mx/SieInternet/ serie SF43718', '2025-01-15', 'MONTHLY_AVERAGE')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'D2 retrieval date before the month is refused', coalesce(r->>'error', ''));
  r := pg_temp.as(oper, $q$SELECT public.f360_fx_rate_propose('COP', '2025-02-01', 0.0049, 'Cruce TRM/FIX', 'BanRep TRM + Banxico FIX', '2025-03-02', 'OTHER')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'D3 method OTHER without an explanation is refused', coalesce(r->>'error', ''));
  r := pg_temp.as(oper, $q$SELECT public.f360_fx_rate_propose('USD', '2025-02-01', 20.31, 'Banxico FIX promedio mensual', 'https://www.banxico.org.mx/SieInternet/ serie SF43718', '2025-03-02', 'MONTHLY_AVERAGE')$q$);
  fx1 := (r->>'id')::uuid;
  PERFORM pg_temp.ok(fx1 IS NOT NULL AND f360.fx_rate_for('USD', '2025-02-10') IS NULL, 'D4 documented rate proposed by operator; NOT used until approved', r::text);
  PERFORM pg_temp.ok(pg_temp.as(oper, format('SELECT public.f360_fx_rate_approve(%L)', fx1)) ? 'error', 'D5 operator cannot approve', '');
  r := pg_temp.as(car, format('SELECT public.f360_fx_rate_approve(%L)', fx1), 'aal1');
  PERFORM pg_temp.ok((r->>'ok')::boolean AND f360.fx_rate_for('USD', '2025-02-10') = 20.31
    AND (SELECT source_reference IS NOT NULL AND source_retrieved_on = '2025-03-02' AND rate_method = 'MONTHLY_AVERAGE' FROM f360.fx_rates WHERE id = fx1),
    'D6 owner approves → rate used, with source name, reference, retrieval date and method stored', r::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.fx_rates WHERE period IN ('2026-08-01', '2026-09-01') AND status = 'approved')
    AND f360.fx_rate_for('COP', '2026-08-15') IS NULL AND f360.fx_rate_for('USD', '2026-09-15') IS NULL,
    'D7 no August / September 2026 rate exists (nothing invented) → those months stay DATA INCOMPLETE', '');
  r := pg_temp.as(car, $q$SELECT public.f360_measurement_truth('2026-08-01', '2026-09-30')$q$, 'aal1');
  PERFORM pg_temp.ok(r->'q8_net_product_revenue'->'consolidated_mxn'->>'status' = 'DATA_INCOMPLETE' AND r->'q8_net_product_revenue'->'consolidated_mxn'->'value' = 'null'::jsonb
    OR NOT EXISTS (SELECT 1 FROM f360.measurement_sales WHERE is_paid_sale AND currency <> 'MXN' AND business_date BETWEEN '2026-08-01' AND '2026-09-30'),
    'D8 consolidated MXN for Aug–Sep 2026 = DATA_INCOMPLETE (value null) while COP/USD sales lack an approved rate', (r->'q8_net_product_revenue'->'consolidated_mxn')::text);

  -- ═════ E · marketing spend sources (Meta spend exists, not configured; Google unknown) ═════
  PERFORM pg_temp.ok((SELECT spend_expected IS TRUE AND config_status = 'NOT_CONFIGURED' FROM f360.measurement_sources WHERE key = 'meta_ads')
    AND (SELECT spend_expected IS NULL AND config_status = 'NOT_CONFIGURED' FROM f360.measurement_sources WHERE key = 'google_ads'),
    'E1 Meta: spend exists = yes, source NOT_CONFIGURED; Google Ads: spend unknown (NULL), NOT_CONFIGURED', '');
  r := pg_temp.as(car, 'SELECT public.f360_measurement_truth(''2026-09-01'', ''2026-09-30'')', 'aal1');
  PERFORM pg_temp.ok(r->'q10_efficiency'->'mer'->>'status' = 'DATA_INCOMPLETE' AND r->'q10_efficiency'->'mer'->'value' = 'null'::jsonb
    AND r->'q10_efficiency'->'cac'->'value' = 'null'::jsonb AND r->'q10_efficiency'->'roas'->'value' = 'null'::jsonb
    AND (r->'q10_efficiency'->'mer'->'missing') ? 'unknown_if_google_ads_has_spend'
    AND ((r->'q10_efficiency'->'mer'->'missing') ? 'marketing_spend_missing' OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'q10_efficiency'->'mer'->'missing') m WHERE m LIKE 'meta_ads_spend_days_missing%')),
    'E2 without Meta spend loaded and Google unknown: MER / CAC / ROAS = DATA_INCOMPLETE with value null (never 0, never $0 Google)', (r->'q10_efficiency'->'mer')::text);
  PERFORM pg_temp.ok((SELECT s->>'status' FROM jsonb_array_elements(f360.sg0_source_health()) s WHERE s->>'key' = 'meta_ads') = 'NOT_CONFIGURED'
    AND (SELECT s->>'status' FROM jsonb_array_elements(f360.sg0_source_health()) s WHERE s->>'key' = 'google_ads') = 'NOT_CONFIGURED',
    'E3 health: Meta Ads and Google Ads NOT_CONFIGURED', '');

  -- ═════ F · IVA / tax pending accounting confirmation ═════
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.measurement_sales WHERE tax_status IS DISTINCT FROM 'PENDING_ACCOUNTING_CONFIRMATION' OR product_net_before_tax IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM f360.measurement_sales WHERE iva_treatment NOT IN ('tax_amount_reported_by_source', 'tax_not_separated_by_source')),
    'F1 every sale: tax_status PENDING_ACCOUNTING_CONFIRMATION, no net-of-tax figure (product_net_before_tax NULL), iva_treatment states only the source fact',
    (SELECT count(*) FROM f360.measurement_sales)::text || ' sales');
  PERFORM pg_temp.ok((SELECT coalesce(sum(m.net_product_revenue), 0) FROM f360.measurement_sales m WHERE m.sales_channel <> 'legacy_store')
                     = (SELECT coalesce(sum(c.net_product), 0) FROM f360.commerce_orders c),
    'F2 raw transaction amounts preserved (measurement net = commerce_orders.net_product, nothing removed for tax)', '');
  r := pg_temp.as(car, 'SELECT public.f360_measurement_truth()', 'aal1');
  PERFORM pg_temp.ok(r->'q8_net_product_revenue'->>'tax_status' = 'PENDING_ACCOUNTING_CONFIRMATION' AND r->'q8_net_product_revenue'->'net_of_tax'->>'status' = 'DATA_INCOMPLETE'
    AND r->'q8_net_product_revenue'->'net_of_tax'->'value' = 'null'::jsonb, 'F3 truth q8: basis RAW, net_of_tax = DATA_INCOMPLETE (null)', (r->'q8_net_product_revenue'->'net_of_tax')::text);
  r := pg_temp.as(oper, 'SELECT public.f360_measurement_sales_list(5)');
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0 OR (r->0->>'tax_status') = 'PENDING_ACCOUNTING_CONFIRMATION', 'F4 sales list carries tax_status', '');

  -- ═════ G · bazaar legacy sales vs bazaar summaries (synthetic, 2025) ═════
  INSERT INTO public.channels (name, type, location) VALUES ('Puebla', 'bazar', 'Puebla') RETURNING id INTO ch_pue;
  INSERT INTO public.channels (name, type, location) VALUES ('Tijuana', 'bazar', 'Tijuana') RETURNING id INTO ch_tij;
  INSERT INTO public.channels (name, type, location) VALUES ('Mérida', 'bazar', 'Mérida') RETURNING id INTO ch_mer;
  INSERT INTO f360.historical_sales (kind, bazaar_name, period_start, period_end, amount, pairs, created_by) VALUES
    ('bazaar', 'Bazar Puebla Angelópolis', '2025-03-10', '2025-03-12', 3000, 3, car),
    ('bazaar', 'TIJUANA - Plaza Río', '2025-04-10', '2025-04-12', 10000, 8, car);
  s_m1 := pg_temp.legacy_sale(ch_pue, '2025-03-11', 1000); s_m2 := pg_temp.legacy_sale(ch_pue, '2025-03-12', 2000);   -- Σ = summary → MATCHED
  s_ld := pg_temp.legacy_sale(ch_tij, '2025-04-11', 1500);                                                             -- inside, Σ ≠ → LIKELY_DUPLICATE
  s_amb_edge := pg_temp.legacy_sale(ch_tij, '2025-04-14', 500);                                                        -- 2 days after → AMBIGUOUS
  s_amb_other := pg_temp.legacy_sale(ch_mer, '2025-04-11', 700);                                                       -- other place, same days → AMBIGUOUS
  s_un := pg_temp.legacy_sale(ch_mer, '2025-06-01', 800);                                                              -- no summary → UNMATCHED
  PERFORM pg_temp.ok((SELECT class FROM f360.bazaar_sale_classification() WHERE sale_id = s_m1) = 'MATCHED'
    AND (SELECT class FROM f360.bazaar_sale_classification() WHERE sale_id = s_m2) = 'MATCHED'
    AND (SELECT class FROM f360.bazaar_sale_classification() WHERE sale_id = s_ld) = 'LIKELY_DUPLICATE'
    AND (SELECT class || ':' || reason FROM f360.bazaar_sale_classification() WHERE sale_id = s_amb_edge) = 'AMBIGUOUS:within_2_days_of_summary_dates'
    AND (SELECT class || ':' || reason FROM f360.bazaar_sale_classification() WHERE sale_id = s_amb_other) = 'AMBIGUOUS:summary_of_another_place_on_same_days'
    AND (SELECT class FROM f360.bazaar_sale_classification() WHERE sale_id = s_un) = 'UNMATCHED',
    'G1 classification: MATCHED (Σ = summary), LIKELY_DUPLICATE (inside, Σ ≠), AMBIGUOUS (edge / other place), UNMATCHED (no summary); accents + case + punctuation normalised',
    (SELECT string_agg(class, ',' ORDER BY sale_day) FROM f360.bazaar_sale_classification() WHERE sale_id IN (s_m1, s_m2, s_ld, s_amb_edge, s_amb_other, s_un)));
  r := pg_temp.as(oper, 'SELECT public.f360_bazaar_reconciliation_preview()');
  PERFORM pg_temp.ok(r->>'kind' = 'PREVIEW_READ_ONLY' AND (r->'by_class'->'MATCHED'->>'sales')::int >= 2 AND (r->'by_class'->'AMBIGUOUS'->>'counts_in_financial_truth')::boolean = false
    AND (r->'by_class'->'UNMATCHED'->>'counts_in_financial_truth')::boolean AND NOT (r::text ~* '"(phone|customer_phone|customer_id|email|staff_id)"'),
    'G2 preview RPC (operator): per-class counts/totals/dates/channels + per-summary comparison, no customer data', left(r->>'by_class', 120));
  PERFORM pg_temp.ok(pg_temp.as(seller, 'SELECT public.f360_bazaar_reconciliation_preview()') ? 'error'
    AND pg_temp.as(NULL, 'SELECT public.f360_bazaar_reconciliation_preview()', 'aal1', 'anon') ? 'error', 'G3 seller and anon denied', '');
  PERFORM pg_temp.ok(NOT (f360.legacy_sale_check(s_m1)->>'ok_to_import')::boolean AND (f360.legacy_sale_check(s_m1)->'issues') ? 'bazaar_reconciliation_matched'
    AND NOT (f360.legacy_sale_check(s_ld)->>'ok_to_import')::boolean AND NOT (f360.legacy_sale_check(s_amb_edge)->>'ok_to_import')::boolean
    AND NOT (f360.legacy_sale_check(s_amb_other)->>'ok_to_import')::boolean AND (f360.legacy_sale_check(s_un)->>'ok_to_import')::boolean,
    'G4 legacy validation: MATCHED / LIKELY_DUPLICATE / AMBIGUOUS are blocking; UNMATCHED passes', (f360.legacy_sale_check(s_un))::text);
  -- H · legacy isolation: importing never touches commerce facts / summaries; AMBIGUOUS & LIKELY_DUPLICATE never count
  SELECT count(*) INTO c0 FROM f360.commerce_orders; SELECT count(*) INTO h0 FROM f360.historical_sales;
  imp := pg_temp.as(car, 'SELECT public.f360_legacy_store_sales_import(true)', 'aal1');
  PERFORM pg_temp.ok((imp->>'dry_run')::boolean AND NOT EXISTS (SELECT 1 FROM f360.legacy_store_sale_imports WHERE sale_id IN (s_m1, s_ld, s_un)),
    'H1 dry run registers nothing', imp::text);
  imp := pg_temp.as(car, 'SELECT public.f360_legacy_store_sales_import(false)', 'aal1');
  PERFORM pg_temp.ok((SELECT status FROM f360.legacy_store_sale_imports WHERE sale_id = s_un) = 'imported'
    AND (SELECT bool_and(status = 'needs_review') FROM f360.legacy_store_sale_imports WHERE sale_id IN (s_m1, s_m2, s_ld, s_amb_edge, s_amb_other)),
    'H2 import: UNMATCHED → imported; MATCHED / LIKELY_DUPLICATE / AMBIGUOUS → needs_review', imp::text);
  PERFORM pg_temp.ok((SELECT is_paid_sale FROM f360.measurement_sales WHERE store_sale_id = s_un)
    AND NOT EXISTS (SELECT 1 FROM f360.measurement_sales WHERE store_sale_id IN (s_m1, s_m2, s_ld, s_amb_edge, s_amb_other) AND is_paid_sale),
    'H3 financial truth: only the UNMATCHED legacy sale counts', '');
  imp := pg_temp.as(car, 'SELECT public.f360_legacy_store_sales_import(false)', 'aal1');
  PERFORM pg_temp.ok((imp->>'candidates')::int = 0, 'H4 legacy import idempotent (re-run registers nothing new)', imp::text);
  -- Carolina loads a summary LATER that covers the already-imported sale → it stops counting at once (live guard)
  INSERT INTO f360.historical_sales (kind, bazaar_name, period_start, period_end, amount, pairs, created_by) VALUES ('bazaar', 'Merida centro', '2025-05-31', '2025-06-02', 5000, 4, car);
  PERFORM pg_temp.ok((SELECT class FROM f360.bazaar_sale_classification() WHERE sale_id = s_un) = 'LIKELY_DUPLICATE'
    AND NOT (SELECT is_paid_sale FROM f360.measurement_sales WHERE store_sale_id = s_un)
    AND (SELECT status_class FROM f360.measurement_sales WHERE store_sale_id = s_un) = 'needs_review',
    'H5 a later summary turns an imported sale into LIKELY_DUPLICATE → excluded live from financial truth (no re-import needed)', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.commerce_orders) = c0 AND (SELECT count(*) FROM f360.historical_sales) = h0 + 1,
    'H6 legacy import never writes commerce facts (commerce_orders unchanged) nor Carolina''s summaries', '');
  -- seller denials on measurement / reconciliation / reports
  n := 0;
  FOREACH q IN ARRAY ARRAY['SELECT public.f360_measurement_health()', 'SELECT public.f360_measurement_truth()', 'SELECT public.f360_measurement_sales_list(5)',
                           'SELECT public.f360_legacy_store_sales_import(true)', 'SELECT public.f360_fx_rates_list()', 'SELECT public.f360_stock_demand(''MX'')',
                           'SELECT public.f360_favorites_report(''woo_staging4'', 30)', 'SELECT public.f360_review_summary(NULL)', 'SELECT public.f360_store_order(''woo_staging4'')'] LOOP
    IF NOT (pg_temp.as(seller, q) ? 'error') THEN n := n + 1; RAISE NOTICE 'seller reached %', q; END IF;
  END LOOP;
  PERFORM pg_temp.ok(n = 0, 'H7 seller denied on every measurement / reconciliation / aggregate report RPC (9)', n || ' leaks');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail, ''), 140) FROM t_results ORDER BY n;
ROLLBACK;
