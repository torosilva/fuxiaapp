-- Fuxia 360 — "¿No encontraste tu color y talla? Lo hacemos a la medida" (STAGING). Decision: Mario 2026-10-03.
-- On the product page a Hilo (HiloLabs) chat asks the customer for colour, size (or foot length), name and WhatsApp and
-- leaves a request here for the team (Carolina). Nothing is sold, priced or reserved: it is a lead to contact.
--   * Written ONLY by the Edge Function f360-custom-order (service role) after validating the input; anonymous visitors
--     never touch the table. Abuse guard: at most 3 requests per phone per day.
--   * Personal data kept to the minimum to call her back: first name + phone. The team list shows the full phone (they
--     have to contact her); viewers do not see it.
-- Rollback: supabase/rollbacks/20261007001800_f360_custom_requests.down.sql

CREATE TABLE f360.custom_requests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id       uuid REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_product_id  integer,
  product_id      uuid REFERENCES f360.products(id) ON DELETE SET NULL,
  product_name    text NOT NULL CHECK (length(product_name) BETWEEN 1 AND 200),
  color_wanted    text NOT NULL CHECK (length(color_wanted) BETWEEN 1 AND 80),
  size_wanted     text CHECK (length(size_wanted) <= 20),       -- as the customer said it (e.g. "25 MX")
  store_size      text CHECK (length(store_size) <= 10),        -- the store's size (35–40) when known
  foot_cm         numeric(4,1) CHECK (foot_cm IS NULL OR foot_cm BETWEEN 18 AND 32),
  customer_name   text NOT NULL CHECK (length(customer_name) BETWEEN 1 AND 80),
  phone           text NOT NULL CHECK (phone ~ '^\+[0-9]{10,15}$'),
  note            text CHECK (length(note) <= 500),
  country         text CHECK (length(country) <= 8),
  status          text NOT NULL DEFAULT 'nueva' CHECK (status IN ('nueva', 'contactada', 'cotizada', 'cerrada', 'descartada')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_by      text
);
CREATE INDEX custom_requests_open_idx ON f360.custom_requests (status, created_at DESC);
CREATE INDEX custom_requests_phone_idx ON f360.custom_requests (phone, created_at);

-- Service only (the Edge Function validated everything; the database validates again).
CREATE FUNCTION public.f360_custom_request_create(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; v_pid uuid; v_name text; r f360.custom_requests; v_phone text := btrim(p->>'phone');
BEGIN
  IF (SELECT count(*) FROM f360.custom_requests WHERE phone = v_phone AND created_at > now() - interval '1 day') >= 3 THEN
    RAISE EXCEPTION 'Ya recibimos tus solicitudes de hoy; te escribimos pronto.';
  END IF;
  SELECT * INTO t FROM f360.sales_targets WHERE key = p->>'target_key' AND active;
  IF t.id IS NOT NULL AND (p->>'woo_product_id') ~ '^[0-9]{1,9}$' THEN
    SELECT v.product_id INTO v_pid FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = t.id AND m.woo_product_id = (p->>'woo_product_id')::int AND m.status = 'confirmado' LIMIT 1;
  END IF;
  SELECT name INTO v_name FROM f360.products WHERE id = v_pid;
  INSERT INTO f360.custom_requests (target_id, woo_product_id, product_id, product_name, color_wanted, size_wanted, store_size, foot_cm,
      customer_name, phone, note, country)
    VALUES (t.id, nullif(p->>'woo_product_id', '')::int, v_pid, coalesce(v_name, left(btrim(p->>'product_name'), 200)),
      left(btrim(p->>'color'), 80), nullif(left(btrim(p->>'size'), 20), ''), nullif(left(btrim(p->>'store_size'), 10), ''),
      nullif(p->>'foot_cm', '')::numeric, left(btrim(p->>'name'), 80), v_phone, nullif(left(btrim(p->>'note'), 500), ''), nullif(left(p->>'country', 8), ''))
    RETURNING * INTO r;
  RETURN jsonb_build_object('id', r.id, 'product', r.product_name);
END $$;

CREATE FUNCTION public.f360_custom_requests_list(p_days int DEFAULT 90) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'product', c.product_name, 'product_id', c.product_id, 'color', c.color_wanted,
      'size', c.size_wanted, 'store_size', c.store_size, 'foot_cm', c.foot_cm, 'name', c.customer_name,
      'phone', CASE WHEN r.role IN ('owner', 'operator', 'seller') THEN c.phone ELSE '···' || right(c.phone, 4) END,
      'note', c.note, 'country', c.country, 'status', c.status, 'created_at', c.created_at, 'updated_by', c.updated_by)
      ORDER BY (c.status IN ('nueva', 'contactada', 'cotizada')) DESC, c.created_at DESC), '[]')
    FROM f360.custom_requests c WHERE c.created_at > now() - make_interval(days => greatest(1, least(p_days, 365))));
END $$;

CREATE FUNCTION public.f360_custom_request_set(p_id uuid, p_status text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.custom_requests;
BEGIN
  r := f360.require_role('operator');
  IF p_status NOT IN ('nueva', 'contactada', 'cotizada', 'cerrada', 'descartada') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  UPDATE f360.custom_requests SET status = p_status, updated_at = clock_timestamp(), updated_by = r.display_name WHERE id = p_id RETURNING * INTO c;
  IF c.id IS NULL THEN RAISE EXCEPTION 'No encontrada.'; END IF;
  RETURN jsonb_build_object('id', c.id, 'status', c.status);
END $$;

REVOKE ALL ON f360.custom_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.custom_requests TO service_role;
REVOKE ALL ON FUNCTION public.f360_custom_request_create(jsonb), public.f360_custom_requests_list(int), public.f360_custom_request_set(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_custom_request_create(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_custom_requests_list(int), public.f360_custom_request_set(uuid, text) TO authenticated, service_role;
