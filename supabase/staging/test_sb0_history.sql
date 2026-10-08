-- Strategy & Board SB0 — HISTORY / CLOSE / CONFLICT-OF-INTEREST / PLAN tests (STAGING). NEVER commits: ends with RAISE 'ENSAYO OK'.
-- Run inside a transaction AFTER 20261015000100..0400 + supabase/staging/sb0_board_members_staging.sql (rehearsal: prepend them).
-- Covers: 8 historical records cannot be silently overwritten (close snapshots, period events, close log, forecast snapshots,
-- approved budget, decisions, plan revisions, member changes) · monthly close OPEN→UNDER_REVIEW→CLOSED→REOPENED with
-- capture ≠ approval and DATA_INCOMPLETE exception · D10B related-party / recusal / approved-by-other-member · D12 Plan 2027 link.
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    SET LOCAL ROLE authenticated;
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE); END;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;
-- runs a statement as the database owner and returns the error text (NULL = it was allowed)
CREATE FUNCTION pg_temp.try(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END;
  RETURN NULL;
END $$;

DO $$
DECLARE car uuid; mar uuid; per uuid; r jsonb; e1 uuid; e2 uuid; e3 uuid; h1 text; d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid;
  fv uuid; bv uuid; err text; gp numeric; pv uuid;
BEGIN
  SELECT auth_user_id INTO car FROM f360_board.board_members WHERE person_key = 'CAROLINA';
  SELECT auth_user_id INTO mar FROM f360_board.board_members WHERE person_key = 'MARIO';
  IF car IS NULL OR mar IS NULL THEN RAISE EXCEPTION 'fixture: Carolina/Mario board members missing'; END IF;
  SELECT id INTO per FROM f360_board.fiscal_periods WHERE entity_key = 'fuxia' AND kind = 'MONTH' AND fiscal_year = 2026 AND period_no = 9;

  -- ── D11 fiscal calendar ────────────────────────────────────────────────────
  IF (SELECT count(*) FROM f360_board.fiscal_periods WHERE fiscal_year = 2027 AND kind = 'MONTH') <> 12
     OR (SELECT count(*) FROM f360_board.fiscal_periods WHERE fiscal_year = 2027 AND kind = 'QUARTER') <> 4
     OR (SELECT period_start || '/' || period_end FROM f360_board.fiscal_periods WHERE fiscal_year = 2027 AND kind = 'YEAR') <> '2027-01-01/2027-12-31'
     OR (SELECT period_start || '/' || period_end FROM f360_board.fiscal_periods WHERE fiscal_year = 2027 AND kind = 'QUARTER' AND period_no = 4) <> '2027-10-01/2027-12-31' THEN
    RAISE EXCEPTION 'FAIL D11 calendar';
  END IF;
  IF pg_temp.try(format('INSERT INTO f360_board.fiscal_periods (entity_key, kind, fiscal_year, period_no, period_start, period_end, status) VALUES (''fuxia'', ''MONTH'', 2028, 1, ''2028-01-15'', ''2028-02-14'', ''OPEN'')')) IS NULL
    THEN RAISE EXCEPTION 'FAIL D11 non-calendar month accepted'; END IF;
  RAISE NOTICE 'PASS D11 fiscal year = calendar: 12 months + 4 quarters + 1 year per year; non-calendar periods rejected';

  -- ── Monthly close: capture ≠ approve, review, close with DATA_INCOMPLETE exception ──
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(%L, %L, ''cogs'', 50000, ''MXN'', ''factura proveedor (prueba)'')', '11111111-1111-4111-8111-000000000001', per));
  e1 := (r->>'id')::uuid;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(%L, %L, ''cogs'', 50000, ''MXN'', ''factura proveedor (prueba)'')', '11111111-1111-4111-8111-000000000001', per));
  IF NOT (r->>'replayed')::boolean OR (r->>'id')::uuid <> e1 THEN RAISE EXCEPTION 'FAIL close idempotency %', r; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''cogs'', 1, ''MXN'', ''otra fuente'')', per));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL second active COGS MXN accepted'; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_rent'', -5, ''MXN'', ''renta'')', per));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL negative OPEX accepted'; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_rent'', 10, ''EUR'', ''renta'')', per));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL unknown currency accepted'; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''revenue'', 10, ''MXN'', ''ventas'')', per));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL sales captured in close (sales come from G1)'; END IF;
  e2 := (pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''cash_bank'', -2500.75, ''MXN'', ''estado de cuenta (prueba)'', NULL, NULL, ''bbva'')', per))->>'id')::uuid;
  IF e2 IS NULL THEN RAISE EXCEPTION 'FAIL negative bank balance (allowed) refused'; END IF;
  e3 := (pg_temp.as(mar, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_rent'', 30000, ''MXN'', ''contrato renta (prueba)'')', per))->>'id')::uuid;
  IF pg_temp.try(format('UPDATE f360_board.monthly_close_entries SET amount = 1 WHERE id = %L', e1)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 amount silently edited'; END IF;
  IF pg_temp.try(format('DELETE FROM f360_board.monthly_close_entries WHERE id = %L', e1)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 capture deleted'; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entries_approve(%L)', per));
  IF (r->>'approved')::int <> 1 OR (r->>'pending_own')::int <> 2 THEN RAISE EXCEPTION 'FAIL approve: Carolina must approve only Mario''s capture %', r; END IF;
  IF pg_temp.try(format('UPDATE f360_board.monthly_close_entries SET approved_by = captured_by, approved_by_name = ''x'', approved_at = now() WHERE id = %L', e1)) IS NULL
    THEN RAISE EXCEPTION 'FAIL self-approval possible directly'; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_period_transition(%L, ''UNDER_REVIEW'')', per));
  IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL to review %', r; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_tech'', 10, ''MXN'', ''tarde'')', per));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL capture while UNDER_REVIEW'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_period_transition(%L, ''CLOSED'', NULL, ''Cierre de prueba'')', per));
  IF (r->>'ok')::boolean OR r->>'error' NOT LIKE '%sin aprobar%' THEN RAISE EXCEPTION 'FAIL close with unapproved captures %', r; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_close_entries_approve(%L)', per));
  IF (r->>'approved')::int <> 2 THEN RAISE EXCEPTION 'FAIL Mario approves Carolina captures %', r; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_period_transition(%L, ''CLOSED'', NULL, ''Excepción: ventas y gasto aún no conectados'')', per));
  IF (r->>'ok')::boolean OR r->>'error' NOT LIKE 'Otra persona%' THEN RAISE EXCEPTION 'FAIL the preparer closed her own month %', r; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_period_transition(%L, ''CLOSED'')', per));
  IF (r->>'ok')::boolean OR NOT (r ? 'readiness') THEN RAISE EXCEPTION 'FAIL closed with DATA_INCOMPLETE and no exception %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'readiness') x WHERE x->>'component' = 'marketing_spend' AND x->>'status' = 'DATA_INCOMPLETE')
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'readiness') x WHERE x->>'component' = 'cogs' AND x->>'status' = 'AVAILABLE')
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'readiness') x WHERE x->>'component' = 'opex' AND x->>'status' = 'PARTIAL')
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'readiness') x WHERE x->>'component' = 'sales' AND x->>'status' = 'DATA_INCOMPLETE') THEN
    RAISE EXCEPTION 'FAIL readiness %', r->'readiness';
  END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_period_transition(%L, ''CLOSED'', NULL, ''Excepción: ventas, gasto e inventario aún no conectados (SB1/S-G0)'')', per));
  IF NOT (r->>'ok')::boolean OR (r->>'close_version')::int <> 1 THEN RAISE EXCEPTION 'FAIL close v1 %', r; END IF;
  SELECT content_hash INTO h1 FROM f360_board.close_actual_snapshots WHERE period_id = per AND close_version = 1;
  IF h1 IS NULL OR (SELECT prepared_by FROM f360_board.close_actual_snapshots WHERE period_id = per AND close_version = 1) <> car
     OR (SELECT approved_by FROM f360_board.close_actual_snapshots WHERE period_id = per AND close_version = 1) <> mar THEN RAISE EXCEPTION 'FAIL snapshot v1 who'; END IF;
  RAISE NOTICE 'PASS CLOSE capture (idempotent, one active per account+currency, sign/currency/account validated, no sales in close) → approval by the OTHER member → UNDER_REVIEW → CLOSED by the other member only with all captures approved and an explicit DATA_INCOMPLETE exception → snapshot v1 (prepared by Carolina, approved by Mario)';

  -- ── 8 · nothing historical can be silently overwritten ─────────────────────
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_void(%L, ''monto equivocado'')', e1));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL T8 void in CLOSED month'; END IF;
  IF pg_temp.try(format('UPDATE f360_board.close_actual_snapshots SET payload = ''{}'' WHERE period_id = %L', per)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 snapshot edited'; END IF;
  IF pg_temp.try(format('DELETE FROM f360_board.close_actual_snapshots WHERE period_id = %L', per)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 snapshot deleted'; END IF;
  IF pg_temp.try(format('UPDATE f360_board.fiscal_periods SET status = ''OPEN'' WHERE id = %L', per)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 closed month silently reopened'; END IF;
  IF pg_temp.try(format('UPDATE f360_board.fiscal_periods SET close_version = 7 WHERE id = %L', per)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 close version edited'; END IF;
  IF pg_temp.try(format('DELETE FROM f360_board.fiscal_periods WHERE id = %L', per)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 period deleted'; END IF;
  IF pg_temp.try('UPDATE f360_board.fiscal_period_events SET reason = ''x''') IS NULL OR pg_temp.try('DELETE FROM f360_board.monthly_close_log') IS NULL
     OR pg_temp.try('UPDATE f360_board.board_member_changes SET after = NULL') IS NULL THEN RAISE EXCEPTION 'FAIL T8 event/log tables editable'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_period_transition(%L, ''REOPENED'', ''corto'')', per));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL T8 reopen without a real reason'; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_period_transition(%L, ''REOPENED'', ''Llegó la factura real del proveedor'')', per));
  IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL reopen %', r; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_void(%L, ''monto equivocado'')', e1));
  IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL void after reopen %', r; END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''cogs'', 48250.10, ''MXN'', ''factura real proveedor (prueba)'')', per));
  IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL recapture %', r; END IF;
  PERFORM pg_temp.as(mar, format('SELECT public.f360_board_close_entries_approve(%L)', per));
  PERFORM pg_temp.as(mar, format('SELECT public.f360_board_period_transition(%L, ''UNDER_REVIEW'')', per));
  r := pg_temp.as(car, format('SELECT public.f360_board_period_transition(%L, ''CLOSED'', NULL, ''Excepción: ventas, gasto e inventario aún no conectados'')', per));
  IF NOT (r->>'ok')::boolean OR (r->>'close_version')::int <> 2 THEN RAISE EXCEPTION 'FAIL close v2 %', r; END IF;
  IF (SELECT content_hash FROM f360_board.close_actual_snapshots WHERE period_id = per AND close_version = 1) <> h1
     OR (SELECT count(*) FROM f360_board.close_actual_snapshots WHERE period_id = per) <> 2 THEN RAISE EXCEPTION 'FAIL T8 v1 snapshot changed'; END IF;
  IF (SELECT status FROM f360_board.monthly_close_entries WHERE id = e1) <> 'voided'
     OR (SELECT count(*) FROM f360_board.monthly_close_log WHERE entry_id = e1) <> 3 THEN RAISE EXCEPTION 'FAIL T8 void+new history'; END IF;
  IF (SELECT string_agg(to_status, '>' ORDER BY id) FROM f360_board.fiscal_period_events WHERE period_id = per) <> 'UNDER_REVIEW>CLOSED>REOPENED>UNDER_REVIEW>CLOSED'
     OR (SELECT reason FROM f360_board.fiscal_period_events WHERE period_id = per AND to_status = 'REOPENED') <> 'Llegó la factura real del proveedor' THEN
    RAISE EXCEPTION 'FAIL T8 period event history';
  END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_close_get(%L)', per));
  IF jsonb_array_length(r->'snapshots') <> 2 OR jsonb_array_length(r->'events') <> 5 THEN RAISE EXCEPTION 'FAIL close_get history %', r; END IF;

  -- forecast: publish freezes + immutable snapshot; budget: approved frozen
  INSERT INTO f360_board.forecast_versions (entity_key, name, window_start, created_by_name) VALUES ('fuxia', 'FC prueba', '2026-10-01', 'test') RETURNING id INTO fv;
  INSERT INTO f360_board.forecast_lines (version_id, period_month, metric_key, method, currency, amount, note) VALUES (fv, '2026-11-01', 'revenue_net_product', 'MANUAL', 'MXN', 900000, 'supuesto de prueba');
  UPDATE f360_board.forecast_versions SET status = 'PUBLISHED', published_at = now() WHERE id = fv;
  IF (SELECT count(*) FROM f360_board.forecast_snapshots WHERE version_id = fv) <> 1 THEN RAISE EXCEPTION 'FAIL T8 publish without snapshot'; END IF;
  IF pg_temp.try(format('UPDATE f360_board.forecast_lines SET amount = 1 WHERE version_id = %L', fv)) IS NULL
     OR pg_temp.try(format('INSERT INTO f360_board.forecast_lines (version_id, period_month, metric_key, method, currency, amount, note) VALUES (%L, ''2026-12-01'', ''orders'', ''MANUAL'', ''MXN'', 1, ''x'')', fv)) IS NULL
     OR pg_temp.try(format('DELETE FROM f360_board.forecast_lines WHERE version_id = %L', fv)) IS NULL
     OR pg_temp.try(format('UPDATE f360_board.forecast_versions SET name = ''otro'' WHERE id = %L', fv)) IS NULL
     OR pg_temp.try(format('UPDATE f360_board.forecast_versions SET status = ''DRAFT'' WHERE id = %L', fv)) IS NULL
     OR pg_temp.try(format('DELETE FROM f360_board.forecast_versions WHERE id = %L', fv)) IS NULL
     OR pg_temp.try(format('UPDATE f360_board.forecast_snapshots SET payload = ''{}'' WHERE version_id = %L', fv)) IS NULL THEN
    RAISE EXCEPTION 'FAIL T8 published forecast could be overwritten';
  END IF;
  IF pg_temp.try(format('UPDATE f360_board.forecast_versions SET status = ''SUPERSEDED'' WHERE id = %L', fv)) IS NOT NULL THEN RAISE EXCEPTION 'FAIL supersede forecast'; END IF;
  INSERT INTO f360_board.budget_versions (entity_key, fiscal_year, name, created_by_name) VALUES ('fuxia', 2027, 'Budget prueba', 'test') RETURNING id INTO bv;
  INSERT INTO f360_board.budget_lines (version_id, period_month, metric_key, currency, amount) VALUES (bv, '2027-01-01', 'revenue_net_product', 'MXN', 1000000);
  UPDATE f360_board.budget_versions SET status = 'APPROVED', approved_at = now(), approved_by = ARRAY[car, mar] WHERE id = bv;
  IF (SELECT content_hash FROM f360_board.budget_versions WHERE id = bv) IS NULL
     OR pg_temp.try(format('UPDATE f360_board.budget_lines SET amount = 2 WHERE version_id = %L', bv)) IS NULL
     OR pg_temp.try(format('UPDATE f360_board.budget_versions SET fiscal_year = 2028 WHERE id = %L', bv)) IS NULL THEN RAISE EXCEPTION 'FAIL T8 approved budget editable'; END IF;
  RAISE NOTICE 'PASS T8 history is never silently overwritten: closed month frozen (no void/capture, no direct status/version change, no delete); snapshots/events/logs/member changes append-only; reopen needs a reason and the next close is v2 with v1 intact (same hash); void+new keeps the trail; published forecast + its snapshot and approved budget are frozen';

  -- ── D10B conflict of interest ──────────────────────────────────────────────
  r := pg_temp.as(mar, 'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Inversión de Mario MXN 500,000 (evaluación)'', ''Registrar la evaluación de la inversión'', ''Mario evalúa invertir'', ''MARIO_INVESTMENT'')');
  d1 := (r->'decision'->>'id')::uuid;
  IF NOT (r->'decision'->>'related_party')::boolean OR NOT (r->'decision'->>'conflict_of_interest')::boolean OR NOT (r->'decision'->>'i_am_recused')::boolean
     OR NOT EXISTS (SELECT 1 FROM f360_board.decision_recusals WHERE decision_id = d1 AND auth_user_id = mar) THEN RAISE EXCEPTION 'FAIL D10B flags %', r; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d1));
  IF (r->>'ok')::boolean OR NOT (r->>'recused')::boolean THEN RAISE EXCEPTION 'FAIL D10B Mario approved his own investment %', r; END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''REJECT'')', d1));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL D10B Mario rejected his own investment'; END IF;
  IF (SELECT status FROM f360_board.decisions WHERE id = d1) <> 'PROPOSED'
     OR (SELECT count(*) FROM f360_board.decision_events WHERE decision_id = d1 AND event = 'APPROVAL_REFUSED_RECUSED') <> 2 THEN RAISE EXCEPTION 'FAIL D10B refusal not recorded'; END IF;
  IF pg_temp.try(format('UPDATE f360_board.decisions SET status = ''APPROVED'', approved_by = ARRAY[%L]::uuid[], approved_at = now(), approval_basis = ''OTHER_MEMBER'' WHERE id = %L', mar, d1)) IS NULL THEN
    RAISE EXCEPTION 'FAIL D10B Mario set as approver directly in the table';
  END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'', ''Aprobado por Carolina como miembro independiente'')', d1));
  IF NOT (r->>'ok')::boolean OR r->'decision'->>'status' <> 'APPROVED' OR r->'decision'->>'approval_basis' <> 'APPROVED_BY_OTHER_MEMBER_RELATED_PARTY'
     OR (SELECT approved_by FROM f360_board.decisions WHERE id = d1) <> ARRAY[car] THEN RAISE EXCEPTION 'FAIL D10B Carolina approval %', r; END IF;
  -- Carolina proposes a Mario compensation decision: Mario still recused, Carolina is the independent approver
  r := pg_temp.as(car, 'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Compensación de Mario'', ''Definir la compensación'', '''', ''MARIO_COMPENSATION'')');
  d2 := (r->'decision'->>'id')::uuid;
  IF (pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d2))->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL D10B Mario approved compensation'; END IF;
  IF NOT (pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d2))->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL D10B Carolina independent approval'; END IF;
  -- MARIO_* kinds always include Mario even if the proposer names somebody else
  r := pg_temp.as(mar, format('SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Aportación tecnológica de Mario'', ''Valuar la aportación'', '''', ''MARIO_TECH_CONTRIBUTION'', ARRAY[%L]::uuid[])', car));
  d3 := (r->'decision'->>'id')::uuid;
  IF NOT EXISTS (SELECT 1 FROM f360_board.decisions WHERE id = d3 AND mar = ANY (interested_members) AND car = ANY (interested_members)) THEN RAISE EXCEPTION 'FAIL D10B Mario not forced as interested'; END IF;
  IF (pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d3))->>'ok')::boolean
     OR (pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d3))->>'ok')::boolean THEN
    RAISE EXCEPTION 'FAIL D10B both interested yet approved';   -- both named → nobody independent can approve (stays open)
  END IF;
  r := pg_temp.as(mar, format('SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Sin conflicto con parte interesada'', ''x y z'', '''', ''NONE'', ARRAY[%L]::uuid[])', car));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL D10B interested member without conflict kind'; END IF;
  -- ordinary decision: proposer cannot approve alone (D5 default), the other member can
  r := pg_temp.as(mar, 'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Abrir pop-up en Monterrey'', ''Evaluar un pop-up'')');
  d4 := (r->'decision'->>'id')::uuid;
  r := pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d4));
  IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL D5 proposer self-approved'; END IF;
  IF NOT (pg_temp.as(car, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d4))->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL D5 other member approval'; END IF;
  RAISE NOTICE 'PASS D10B Mario-related decisions (investment, compensation, tech contribution) mark RELATED PARTY + CONFLICT OF INTEREST, record Mario as RECUSED, refuse (and record) his approve/reject, and are APPROVED BY OTHER MEMBER (Carolina) only; the table itself refuses an interested approver; ordinary decisions need a member other than the proposer';

  -- decisions are immutable after approval; change = superseding decision
  IF pg_temp.try(format('UPDATE f360_board.decisions SET title = ''otro'' WHERE id = %L', d4)) IS NULL
     OR pg_temp.try(format('DELETE FROM f360_board.decisions WHERE id = %L', d4)) IS NULL
     OR pg_temp.try(format('UPDATE f360_board.decisions SET interested_members = ''{}'' WHERE id = %L', d3)) IS NULL
     OR pg_temp.try('UPDATE f360_board.decision_events SET note = ''x''') IS NULL OR pg_temp.try('DELETE FROM f360_board.decision_revisions') IS NULL THEN
    RAISE EXCEPTION 'FAIL T8 approved decision / conflict flags / decision history editable';
  END IF;
  r := pg_temp.as(car, format('SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Pop-up en Monterrey (versión 2)'', ''Pop-up dos semanas'', '''', ''NONE'', ''{}'', NULL, ''[]'', %L)', d4));
  d5 := (r->'decision'->>'id')::uuid;
  IF NOT (pg_temp.as(mar, format('SELECT public.f360_board_decision_act(%L, ''APPROVE'')', d5))->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL supersede approve'; END IF;
  IF (SELECT status || ':' || superseded_by_id FROM f360_board.decisions WHERE id = d4) <> 'SUPERSEDED:' || d5
     OR (SELECT title FROM f360_board.decisions WHERE id = d4) <> 'Abrir pop-up en Monterrey' THEN RAISE EXCEPTION 'FAIL T8 supersede keeps old text'; END IF;
  RAISE NOTICE 'PASS T8 decisions: content frozen after approval, never deleted, conflict flags immutable, events/revisions append-only; a change is a new decision that supersedes the old one (old text kept, marked SUPERSEDED)';

  -- ── D12 Plan 2027 = B4 North Star, linked (one source), labelled DRAFT MANAGEMENT TARGET ──
  SELECT north_star INTO gp FROM f360.growth_plans WHERE plan_year = 2027;
  r := pg_temp.as(car, 'SELECT public.f360_board_plans()');
  IF gp IS NOT NULL THEN
    IF jsonb_array_length(r->'plans') <> 1 OR (r->'plans'->0->'years'->0->>'revenue_target')::numeric <> gp
       OR r->'plans'->0->'years'->0->>'source' <> 'f360.growth_plans' OR r->'plans'->0->>'target_label' <> 'DRAFT MANAGEMENT TARGET'
       OR jsonb_array_length(r->'plans'->0->'years'->0->'source_history') < 1 THEN RAISE EXCEPTION 'FAIL D12 plan %', r; END IF;
    SELECT version_id INTO pv FROM f360_board.plan_years WHERE linked_source = 'f360.growth_plans' AND linked_key = '2027';
    IF pg_temp.try(format('UPDATE f360_board.plan_years SET revenue_target = 1 WHERE version_id = %L', pv)) IS NULL THEN RAISE EXCEPTION 'FAIL D12 linked row stored its own amount'; END IF;
    IF pg_temp.try('UPDATE f360_board.plan_revisions SET payload = ''{}''') IS NULL THEN RAISE EXCEPTION 'FAIL D12 import history editable'; END IF;
    -- the B4 editor stays the single editable source: a new North Star shows up in the Board plan, the import stays as history
    PERFORM set_config('request.jwt.claims', json_build_object('sub', car, 'role', 'authenticated')::text, true);
    PERFORM public.f360_save_growth_plan(2027, gp + 1000, 'prueba SB0');
    PERFORM set_config('request.jwt.claims', '', true);
    r := pg_temp.as(car, 'SELECT public.f360_board_plans()');
    IF (r->'plans'->0->'years'->0->>'revenue_target')::numeric <> gp + 1000 OR (r->'plans'->0->'years'->0->>'imported_value')::numeric <> gp THEN
      RAISE EXCEPTION 'FAIL D12 live link / import history %', r->'plans'->0->'years';
    END IF;
    RAISE NOTICE 'PASS D12 Plan 2027 = B4 North Star (%), read LIVE from f360.growth_plans (one source, history from growth_plan_changes), import kept as revision 1, labelled DRAFT MANAGEMENT TARGET; linked rows cannot hold their own amount', gp;
  ELSE
    RAISE NOTICE 'SKIP D12: no B4 plan 2027 in this database';
  END IF;

  RAISE NOTICE 'SB0 history: all checks passed';
  RAISE EXCEPTION 'ENSAYO OK';
END $$;
