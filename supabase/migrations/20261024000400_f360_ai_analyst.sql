-- Fuxia 360 · I3 AI Business Analyst — auditoría y controles de consumo (Mario 2026-10-11: Claude como proveedor inicial,
-- separado de Hilo, presupuesto objetivo USD 100/mes, límites por usuario, consumo, herramientas y tokens). STAGING. ADDITIVE.
--   · f360.ai_settings — ONE row of limits and prices (provider/model configurable; prices documented with their source).
--     Changes only through f360_ai_settings_set (scope 'budget' = Mario), every change kept in f360.ai_settings_changes.
--   · f360.ai_queries — append-only audit of every question: who, when, the question with emails / phone numbers masked,
--     tools + arguments, sources cited, tokens, estimated cost, model, duration, outcome, numbers the verifier could not match.
--     It stores the structured answer (aggregates only: the tools never return customer data). Retention: 12 months (purge job
--     is a later decision; nothing is deleted today).
--   · f360_ai_quota(user) — checked BEFORE calling the model: per-user daily cap and the monthly USD budget (hard stop at 100 %,
--     warning from 80 %). Only the analyst function (service role) calls it and writes the audit.
-- The analyst reads data ONLY through public.f360_intel_query with the user's own session (I1b); it has no write path to
-- commerce, inventory, customers or Hilo. Rollback: supabase/rollbacks/20261024000400_f360_ai_analyst.down.sql

CREATE TABLE f360.ai_settings (
  id                    boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled               boolean NOT NULL DEFAULT true,
  provider              text NOT NULL DEFAULT 'anthropic' CHECK (provider ~ '^[a-z0-9_-]{2,40}$'),
  model                 text NOT NULL DEFAULT 'claude-sonnet-5-5' CHECK (model ~ '^[a-z0-9._-]{2,80}$'),
  monthly_budget_usd    numeric(10,2) NOT NULL DEFAULT 100 CHECK (monthly_budget_usd >= 0),
  per_user_daily        int NOT NULL DEFAULT 40 CHECK (per_user_daily BETWEEN 0 AND 1000),
  max_tool_calls        int NOT NULL DEFAULT 6 CHECK (max_tool_calls BETWEEN 1 AND 20),
  max_output_tokens     int NOT NULL DEFAULT 1500 CHECK (max_output_tokens BETWEEN 200 AND 8000),
  timeout_seconds       int NOT NULL DEFAULT 60 CHECK (timeout_seconds BETWEEN 10 AND 140),
  price_input_mtok      numeric(10,4) NOT NULL DEFAULT 2,       -- USD per million tokens
  price_output_mtok     numeric(10,4) NOT NULL DEFAULT 10,
  price_cache_write_mtok numeric(10,4) NOT NULL DEFAULT 2.5,
  price_cache_read_mtok numeric(10,4) NOT NULL DEFAULT 0.1,
  prices_source         text NOT NULL DEFAULT 'platform.claude.com/docs/en/about-claude/pricing — Claude Sonnet 5.5, consultado 2026-10-11',
  updated_by_name       text NOT NULL DEFAULT 'migración 20261024000400',
  updated_at            timestamptz NOT NULL DEFAULT now()
);
INSERT INTO f360.ai_settings DEFAULT VALUES;
CREATE TABLE f360.ai_settings_changes (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_uid     uuid NOT NULL,
  by_name    text NOT NULL,
  reason     text NOT NULL CHECK (length(btrim(reason)) >= 5),
  before     jsonb NOT NULL,
  after      jsonb NOT NULL
);
CREATE TRIGGER ai_settings_changes_append_only BEFORE UPDATE OR DELETE ON f360.ai_settings_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE TABLE f360.ai_queries (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at                 timestamptz NOT NULL DEFAULT clock_timestamp(),
  auth_user_id       uuid NOT NULL,
  user_name          text NOT NULL,
  kind               text NOT NULL CHECK (kind IN ('pregunta', 'prioridades')),
  question_masked    text NOT NULL CHECK (length(question_masked) <= 2000),
  status             text NOT NULL CHECK (status IN ('ok', 'denegado', 'limite_usuario', 'limite_mes', 'sin_configurar', 'error', 'apagado')),
  provider           text,
  model              text,
  tools              jsonb NOT NULL DEFAULT '[]',     -- [{tool, args, disponibilidad, fuente}] — never the payloads
  sources            jsonb NOT NULL DEFAULT '[]',
  answer             jsonb,                           -- structured answer (aggregates only)
  unverified         jsonb NOT NULL DEFAULT '[]',     -- numbers in "hechos" not found in any tool payload
  tokens_input       int NOT NULL DEFAULT 0,
  tokens_output      int NOT NULL DEFAULT 0,
  tokens_cache_read  int NOT NULL DEFAULT 0,
  tokens_cache_write int NOT NULL DEFAULT 0,
  cost_usd           numeric(10,5) NOT NULL DEFAULT 0,
  duration_ms        int,
  error              text CHECK (error IS NULL OR length(error) <= 500)
);
CREATE INDEX ai_queries_user_idx ON f360.ai_queries (auth_user_id, at DESC);
CREATE INDEX ai_queries_at_idx ON f360.ai_queries (at DESC);
CREATE TRIGGER ai_queries_append_only BEFORE UPDATE OR DELETE ON f360.ai_queries FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
COMMENT ON TABLE f360.ai_queries IS 'I3: append-only audit of the AI Business Analyst (no customer data; questions masked). Retention 12 months (purge = later decision).';

