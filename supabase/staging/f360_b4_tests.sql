-- Fuxia 360 B4 (revenue planning) — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE FUNCTION pg_temp.as_user(p_uid uuid, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated, anon;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c2', :'c2', true) \gset t_
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (:'c2', 'operator', 'Operadora de prueba', 'test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'operator', display_name = 'Operadora de prueba', granted_by = 'test (rolled back)';

DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; g jsonb; err text; yr int := 2099;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  g := public.f360_growth_plan(yr);
  PERFORM pg_temp.ok(g->'plan' = 'null'::jsonb AND g->'scenarios' = '{}'::jsonb AND (g->>'can_edit')::boolean, 'empty plan: no preloaded numbers; owner can edit', g::text);
  BEGIN PERFORM public.f360_save_growth_scenario(yr, 'base', '{"aov":2800}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'scenario needs a North Star first', err);
  g := public.f360_save_growth_plan(yr, 15000000, 'Objetivo, no pronóstico');
  PERFORM pg_temp.ok((g->'plan'->>'north_star')::numeric = 15000000, 'North Star saved (configurable)', g->'plan'->>'north_star');
  g := public.f360_save_growth_scenario(yr, 'base', '{"active_customers":3000,"orders_per_customer":1.6,"aov":2900,"ecommerce_pct":70,"retail_pct":30,"regions":[{"name":"CDMX","pct":40}]}');
  PERFORM pg_temp.ok((g->'scenarios'->'base'->'inputs'->>'aov')::numeric = 2900, 'scenario assumptions saved', '');
  BEGIN PERFORM public.f360_save_growth_scenario(yr, 'base', '{"ecommerce_pct":80,"retail_pct":30}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%más de 100%', 'shares over 100% rejected', err);
  BEGIN PERFORM public.f360_save_growth_scenario(yr, 'base', '{"aov":-5}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'negative AOV rejected', err);
  BEGIN PERFORM public.f360_save_growth_scenario(yr, 'base', '{"revenue_2025":5500000}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE 'Campo desconocido%', 'no way to smuggle historical figures into assumptions', err);
  BEGIN PERFORM public.f360_save_growth_scenario(yr, 'optimista', '{}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'only conservador/base/agresivo', err);
  BEGIN PERFORM public.f360_add_reported_figure('2025', 5500000, '', 'Mario'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'reported figure requires scope and source', err);
  g := public.f360_add_reported_figure('2025', 5500000, 'todos los canales (según Mario)', 'Mario, conversación 2026-09', NULL);
  PERFORM pg_temp.ok(g->>'status' = 'reportada_no_verificada', 'reported figure starts as NOT verified', g->>'status');
  BEGIN PERFORM public.f360_set_reported_figure_status((g->>'id')::uuid, 'verificada', ''); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'verifying requires an explanation', err);
  RESET ROLE;
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.growth_plan_changes WHERE plan_year = yr) = 2 AND EXISTS (SELECT 1 FROM f360.growth_plan_changes WHERE plan_year = 2025 AND what = 'reported_figure' AND by_name = 'Carolina'), 'every change is in the append-only audit (who/what)', '');
  BEGIN UPDATE f360.growth_plan_changes SET by_name = 'x' WHERE plan_year = yr; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'plan audit is append-only', err);

  PERFORM pg_temp.as_user(current_setting('t.c2')::uuid, 'authenticated');
  g := public.f360_growth_plan(yr);
  BEGIN PERFORM public.f360_save_growth_plan(yr, 1, NULL); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(NOT (g->>'can_edit')::boolean AND err <> 'accepted', 'operator can read the plan but not change it', err);
  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.f360_growth_plan(yr); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anon cannot read the plan', err);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
