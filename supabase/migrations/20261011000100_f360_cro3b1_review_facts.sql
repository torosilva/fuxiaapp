-- Fuxia 360 · CRO-3B1 — review intelligence layer over CusRev: fit facts + purchase verification (STAGING). Mario 2026-10-05.
-- CusRev / WooCommerce stay the review engine (text, stars, photos, moderation, Q&A). Fuxia 360 keeps ONLY:
--   · per review: model (canonical product), star number, moderation state, media count (projections, no text, no PII);
--   · verification decided by F360 from its OWN facts (paid Woo order in Commerce Facts, store sale in offline_sales);
--   · structured fit (usual size, purchased size, fit, comfort, would recommend) in the canonical size scale;
--   · per-model aggregates with the approved progressive display rule (<5 editorial · 5–9 count · ≥10 percent · Wilson guard).
-- Identity: canonical product / variant through f360.channel_product_identity / channel_variant_identity (no new identity).
-- PII: the reviewer's e-mail never reaches F360; WordPress sends a SHA-256 of it, compared on the fly and never stored.
-- Verification is per MODEL (all colours share the last): evidence.match says whether she bought the reviewed Woo product
-- itself ('same_product') or the same model in another colour ('same_model'), so channels never imply the wrong colour.
-- A review is NEVER verified because somebody says so: Carolina can only identify the ITEM of a store sale whose buyer
-- identity the system already proved (legacy items without a canonical variant), like legacy homologation.
-- Rollback: supabase/rollbacks/20261011000100_f360_cro3b1_review_facts.down.sql

