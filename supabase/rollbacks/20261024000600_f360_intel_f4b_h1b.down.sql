-- Rollback of 20261024000600_f360_intel_f4b_h1b: restores the EXACT previous bodies (copied verbatim from 20261024000300 and
-- 20261024000400). Run inside one transaction (no BEGIN/COMMIT here). No data involved.
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
  IF jsonb_array_length(inv->'baja_salida') > 0 THEN
    s := s || jsonb_build_object('codigo', 'INVENTARIO_BAJA_SALIDA', 'area', 'inventario', 'titulo', 'Modelos con pares y sin ventas en 60 días',
      'evidencia', jsonb_build_object('modelos', jsonb_array_length(inv->'baja_salida'),
        'pares', (SELECT sum((z->>'pares')::int) FROM jsonb_array_elements(inv->'baja_salida') z), 'ejemplos', (SELECT jsonb_agg(z) FROM (SELECT z FROM jsonb_array_elements(inv->'baja_salida') z LIMIT 5) q)),
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

CREATE OR REPLACE FUNCTION f360.ai_mask(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT left(regexp_replace(regexp_replace(coalesce(p, ''), '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[correo]', 'g'),
                             '\+?\d[\d\s().-]{8,}\d', '[número]', 'g'), 2000) $$;

DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261024000600';