-- masks emails and phone-like digit runs before anything is stored
CREATE FUNCTION f360.ai_mask(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT left(regexp_replace(regexp_replace(coalesce(p, ''), '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[correo]', 'g'),
                             '\+?\d[\d\s().-]{8,}\d', '[número]', 'g'), 2000) $$;

-- service role: may this user ask now? (enabled, daily cap, monthly budget)
CREATE FUNCTION public.f360_ai_quota(p_user uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.ai_settings; n_today int; spent numeric; m0 timestamptz := date_trunc('month', now() AT TIME ZONE 'America/Mexico_City') AT TIME ZONE 'America/Mexico_City';
  d0 timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Mexico_City') AT TIME ZONE 'America/Mexico_City';
BEGIN
  SELECT * INTO s FROM f360.ai_settings;
  SELECT count(*) INTO n_today FROM f360.ai_queries WHERE auth_user_id = p_user AND at >= d0 AND status = 'ok';
  SELECT coalesce(sum(cost_usd), 0) INTO spent FROM f360.ai_queries WHERE at >= m0;
  RETURN jsonb_build_object(
    'allowed', s.enabled AND n_today < s.per_user_daily AND spent < s.monthly_budget_usd,
    'reason', CASE WHEN NOT s.enabled THEN 'apagado' WHEN spent >= s.monthly_budget_usd THEN 'limite_mes' WHEN n_today >= s.per_user_daily THEN 'limite_usuario' END,
    'used_today', n_today, 'spent_month_usd', round(spent, 4), 'budget_usd', s.monthly_budget_usd,
    'warning', spent >= 0.8 * s.monthly_budget_usd,
    'settings', jsonb_build_object('provider', s.provider, 'model', s.model, 'max_tool_calls', s.max_tool_calls, 'max_output_tokens', s.max_output_tokens,
      'timeout_seconds', s.timeout_seconds, 'price_input_mtok', s.price_input_mtok, 'price_output_mtok', s.price_output_mtok,
      'price_cache_write_mtok', s.price_cache_write_mtok, 'price_cache_read_mtok', s.price_cache_read_mtok));
END $$;

-- service role: write one audit row (the function computes the cost from the settings, never trusts a caller's figure)
CREATE FUNCTION public.f360_ai_log(p jsonb) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.ai_settings; v bigint; ti int := coalesce((p->>'tokens_input')::int, 0); tout int := coalesce((p->>'tokens_output')::int, 0);
  tcr int := coalesce((p->>'tokens_cache_read')::int, 0); tcw int := coalesce((p->>'tokens_cache_write')::int, 0);
BEGIN
  SELECT * INTO s FROM f360.ai_settings;
  INSERT INTO f360.ai_queries (auth_user_id, user_name, kind, question_masked, status, provider, model, tools, sources, answer, unverified,
                               tokens_input, tokens_output, tokens_cache_read, tokens_cache_write, cost_usd, duration_ms, error)
  VALUES ((p->>'auth_user_id')::uuid, coalesce((SELECT display_name FROM f360.user_roles WHERE auth_user_id = (p->>'auth_user_id')::uuid), 'Sin nombre'),
          coalesce(p->>'kind', 'pregunta'), f360.ai_mask(p->>'question'), p->>'status', p->>'provider', p->>'model',
          coalesce(p->'tools', '[]'), coalesce(p->'sources', '[]'), p->'answer', coalesce(p->'unverified', '[]'), ti, tout, tcr, tcw,
          round((ti * s.price_input_mtok + tout * s.price_output_mtok + tcr * s.price_cache_read_mtok + tcw * s.price_cache_write_mtok) / 1e6, 5),
          (p->>'duration_ms')::int, left(p->>'error', 500))
  RETURNING id INTO v;
  RETURN v;
END $$;

-- board: my own history (last 30)
CREATE FUNCTION public.f360_ai_history() RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_ai_history');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'at', at, 'kind', kind, 'question', question_masked,
      'status', status, 'answer', answer, 'unverified', unverified, 'tools', tools, 'cost_usd', cost_usd, 'model', model) ORDER BY at DESC), '[]')
    FROM (SELECT * FROM f360.ai_queries WHERE auth_user_id = uid ORDER BY at DESC LIMIT 30) q));
END $$;

