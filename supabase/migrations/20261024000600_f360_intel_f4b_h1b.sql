-- Fuxia 360 · Centro de Inteligencia — F4b y H1b (reevaluación I4). PROPUESTA para revisión de Mario (2026-10-11): NO ejecutada.
-- Al aprobarse se aplica SOLO en STAGING, en una transacción, con su fila en supabase_migrations.schema_migrations.
--   F4b · f360.intel_signals_core: the weekly-priorities signal "INVENTARIO_BAJA_SALIDA" reports the totals of the WHOLE list
--         (baja_salida_total, added by 20261024000500) instead of counting the 20-row sample. Same signature, same output keys
--         (modelos, pares, ejemplos) + valor_precio_venta and ejemplos_nota. Every other signal is unchanged (same text as 20261024000300).
--   H1b · f360.ai_mask: the audit masking keeps valid dates (AAAA-MM-DD, DD/MM/AAAA) while still masking emails and long digit runs
--         (phones, card / account numbers). Same signature and return type; language sql → plpgsql to set dates aside safely.
-- Only CREATE OR REPLACE of two existing functions: no table, data, grant, RLS policy or other function is touched; CREATE OR REPLACE
-- keeps the existing privileges (both are revoked from PUBLIC/anon/authenticated and only used inside SECURITY DEFINER code).
-- Rollback: 20261024000600_f360_intel_f4b_h1b.down.sql (restores both bodies exactly as in 20261024000300 / 20261024000400).

CREATE OR REPLACE FUNCTION f360.intel_signals_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s jsonb := '[]'; g jsonb; x jsonb; inv jsonb; mk jsonb;
BEGIN
  g := (f360.intel_goal_core('ecommerce_mx_mensual', f360.intel_today()))->'data';
  IF g IS NOT NULL AND (g->>'ritmo_necesario_diario') IS NOT NULL AND coalesce((g->>'ritmo_actual_diario')::numeric, 0) * 2 < (g->>'ritmo_necesario_diario')::numeric THEN
    s := s || jsonb_build_object('codigo', 'META_ECOMMERCE_MX', 'area', 'ventas', 'titulo', 'El ritmo de ecommerce México está lejos de la meta',
      'evidencia', jsonb_build_object('real_al_dia', g->'real_al_dia', 'meta', g->'meta', 'ritmo_actual_diario', g->'ritmo_actual_diario',
                                      'ritmo_necesario_diario', g->'ritmo_necesario_diario', 'mejor_mes_ultimos_12', g->'mejor_mes_ultimos_12'),
      'tipo', 'hecho + cálculo');
  END IF;
  FOR x IN SELECT * FROM jsonb_array_elements((f360.intel_payments_core(p_from, p_to))->'data'->'por_metodo') LOOP
    IF (x->>'creados')::int >= 3 AND (x->>'tasa_no_completado_pct')::numeric >= 30 THEN
      s := s || jsonb_build_object('codigo', 'PAGOS_NO_COMPLETADOS', 'area', 'conversión', 'titulo', format('Pagos que no se completan con %s (%s)', x->>'metodo', x->>'mercado'),
        'evidencia', x, 'tipo', 'hecho');
    END IF;
  END LOOP;
  FOR mk IN SELECT * FROM jsonb_array_elements((f360.intel_marketing_core(p_from, p_to))->'data'->'por_mercado') LOOP
    IF coalesce((mk->'inversion'->>'monto')::numeric, 0) > 0 AND (mk->>'pedidos_pagados')::int = 0 THEN
      s := s || jsonb_build_object('codigo', 'INVERSION_SIN_VENTAS', 'area', 'marketing', 'titulo', format('Inversión en %s sin pedidos pagados en el periodo', mk->>'mercado'),
        'evidencia', jsonb_build_object('mercado', mk->'mercado', 'inversion', mk->'inversion', 'pedidos_pagados', 0), 'tipo', 'hecho');
    END IF;
  END LOOP;
  inv := (f360.intel_inventory_core(60))->'data';
  -- F4b: totals come from baja_salida_total (the WHOLE list), never from the length of the capped sample
  IF coalesce((inv->'baja_salida_total'->>'modelos')::int, 0) > 0 THEN
    s := s || jsonb_build_object('codigo', 'INVENTARIO_BAJA_SALIDA', 'area', 'inventario', 'titulo', 'Modelos con pares y sin ventas en 60 días',
      'evidencia', jsonb_build_object('modelos', (inv->'baja_salida_total'->>'modelos')::int, 'pares', (inv->'baja_salida_total'->>'pares')::int,
        'valor_precio_venta', inv->'baja_salida_total'->'valor_precio_venta',
        'ejemplos', (SELECT jsonb_agg(z) FROM (SELECT z FROM jsonb_array_elements(inv->'baja_salida') z LIMIT 5) q),
        'ejemplos_nota', format('5 ejemplos de %s modelos; la lista completa está en la herramienta inventario_baja_salida', (inv->'baja_salida_total'->>'modelos')::int)),
      'tipo', 'hecho');
  END IF;
  IF jsonb_array_length(inv->'riesgo_agotarse') > 0 THEN
    s := s || jsonb_build_object('codigo', 'RIESGO_AGOTARSE', 'area', 'inventario', 'titulo', 'Modelos que se agotarían en menos de 3 semanas al ritmo actual',
      'evidencia', inv->'riesgo_agotarse', 'tipo', 'cálculo');
  END IF;
  RETURN jsonb_build_object('data', jsonb_build_object('senales', s),
    'meta', f360.intel_meta('Reglas fijas sobre ventas, pagos, marketing e inventario', p_from, p_to, NULL, 'DISPONIBLE', '[]',
      jsonb_build_array('Las señales son hechos o cálculos con evidencia. Las prioridades y responsables los propone el analista como recomendación.')));
END $$;

CREATE OR REPLACE FUNCTION f360.ai_mask(p text) RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
-- H1b: same masking as before (emails → [correo]; runs of 10+ digits with phone separators → [número], e.g. phones, card or account
-- numbers) but VALID DATES written in the question are kept: AAAA-MM-DD and DD/MM/AAAA (or DD/MM/AA). Dates are set aside with
-- placeholders the digit rule cannot match, the rule runs, and the dates are put back. Same signature, same output length limit.
DECLARE s text := coalesce(p, ''); kept text[] := '{}'; m text[]; n int := 0;
BEGIN
  s := regexp_replace(s, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[correo]', 'g');
  LOOP
    m := regexp_match(s, '(?:^|[^0-9])((?:19|20)[0-9]{2}-(?:0?[1-9]|1[0-2])-(?:0?[1-9]|[12][0-9]|3[01])|(?:0?[1-9]|[12][0-9]|3[01])/(?:0?[1-9]|1[0-2])/(?:(?:19|20)?[0-9]{2}))(?![0-9])');
    EXIT WHEN m IS NULL OR n >= 20;
    n := n + 1; kept := kept || m[1];
    s := overlay(s placing chr(1) || n::text || chr(2) from strpos(s, m[1]) for length(m[1]));
  END LOOP;
  s := regexp_replace(s, '\+?\d[\d\s().-]{8,}\d', '[número]', 'g');
  FOR i IN 1..n LOOP s := replace(s, chr(1) || i::text || chr(2), kept[i]); END LOOP;
  RETURN left(s, 2000);
END $$;
