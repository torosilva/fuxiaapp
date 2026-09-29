-- S0.5 — Single loyalty write path: public.loyalty_apply. STAGING. Additive.
-- Preserves EXACTLY today's production in-store economics (claim-sale v14 creditPoints), verified BEFORE/AFTER
-- (docs/fuxia360/audit/s00a_results/s05_economics.json):
--   pairs = Σ line quantity (a line without quantity counts 1) · 100 points per pair · tier from points 300/900 via the
--   existing trg_update_tier · purchase stats via the existing trg_purchase_stats · transactions channel/status/currency as today.
-- Decisions: D-R1 NO referral bonus (production has none) · D-S2 self_sale = 0 loyalty, audited · Q7 not callable by clients.
-- Deliberate fixes (no economics effect): purchase_items are actually saved (they failed silently: sku NOT NULL);
-- concurrent credits can't lose updates (card row lock + relative increments); idempotent by key.
-- Rollback: supabase/rollbacks/20261002000100_s05_loyalty_apply.down.sql

ALTER TABLE public.transactions
  ADD COLUMN ref_type text,
  ADD COLUMN ref_id text,
  ADD COLUMN idempotency_key text,
  ADD COLUMN actor jsonb;
CREATE UNIQUE INDEX transactions_idempotency_key_key ON public.transactions (idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE public.loyalty_apply_audit (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  idempotency_key  text NOT NULL,
  card_id          uuid,
  customer_id      uuid,
  ref_type         text,
  ref_id           text,
  channel          text,
  result           text NOT NULL CHECK (result IN ('applied', 'replayed', 'self_sale')),
  points           integer NOT NULL DEFAULT 0,
  pairs            integer NOT NULL DEFAULT 0,
  transaction_id   uuid,
  actor            jsonb,
  at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX loyalty_apply_audit_key_idx ON public.loyalty_apply_audit (idempotency_key);
ALTER TABLE public.loyalty_apply_audit ENABLE ROW LEVEL SECURITY;          -- no policies: service/definer only
CREATE TRIGGER loyalty_apply_audit_append_only BEFORE UPDATE OR DELETE ON public.loyalty_apply_audit
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
REVOKE ALL ON public.loyalty_apply_audit FROM PUBLIC, anon, authenticated;

-- The ONLY place that decides which quantities count as pairs (Q4 hook for future category rules).
CREATE FUNCTION public.loyalty_pairs_for_lines(p_lines jsonb) RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(sum(greatest(coalesce((l->>'quantity')::int, 1), 0)), 0)::int FROM jsonb_array_elements(coalesce(p_lines, '[]')) l
$$;
CREATE FUNCTION public.loyalty_points_per_pair() RETURNS integer LANGUAGE sql IMMUTABLE AS $$ SELECT 100 $$;

CREATE FUNCTION public.loyalty_apply(p_card_id uuid, p_lines jsonb, p_amount numeric, p_channel text, p_ref_type text, p_ref_id text,
  p_idempotency_key text, p_actor jsonb DEFAULT '{}', p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE card public.loyalty_cards; v_customer public.customers; prior public.loyalty_apply_audit; v_pairs int; v_points int; v_tx uuid; li jsonb; n int := 0;
BEGIN
  IF coalesce(btrim(p_idempotency_key), '') = '' THEN RAISE EXCEPTION 'loyalty_apply: falta la llave de idempotencia.'; END IF;
  IF p_channel NOT IN ('store', 'web', 'app') THEN RAISE EXCEPTION 'loyalty_apply: canal no válido.'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN RAISE EXCEPTION 'loyalty_apply: no hay líneas.'; END IF;

  -- idempotency: the same key returns the first result (applied or self_sale), never a second credit
  SELECT * INTO prior FROM public.loyalty_apply_audit WHERE idempotency_key = p_idempotency_key AND result IN ('applied', 'self_sale') ORDER BY id LIMIT 1;
  IF prior.id IS NOT NULL THEN
    INSERT INTO public.loyalty_apply_audit (idempotency_key, card_id, customer_id, ref_type, ref_id, channel, result, points, pairs, transaction_id, actor)
      VALUES (p_idempotency_key, prior.card_id, prior.customer_id, p_ref_type, p_ref_id, p_channel, 'replayed', 0, 0, prior.transaction_id, p_actor);
    RETURN jsonb_build_object('applied', prior.result = 'applied', 'replayed', true, 'self_sale', prior.result = 'self_sale',
      'points', prior.points, 'pairs', prior.pairs, 'transaction_id', prior.transaction_id);
  END IF;

  -- lock the card: concurrent credits are serialized (P1-1)
  SELECT * INTO card FROM public.loyalty_cards WHERE id = p_card_id FOR UPDATE;
  IF card.id IS NULL THEN RAISE EXCEPTION 'loyalty_apply: tarjeta no encontrada.'; END IF;
  SELECT * INTO v_customer FROM public.customers WHERE id = card.customer_id;

  -- D-S2: the pair left, but the seller never earns loyalty on her own identity
  IF nullif(p_actor->>'auth_user_id', '') IS NOT NULL AND v_customer.auth_user_id IS NOT NULL AND v_customer.auth_user_id = (p_actor->>'auth_user_id')::uuid THEN
    INSERT INTO public.loyalty_apply_audit (idempotency_key, card_id, customer_id, ref_type, ref_id, channel, result, points, pairs, actor)
      VALUES (p_idempotency_key, card.id, card.customer_id, p_ref_type, p_ref_id, p_channel, 'self_sale', 0, public.loyalty_pairs_for_lines(p_lines), p_actor);
    RETURN jsonb_build_object('applied', false, 'replayed', false, 'self_sale', true, 'points', 0, 'pairs', public.loyalty_pairs_for_lines(p_lines));
  END IF;

  v_pairs := public.loyalty_pairs_for_lines(p_lines);
  IF v_pairs <= 0 THEN RAISE EXCEPTION 'loyalty_apply: la venta no tiene pares.'; END IF;
  v_points := v_pairs * public.loyalty_points_per_pair();

  -- same row shape as today (claim-sale v14): wc_order_id NULL, currency MXN, status completed → trg_purchase_stats as today
  INSERT INTO public.transactions (loyalty_card_id, wc_order_id, amount, currency, points_earned, pairs_in_order, channel, status, notes,
      ref_type, ref_id, idempotency_key, actor)
    VALUES (card.id, NULL, p_amount, 'MXN', v_points, v_pairs, p_channel, 'completed', p_notes, p_ref_type, p_ref_id, p_idempotency_key, p_actor)
    RETURNING id INTO v_tx;

  -- line items are actually saved now (sku is NOT NULL: legacy lines without SKU get a deterministic surrogate)
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    n := n + 1;
    INSERT INTO public.purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price, wc_product_id)
      VALUES (v_tx,
              coalesce(nullif(btrim(li->>'sku'), ''), 'LEGACY-' || coalesce(nullif(li->>'channel_inventory_id', ''), nullif(li->>'inventory_id', ''), 'SIN-REF') || '-' || n),
              coalesce(nullif(li->>'product_name', ''), 'Producto'), nullif(li->>'size', ''), nullif(li->>'color', ''), nullif(li->>'category', ''),
              greatest(coalesce((li->>'quantity')::int, 1), 0), nullif(li->>'unit_price', '')::numeric, nullif(li->>'wc_product_id', '')::int);
  END LOOP;

  -- relative increments under the lock; tier recalculated by the existing trigger exactly as today (300/900)
  UPDATE public.loyalty_cards SET total_points = coalesce(total_points, 0) + v_points, pairs_count = coalesce(pairs_count, 0) + v_pairs, updated_at = now()
    WHERE id = card.id RETURNING * INTO card;

  INSERT INTO public.loyalty_apply_audit (idempotency_key, card_id, customer_id, ref_type, ref_id, channel, result, points, pairs, transaction_id, actor)
    VALUES (p_idempotency_key, card.id, card.customer_id, p_ref_type, p_ref_id, p_channel, 'applied', v_points, v_pairs, v_tx, p_actor);
  -- D-R1: NO referral bonus here (production claim-sale v14 pays none). Referral is a separate future decision.
  RETURN jsonb_build_object('applied', true, 'replayed', false, 'self_sale', false, 'points', v_points, 'pairs', v_pairs,
    'transaction_id', v_tx, 'total_points', card.total_points, 'tier', card.tier);
END $$;

-- Q7: never callable by the app (anon/authenticated); only service_role and SECURITY DEFINER sale/claim RPCs.
REVOKE ALL ON FUNCTION public.loyalty_apply(uuid, jsonb, numeric, text, text, text, text, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.loyalty_apply(uuid, jsonb, numeric, text, text, text, text, jsonb, text) TO service_role;
REVOKE ALL ON FUNCTION public.loyalty_pairs_for_lines(jsonb), public.loyalty_points_per_pair() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.loyalty_pairs_for_lines(jsonb), public.loyalty_points_per_pair() TO service_role;
