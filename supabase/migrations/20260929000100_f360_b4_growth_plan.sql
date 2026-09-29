-- Fuxia 360 B4 — Revenue planning model (STAGING). Additive; independent of customer identity.
-- PLANNING, not history: every number here is an ASSUMPTION typed by an owner, never a measured fact.
--   f360.growth_plans              North Star per year (default suggested in the UI: $15,000,000 MXN for 2027)
--   f360.growth_scenarios          Conservador / Base / Agresivo — editable assumptions (jsonb, validated)
--   f360.growth_plan_changes       append-only audit of every change (who, what, when)
--   f360.reported_figures          figures reported by people (e.g. Mario's 2025/2026 revenue) with source, scope and
--                                  status; NOT facts until verified. Nothing is preloaded.
-- Rollback: supabase/rollbacks/20260929000100_f360_b4_growth_plan.down.sql

CREATE TABLE f360.growth_plans (
  plan_year        integer PRIMARY KEY CHECK (plan_year BETWEEN 2024 AND 2100),
  north_star       numeric(14,2) NOT NULL CHECK (north_star > 0),
  currency         text NOT NULL DEFAULT 'MXN' CHECK (currency = 'MXN'),
  note             text,
  updated_by_name  text NOT NULL,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE f360.growth_scenarios (
  plan_year        integer NOT NULL REFERENCES f360.growth_plans(plan_year) ON DELETE RESTRICT,
  kind             text NOT NULL CHECK (kind IN ('conservador', 'base', 'agresivo')),
  inputs           jsonb NOT NULL DEFAULT '{}',
  updated_by_name  text NOT NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (plan_year, kind)
);

CREATE TABLE f360.growth_plan_changes (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  plan_year   integer NOT NULL,
  what        text NOT NULL,            -- north_star | scenario:<kind> | reported_figure
  before      jsonb,
  after       jsonb,
  by_name     text NOT NULL,
  by_user     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  at          timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER growth_plan_changes_append_only BEFORE UPDATE OR DELETE ON f360.growth_plan_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE TABLE f360.reported_figures (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metric            text NOT NULL CHECK (metric IN ('revenue_annual')),
  period            text NOT NULL CHECK (period ~ '^\d{4}$'),
  value             numeric(14,2) NOT NULL CHECK (value >= 0),
  currency          text NOT NULL DEFAULT 'MXN' CHECK (currency = 'MXN'),
  scope             text NOT NULL,     -- e.g. "todos los canales", "solo ecommerce", "bruto con IVA" — as stated by the source
  source            text NOT NULL,     -- who / what document
  status            text NOT NULL DEFAULT 'reportada_no_verificada' CHECK (status IN ('reportada_no_verificada', 'verificada', 'descartada')),
  note              text,
  created_by_name   text NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  status_by_name    text,
  status_at         timestamptz,
  status_note       text
);

-- Validates scenario assumptions: all optional; numbers ≥ 0; percentages 0–100; each pair of shares ≤ 100.
CREATE FUNCTION f360.validate_growth_inputs(p jsonb) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text; v jsonb; r jsonb; total numeric := 0;
BEGIN
  IF jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'Supuestos no válidos.'; END IF;
  FOR k, v IN SELECT * FROM jsonb_each(p) LOOP
    IF k IN ('active_customers', 'orders_per_customer', 'aov') THEN
      IF jsonb_typeof(v) <> 'null' AND (jsonb_typeof(v) <> 'number' OR (v #>> '{}')::numeric < 0) THEN RAISE EXCEPTION 'El valor de % debe ser un número positivo.', k; END IF;
    ELSIF k IN ('ecommerce_pct', 'retail_pct', 'shoes_pct', 'accessories_pct', 'new_pct', 'returning_pct') THEN
      IF jsonb_typeof(v) <> 'null' AND (jsonb_typeof(v) <> 'number' OR (v #>> '{}')::numeric NOT BETWEEN 0 AND 100) THEN RAISE EXCEPTION 'El porcentaje % debe estar entre 0 y 100.', k; END IF;
    ELSIF k = 'regions' THEN
      IF jsonb_typeof(v) <> 'array' THEN RAISE EXCEPTION 'Regiones no válidas.'; END IF;
      FOR r IN SELECT * FROM jsonb_array_elements(v) LOOP
        IF coalesce(btrim(r->>'name'), '') = '' OR jsonb_typeof(r->'pct') <> 'number' OR (r->>'pct')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Cada región necesita nombre y porcentaje (0–100).'; END IF;
        total := total + (r->>'pct')::numeric;
      END LOOP;
      IF total > 100 THEN RAISE EXCEPTION 'Las regiones suman más de 100%%.'; END IF;
    ELSIF k = 'note' THEN
      IF jsonb_typeof(v) NOT IN ('string', 'null') THEN RAISE EXCEPTION 'Nota no válida.'; END IF;
    ELSE
      RAISE EXCEPTION 'Campo desconocido: %.', k;
    END IF;
  END LOOP;
  IF coalesce((p->>'ecommerce_pct')::numeric, 0) + coalesce((p->>'retail_pct')::numeric, 0) > 100 THEN RAISE EXCEPTION 'Ecommerce + tiendas físicas suman más de 100%%.'; END IF;
  IF coalesce((p->>'shoes_pct')::numeric, 0) + coalesce((p->>'accessories_pct')::numeric, 0) > 100 THEN RAISE EXCEPTION 'Zapatos + accesorios suman más de 100%%.'; END IF;
  IF coalesce((p->>'new_pct')::numeric, 0) + coalesce((p->>'returning_pct')::numeric, 0) > 100 THEN RAISE EXCEPTION 'Nuevas + recurrentes suman más de 100%%.'; END IF;
END $$;

CREATE FUNCTION public.f360_growth_plan(p_year integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; gp f360.growth_plans;
BEGIN
  r := f360.require_role('viewer');
  SELECT * INTO gp FROM f360.growth_plans WHERE plan_year = p_year;
  RETURN jsonb_build_object(
    'year', p_year,
    'plan', CASE WHEN gp.plan_year IS NULL THEN NULL ELSE jsonb_build_object('north_star', gp.north_star, 'note', gp.note, 'updated_by_name', gp.updated_by_name, 'updated_at', gp.updated_at) END,
    'scenarios', (SELECT coalesce(jsonb_object_agg(kind, jsonb_build_object('inputs', inputs, 'updated_by_name', updated_by_name, 'updated_at', updated_at)), '{}')
                  FROM f360.growth_scenarios WHERE plan_year = p_year),
    'reported_figures', (SELECT coalesce(jsonb_agg(to_jsonb(f) - 'currency' ORDER BY f.period DESC, f.created_at DESC), '[]') FROM f360.reported_figures f),
    'changes', (SELECT coalesce(jsonb_agg(jsonb_build_object('what', what, 'by', by_name, 'at', at) ORDER BY id DESC), '[]')
                FROM (SELECT * FROM f360.growth_plan_changes WHERE plan_year = p_year ORDER BY id DESC LIMIT 10) c),
    'can_edit', r.role = 'owner');
END $$;

CREATE FUNCTION public.f360_save_growth_plan(p_year integer, p_north_star numeric, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; before jsonb;
BEGIN
  r := f360.require_role('owner');
  IF p_north_star IS NULL OR p_north_star <= 0 THEN RAISE EXCEPTION 'El objetivo debe ser mayor a cero.'; END IF;
  SELECT to_jsonb(g) INTO before FROM f360.growth_plans g WHERE plan_year = p_year;
  INSERT INTO f360.growth_plans (plan_year, north_star, note, updated_by_name) VALUES (p_year, p_north_star, nullif(btrim(p_note), ''), r.display_name)
    ON CONFLICT (plan_year) DO UPDATE SET north_star = EXCLUDED.north_star, note = EXCLUDED.note, updated_by_name = EXCLUDED.updated_by_name, updated_at = now();
  INSERT INTO f360.growth_plan_changes (plan_year, what, before, after, by_name, by_user)
    VALUES (p_year, 'north_star', before, jsonb_build_object('north_star', p_north_star, 'note', p_note), r.display_name, r.auth_user_id);
  RETURN public.f360_growth_plan(p_year);
END $$;

CREATE FUNCTION public.f360_save_growth_scenario(p_year integer, p_kind text, p_inputs jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; before jsonb;
BEGIN
  r := f360.require_role('owner');
  IF NOT EXISTS (SELECT 1 FROM f360.growth_plans WHERE plan_year = p_year) THEN RAISE EXCEPTION 'Primero define el objetivo del año.'; END IF;
  IF p_kind NOT IN ('conservador', 'base', 'agresivo') THEN RAISE EXCEPTION 'Escenario no válido.'; END IF;
  PERFORM f360.validate_growth_inputs(coalesce(p_inputs, '{}'));
  SELECT inputs INTO before FROM f360.growth_scenarios WHERE plan_year = p_year AND kind = p_kind;
  INSERT INTO f360.growth_scenarios (plan_year, kind, inputs, updated_by_name) VALUES (p_year, p_kind, coalesce(p_inputs, '{}'), r.display_name)
    ON CONFLICT (plan_year, kind) DO UPDATE SET inputs = EXCLUDED.inputs, updated_by_name = EXCLUDED.updated_by_name, updated_at = now();
  INSERT INTO f360.growth_plan_changes (plan_year, what, before, after, by_name, by_user) VALUES (p_year, 'scenario:' || p_kind, before, p_inputs, r.display_name, r.auth_user_id);
  RETURN public.f360_growth_plan(p_year);
END $$;

CREATE FUNCTION public.f360_add_reported_figure(p_period text, p_value numeric, p_scope text, p_source text, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; f f360.reported_figures;
BEGIN
  r := f360.require_role('owner');
  IF coalesce(btrim(p_scope), '') = '' OR coalesce(btrim(p_source), '') = '' THEN RAISE EXCEPTION 'Indica el alcance (qué incluye) y la fuente de la cifra.'; END IF;
  INSERT INTO f360.reported_figures (metric, period, value, scope, source, note, created_by_name)
    VALUES ('revenue_annual', p_period, p_value, btrim(p_scope), btrim(p_source), nullif(btrim(p_note), ''), r.display_name) RETURNING * INTO f;
  INSERT INTO f360.growth_plan_changes (plan_year, what, after, by_name, by_user) VALUES (p_period::int, 'reported_figure', to_jsonb(f), r.display_name, r.auth_user_id);
  RETURN to_jsonb(f);
END $$;

CREATE FUNCTION public.f360_set_reported_figure_status(p_id uuid, p_status text, p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; f f360.reported_figures;
BEGIN
  r := f360.require_role('owner');
  IF p_status NOT IN ('verificada', 'descartada', 'reportada_no_verificada') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  IF coalesce(btrim(p_note), '') = '' THEN RAISE EXCEPTION 'Explica cómo se verificó o por qué se descarta.'; END IF;
  UPDATE f360.reported_figures SET status = p_status, status_by_name = r.display_name, status_at = now(), status_note = btrim(p_note) WHERE id = p_id RETURNING * INTO f;
  IF f.id IS NULL THEN RAISE EXCEPTION 'Cifra no encontrada.'; END IF;
  INSERT INTO f360.growth_plan_changes (plan_year, what, after, by_name, by_user) VALUES (f.period::int, 'reported_figure_status', to_jsonb(f), r.display_name, r.auth_user_id);
  RETURN to_jsonb(f);
END $$;

REVOKE ALL ON f360.growth_plans, f360.growth_scenarios, f360.growth_plan_changes, f360.reported_figures FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.f360_growth_plan(integer), public.f360_save_growth_plan(integer, numeric, text),
  public.f360_save_growth_scenario(integer, text, jsonb), public.f360_add_reported_figure(text, numeric, text, text, text),
  public.f360_set_reported_figure_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_growth_plan(integer), public.f360_save_growth_plan(integer, numeric, text),
  public.f360_save_growth_scenario(integer, text, jsonb), public.f360_add_reported_figure(text, numeric, text, text, text),
  public.f360_set_reported_figure_status(uuid, text, text) TO authenticated, service_role;
