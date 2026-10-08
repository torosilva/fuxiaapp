-- Pre-production gate · decision 8 · READ-ONLY bazaar reconciliation preview for PRODUCTION (aggregates only, no customer data).
-- Same classification SELECT as f360.bazaar_sale_classification() (20261016000500). Run: scripts/f360/prod_read.sh < this file
WITH s AS (
    SELECT o.id AS sale_id, (o.created_at AT TIME ZONE 'America/Mexico_City')::date AS sale_day, o.total, c.name AS channel_name,
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || btrim(regexp_replace(translate(lower(coalesce(c.name || ' ' || coalesce(c.location, ''), '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', ' ', 'g')) || ' ', ' gdl ', ' guadalajara ', 'g'), ' qro ', ' queretaro ', 'g'), ' mty ', ' monterrey ', 'g'), ' cdmx ', ' ciudad de mexico ', 'g'), ' df ', ' ciudad de mexico ', 'g') AS place_norm
    FROM public.offline_sales o LEFT JOIN public.channels c ON c.id = o.channel_id
    WHERE NOT o.created_by_rpc AND lower(coalesce(c.type, '')) IN ('bazar', 'bazaar')),
  h AS (
    SELECT hs.id AS summary_id, coalesce(l.name, hs.bazaar_name) AS summary_name, hs.period_start, hs.period_end, hs.amount, hs.pairs,
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || btrim(regexp_replace(translate(lower(coalesce(coalesce(l.name, hs.bazaar_name), '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', ' ', 'g')) || ' ', ' gdl ', ' guadalajara ', 'g'), ' qro ', ' queretaro ', 'g'), ' mty ', ' monterrey ', 'g'), ' cdmx ', ' ciudad de mexico ', 'g'), ' df ', ' ciudad de mexico ', 'g') AS name_norm
    FROM f360.historical_sales hs LEFT JOIN f360.locations l ON l.id = hs.location_id
    WHERE hs.status = 'active' AND hs.kind = 'bazaar'),
  cand AS (
    SELECT s.sale_id, h.summary_id, s.sale_day BETWEEN h.period_start AND h.period_end AS in_window,
           EXISTS (SELECT 1 FROM regexp_split_to_table(btrim(s.place_norm), ' ') w
                   WHERE length(w) >= 4 AND w NOT IN ('bazar', 'bazaar', 'tienda', 'fuxia', 'store', 'ciudad', 'mexico')
                     AND position(' ' || w || ' ' IN h.name_norm) > 0) AS name_match
    FROM s JOIN h ON s.sale_day BETWEEN h.period_start - 2 AND h.period_end + 2),
  agg AS (
    SELECT s.sale_id, count(c.summary_id) AS n_cand, count(c.summary_id) FILTER (WHERE c.in_window AND c.name_match) AS n_strict,
           (array_agg(c.summary_id ORDER BY (c.in_window AND c.name_match) DESC, c.name_match DESC) FILTER (WHERE c.summary_id IS NOT NULL))[1] AS summary_id,
           bool_or(c.in_window AND NOT c.name_match) AS other_place_same_days, bool_or(NOT c.in_window) AS near_edge
    FROM s LEFT JOIN cand c ON c.sale_id = s.sale_id GROUP BY s.sale_id),
  win AS (
    SELECT c.summary_id, sum(s.total) AS sales_total, count(*) AS sales_n
    FROM cand c JOIN s ON s.sale_id = c.sale_id WHERE c.in_window AND c.name_match GROUP BY c.summary_id),
  cls AS (
    SELECT s.sale_id, s.sale_day, s.total, s.channel_name, a.summary_id, h.summary_name,
           CASE WHEN a.n_cand = 0 THEN 'UNMATCHED'
                WHEN a.n_cand = 1 AND a.n_strict = 1 AND abs(w.sales_total - h.amount) <= greatest(1, 0.01 * h.amount) THEN 'MATCHED'
                WHEN a.n_cand = 1 AND a.n_strict = 1 THEN 'LIKELY_DUPLICATE'
                ELSE 'AMBIGUOUS' END AS class,
           CASE WHEN a.n_cand = 0 THEN 'no_bazaar_summary_within_2_days'
                WHEN a.n_cand = 1 AND a.n_strict = 1 AND abs(w.sales_total - h.amount) <= greatest(1, 0.01 * h.amount) THEN 'window_sales_total_equals_summary_amount'
                WHEN a.n_cand = 1 AND a.n_strict = 1 THEN 'inside_summary_dates_same_place'
                WHEN a.n_cand > 1 THEN 'several_summaries_nearby'
                WHEN a.other_place_same_days THEN 'summary_of_another_place_on_same_days'
                WHEN a.near_edge THEN 'within_2_days_of_summary_dates'
                ELSE 'unclear' END AS reason
    FROM s JOIN agg a ON a.sale_id = s.sale_id LEFT JOIN h ON h.summary_id = a.summary_id LEFT JOIN win w ON w.summary_id = a.summary_id)
SELECT json_build_object(
  'by_class', (SELECT json_agg(json_build_object('class', class, 'sales', n, 'total_mxn', t, 'first_day', d1, 'last_day', d2, 'channels', ch, 'reasons', rs) ORDER BY class) FROM (
      SELECT class, count(*) n, sum(total) t, min(sale_day) d1, max(sale_day) d2, json_agg(DISTINCT channel_name) ch, json_agg(DISTINCT reason) rs FROM cls GROUP BY class) q),
  'by_day', (SELECT json_agg(json_build_object('day', sale_day, 'class', class, 'sales', n, 'total_mxn', t) ORDER BY sale_day) FROM (
      SELECT sale_day, class, count(*) n, sum(total) t FROM cls WHERE class <> 'UNMATCHED' GROUP BY 1, 2) q),
  'summaries', (SELECT json_agg(json_build_object('name', h.summary_name, 'from', h.period_start, 'to', h.period_end, 'amount_mxn', h.amount, 'pairs', h.pairs,
      'legacy_sales_linked', (SELECT count(*) FROM cls WHERE cls.summary_id = h.summary_id),
      'legacy_total_linked', (SELECT coalesce(sum(total), 0) FROM cls WHERE cls.summary_id = h.summary_id)) ORDER BY h.period_start) FROM h),
  'legacy_bazaar_sales_total', (SELECT json_build_object('sales', count(*), 'total_mxn', sum(total)) FROM s))