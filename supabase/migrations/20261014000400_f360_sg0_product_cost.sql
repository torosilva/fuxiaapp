-- Fuxia 360 · S-G0 Measurement Truth · D5 PRODUCT COST (Mario 2026-10-08: Fuxia 360 is the source of product cost, VERSIONED).
-- ADDITIVE, empty on creation: NO current cost is invented or seeded.
--   · One row = one cost VERSION for a scope: product (required) + variant (optional) + market (optional), amount + currency,
--     effective_from / effective_to, source, notes, created_by, approved_by.
--   · History is never overwritten: a new cost is a NEW row. Approving a version closes the previous open approved version of the
--     same scope (its effective_to = new effective_from − 1 day) — the ONLY change ever made to an existing approved row.
--     Everything else is immutable (trigger); rows are never deleted; a wrong proposal is rejected, not edited.
--   · Approved versions must not overlap: a version that starts on or before an existing approved start of the same scope
--     is refused (backdating = an explicit decision, documented in S-G0_DELIVERY.md).
--   · Write: propose = owner / operator; approve / reject = owner. Read: owner / operator. Cost is financial data: never sellers.
-- Coordination: f360.product_cost_versions is OWNED by S-G0; Strategy & Board (SB0) reads it.
-- Rollback: supabase/rollbacks/20261014000400_f360_sg0_product_cost.down.sql

CREATE TABLE f360.product_cost_versions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id       uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  variant_id       uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  market           text CHECK (market IN ('MX', 'CO', 'ROW')),
  cost_amount      numeric(12,2) NOT NULL CHECK (cost_amount > 0 AND cost_amount < 10000000),
  currency         text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  effective_from   date NOT NULL,
  effective_to     date,
  source           text NOT NULL CHECK (source IN ('supplier_invoice', 'production_order', 'accounting', 'owner_estimate', 'other')),
  notes            text CHECK (notes IS NULL OR length(notes) <= 500),
  status           text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'approved', 'rejected')),
  created_by       uuid NOT NULL,
  created_by_name  text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  approved_by      uuid,
  approved_by_name text,
  approved_at      timestamptz,
  rejected_reason  text,
  CONSTRAINT pcv_period CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT pcv_approval CHECK ((status IN ('approved', 'rejected')) = (approved_at IS NOT NULL AND approved_by IS NOT NULL))
);
CREATE INDEX product_cost_versions_scope_idx ON f360.product_cost_versions (product_id, variant_id, market, effective_from);
COMMENT ON TABLE f360.product_cost_versions IS 'S-G0 D5: versioned product cost (source of truth = Fuxia 360). New cost = new row; history never overwritten.';
COMMENT ON COLUMN f360.product_cost_versions.approved_by IS 'Owner who approved OR rejected the version (status says which).';

CREATE FUNCTION f360.product_cost_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text[] := ARRAY['status', 'approved_by', 'approved_by_name', 'approved_at', 'rejected_reason', 'effective_to'];
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Un costo no se borra: el historial se conserva.'; END IF;
  IF (to_jsonb(NEW) - k) <> (to_jsonb(OLD) - k) THEN RAISE EXCEPTION 'Un costo no se modifica: registra una versión nueva.'; END IF;
  IF OLD.status = 'proposed' AND NEW.status IN ('approved', 'rejected') AND NEW.effective_to IS NOT DISTINCT FROM OLD.effective_to THEN RETURN NEW; END IF;
  -- closing an approved open version when the next one is approved (only effective_to, only once)
  IF OLD.status = 'approved' AND NEW.status = 'approved' AND OLD.effective_to IS NULL AND NEW.effective_to IS NOT NULL
     AND NEW.approved_at = OLD.approved_at AND NEW.approved_by = OLD.approved_by THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Cambio no permitido en un costo (% → %).', OLD.status, NEW.status;
END $$;
CREATE TRIGGER product_cost_versions_guard BEFORE UPDATE OR DELETE ON f360.product_cost_versions
  FOR EACH ROW EXECUTE FUNCTION f360.product_cost_guard();

-- Approved cost timeline (what was valid when). Never includes proposals.
CREATE VIEW f360.product_cost_effective AS
  SELECT c.id, c.product_id, c.variant_id, c.market, c.cost_amount, c.currency, c.effective_from, c.effective_to, c.source,
         c.created_by_name, c.approved_by_name, c.approved_at
  FROM f360.product_cost_versions c WHERE c.status = 'approved';