-- board: consumption of the month (per person, by outcome) vs the budget
CREATE FUNCTION public.f360_ai_usage() RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_ai_usage'); s f360.ai_settings;
  m0 timestamptz := date_trunc('month', now() AT TIME ZONE 'America/Mexico_City') AT TIME ZONE 'America/Mexico_City';
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO s FROM f360.ai_settings;
  RETURN jsonb_build_object('ok', true, 'settings', to_jsonb(s), 'can_change', f360.can_approve('budget', uid),
    'month', (SELECT jsonb_build_object('preguntas', count(*) FILTER (WHERE status = 'ok'), 'costo_usd', round(coalesce(sum(cost_usd), 0), 4),
                'tokens_entrada', coalesce(sum(tokens_input), 0), 'tokens_salida', coalesce(sum(tokens_output), 0),
                'promedio_usd', round(coalesce(avg(cost_usd) FILTER (WHERE status = 'ok'), 0), 4),
                'por_estado', (SELECT coalesce(jsonb_object_agg(status, n), '{}') FROM (SELECT status, count(*) n FROM f360.ai_queries WHERE at >= m0 GROUP BY 1) z),
                'por_persona', (SELECT coalesce(jsonb_agg(jsonb_build_object('persona', user_name, 'preguntas', n, 'costo_usd', c)), '[]')
                                FROM (SELECT user_name, count(*) n, round(sum(cost_usd), 4) c FROM f360.ai_queries WHERE at >= m0 GROUP BY 1) z))
              FROM f360.ai_queries WHERE at >= m0),
    'changes', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', at, 'by', by_name, 'reason', reason, 'after', after) ORDER BY at DESC), '[]') FROM f360.ai_settings_changes));
END $$;

-- Mario (scope budget): change limits / model / prices, with a reason; history kept
CREATE FUNCTION public.f360_ai_settings_set(p_patch jsonb, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_ai_settings_set'); b jsonb; a jsonb;
  allowed text[] := ARRAY['enabled', 'model', 'monthly_budget_usd', 'per_user_daily', 'max_tool_calls', 'max_output_tokens', 'timeout_seconds',
                          'price_input_mtok', 'price_output_mtok', 'price_cache_write_mtok', 'price_cache_read_mtok', 'prices_source'];
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF NOT f360.can_approve('budget', uid) THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo quien aprueba presupuestos cambia los límites de IA.'); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 5 OR jsonb_typeof(p_patch) <> 'object' OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_patch) k WHERE k <> ALL (allowed)) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Cambio no válido (campos permitidos y motivo).');
  END IF;
  SELECT to_jsonb(s) INTO b FROM f360.ai_settings s;
  BEGIN
    UPDATE f360.ai_settings s SET
      enabled = coalesce((p_patch->>'enabled')::boolean, s.enabled), model = coalesce(p_patch->>'model', s.model),
      monthly_budget_usd = coalesce((p_patch->>'monthly_budget_usd')::numeric, s.monthly_budget_usd),
      per_user_daily = coalesce((p_patch->>'per_user_daily')::int, s.per_user_daily), max_tool_calls = coalesce((p_patch->>'max_tool_calls')::int, s.max_tool_calls),
      max_output_tokens = coalesce((p_patch->>'max_output_tokens')::int, s.max_output_tokens), timeout_seconds = coalesce((p_patch->>'timeout_seconds')::int, s.timeout_seconds),
      price_input_mtok = coalesce((p_patch->>'price_input_mtok')::numeric, s.price_input_mtok), price_output_mtok = coalesce((p_patch->>'price_output_mtok')::numeric, s.price_output_mtok),
      price_cache_write_mtok = coalesce((p_patch->>'price_cache_write_mtok')::numeric, s.price_cache_write_mtok),
      price_cache_read_mtok = coalesce((p_patch->>'price_cache_read_mtok')::numeric, s.price_cache_read_mtok),
      prices_source = coalesce(p_patch->>'prices_source', s.prices_source), updated_by_name = f360_board.member_name(uid), updated_at = now();
  EXCEPTION WHEN check_violation OR invalid_text_representation THEN RETURN jsonb_build_object('ok', false, 'error', 'Valor fuera de rango.');
  END;
  SELECT to_jsonb(s) INTO a FROM f360.ai_settings s;
  INSERT INTO f360.ai_settings_changes (by_uid, by_name, reason, before, after) VALUES (uid, f360_board.member_name(uid), btrim(p_reason), b, a);
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_ai_settings_set', 'ai_settings', p_patch);
  RETURN jsonb_build_object('ok', true, 'settings', a);
END $$;

ALTER TABLE f360.ai_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.ai_settings_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.ai_queries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.ai_settings, f360.ai_settings_changes, f360.ai_queries FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.ai_settings, f360.ai_settings_changes, f360.ai_queries TO service_role;
REVOKE ALL ON FUNCTION f360.ai_mask(text), public.f360_ai_quota(uuid), public.f360_ai_log(jsonb), public.f360_ai_history(), public.f360_ai_usage(),
  public.f360_ai_settings_set(jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_ai_quota(uuid), public.f360_ai_log(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_ai_history(), public.f360_ai_usage(), public.f360_ai_settings_set(jsonb, text) TO authenticated;