-- ── Sizes: canonical labels are Fuxia sizes (35–40); the Mexican size is Fuxia − 13 (rule already used by the PDP and
--    Hilo's KB table). One place in the database to convert.
CREATE FUNCTION f360.size_mx(p_label text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_label ~ '^\d{2}(\.5)?$' THEN trim_scale(p_label::numeric - 13)::text END
$$;
CREATE FUNCTION f360.size_from_mx(p_mx text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_mx ~ '^\d{2}(\.5)?$' THEN trim_scale(p_mx::numeric + 13)::text END
$$;

-- ── Display / statistics parameters (one place) ──
CREATE FUNCTION f360.review_params() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('min_count', 5, 'min_percent', 10, 'wilson_z', 1.96, 'wilson_min_claim', 0.70, 'window_months', 24)
$$;

-- Wilson score interval, lower bound (k successes out of n).
CREATE FUNCTION f360.wilson_lower(p_k integer, p_n integer, p_z numeric DEFAULT 1.96) RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN coalesce(p_n, 0) <= 0 THEN NULL ELSE
    round(((p_k::numeric / p_n) + p_z * p_z / (2 * p_n)
           - p_z * sqrt((p_k::numeric / p_n) * (1 - p_k::numeric / p_n) / p_n + p_z * p_z / (4.0 * p_n * p_n)))
          / (1 + p_z * p_z / p_n), 4) END
$$;

-- ── One row per Woo/CusRev review ──
CREATE TABLE f360.review_facts (
  sales_channel_id      uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_review_id         bigint NOT NULL CHECK (woo_review_id > 0),
  woo_product_id        bigint NOT NULL CHECK (woo_product_id > 0),
  product_id            uuid REFERENCES f360.products(id) ON DELETE RESTRICT,     -- the MODEL; NULL = Woo product not homologated
  rating                smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),          -- projection of the CusRev stars (number only)
  review_status         text NOT NULL CHECK (review_status IN ('approved', 'pending', 'spam', 'trash')),
  media_count           smallint NOT NULL DEFAULT 0 CHECK (media_count >= 0),
  woo_verified          boolean NOT NULL DEFAULT false,                             -- what Woo/CusRev says today (informative only)
  reviewed_at           timestamptz NOT NULL,
  verification          text NOT NULL DEFAULT 'UNVERIFIED' CHECK (verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE', 'UNVERIFIED', 'NEEDS_REVIEW')),
  woo_order_id          bigint,
  offline_sale_id       uuid REFERENCES public.offline_sales(id) ON DELETE RESTRICT,
  offline_sale_item_id  uuid REFERENCES public.offline_sale_items(id) ON DELETE RESTRICT,
  purchased_variant_id  uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,   -- set when the purchase has ONE variant of the model
  purchased_size        text CHECK (purchased_size ~ '^\d{2}(\.5)?$'),            -- canonical (Fuxia) scale
  verified_at           timestamptz,
  verified_by           text,
  evidence              jsonb NOT NULL DEFAULT '{}',                                -- kinds only; never e-mail, phone, name or hash
  usual_size            text CHECK (usual_size ~ '^\d{2}(\.5)?$'),                -- canonical (Fuxia) scale
  fit                   text CHECK (fit IN ('small', 'true', 'large')),
  comfort               smallint CHECK (comfort BETWEEN 1 AND 5),
  would_recommend       boolean,
  fit_captured_via      text CHECK (fit_captured_via IN ('review_form', 'review_request')),
  fit_captured_at       timestamptz,
  first_synced_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_synced_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (sales_channel_id, woo_review_id),
  CONSTRAINT review_verified_online_ref CHECK (verification <> 'VERIFIED_ONLINE' OR (woo_order_id IS NOT NULL AND offline_sale_id IS NULL)),
  CONSTRAINT review_verified_store_ref  CHECK (verification <> 'VERIFIED_STORE' OR (offline_sale_id IS NOT NULL AND woo_order_id IS NULL)),
  CONSTRAINT review_unverified_no_ref   CHECK (verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE')
                                               OR (woo_order_id IS NULL AND offline_sale_id IS NULL AND purchased_variant_id IS NULL AND verified_at IS NULL)),
  CONSTRAINT review_verified_has_model  CHECK (verification NOT IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') OR product_id IS NOT NULL),
  CONSTRAINT review_fit_needs_capture   CHECK ((fit IS NULL AND comfort IS NULL AND would_recommend IS NULL AND usual_size IS NULL) = (fit_captured_at IS NULL))
);
CREATE INDEX review_facts_product_idx ON f360.review_facts (product_id) WHERE product_id IS NOT NULL;
COMMENT ON TABLE f360.review_facts IS 'CRO-3B1: F360 intelligence per CusRev review (model, verification, fit). Text, author, photos and moderation live in CusRev/WP.';

-- Store purchases whose BUYER the system proved but whose ITEM has no canonical variant (legacy). Carolina identifies the item.
CREATE TABLE f360.review_purchase_candidates (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sales_channel_id      uuid NOT NULL,
  woo_review_id         bigint NOT NULL,
  offline_sale_id       uuid NOT NULL REFERENCES public.offline_sales(id) ON DELETE RESTRICT,
  offline_sale_item_id  uuid REFERENCES public.offline_sale_items(id) ON DELETE RESTRICT,   -- NULL = old app sale (items only in jsonb)
  item_index            integer NOT NULL DEFAULT 0,
  item_snapshot         jsonb NOT NULL,                                             -- product name / size / color only
  sale_at               timestamptz NOT NULL,
  location_id           uuid,
  identity_evidence     text NOT NULL CHECK (identity_evidence IN ('email_hash', 'woo_customer_id')),
  status                text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'confirmed', 'rejected')),
  decided_by            text,
  decided_at            timestamptz,
  decision_note         text CHECK (length(decision_note) <= 300),
  created_at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (sales_channel_id, woo_review_id) REFERENCES f360.review_facts (sales_channel_id, woo_review_id) ON DELETE CASCADE,
  UNIQUE NULLS NOT DISTINCT (sales_channel_id, woo_review_id, offline_sale_id, offline_sale_item_id, item_index)
);

-- Append-only audit of every verification / fit change.
CREATE TABLE f360.review_facts_log (
  id                bigserial PRIMARY KEY,
  sales_channel_id  uuid NOT NULL,
  woo_review_id     bigint NOT NULL,
  action            text NOT NULL CHECK (action IN ('synced', 'verified', 'needs_review', 'unverified', 'candidate_confirmed',
                                                    'candidate_rejected', 'revoked', 'fit_captured')),
  from_state        text,
  to_state          text,
  by_name           text NOT NULL,
  detail            jsonb NOT NULL DEFAULT '{}',
  at                timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER review_facts_log_append_only BEFORE UPDATE OR DELETE ON f360.review_facts_log FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

ALTER TABLE f360.review_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.review_purchase_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.review_facts_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.review_facts, f360.review_purchase_candidates, f360.review_facts_log FROM PUBLIC, anon, authenticated;

-- ── Verification (F360 decides from its own facts). Sticky: a verified review is only un-verified by an owner (revoke).
-- p_claims (from the WordPress server, never stored): {woo_user_id, email_sha256, woo_order_ids: [..]}
--   woo_order_ids = paid orders WordPress found for the reviewer's account or billing e-mail (WP owns the e-mail).
--   F360 accepts an order only if Commerce Facts has it as paid, before the review, with a line of the review's model.
CREATE FUNCTION f360.review_verify(p_channel uuid, p_review bigint, p_claims jsonb, p_by text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.review_facts; t f360.sales_targets; c jsonb := coalesce(p_claims, '{}');
  v_user bigint; v_hash text; v_orders bigint[]; online record; store record; n_legacy int := 0; v_sizes text[]; v_variants uuid[];
  v_state text; v_detail jsonb;
BEGIN
  SELECT * INTO r FROM f360.review_facts WHERE sales_channel_id = p_channel AND woo_review_id = p_review FOR UPDATE;
  IF r.woo_review_id IS NULL THEN RAISE EXCEPTION 'Reseña no encontrada.'; END IF;
  IF r.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') THEN RETURN jsonb_build_object('verification', r.verification, 'changed', false); END IF;
  SELECT * INTO t FROM f360.sales_targets WHERE id = p_channel;

  v_user := CASE WHEN (c->>'woo_user_id') ~ '^\d{1,18}$' AND (c->>'woo_user_id')::bigint > 0 THEN (c->>'woo_user_id')::bigint END;
  v_hash := CASE WHEN lower(c->>'email_sha256') ~ '^[0-9a-f]{64}$' THEN lower(c->>'email_sha256') END;
  SELECT array_agg(DISTINCT x::bigint) INTO v_orders FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(c->'woo_order_ids') = 'array' THEN c->'woo_order_ids' ELSE '[]' END) x
    WHERE x ~ '^\d{1,18}$';

  IF r.product_id IS NULL THEN
    v_state := 'UNVERIFIED'; v_detail := jsonb_build_object('reason', 'model_not_homologated');
  ELSE
    -- 1 · Online: paid order of this channel, before the review, containing the model.
    SELECT o.woo_order_id,
           CASE WHEN v_user IS NOT NULL AND o.woo_customer_id = v_user THEN 'woo_customer_id' ELSE 'wp_order_email' END AS identity,
           array_agg(DISTINCT l.variant_id) FILTER (WHERE l.variant_id IS NOT NULL) AS variants,
           bool_or(l.woo_product_id = r.woo_product_id) AS same_product,
           coalesce(o.first_paid_at, o.woo_created_at) AS at
      INTO online
    FROM f360.commerce_woo_orders o
    JOIN f360.commerce_order_lines l ON l.source_system = 'woo' AND l.external_ref = t.key || ':' || o.woo_order_id AND l.product_id = r.product_id
    WHERE o.target_id = p_channel AND o.ever_paid
      AND (o.woo_order_id = ANY (coalesce(v_orders, '{}')) OR (v_user IS NOT NULL AND o.woo_customer_id = v_user))
      AND coalesce(o.first_paid_at, o.woo_created_at) <= r.reviewed_at
    GROUP BY o.woo_order_id, o.woo_customer_id, o.first_paid_at, o.woo_created_at
    ORDER BY coalesce(o.first_paid_at, o.woo_created_at) DESC LIMIT 1;

    -- 2 · Store: a sale of a customer whose e-mail hash / Woo account matches, before the review, with the model (canonical item).
    WITH buyer AS (
      SELECT cu.id, CASE WHEN v_user IS NOT NULL AND cu.wc_customer_id = v_user THEN 'woo_customer_id' ELSE 'email_hash' END AS identity
      FROM public.customers cu
      WHERE (v_hash IS NOT NULL AND cu.email IS NOT NULL AND encode(extensions.digest(lower(btrim(cu.email)), 'sha256'), 'hex') = v_hash)
         OR (v_user IS NOT NULL AND cu.wc_customer_id = v_user))
    SELECT s.id AS sale_id, s.created_at AS at, b.identity, array_agg(i.id) AS items, array_agg(DISTINCT i.variant_id) AS variants,
           bool_or(EXISTS (SELECT 1 FROM f360.channel_variant_identity cvi WHERE cvi.sales_channel_id = p_channel
                             AND cvi.canonical_variant_id = i.variant_id AND cvi.woo_product_id = r.woo_product_id)) AS same_product
      INTO store
    FROM buyer b JOIN public.offline_sales s ON s.customer_id = b.id AND NOT s.self_sale AND s.created_at <= r.reviewed_at
    JOIN public.offline_sale_items i ON i.sale_id = s.id AND i.variant_id IS NOT NULL
    JOIN f360.product_variants pv ON pv.id = i.variant_id AND pv.product_id = r.product_id
    GROUP BY s.id, s.created_at, b.identity
    ORDER BY s.created_at DESC LIMIT 1;

    IF online.woo_order_id IS NOT NULL AND (store.sale_id IS NULL OR online.at >= store.at) THEN
      v_variants := online.variants;
      SELECT array_agg(DISTINCT pv.size_label ORDER BY pv.size_label) INTO v_sizes FROM f360.product_variants pv WHERE pv.id = ANY (v_variants);
      UPDATE f360.review_facts SET verification = 'VERIFIED_ONLINE', woo_order_id = online.woo_order_id,
        purchased_variant_id = CASE WHEN cardinality(v_variants) = 1 THEN v_variants[1] END,
        purchased_size = CASE WHEN cardinality(v_sizes) = 1 THEN v_sizes[1] ELSE purchased_size END,
        verified_at = clock_timestamp(), verified_by = p_by,
        evidence = jsonb_build_object('source', 'commerce_woo_orders', 'identity', online.identity, 'sizes', to_jsonb(coalesce(v_sizes, '{}')),
                                      'match', CASE WHEN online.same_product THEN 'same_product' ELSE 'same_model' END)
      WHERE sales_channel_id = p_channel AND woo_review_id = p_review;
      v_state := 'VERIFIED_ONLINE'; v_detail := jsonb_build_object('identity', online.identity);
    ELSIF store.sale_id IS NOT NULL THEN
      v_variants := store.variants;
      SELECT array_agg(DISTINCT pv.size_label ORDER BY pv.size_label) INTO v_sizes FROM f360.product_variants pv WHERE pv.id = ANY (v_variants);
      UPDATE f360.review_facts SET verification = 'VERIFIED_STORE', offline_sale_id = store.sale_id,
        offline_sale_item_id = CASE WHEN cardinality(store.items) = 1 THEN store.items[1] END,
        purchased_variant_id = CASE WHEN cardinality(v_variants) = 1 THEN v_variants[1] END,
        purchased_size = CASE WHEN cardinality(v_sizes) = 1 THEN v_sizes[1] ELSE purchased_size END,
        verified_at = clock_timestamp(), verified_by = p_by,
        evidence = jsonb_build_object('source', 'offline_sales', 'identity', store.identity, 'sizes', to_jsonb(coalesce(v_sizes, '{}')),
                                      'match', CASE WHEN store.same_product THEN 'same_product' ELSE 'same_model' END)
      WHERE sales_channel_id = p_channel AND woo_review_id = p_review;
      v_state := 'VERIFIED_STORE'; v_detail := jsonb_build_object('identity', store.identity);
    ELSE
      -- 3 · Proven buyer, store sale BEFORE the review, item without canonical variant → candidate for Carolina (item identification only).
      WITH buyer AS (
        SELECT cu.id, CASE WHEN v_user IS NOT NULL AND cu.wc_customer_id = v_user THEN 'woo_customer_id' ELSE 'email_hash' END AS identity
        FROM public.customers cu
        WHERE (v_hash IS NOT NULL AND cu.email IS NOT NULL AND encode(extensions.digest(lower(btrim(cu.email)), 'sha256'), 'hex') = v_hash)
           OR (v_user IS NOT NULL AND cu.wc_customer_id = v_user)),
      legacy AS (
        SELECT s.id AS sale_id, i.id AS item_id, i.line_no AS idx, s.created_at, s.location_id, b.identity,
               jsonb_strip_nulls(jsonb_build_object('product_name', i.product_name, 'size', i.size, 'color', i.color)) AS snap
        FROM buyer b JOIN public.offline_sales s ON s.customer_id = b.id AND NOT s.self_sale AND s.created_at <= r.reviewed_at
        JOIN public.offline_sale_items i ON i.sale_id = s.id AND i.variant_id IS NULL
        UNION ALL
        SELECT s.id, NULL, e.ord::int, s.created_at, s.location_id, b.identity,
               jsonb_strip_nulls(jsonb_build_object('product_name', coalesce(e.it->>'product_name', e.it->>'name', e.it->>'model'),
                                                    'size', coalesce(e.it->>'size', e.it->>'talla'), 'color', e.it->>'color'))
        FROM buyer b JOIN public.offline_sales s ON s.customer_id = b.id AND NOT s.self_sale AND s.created_at <= r.reviewed_at
        CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(s.items) = 'array' THEN s.items ELSE '[]' END) WITH ORDINALITY e(it, ord)
        WHERE NOT EXISTS (SELECT 1 FROM public.offline_sale_items i2 WHERE i2.sale_id = s.id))
      INSERT INTO f360.review_purchase_candidates (sales_channel_id, woo_review_id, offline_sale_id, offline_sale_item_id, item_index,
                                                   item_snapshot, sale_at, location_id, identity_evidence)
      SELECT p_channel, p_review, sale_id, item_id, coalesce(idx, 0), snap, created_at, location_id, identity FROM legacy
      ON CONFLICT DO NOTHING;
      SELECT count(*) INTO n_legacy FROM f360.review_purchase_candidates
        WHERE sales_channel_id = p_channel AND woo_review_id = p_review AND status = 'open';
      v_state := CASE WHEN n_legacy > 0 THEN 'NEEDS_REVIEW' ELSE 'UNVERIFIED' END;
      v_detail := CASE WHEN n_legacy > 0 THEN jsonb_build_object('reason', 'buyer_proven_item_unlinked', 'candidates', n_legacy)
                       ELSE jsonb_build_object('reason', 'no_purchase_found') END;
    END IF;
  END IF;

  IF v_state IN ('UNVERIFIED', 'NEEDS_REVIEW') THEN
    UPDATE f360.review_facts SET verification = v_state, evidence = v_detail WHERE sales_channel_id = p_channel AND woo_review_id = p_review;
  END IF;
  IF v_state <> r.verification THEN
    INSERT INTO f360.review_facts_log (sales_channel_id, woo_review_id, action, from_state, to_state, by_name, detail)
    VALUES (p_channel, p_review, CASE v_state WHEN 'NEEDS_REVIEW' THEN 'needs_review' WHEN 'UNVERIFIED' THEN 'unverified' ELSE 'verified' END,
            r.verification, v_state, p_by, v_detail);
  END IF;
  RETURN jsonb_build_object('verification', v_state, 'changed', v_state <> r.verification, 'detail', v_detail);
END $$;

-- ── Sync one review from the WordPress server (Edge Function f360-storefront · review_sync, server key). service_role only.
-- p_review: {woo_review_id, woo_product_id, rating, status, media_count, woo_verified, reviewed_at, claims{...}}
CREATE FUNCTION public.f360_review_sync(p_target_key text, p_review jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; j jsonb := coalesce(p_review, '{}'); v_id bigint; v_prod bigint; v_model uuid; v_models int;
  v_status text; v_at timestamptz; prior f360.review_facts; res jsonb;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND active;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  IF NOT ((j->>'woo_review_id') ~ '^\d{1,18}$' AND (j->>'woo_product_id') ~ '^\d{1,18}$') THEN RAISE EXCEPTION 'Reseña no válida.'; END IF;
  v_id := (j->>'woo_review_id')::bigint; v_prod := (j->>'woo_product_id')::bigint;
  IF NOT ((j->>'rating') ~ '^[1-5]$') THEN RAISE EXCEPTION 'Calificación no válida.'; END IF;
  v_status := CASE j->>'status' WHEN '1' THEN 'approved' WHEN 'approved' THEN 'approved' WHEN '0' THEN 'pending' WHEN 'hold' THEN 'pending'
                WHEN 'pending' THEN 'pending' WHEN 'spam' THEN 'spam' WHEN 'trash' THEN 'trash' END;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  BEGIN v_at := (j->>'reviewed_at')::timestamptz; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Fecha no válida.'; END;
  IF v_at IS NULL OR v_at > clock_timestamp() + interval '1 day' THEN RAISE EXCEPTION 'Fecha no válida.'; END IF;

  -- the model: only when the Woo product maps to exactly ONE canonical product
  SELECT min(canonical_product_id::text)::uuid, count(DISTINCT canonical_product_id) INTO v_model, v_models
  FROM f360.channel_product_identity WHERE sales_channel_id = t.id AND woo_product_id = v_prod;
  IF v_models <> 1 THEN v_model := NULL; END IF;

  SELECT * INTO prior FROM f360.review_facts WHERE sales_channel_id = t.id AND woo_review_id = v_id;
  IF prior.woo_review_id IS NOT NULL AND prior.woo_product_id <> v_prod THEN RAISE EXCEPTION 'La reseña cambió de producto.'; END IF;
  INSERT INTO f360.review_facts AS f (sales_channel_id, woo_review_id, woo_product_id, product_id, rating, review_status, media_count, woo_verified, reviewed_at)
  VALUES (t.id, v_id, v_prod, v_model, (j->>'rating')::smallint, v_status,
          least(greatest(coalesce(CASE WHEN (j->>'media_count') ~ '^\d{1,4}$' THEN (j->>'media_count')::int END, 0), 0), 100),
          coalesce((j->>'woo_verified')::boolean, false), v_at)
  ON CONFLICT (sales_channel_id, woo_review_id) DO UPDATE SET
    product_id = CASE WHEN f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') THEN f.product_id ELSE EXCLUDED.product_id END,
    rating = EXCLUDED.rating, review_status = EXCLUDED.review_status, media_count = EXCLUDED.media_count,
    woo_verified = EXCLUDED.woo_verified, last_synced_at = clock_timestamp();
  IF prior.woo_review_id IS NULL OR prior.review_status <> v_status OR prior.rating <> (j->>'rating')::smallint THEN
    INSERT INTO f360.review_facts_log (sales_channel_id, woo_review_id, action, from_state, to_state, by_name, detail)
    VALUES (t.id, v_id, 'synced', prior.review_status, v_status, 'woo', jsonb_build_object('rating', (j->>'rating')::int));
  END IF;

  res := f360.review_verify(t.id, v_id, j->'claims', 'system');
  RETURN jsonb_build_object('ok', true, 'woo_review_id', v_id,
    'product_key', (SELECT 'F360-' || code FROM f360.products WHERE id = v_model), 'verification', res->>'verification', 'detail', res->'detail');
END $$;

-- ── Structured fit for one review (Edge Function, server key; the forms come in 3B3). Sizes arrive in MX or Fuxia scale.
-- p_fit: {scale: 'mx'|'fuxia', usual_size, purchased_size?, fit: small|true|large, comfort: 1-5, would_recommend: bool, via}
CREATE FUNCTION public.f360_review_set_fit(p_target_key text, p_woo_review_id bigint, p_fit jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; r f360.review_facts; j jsonb := coalesce(p_fit, '{}'); mx boolean; v_usual text; v_bought text; v_sizes text[];
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND active;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  SELECT * INTO r FROM f360.review_facts WHERE sales_channel_id = t.id AND woo_review_id = p_woo_review_id FOR UPDATE;
  IF r.woo_review_id IS NULL THEN RAISE EXCEPTION 'Reseña no encontrada.'; END IF;
  IF r.fit_captured_at IS NOT NULL THEN RAISE EXCEPTION 'Esta reseña ya tiene ajuste.'; END IF;
  IF coalesce(j->>'scale', '') NOT IN ('mx', 'fuxia') THEN RAISE EXCEPTION 'Escala de talla no válida.'; END IF;
  mx := j->>'scale' = 'mx';
  v_usual  := CASE WHEN mx THEN f360.size_from_mx(j->>'usual_size') ELSE j->>'usual_size' END;
  v_bought := CASE WHEN mx THEN f360.size_from_mx(j->>'purchased_size') ELSE j->>'purchased_size' END;
  IF v_usual IS NULL OR v_usual !~ '^\d{2}(\.5)?$' THEN RAISE EXCEPTION 'Talla habitual no válida.'; END IF;
  IF coalesce(j->>'fit', '') NOT IN ('small', 'true', 'large') THEN RAISE EXCEPTION 'Ajuste no válido.'; END IF;
  IF NOT coalesce((j->>'comfort') ~ '^[1-5]$', false) THEN RAISE EXCEPTION 'Comodidad no válida.'; END IF;
  IF jsonb_typeof(j->'would_recommend') <> 'boolean' THEN RAISE EXCEPTION 'Recomendación no válida.'; END IF;
  IF coalesce(j->>'via', '') NOT IN ('review_form', 'review_request') THEN RAISE EXCEPTION 'Origen no válido.'; END IF;
  -- purchased size: from the verified purchase; if it had several sizes of the model, she picks one OF THOSE
  SELECT array_agg(x) INTO v_sizes FROM jsonb_array_elements_text(coalesce(r.evidence->'sizes', '[]')) x;
  IF r.purchased_size IS NOT NULL THEN
    IF v_bought IS NOT NULL AND v_bought <> r.purchased_size THEN RAISE EXCEPTION 'La talla comprada no coincide con la compra.'; END IF;
    v_bought := r.purchased_size;
  ELSIF v_bought IS NOT NULL AND r.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') AND NOT (v_bought = ANY (coalesce(v_sizes, '{}'))) THEN
    RAISE EXCEPTION 'La talla comprada no coincide con la compra.';
  END IF;
  IF v_bought IS NOT NULL AND v_bought !~ '^\d{2}(\.5)?$' THEN RAISE EXCEPTION 'Talla comprada no válida.'; END IF;

  UPDATE f360.review_facts SET usual_size = v_usual, purchased_size = v_bought, fit = j->>'fit', comfort = (j->>'comfort')::smallint,
    would_recommend = (j->>'would_recommend')::boolean, fit_captured_via = j->>'via', fit_captured_at = clock_timestamp()
  WHERE sales_channel_id = t.id AND woo_review_id = p_woo_review_id;
  INSERT INTO f360.review_facts_log (sales_channel_id, woo_review_id, action, to_state, by_name, detail)
  VALUES (t.id, p_woo_review_id, 'fit_captured', j->>'fit', j->>'via', jsonb_build_object('comfort', (j->>'comfort')::int));
  RETURN jsonb_build_object('ok', true, 'counts_for_fit', r.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE'));
END $$;

-- ── Carolina: identify the ITEM of a store sale whose buyer the system proved (owner only), or reject it. Revoke (owner).
CREATE FUNCTION public.f360_review_confirm_candidate(p_candidate_id uuid, p_variant_id uuid, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); c f360.review_purchase_candidates; f f360.review_facts; v f360.product_variants;
BEGIN
  SELECT * INTO c FROM f360.review_purchase_candidates WHERE id = p_candidate_id FOR UPDATE;
  IF c.id IS NULL OR c.status <> 'open' THEN RAISE EXCEPTION 'Esta compra ya no está pendiente.'; END IF;
  SELECT * INTO f FROM f360.review_facts WHERE sales_channel_id = c.sales_channel_id AND woo_review_id = c.woo_review_id FOR UPDATE;
  IF f.verification <> 'NEEDS_REVIEW' THEN RAISE EXCEPTION 'Esta reseña ya no está pendiente.'; END IF;
  SELECT * INTO v FROM f360.product_variants WHERE id = p_variant_id;
  IF v.id IS NULL OR v.product_id IS DISTINCT FROM f.product_id THEN RAISE EXCEPTION 'Elige una talla y color del mismo modelo de la reseña.'; END IF;

  UPDATE f360.review_purchase_candidates SET status = 'confirmed', decided_by = r.display_name, decided_at = clock_timestamp(), decision_note = left(p_note, 300)
  WHERE id = c.id;
  UPDATE f360.review_purchase_candidates SET status = 'rejected', decided_by = r.display_name, decided_at = clock_timestamp(), decision_note = 'otra compra confirmada'
  WHERE sales_channel_id = c.sales_channel_id AND woo_review_id = c.woo_review_id AND status = 'open';
  UPDATE f360.review_facts SET verification = 'VERIFIED_STORE', offline_sale_id = c.offline_sale_id, offline_sale_item_id = c.offline_sale_item_id,
    purchased_variant_id = v.id, purchased_size = v.size_label, verified_at = clock_timestamp(), verified_by = r.display_name,
    evidence = jsonb_build_object('source', 'offline_sales', 'identity', c.identity_evidence, 'item', 'identified_by_owner', 'sizes', jsonb_build_array(v.size_label),
                                  'match', CASE WHEN EXISTS (SELECT 1 FROM f360.channel_variant_identity cvi WHERE cvi.sales_channel_id = c.sales_channel_id
                                                               AND cvi.canonical_variant_id = v.id AND cvi.woo_product_id = f.woo_product_id)
                                                THEN 'same_product' ELSE 'same_model' END)
  WHERE sales_channel_id = c.sales_channel_id AND woo_review_id = c.woo_review_id;
  INSERT INTO f360.review_facts_log (sales_channel_id, woo_review_id, action, from_state, to_state, by_name, detail)
  VALUES (c.sales_channel_id, c.woo_review_id, 'candidate_confirmed', 'NEEDS_REVIEW', 'VERIFIED_STORE', r.display_name,
          jsonb_build_object('candidate', c.id, 'identity', c.identity_evidence, 'variant', v.sku));
  RETURN jsonb_build_object('ok', true, 'verification', 'VERIFIED_STORE');
END $$;

CREATE FUNCTION public.f360_review_reject_candidate(p_candidate_id uuid, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); c f360.review_purchase_candidates; left_open int;
BEGIN
  SELECT * INTO c FROM f360.review_purchase_candidates WHERE id = p_candidate_id FOR UPDATE;
  IF c.id IS NULL OR c.status <> 'open' THEN RAISE EXCEPTION 'Esta compra ya no está pendiente.'; END IF;
  UPDATE f360.review_purchase_candidates SET status = 'rejected', decided_by = r.display_name, decided_at = clock_timestamp(), decision_note = left(p_note, 300)
  WHERE id = c.id;
  SELECT count(*) INTO left_open FROM f360.review_purchase_candidates WHERE sales_channel_id = c.sales_channel_id AND woo_review_id = c.woo_review_id AND status = 'open';
  INSERT INTO f360.review_facts_log (sales_channel_id, woo_review_id, action, from_state, to_state, by_name, detail)
  VALUES (c.sales_channel_id, c.woo_review_id, 'candidate_rejected', 'NEEDS_REVIEW', CASE WHEN left_open = 0 THEN 'UNVERIFIED' ELSE 'NEEDS_REVIEW' END,
          r.display_name, jsonb_build_object('candidate', c.id));
  IF left_open = 0 THEN
    UPDATE f360.review_facts SET verification = 'UNVERIFIED', evidence = jsonb_build_object('reason', 'candidates_rejected')
    WHERE sales_channel_id = c.sales_channel_id AND woo_review_id = c.woo_review_id AND verification = 'NEEDS_REVIEW';
  END IF;
  RETURN jsonb_build_object('ok', true, 'verification', CASE WHEN left_open = 0 THEN 'UNVERIFIED' ELSE 'NEEDS_REVIEW' END);
END $$;

CREATE FUNCTION public.f360_review_revoke_verification(p_target_key text, p_woo_review_id bigint, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); t f360.sales_targets; f f360.review_facts;
BEGIN
  IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key;
  SELECT * INTO f FROM f360.review_facts WHERE sales_channel_id = t.id AND woo_review_id = p_woo_review_id FOR UPDATE;
  IF f.verification NOT IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') THEN RAISE EXCEPTION 'La reseña no está verificada.'; END IF;
  UPDATE f360.review_facts SET verification = 'UNVERIFIED', woo_order_id = NULL, offline_sale_id = NULL, offline_sale_item_id = NULL,
    purchased_variant_id = NULL, verified_at = NULL, verified_by = NULL, evidence = jsonb_build_object('reason', 'revoked')
  WHERE sales_channel_id = t.id AND woo_review_id = p_woo_review_id;
  INSERT INTO f360.review_facts_log (sales_channel_id, woo_review_id, action, from_state, to_state, by_name, detail)
  VALUES (t.id, p_woo_review_id, 'revoked', f.verification, 'UNVERIFIED', r.display_name, jsonb_build_object('reason', left(p_reason, 300)));
  RETURN jsonb_build_object('ok', true);
END $$;

-- ── Per-model metrics (Growth-ready; no conversion attribution). Only approved reviews; fit/comfort/recommend only verified.
CREATE VIEW f360.review_model_metrics AS
  WITH p AS (SELECT (f360.review_params()->>'window_months')::int AS months),
  f AS (SELECT r.* FROM f360.review_facts r, p
        WHERE r.product_id IS NOT NULL AND r.review_status = 'approved' AND r.reviewed_at >= now() - make_interval(months => p.months))
  SELECT f.product_id, 'F360-' || pr.code AS product_key,
    count(*)::int AS reviews,
    round(avg(f.rating), 2) AS rating_avg,
    count(*) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE'))::int AS verified_reviews,
    count(*) FILTER (WHERE f.verification = 'VERIFIED_ONLINE')::int AS verified_online,
    count(*) FILTER (WHERE f.verification = 'VERIFIED_STORE')::int AS verified_store,
    round(count(*) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE'))::numeric / count(*), 4) AS verified_rate,
    count(*) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') AND f.fit IS NOT NULL)::int AS fit_n,
    count(*) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') AND f.fit = 'small')::int AS fit_small,
    count(*) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') AND f.fit = 'true')::int AS fit_true,
    count(*) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') AND f.fit = 'large')::int AS fit_large,
    count(f.comfort) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE'))::int AS comfort_n,
    round(avg(f.comfort) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE')), 2) AS comfort_avg,
    count(f.would_recommend) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE'))::int AS recommend_n,
    count(*) FILTER (WHERE f.verification IN ('VERIFIED_ONLINE', 'VERIFIED_STORE') AND f.would_recommend)::int AS recommend_yes,
    count(*) FILTER (WHERE f.media_count > 0)::int AS photo_reviews,
    round(count(*) FILTER (WHERE f.media_count > 0)::numeric / count(*), 4) AS photo_rate,
    max(f.reviewed_at) AS last_review_at
  FROM f JOIN f360.products pr ON pr.id = f.product_id
  GROUP BY f.product_id, pr.code;
COMMENT ON VIEW f360.review_model_metrics IS 'CRO-3B1: per-model review metrics (approved reviews, 24-month window). Fit/comfort/recommend count verified purchases only. Questions are added by CRO-3C1.';

-- ── The ONE display rule (PDP, Hilo, admin). Texts live here. Never returns a number without its sample size.
CREATE FUNCTION f360.review_summary(p_product uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE m record; prm jsonb := f360.review_params(); min_c int := (prm->>'min_count')::int; min_p int := (prm->>'min_percent')::int;
  z numeric := (prm->>'wilson_z')::numeric; claim_min numeric := (prm->>'wilson_min_claim')::numeric;
  top text; k int; lb numeric; fit jsonb; comfort jsonb := NULL; rec jsonb := NULL; ed jsonb;
  word jsonb := '{"true": "viene a talla exacta", "small": "viene chica", "large": "viene grande"}';
BEGIN
  SELECT * INTO m FROM f360.review_model_metrics WHERE product_id = p_product;
  ed := f360.product_knowledge_public(p_product)->'fit';
  IF m.product_id IS NULL OR coalesce(m.fit_n, 0) < min_c THEN
    -- n < 5 verified: editorial fit validated by Carolina only (or nothing)
    fit := CASE WHEN ed IS NOT NULL THEN jsonb_build_object('tier', 'editorial', 'category', ed->>'category', 'headline', 'Horma: ' || lower(ed->>'label'),
                                                             'advice', ed->>'advice', 'basis', 'Según Fuxia', 'n', coalesce(m.fit_n, 0)) END;
  ELSE
    SELECT c, n INTO top, k FROM (VALUES ('true', m.fit_true), ('small', m.fit_small), ('large', m.fit_large)) v(c, n) ORDER BY n DESC, (c = 'true') DESC LIMIT 1;
    lb := f360.wilson_lower(k, m.fit_n, z);
    fit := jsonb_build_object('n', m.fit_n, 'counts', jsonb_build_object('small', m.fit_small, 'true', m.fit_true, 'large', m.fit_large),
      'category', top, 'wilson_lower', lb, 'claim', lb >= claim_min AND m.fit_n >= min_p,
      'basis', 'Basado en ' || m.fit_n || ' compras verificadas');
    IF m.fit_n < min_p THEN
      fit := fit || jsonb_build_object('tier', 'count', 'headline', k || ' de ' || m.fit_n || ' compradoras verificadas dicen que ' || (word->>top));
    ELSE
      fit := fit || jsonb_build_object('tier', 'percent', 'percent', round(100.0 * k / m.fit_n),
                                       'headline', round(100.0 * k / m.fit_n) || '% dice que ' || (word->>top));
    END IF;
    IF ed IS NOT NULL THEN fit := fit || jsonb_build_object('editorial', jsonb_build_object('category', ed->>'category', 'label', ed->>'label')); END IF;
  END IF;
  IF coalesce(m.comfort_n, 0) >= min_c THEN
    comfort := jsonb_build_object('n', m.comfort_n, 'avg', m.comfort_avg, 'headline', 'Comodidad ' || to_char(m.comfort_avg, 'FM0.0') || '/5');
  END IF;
  IF coalesce(m.recommend_n, 0) >= min_c THEN
    rec := jsonb_build_object('n', m.recommend_n, 'yes', m.recommend_yes, 'headline', CASE WHEN m.recommend_n < min_p
      THEN m.recommend_yes || ' de ' || m.recommend_n || ' la recomendarían'
      ELSE round(100.0 * m.recommend_yes / m.recommend_n) || '% la recomendaría' END);
  END IF;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'product_key', (SELECT 'F360-' || code FROM f360.products WHERE id = p_product),
    'reviews', CASE WHEN coalesce(m.reviews, 0) > 0 THEN jsonb_build_object('count', m.reviews, 'rating_avg', m.rating_avg,
                    'verified', m.verified_reviews, 'verified_online', m.verified_online, 'verified_store', m.verified_store, 'with_photos', m.photo_reviews) END,
    'fit', fit, 'comfort', comfort, 'recommend', rec));
END $$;

-- ── Carolina's work queue (one place). No review text or PII: links to the CusRev admin for the text.
CREATE FUNCTION public.f360_review_work_queue() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); min_c int := (f360.review_params()->>'min_count')::int;
BEGIN
  RETURN (WITH sold AS (
      SELECT product_id, sum(q)::int AS units FROM (
        SELECT l.product_id, l.quantity AS q FROM f360.commerce_order_lines l
          JOIN f360.commerce_woo_orders o ON l.source_system = 'woo' AND l.external_ref = (SELECT key FROM f360.sales_targets WHERE id = o.target_id) || ':' || o.woo_order_id
          WHERE o.ever_paid AND coalesce(o.first_paid_at, o.woo_created_at) >= now() - interval '90 days' AND l.product_id IS NOT NULL
        UNION ALL
        SELECT pv.product_id, i.quantity FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id
          JOIN f360.product_variants pv ON pv.id = i.variant_id WHERE s.created_at >= now() - interval '90 days') x
      GROUP BY product_id),
    models AS (
      SELECT p.id, 'F360-' || p.code AS product_key, p.name, coalesce(s.units, 0) AS units_90d,
             coalesce(k.status = 'validado', false) AS fit_validated, coalesce(m.reviews, 0) AS reviews, coalesce(m.verified_reviews, 0) AS verified,
             coalesce(m.fit_n, 0) AS fit_n
      FROM f360.products p LEFT JOIN sold s ON s.product_id = p.id LEFT JOIN f360.product_knowledge k ON k.product_id = p.id
      LEFT JOIN f360.review_model_metrics m ON m.product_id = p.id
      WHERE p.status = 'active')
    SELECT jsonb_build_object(
      'priority_models', coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.units_90d DESC, x.name) FROM (SELECT * FROM models WHERE units_90d > 0 ORDER BY units_90d DESC LIMIT 10) x), '[]'),
      'models_without_fit', coalesce((SELECT jsonb_agg(jsonb_build_object('product_key', product_key, 'name', name, 'units_90d', units_90d) ORDER BY units_90d DESC, name)
                                      FROM models WHERE NOT fit_validated), '[]'),
      'models_few_reviews', coalesce((SELECT jsonb_agg(jsonb_build_object('product_key', product_key, 'name', name, 'reviews', reviews, 'verified', verified, 'fit_n', fit_n, 'units_90d', units_90d)
                                                       ORDER BY units_90d DESC, name) FROM models WHERE fit_n < min_c), '[]'),
      'reviews_pending_moderation', coalesce((SELECT jsonb_agg(jsonb_build_object('woo_review_id', f.woo_review_id, 'product_key', 'F360-' || p.code, 'rating', f.rating,
                                                    'reviewed_at', f.reviewed_at, 'admin_url', t.base_url || '/wp-admin/comment.php?action=editcomment&c=' || f.woo_review_id) ORDER BY f.reviewed_at)
                                              FROM f360.review_facts f JOIN f360.sales_targets t ON t.id = f.sales_channel_id LEFT JOIN f360.products p ON p.id = f.product_id
                                              WHERE f.review_status = 'pending'), '[]'),
      'reviews_needs_review', coalesce((SELECT jsonb_agg(jsonb_build_object('woo_review_id', f.woo_review_id, 'product_key', 'F360-' || p.code, 'product_name', p.name,
                                              'reviewed_at', f.reviewed_at, 'admin_url', t.base_url || '/wp-admin/comment.php?action=editcomment&c=' || f.woo_review_id,
                                              'candidates', (SELECT jsonb_agg(jsonb_build_object('candidate_id', c.id, 'sale_at', c.sale_at, 'item', c.item_snapshot,
                                                              'location', (SELECT name FROM f360.locations WHERE id = c.location_id), 'identity', c.identity_evidence) ORDER BY c.sale_at DESC)
                                                             FROM f360.review_purchase_candidates c WHERE c.sales_channel_id = f.sales_channel_id AND c.woo_review_id = f.woo_review_id AND c.status = 'open'))
                                        ORDER BY f.reviewed_at)
                                        FROM f360.review_facts f JOIN f360.sales_targets t ON t.id = f.sales_channel_id JOIN f360.products p ON p.id = f.product_id
                                        WHERE f.verification = 'NEEDS_REVIEW'), '[]'),
      'reviews_without_model', coalesce((SELECT jsonb_agg(jsonb_build_object('woo_review_id', f.woo_review_id, 'woo_product_id', f.woo_product_id,
                                               'admin_url', t.base_url || '/wp-admin/comment.php?action=editcomment&c=' || f.woo_review_id) ORDER BY f.reviewed_at)
                                         FROM f360.review_facts f JOIN f360.sales_targets t ON t.id = f.sales_channel_id WHERE f.product_id IS NULL AND f.review_status = 'approved'), '[]'),
      'counts', (SELECT jsonb_build_object('reviews', count(*), 'approved', count(*) FILTER (WHERE review_status = 'approved'),
                   'verified_online', count(*) FILTER (WHERE verification = 'VERIFIED_ONLINE'), 'verified_store', count(*) FILTER (WHERE verification = 'VERIFIED_STORE'),
                   'needs_review', count(*) FILTER (WHERE verification = 'NEEDS_REVIEW'), 'unverified', count(*) FILTER (WHERE verification = 'UNVERIFIED'))
                 FROM f360.review_facts)));
END $$;

-- Admin read of one model's summary (same rule the channels will use).
CREATE FUNCTION public.f360_review_summary(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer');
BEGIN RETURN f360.review_summary(p_product_id); END $$;

REVOKE ALL ON FUNCTION f360.review_verify(uuid, bigint, jsonb, text), f360.review_summary(uuid),
  public.f360_review_sync(text, jsonb), public.f360_review_set_fit(text, bigint, jsonb),
  public.f360_review_confirm_candidate(uuid, uuid, text), public.f360_review_reject_candidate(uuid, text),
  public.f360_review_revoke_verification(text, bigint, text), public.f360_review_work_queue(), public.f360_review_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_review_sync(text, jsonb), public.f360_review_set_fit(text, bigint, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.f360_review_sync(text, jsonb), public.f360_review_set_fit(text, bigint, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.f360_review_confirm_candidate(uuid, uuid, text), public.f360_review_reject_candidate(uuid, text),
  public.f360_review_revoke_verification(text, bigint, text), public.f360_review_work_queue(), public.f360_review_summary(uuid) TO authenticated;