CREATE FUNCTION public.f360_product_cost_propose(p_product_id uuid, p_variant_id uuid, p_market text, p_amount numeric, p_currency text,
  p_effective_from date, p_source text, p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); v_id uuid; v_cur text := upper(btrim(coalesce(p_currency, '')));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  IF p_variant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = p_variant_id AND product_id = p_product_id) THEN
    RAISE EXCEPTION 'La variante no es de este producto.';
  END IF;
  IF p_market IS NOT NULL AND p_market NOT IN ('MX', 'CO', 'ROW') THEN RAISE EXCEPTION 'Mercado no válido (MX, CO, ROW o vacío).'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) THEN RAISE EXCEPTION 'El costo debe ser mayor que 0 (máximo 2 decimales).'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.currencies WHERE code = v_cur) THEN RAISE EXCEPTION 'Moneda no válida.'; END IF;
  IF p_effective_from IS NULL THEN RAISE EXCEPTION 'Indica desde cuándo vale este costo.'; END IF;
  IF p_source NOT IN ('supplier_invoice', 'production_order', 'accounting', 'owner_estimate', 'other') THEN RAISE EXCEPTION 'Fuente del costo no válida.'; END IF;
  INSERT INTO f360.product_cost_versions (product_id, variant_id, market, cost_amount, currency, effective_from, source, notes, created_by, created_by_name)
    VALUES (p_product_id, p_variant_id, p_market, p_amount, v_cur, p_effective_from, p_source, nullif(btrim(coalesce(p_notes, '')), ''), r.auth_user_id, r.display_name)
    RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'status', 'proposed');
END $$;

CREATE FUNCTION public.f360_product_cost_decide(p_id uuid, p_approve boolean, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); v f360.product_cost_versions; v_closed uuid;
BEGIN
  SELECT * INTO v FROM f360.product_cost_versions WHERE id = p_id FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'proposed' THEN RAISE EXCEPTION 'Costo no encontrado o ya decidido.'; END IF;
  IF NOT coalesce(p_approve, false) THEN
    IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el motivo del rechazo.'; END IF;
    UPDATE f360.product_cost_versions SET status = 'rejected', approved_by = r.auth_user_id, approved_by_name = r.display_name,
        approved_at = clock_timestamp(), rejected_reason = left(btrim(p_reason), 300) WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'rejected');
  END IF;
  -- one decision at a time per scope
  PERFORM pg_advisory_xact_lock(hashtextextended('product_cost:' || v.product_id || ':' || coalesce(v.variant_id::text, '') || ':' || coalesce(v.market, ''), 0));
  IF EXISTS (SELECT 1 FROM f360.product_cost_versions c WHERE c.status = 'approved' AND c.product_id = v.product_id
               AND c.variant_id IS NOT DISTINCT FROM v.variant_id AND c.market IS NOT DISTINCT FROM v.market AND c.effective_from >= v.effective_from) THEN
    RAISE EXCEPTION 'Ya hay un costo aprobado que empieza en esa fecha o después: no se reescribe la historia.';
  END IF;
  UPDATE f360.product_cost_versions c SET effective_to = v.effective_from - 1
    WHERE c.status = 'approved' AND c.product_id = v.product_id AND c.variant_id IS NOT DISTINCT FROM v.variant_id
      AND c.market IS NOT DISTINCT FROM v.market AND c.effective_to IS NULL
    RETURNING c.id INTO v_closed;
  UPDATE f360.product_cost_versions SET status = 'approved', approved_by = r.auth_user_id, approved_by_name = r.display_name,
      approved_at = clock_timestamp() WHERE id = p_id;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'approved', 'closed_previous', v_closed);
END $$;

CREATE FUNCTION public.f360_product_cost_history(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(to_jsonb(c) - 'created_by' - 'approved_by' ORDER BY c.variant_id NULLS FIRST, c.market NULLS FIRST, c.effective_from DESC, c.created_at DESC), '[]')
          FROM f360.product_cost_versions c WHERE c.product_id = p_product_id);
END $$;

ALTER TABLE f360.product_cost_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.product_cost_versions, f360.product_cost_effective FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.product_cost_versions TO service_role;
GRANT SELECT ON f360.product_cost_effective TO service_role;
REVOKE ALL ON FUNCTION f360.product_cost_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_product_cost_propose(uuid, uuid, text, numeric, text, date, text, text), public.f360_product_cost_decide(uuid, boolean, text),
  public.f360_product_cost_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_product_cost_propose(uuid, uuid, text, numeric, text, date, text, text), public.f360_product_cost_decide(uuid, boolean, text),
  public.f360_product_cost_history(uuid) TO authenticated, service_role;
