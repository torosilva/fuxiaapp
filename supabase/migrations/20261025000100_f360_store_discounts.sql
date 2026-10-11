-- Fuxia 360 · Descuentos en la venta de tienda (Mario 2026-10-11). Reverses SPRINT_0 Q3 ("sellers may not discount") by an
-- explicit owner decision; the thresholds come from Mario, none invented here:
--   · ONE percentage on the whole sale (not per pair, not an amount).
--   · A seller may give up to 10 % on her own.
--   · More than 10 % needs CAROLINA: her PIN typed on the seller's phone (she is in the store) OR a request she approves from
--     Fuxia 360 (she is not). Only people in f360.approval_scopes scope 'store_discount' approve (production: Carolina only;
--     owner role alone is NOT enough — Mario and Adrián are owners too).
--   · Carolina selling with her own shift may give any percentage.
--   · A pair sold with a store discount has NO exchange (Carolina's rule, BITACORA 2026-10-02): offline_sales.no_exchange.
-- Server-side, as every price rule: the client sends a percentage and (above 10 %) an approval reference; price, gross, the
-- discount amount, the net total and who authorized it are the server's. Each line keeps its list unit_price and gets its NET
-- line_total (the rounding cent goes to the last line), so Σ line_total = total and the commerce views stay VERIFIED.
-- Loyalty: points are per pair (unchanged); the amount sent to loyalty is the NET total, purchase lines carry the net unit price.
-- Depends on 20261024000100 (f360.approval_scopes). ADDITIVE except: f360_record_store_sale / _for gain two optional parameters
-- (old calls — the published app — keep working with no discount).
-- Rollback: supabase/rollbacks/20261025000100_f360_store_discounts.down.sql

DO $$ BEGIN
  IF to_regclass('f360.approval_scopes') IS NULL THEN RAISE EXCEPTION 'ABORT: needs 20261024000100 (f360.approval_scopes)'; END IF;
END $$;
ALTER TABLE f360.approval_scopes DROP CONSTRAINT approval_scopes_scope_check;
ALTER TABLE f360.approval_scopes ADD CONSTRAINT approval_scopes_scope_check CHECK (scope IN ('fx_rate', 'budget', 'close', 'store_discount'));

CREATE FUNCTION f360.store_discount_params() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'seller_max_pct', 10,          -- Mario 2026-10-11
    'request_minutes', 15,         -- a remote request waits this long for Carolina
    'approval_minutes', 30,        -- an approval (PIN or remote) must be used within this
    'pin_failures', 5,             -- wrong approver PINs per seller in pin_window_minutes → refused until the window passes
    'pin_window_minutes', 15)
$$;

ALTER TABLE public.offline_sales
  ADD COLUMN gross_total numeric(12,2),
  ADD COLUMN discount_pct numeric(5,2) NOT NULL DEFAULT 0 CHECK (discount_pct >= 0 AND discount_pct <= 100),
  ADD COLUMN discount_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  ADD COLUMN discount_reason text CHECK (discount_reason IS NULL OR length(discount_reason) <= 200),
  ADD COLUMN discount_authorization text CHECK (discount_authorization IN ('approver_self', 'within_seller_limit', 'approver_pin', 'approver_remote')),
  ADD COLUMN discount_approved_by uuid,
  ADD COLUMN discount_approved_by_name text,
  ADD COLUMN discount_request_id uuid,
  ADD COLUMN no_exchange boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.offline_sales.no_exchange IS 'Sold with a store discount: no exchange (Carolina). Set by f360_record_store_sale only.';

CREATE TABLE f360.store_discount_requests (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_auth_user_id uuid NOT NULL,
  seller_name      text NOT NULL,
  session_id       uuid NOT NULL,
  location_id      uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  location_name    text NOT NULL,
  lines            jsonb NOT NULL,                       -- normalized {id: quantity}, exactly as the sale builds it
  summary          text NOT NULL,
  gross_total      numeric(12,2) NOT NULL CHECK (gross_total > 0),
  discount_pct     numeric(5,2) NOT NULL CHECK (discount_pct > 0 AND discount_pct <= 100),
  net_total        numeric(12,2) NOT NULL CHECK (net_total >= 0),
  reason           text CHECK (reason IS NULL OR length(reason) <= 200),
  via              text NOT NULL CHECK (via IN ('pin', 'remote')),
  status           text NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'used', 'cancelled')),
  created_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at       timestamptz NOT NULL,
  decided_at       timestamptz,
  decided_by       uuid,
  decided_by_name  text,
  decision_note    text CHECK (decision_note IS NULL OR length(decision_note) <= 200),
  used_sale_id     uuid,
  used_at          timestamptz,
  CONSTRAINT store_discount_decided CHECK ((status NOT IN ('approved', 'rejected', 'used') OR decided_at IS NOT NULL) AND (status <> 'pending' OR decided_at IS NULL))
);
CREATE INDEX store_discount_requests_pending_idx ON f360.store_discount_requests (created_at) WHERE status = 'pending';
CREATE INDEX store_discount_requests_seller_idx ON f360.store_discount_requests (seller_auth_user_id, created_at DESC);
ALTER TABLE f360.store_discount_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.store_discount_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.store_discount_requests TO service_role;

-- ── helpers ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION f360.store_discount_approvers() RETURNS TABLE (auth_user_id uuid, display_name text) LANGUAGE sql STABLE AS $$
  SELECT a.auth_user_id, a.display_name FROM f360.approval_scopes a WHERE a.scope = 'store_discount' ORDER BY a.display_name $$;
CREATE FUNCTION f360.store_discount_approver_names() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(string_agg(split_part(display_name, ' ', 1), ' o ' ORDER BY display_name), 'quien aprueba') FROM f360.store_discount_approvers() $$;

-- the same line validation as the sale (only id + quantity; same product twice → summed)
CREATE FUNCTION f360.store_lines_req(p_lines jsonb, p_is_f360 boolean) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE li jsonb; k text; v_qty int; v_id uuid; req jsonb := '{}';
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 OR jsonb_array_length(p_lines) > 50 THEN
    RAISE EXCEPTION 'La venta necesita entre 1 y 50 productos.';
  END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    IF jsonb_typeof(li) <> 'object' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN (CASE WHEN p_is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END, 'quantity') THEN
        RAISE EXCEPTION 'Solo se aceptan producto y cantidad: el precio, la ubicación y la vendedora los pone el sistema (campo "%").', k;
      END IF;
    END LOOP;
    v_qty := (li->>'quantity')::int;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN RAISE EXCEPTION 'Cantidad no válida.'; END IF;
    v_id := (li->>CASE WHEN p_is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END)::uuid;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Falta el producto en una línea.'; END IF;
    req := jsonb_set(req, ARRAY[v_id::text], to_jsonb(coalesce((req->>v_id::text)::int, 0) + v_qty));
  END LOOP;
  RETURN req;
END $$;

-- gross at list price (read-only; the sale re-prices under its locks and must get the same number)
CREATE FUNCTION f360.store_lines_gross(p_location f360.locations, p_req jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE g numeric := 0; summ text; n_rows int; n int;
BEGIN
  IF p_location.ledger_authority = 'f360' THEN
    SELECT count(*), sum(coalesce(p.sale_price, p.regular_price) * (p_req->>v.id::text)::int),
           string_agg(p.name || ' ' || c.name || ' ' || v.size_label || CASE WHEN (p_req->>v.id::text)::int > 1 THEN ' ×' || (p_req->>v.id::text) ELSE '' END, ' · ' ORDER BY p.name, v.size_label),
           count(*) FILTER (WHERE coalesce(p.sale_price, p.regular_price) IS NULL)
      INTO n_rows, g, summ, n
      FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
      WHERE v.status = 'active' AND v.id IN (SELECT x::uuid FROM jsonb_object_keys(p_req) x);
    IF (SELECT count(*) FROM f360.product_variants v WHERE v.status = 'active' AND v.id IN (SELECT x::uuid FROM jsonb_object_keys(p_req) x))
       <> (SELECT count(*) FROM jsonb_object_keys(p_req)) THEN RAISE EXCEPTION 'Un producto no existe.'; END IF;
    IF n > 0 THEN RAISE EXCEPTION 'Un producto no tiene precio en Fuxia 360.'; END IF;
  ELSE
    IF (SELECT count(*) FROM public.channel_inventory ci WHERE ci.id IN (SELECT x::uuid FROM jsonb_object_keys(p_req) x) AND ci.channel_id = p_location.legacy_channel_id)
       <> (SELECT count(*) FROM jsonb_object_keys(p_req)) THEN RAISE EXCEPTION 'Un producto no pertenece a tu tienda.'; END IF;
    SELECT sum(ci.price * (p_req->>ci.id::text)::int),
           string_agg(ci.product_name || ' ' || coalesce(ci.color, '') || ' ' || coalesce(ci.size, '') || CASE WHEN (p_req->>ci.id::text)::int > 1 THEN ' ×' || (p_req->>ci.id::text) ELSE '' END, ' · ' ORDER BY ci.product_name, ci.size)
      INTO g, summ FROM public.channel_inventory ci WHERE ci.id IN (SELECT x::uuid FROM jsonb_object_keys(p_req) x);
  END IF;
  RETURN jsonb_build_object('gross', round(coalesce(g, 0), 2), 'summary', left(coalesce(summ, ''), 500));
END $$;

CREATE FUNCTION f360.store_discount_check_pct(p_pct numeric) RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_pct IS NULL OR p_pct = 0 THEN RETURN 0; END IF;
  IF p_pct < 0 OR p_pct > 100 OR p_pct <> round(p_pct, 2) THEN RAISE EXCEPTION 'El descuento debe ser un porcentaje entre 0 y 100.'; END IF;
  RETURN p_pct;
END $$;

-- push to people (no-op where push is not configured; the admin "Avisos" and the app's own polling cover it)
CREATE FUNCTION f360.store_discount_push(p_users uuid[], p_title text, p_body text, p_data jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO f360.push_outbox (auth_user_id, title, body, data) SELECT u, p_title, p_body, p_data FROM unnest(p_users) u WHERE u IS NOT NULL;
  BEGIN PERFORM f360.push_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

-- Who authorizes this sale's discount? Raises when nobody does. A used request is consumed here (status 'used').
CREATE FUNCTION f360.store_discount_authorize(s f360.seller_sessions, p_pct numeric, p_req jsonb, p_gross numeric, p_auth jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE prm jsonb := f360.store_discount_params(); pct numeric := f360.store_discount_check_pct(p_pct); q f360.store_discount_requests;
  rid uuid; me text;
BEGIN
  IF pct = 0 THEN RETURN jsonb_build_object('pct', 0); END IF;
  SELECT display_name INTO me FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;
  IF f360.can_approve('store_discount', s.auth_user_id) THEN
    RETURN jsonb_build_object('pct', pct, 'via', 'approver_self', 'approver', s.auth_user_id, 'approver_name', me);
  END IF;
  IF pct <= (prm->>'seller_max_pct')::numeric THEN
    RETURN jsonb_build_object('pct', pct, 'via', 'within_seller_limit');
  END IF;
  rid := nullif(p_auth->>'request_id', '')::uuid;
  IF rid IS NULL THEN
    RAISE EXCEPTION 'Un descuento de más de % necesita la aprobación de %.', (prm->>'seller_max_pct') || '%', f360.store_discount_approver_names();
  END IF;
  SELECT * INTO q FROM f360.store_discount_requests WHERE id = rid FOR UPDATE;
  IF q.id IS NULL OR q.seller_auth_user_id <> s.auth_user_id THEN RAISE EXCEPTION 'Esa aprobación no es de esta venta.'; END IF;
  IF q.status = 'used' THEN RAISE EXCEPTION 'Esa aprobación ya se usó en otra venta.'; END IF;
  IF q.status <> 'approved' THEN RAISE EXCEPTION 'El descuento todavía no está aprobado.'; END IF;
  IF q.decided_at + make_interval(mins => (prm->>'approval_minutes')::int) < clock_timestamp() THEN RAISE EXCEPTION 'La aprobación venció. Pídela de nuevo.'; END IF;
  IF q.location_id <> s.location_id OR q.lines <> p_req OR q.gross_total <> round(p_gross, 2) OR q.discount_pct <> pct THEN
    RAISE EXCEPTION 'La venta cambió desde que se aprobó el descuento (productos, precio o porcentaje). Pide la aprobación de nuevo.';
  END IF;
  UPDATE f360.store_discount_requests SET status = 'used', used_at = clock_timestamp() WHERE id = q.id;
  RETURN jsonb_build_object('pct', pct, 'via', CASE q.via WHEN 'pin' THEN 'approver_pin' ELSE 'approver_remote' END,
    'approver', q.decided_by, 'approver_name', q.decided_by_name, 'request_id', q.id, 'reason', q.reason);
END $$;

-- ── seller app ──────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_shift_discount_policy(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); prm jsonb := f360.store_discount_params();
BEGIN
  RETURN jsonb_build_object('seller_max_pct', (prm->>'seller_max_pct')::numeric, 'can_any', f360.can_approve('store_discount', s.auth_user_id),
    'approvers', f360.store_discount_approver_names(), 'has_approvers', EXISTS (SELECT 1 FROM f360.store_discount_approvers()));
END $$;

-- internal: validate a request for THIS shift's sale and return the row to insert
CREATE FUNCTION f360.store_discount_prepare(s f360.seller_sessions, p_lines jsonb, p_pct numeric, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE prm jsonb := f360.store_discount_params(); l f360.locations; pct numeric := f360.store_discount_check_pct(p_pct); req jsonb; g jsonb;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF pct <= (prm->>'seller_max_pct')::numeric THEN RAISE EXCEPTION 'Hasta % no necesita aprobación.', (prm->>'seller_max_pct') || '%'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.store_discount_approvers()) THEN RAISE EXCEPTION 'Nadie tiene permiso para aprobar descuentos todavía.'; END IF;
  req := f360.store_lines_req(p_lines, l.ledger_authority = 'f360');
  g := f360.store_lines_gross(l, req);
  IF (g->>'gross')::numeric <= 0 THEN RAISE EXCEPTION 'La venta no tiene importe.'; END IF;
  RETURN jsonb_build_object('location', l.id, 'location_name', l.name, 'lines', req, 'summary', g->>'summary', 'gross', (g->>'gross')::numeric,
    'pct', pct, 'net', (g->>'gross')::numeric - round((g->>'gross')::numeric * pct / 100, 2), 'reason', nullif(left(btrim(coalesce(p_reason, '')), 200), ''));
END $$;

-- Carolina is in the store: her PIN on the seller's phone. A wrong PIN never raises (so the attempt stays recorded).
CREATE FUNCTION public.f360_store_discount_pin(p_token text, p_lines jsonb, p_pct numeric, p_reason text, p_pin text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); prm jsonb := f360.store_discount_params(); x jsonb; ap record;
  fails int; v_id uuid; me text;
BEGIN
  x := f360.store_discount_prepare(s, p_lines, p_pct, p_reason);
  SELECT count(*) INTO fails FROM f360.seller_auth_events WHERE auth_user_id = s.auth_user_id AND event = 'discount_bad_pin'
    AND at > now() - make_interval(mins => (prm->>'pin_window_minutes')::int);
  IF fails >= (prm->>'pin_failures')::int THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Demasiados intentos con PIN equivocado. Espera ' || (prm->>'pin_window_minutes') || ' minutos o envía la solicitud a ' || f360.store_discount_approver_names() || '.');
  END IF;
  SELECT a.auth_user_id, a.display_name INTO ap FROM f360.store_discount_approvers() a JOIN f360.seller_credentials c ON c.auth_user_id = a.auth_user_id
    WHERE NOT c.hard_locked AND coalesce(p_pin, '') ~ '^[0-9]{4,8}$' AND c.pin_hash = extensions.crypt(p_pin, c.pin_hash) LIMIT 1;
  IF ap.auth_user_id IS NULL THEN
    PERFORM f360.log_seller(s.auth_user_id, s.location_id, 'discount_bad_pin', jsonb_build_object('pct', x->'pct'));
    RETURN jsonb_build_object('ok', false, 'error', 'PIN incorrecto.', 'attempts_left', greatest(0, (prm->>'pin_failures')::int - fails - 1));
  END IF;
  SELECT display_name INTO me FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;
  UPDATE f360.store_discount_requests SET status = 'cancelled' WHERE seller_auth_user_id = s.auth_user_id AND status IN ('pending', 'approved');
  INSERT INTO f360.store_discount_requests (seller_auth_user_id, seller_name, session_id, location_id, location_name, lines, summary, gross_total,
      discount_pct, net_total, reason, via, status, expires_at, decided_at, decided_by, decided_by_name)
    VALUES (s.auth_user_id, coalesce(me, 'Vendedora'), s.id, (x->>'location')::uuid, x->>'location_name', x->'lines', x->>'summary', (x->>'gross')::numeric,
      (x->>'pct')::numeric, (x->>'net')::numeric, x->>'reason', 'pin', 'approved', clock_timestamp() + make_interval(mins => (prm->>'approval_minutes')::int),
      clock_timestamp(), ap.auth_user_id, ap.display_name)
    RETURNING id INTO v_id;
  PERFORM f360.log_seller(s.auth_user_id, s.location_id, 'discount_pin_ok', jsonb_build_object('pct', x->'pct', 'approver', ap.display_name, 'request_id', v_id));
  RETURN jsonb_build_object('ok', true, 'request_id', v_id, 'approved_by', ap.display_name, 'gross_total', x->'gross', 'net_total', x->'net');
END $$;

-- Carolina is not in the store: a request she approves from Fuxia 360 ("Avisos") or her phone.
CREATE FUNCTION public.f360_store_discount_request(p_token text, p_lines jsonb, p_pct numeric, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); prm jsonb := f360.store_discount_params(); x jsonb; v_id uuid; me text; v_exp timestamptz;
BEGIN
  x := f360.store_discount_prepare(s, p_lines, p_pct, p_reason);
  SELECT display_name INTO me FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;
  UPDATE f360.store_discount_requests SET status = 'cancelled' WHERE seller_auth_user_id = s.auth_user_id AND status IN ('pending', 'approved');
  INSERT INTO f360.store_discount_requests (seller_auth_user_id, seller_name, session_id, location_id, location_name, lines, summary, gross_total,
      discount_pct, net_total, reason, via, status, expires_at)
    VALUES (s.auth_user_id, coalesce(me, 'Vendedora'), s.id, (x->>'location')::uuid, x->>'location_name', x->'lines', x->>'summary', (x->>'gross')::numeric,
      (x->>'pct')::numeric, (x->>'net')::numeric, x->>'reason', 'remote', 'pending', clock_timestamp() + make_interval(mins => (prm->>'request_minutes')::int))
    RETURNING id, expires_at INTO v_id, v_exp;
  PERFORM f360.store_discount_push(ARRAY(SELECT auth_user_id FROM f360.store_discount_approvers()), 'Descuento por aprobar',
    coalesce(me, 'Una vendedora') || ' · ' || (x->>'location_name') || ': ' || trim(to_char((x->>'pct')::numeric, 'FM990.##')) || '% · $' || to_char((x->>'gross')::numeric, 'FM999,990') || ' → $' || to_char((x->>'net')::numeric, 'FM999,990.00'),
    jsonb_build_object('type', 'f360_discount_request', 'request_id', v_id));
  RETURN jsonb_build_object('ok', true, 'request_id', v_id, 'expires_at', v_exp, 'approvers', f360.store_discount_approver_names(), 'gross_total', x->'gross', 'net_total', x->'net');
END $$;

CREATE FUNCTION public.f360_store_discount_status(p_token text, p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); q f360.store_discount_requests;
BEGIN
  SELECT * INTO q FROM f360.store_discount_requests WHERE id = p_request_id AND seller_auth_user_id = s.auth_user_id;
  IF q.id IS NULL THEN RAISE EXCEPTION 'Solicitud no encontrada.'; END IF;
  RETURN jsonb_build_object('request_id', q.id,
    'status', CASE WHEN q.status = 'pending' AND q.expires_at < clock_timestamp() THEN 'expired' ELSE q.status END,
    'decided_by', q.decided_by_name, 'note', q.decision_note, 'pct', q.discount_pct, 'net_total', q.net_total, 'expires_at', q.expires_at);
END $$;

-- ── approvers (Fuxia 360 admin) ─────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_store_discount_inbox() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF uid IS NULL OR NOT f360.can_approve('store_discount', uid) THEN
    RETURN jsonb_build_object('can_approve', false, 'pending', '[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('can_approve', true,
    'pending', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'seller', q.seller_name, 'location', q.location_name, 'summary', q.summary,
        'gross_total', q.gross_total, 'pct', q.discount_pct, 'net_total', q.net_total, 'reason', q.reason, 'created_at', q.created_at, 'expires_at', q.expires_at)
        ORDER BY q.created_at), '[]') FROM f360.store_discount_requests q WHERE q.status = 'pending' AND q.expires_at >= clock_timestamp()),
    'recent', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'at' DESC), '[]') FROM (
        SELECT jsonb_build_object('id', q.id, 'seller', q.seller_name, 'location', q.location_name, 'pct', q.discount_pct, 'net_total', q.net_total,
          'status', CASE WHEN q.status = 'pending' THEN 'expired' ELSE q.status END, 'via', q.via, 'decided_by', q.decided_by_name, 'at', coalesce(q.decided_at, q.expires_at)) x
        FROM f360.store_discount_requests q WHERE q.created_at > now() - interval '7 days' AND NOT (q.status = 'pending' AND q.expires_at >= clock_timestamp())
          AND q.status <> 'cancelled' ORDER BY q.created_at DESC LIMIT 20) r));
END $$;

CREATE FUNCTION public.f360_store_discount_decide(p_request_id uuid, p_approve boolean, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); q f360.store_discount_requests; me text;
BEGIN
  IF uid IS NULL OR NOT f360.can_approve('store_discount', uid) THEN RAISE EXCEPTION 'No tienes permiso para aprobar descuentos.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF p_approve IS NULL THEN RAISE EXCEPTION 'Elige aprobar o rechazar.'; END IF;
  SELECT display_name INTO me FROM f360.user_roles WHERE auth_user_id = uid;
  SELECT * INTO q FROM f360.store_discount_requests WHERE id = p_request_id FOR UPDATE;
  IF q.id IS NULL THEN RAISE EXCEPTION 'Solicitud no encontrada.'; END IF;
  IF q.status <> 'pending' THEN RAISE EXCEPTION 'Esa solicitud ya no está pendiente.'; END IF;
  IF q.expires_at < clock_timestamp() THEN RAISE EXCEPTION 'Esa solicitud ya venció.'; END IF;
  UPDATE f360.store_discount_requests SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END, decided_at = clock_timestamp(),
      decided_by = uid, decided_by_name = coalesce(me, 'Aprobación'), decision_note = nullif(left(btrim(coalesce(p_note, '')), 200), '')
    WHERE id = q.id RETURNING * INTO q;
  PERFORM f360.store_discount_push(ARRAY[q.seller_auth_user_id], CASE WHEN p_approve THEN 'Descuento aprobado' ELSE 'Descuento rechazado' END,
    trim(to_char(q.discount_pct, 'FM990.##')) || '% · ' || coalesce(me, '') || CASE WHEN q.decision_note IS NOT NULL THEN ': ' || q.decision_note ELSE '' END,
    jsonb_build_object('type', 'f360_discount_decision', 'request_id', q.id, 'status', q.status));
  RETURN jsonb_build_object('ok', true, 'status', q.status);
END $$;

-- ── the store sale (body = 20261007001100 + the marked DISCOUNT lines) ──────────────────────────────────────────────────
DROP FUNCTION public.f360_record_store_sale_for(text, uuid, jsonb, text, text, uuid);
DROP FUNCTION public.f360_record_store_sale(text, uuid, jsonb, text, text, text);
CREATE FUNCTION public.f360_record_store_sale(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text,
  p_payment_reference text DEFAULT NULL, p_customer_qr text DEFAULT NULL, p_discount_pct numeric DEFAULT 0, p_discount jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations; seller_name text; seller_role text; prior public.offline_sales; sale public.offline_sales;
  li jsonb; k text; v_id uuid; v_qty int; ci record; v_total numeric := 0; n int := 0; v_code text; card public.loyalty_cards;
  loy jsonb; lines_for_loyalty jsonb := '[]'; items_compat jsonb := '[]'; req jsonb := '{}'; is_f360 boolean; v_event uuid;
  d jsonb; v_gross numeric; v_pct numeric := 0; v_disc numeric := 0; v_lines int; v_alloc numeric := 0; v_line numeric;   -- DISCOUNT
BEGIN
  -- 1 · WHO and WHERE come from the server: authenticated seller + active shift at an assigned location
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF f360.location_in_cutover(l.id) THEN RAISE EXCEPTION '% está en corte de inventario: no se puede vender hasta terminar el conteo.', l.name; END IF;
  is_f360 := l.ledger_authority = 'f360';
  IF NOT is_f360 AND l.legacy_channel_id IS NULL THEN RAISE EXCEPTION 'Esta ubicación no tiene inventario del sistema anterior.'; END IF;
  SELECT display_name, role INTO seller_name, seller_role FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;

  -- 2 · idempotency (double tap / retry): the same key returns the same sale
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la venta.'; END IF;
  SELECT * INTO prior FROM public.offline_sales WHERE idempotency_key = p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.seller_auth_user_id IS DISTINCT FROM s.auth_user_id THEN RAISE EXCEPTION 'Llave de venta repetida.'; END IF;
    RETURN jsonb_build_object('ok', true, 'replayed', true, 'sale_id', prior.id, 'code', CASE WHEN prior.claimed_at IS NULL THEN prior.code END,
      'total', prior.total, 'points', prior.points_earned, 'self_sale', prior.self_sale, 'claimed', prior.claimed_at IS NOT NULL,
      'gross_total', coalesce(prior.gross_total, prior.total), 'discount_pct', prior.discount_pct, 'discount_amount', prior.discount_amount, 'no_exchange', prior.no_exchange);
  END IF;

  -- 3 · payment (D-PM)
  IF p_payment_method IS NULL OR p_payment_method NOT IN ('cash', 'card', 'transfer', 'other') THEN RAISE EXCEPTION 'Elige cómo pagó la clienta.'; END IF;
  IF p_payment_reference IS NOT NULL AND (length(p_payment_reference) > 64 OR p_payment_reference ~ '[0-9]{12,}') THEN
    RAISE EXCEPTION 'La referencia no puede contener números de tarjeta.';
  END IF;

  -- 4 · input: ONLY {channel_inventory_id | variant_id, quantity}. Any price/total/points/location/seller key is refused.
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 OR jsonb_array_length(p_lines) > 50 THEN
    RAISE EXCEPTION 'La venta necesita entre 1 y 50 productos.';
  END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    IF jsonb_typeof(li) <> 'object' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN (CASE WHEN is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END, 'quantity') THEN
        RAISE EXCEPTION 'Solo se aceptan producto y cantidad: el precio, la ubicación y la vendedora los pone el sistema (campo "%").', k;
      END IF;
    END LOOP;
    v_qty := (li->>'quantity')::int;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN RAISE EXCEPTION 'Cantidad no válida.'; END IF;
    v_id := (li->>CASE WHEN is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END)::uuid;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Falta el producto en una línea.'; END IF;
    req := jsonb_set(req, ARRAY[v_id::text], to_jsonb(coalesce((req->>v_id::text)::int, 0) + v_qty));   -- same product twice → summed
  END LOOP;

  IF is_f360 THEN
    -- ═══ F360 branch (C3): the single ledger is the stock; master price; never negative ═══
    -- Reservations (Apartado Gold): the buying customer (by her card QR) may take HER reserved pairs; nobody else may.
    PERFORM set_config('f360.sale_customer', coalesce((SELECT customer_id::text FROM public.loyalty_cards WHERE qr_code = btrim(coalesce(p_customer_qr, ''))), ''), true);
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(req) x LEFT JOIN f360.product_variants v ON v.id = x::uuid AND v.status = 'active' WHERE v.id IS NULL) THEN
      RAISE EXCEPTION 'Un producto no existe.';
    END IF;
    PERFORM 1 FROM f360.inventory_balances b WHERE b.location_id = l.id AND b.variant_id IN (SELECT x::uuid FROM jsonb_object_keys(req) x)
      ORDER BY b.variant_id FOR UPDATE;                                                             -- same lock order as transfers
    FOR ci IN SELECT v.id, v.sku, v.size_label, p.name AS product_name, c.name AS color, p.category_key,
                     coalesce(p.sale_price, p.regular_price) AS price, CASE WHEN p.sale_price IS NOT NULL THEN 'f360_master_sale_price' ELSE 'f360_master_price' END AS price_source,
                     coalesce(b.on_hand, 0) AS on_hand, (req->>v.id::text)::int AS qty
              FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
              LEFT JOIN f360.inventory_balances b ON b.variant_id = v.id AND b.location_id = l.id
              WHERE v.id IN (SELECT x::uuid FROM jsonb_object_keys(req) x) ORDER BY v.id LOOP
      IF ci.on_hand < ci.qty THEN
        RAISE EXCEPTION 'No hay existencia suficiente de % % % (quedan %).', ci.product_name, ci.color, ci.size_label, ci.on_hand;
      END IF;
      IF ci.on_hand - f360.reserved_qty(ci.id, l.id, nullif(current_setting('f360.sale_customer', true), '')::uuid) < ci.qty THEN
        RAISE EXCEPTION 'Ese par de % % % está apartado para otra clienta (Apartado Gold). Quedan % libres.', ci.product_name, ci.color, ci.size_label,
          greatest(0, ci.on_hand - f360.reserved_qty(ci.id, l.id, nullif(current_setting('f360.sale_customer', true), '')::uuid));
      END IF;
      IF ci.price IS NULL THEN RAISE EXCEPTION '% no tiene precio en Fuxia 360: no se puede vender.', ci.product_name; END IF;
      v_total := v_total + ci.price * ci.qty;
    END LOOP;
  ELSE
    -- ═══ Legacy branch (S0.3, unchanged): lock the legacy stock rows; every row must belong to THIS shift's channel ═══
    FOR ci IN SELECT * FROM public.channel_inventory WHERE id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY id FOR UPDATE LOOP
      IF ci.channel_id IS DISTINCT FROM l.legacy_channel_id THEN RAISE EXCEPTION 'Un producto no pertenece a tu tienda.'; END IF;
    END LOOP;
    IF (SELECT count(*) FROM public.channel_inventory WHERE id IN (SELECT (jsonb_object_keys(req))::uuid)) <> (SELECT count(*) FROM jsonb_object_keys(req)) THEN
      RAISE EXCEPTION 'Un producto no existe.';
    END IF;
    FOR ci IN SELECT c.*, (req->>c.id::text)::int AS qty FROM public.channel_inventory c WHERE c.id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY c.id LOOP
      IF coalesce(ci.stock, 0) - coalesce(ci.sold, 0) < ci.qty THEN
        RAISE EXCEPTION 'No hay existencia suficiente de % % % (quedan %). Pide un ajuste de inventario.', ci.product_name, coalesce(ci.color, ''), coalesce(ci.size, ''),
          greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0);
      END IF;
      v_total := v_total + ci.price * ci.qty;                                                 -- authoritative legacy price (D-P2)
    END LOOP;
  END IF;

  -- DISCOUNT · gross at list price → authorized percentage → net total (server's numbers only)
  v_gross := round(v_total, 2);
  d := f360.store_discount_authorize(s, p_discount_pct, req, v_gross, p_discount);
  v_pct := (d->>'pct')::numeric;
  v_disc := round(v_gross * v_pct / 100, 2);
  v_total := v_gross - v_disc;
  v_lines := (SELECT count(*) FROM jsonb_object_keys(req));

  -- 5 · the sale (claim code from a CSPRNG)
  LOOP
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.offline_sales WHERE code = v_code);
  END LOOP;
  INSERT INTO public.offline_sales (code, channel_id, staff_id, customer_phone, customer_id, items, total, points_earned,
      idempotency_key, seller_auth_user_id, location_id, session_id, payment_method, payment_reference, price_source, created_by_rpc,
      gross_total, discount_pct, discount_amount, discount_reason, discount_authorization, discount_approved_by, discount_approved_by_name,   -- DISCOUNT
      discount_request_id, no_exchange)
    VALUES (v_code, CASE WHEN is_f360 THEN NULL ELSE l.legacy_channel_id END, NULL, NULL, NULL, '[]', v_total, 0,
      p_idempotency_key, s.auth_user_id, l.id, s.id, p_payment_method, nullif(btrim(p_payment_reference), ''),
      CASE WHEN is_f360 THEN 'f360_master_price' ELSE 'legacy_channel_inventory' END, true,
      v_gross, v_pct, v_disc, CASE WHEN v_pct > 0 THEN coalesce(d->>'reason', nullif(left(btrim(coalesce(p_discount->>'reason', '')), 200), '')) END,
      d->>'via', nullif(d->>'approver', '')::uuid, d->>'approver_name', nullif(d->>'request_id', '')::uuid, v_pct > 0)
    RETURNING * INTO sale;
  IF d->>'request_id' IS NOT NULL THEN UPDATE f360.store_discount_requests SET used_sale_id = sale.id WHERE id = (d->>'request_id')::uuid; END IF;

  IF is_f360 THEN
    INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
      VALUES ('SALE', p_idempotency_key, s.auth_user_id, coalesce(seller_name, 'Vendedora'), coalesce(seller_role, 'seller'),
        'Venta en ' || l.name || CASE WHEN v_pct > 0 THEN ' · descuento ' || trim(to_char(v_pct, 'FM990.##')) || '%' ELSE '' END, 'offline_sale', sale.id::text)
      RETURNING id INTO v_event;
    FOR ci IN SELECT v.id, v.sku, v.size_label, p.name AS product_name, c.name AS color, p.category_key,
                     coalesce(p.sale_price, p.regular_price) AS price, CASE WHEN p.sale_price IS NOT NULL THEN 'f360_master_sale_price' ELSE 'f360_master_price' END AS price_source,
                     (req->>v.id::text)::int AS qty
              FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
              WHERE v.id IN (SELECT x::uuid FROM jsonb_object_keys(req) x) ORDER BY v.id LOOP
      n := n + 1;
      v_line := CASE WHEN n = v_lines THEN v_total - v_alloc ELSE round(ci.price * ci.qty * (100 - v_pct) / 100, 2) END;   -- DISCOUNT: net line, last line takes the cent
      v_alloc := v_alloc + v_line;
      INSERT INTO public.offline_sale_items (sale_id, line_no, channel_inventory_id, variant_id, sku, product_name, size, color, quantity, unit_price, line_total, price_source)
        VALUES (sale.id, n, NULL, ci.id, ci.sku, ci.product_name, ci.size_label, ci.color, ci.qty, ci.price, v_line, ci.price_source);
      PERFORM f360.ledger_move(v_event, ci.id, l.id, NULL, ci.qty);                             -- never negative (guarded update)
      lines_for_loyalty := lines_for_loyalty || jsonb_build_object('sku', ci.sku, 'product_name', ci.product_name, 'size', ci.size_label,
        'color', ci.color, 'category', ci.category_key, 'quantity', ci.qty, 'unit_price', round(v_line / ci.qty, 2));
      items_compat := items_compat || jsonb_build_object('variant_id', ci.id, 'product_name', ci.product_name, 'size', ci.size_label, 'color', ci.color,
        'quantity', ci.qty, 'unit_price', ci.price);
    END LOOP;
    UPDATE public.offline_sales SET sale_event_id = v_event WHERE id = sale.id RETURNING * INTO sale;
  ELSE
    FOR ci IN SELECT c.*, (req->>c.id::text)::int AS qty FROM public.channel_inventory c WHERE c.id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY c.id LOOP
      n := n + 1;
      v_line := CASE WHEN n = v_lines THEN v_total - v_alloc ELSE round(ci.price * ci.qty * (100 - v_pct) / 100, 2) END;   -- DISCOUNT
      v_alloc := v_alloc + v_line;
      INSERT INTO public.offline_sale_items (sale_id, line_no, channel_inventory_id, sku, product_name, size, color, quantity, unit_price, line_total, price_source)
        VALUES (sale.id, n, ci.id, ci.sku, ci.product_name, ci.size, ci.color, ci.qty, ci.price, v_line, 'legacy_channel_inventory');
      UPDATE public.channel_inventory SET sold = coalesce(sold, 0) + ci.qty, updated_at = now() WHERE id = ci.id;   -- relative, under the lock
      lines_for_loyalty := lines_for_loyalty || jsonb_build_object('channel_inventory_id', ci.id, 'sku', ci.sku, 'product_name', ci.product_name,
        'size', ci.size, 'color', ci.color, 'quantity', ci.qty, 'unit_price', round(v_line / ci.qty, 2));
      items_compat := items_compat || jsonb_build_object('inventory_id', ci.id, 'product_name', ci.product_name, 'size', ci.size, 'color', ci.color,
        'quantity', ci.qty, 'unit_price', ci.price);   -- same shape the existing app screens read
    END LOOP;
  END IF;

  -- 6 · customer (optional, never required to discount stock). Unknown QR → the WHOLE sale is refused (rollback).
  IF nullif(btrim(p_customer_qr), '') IS NOT NULL THEN
    SELECT * INTO card FROM public.loyalty_cards WHERE qr_code = btrim(p_customer_qr);
    IF card.id IS NULL THEN RAISE EXCEPTION 'No encontramos esa tarjeta de clienta. Vuelve a escanear o registra la venta sin clienta.'; END IF;
    loy := public.loyalty_apply(card.id, lines_for_loyalty, v_total, 'store', 'offline_sale', sale.id::text, 'offline_sale:' || sale.id,
      jsonb_build_object('type', 'seller', 'auth_user_id', s.auth_user_id, 'name', seller_name, 'location_id', l.id, 'session_id', s.id));
    UPDATE public.offline_sales SET customer_id = card.customer_id, claimed_at = now(), items = items_compat,
      points_earned = coalesce((loy->>'points')::int, 0), self_sale = coalesce((loy->>'self_sale')::boolean, false),
      loyalty_transaction_id = nullif(loy->>'transaction_id', '')::uuid
      WHERE id = sale.id RETURNING * INTO sale;
  ELSE
    UPDATE public.offline_sales SET items = items_compat WHERE id = sale.id RETURNING * INTO sale;
  END IF;

  RETURN jsonb_build_object('ok', true, 'replayed', false, 'sale_id', sale.id, 'code', CASE WHEN sale.claimed_at IS NULL THEN sale.code END,
    'total', sale.total, 'lines', n, 'points', sale.points_earned, 'self_sale', sale.self_sale, 'claimed', sale.claimed_at IS NOT NULL,
    'location', l.name, 'seller', seller_name, 'payment_method', sale.payment_method, 'ledger', CASE WHEN is_f360 THEN 'f360' ELSE 'legacy' END,
    'gross_total', sale.gross_total, 'discount_pct', sale.discount_pct, 'discount_amount', sale.discount_amount, 'no_exchange', sale.no_exchange,
    'discount_approved_by', sale.discount_approved_by_name);
END $$;

-- unchanged from 20261013000200 except: the two DISCOUNT parameters are passed through
CREATE FUNCTION public.f360_record_store_sale_for(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text,
  p_payment_reference text DEFAULT NULL, p_customer_ref uuid DEFAULT NULL, p_discount_pct numeric DEFAULT 0, p_discount jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); cu public.customers; card public.loyalty_cards;
  r jsonb; sale public.offline_sales; loy jsonb; lines jsonb; seller_name text;
BEGIN
  IF p_customer_ref IS NULL THEN
    RETURN public.f360_record_store_sale(p_token, p_idempotency_key, p_lines, p_payment_method, p_payment_reference, NULL, p_discount_pct, p_discount);
  END IF;
  SELECT * INTO cu FROM public.customers WHERE id = p_customer_ref;
  IF cu.id IS NULL THEN RAISE EXCEPTION 'No encontramos a esa clienta.'; END IF;
  SELECT * INTO card FROM public.loyalty_cards WHERE customer_id = cu.id ORDER BY created_at LIMIT 1;
  IF card.id IS NULL THEN
    INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (cu.id, '', 0, 0, 'bronze') RETURNING * INTO card;
    SELECT * INTO card FROM public.loyalty_cards WHERE id = card.id;                    -- token set by trigger
  END IF;

  IF f360.customer_identity_verified(cu.id) THEN
    r := public.f360_record_store_sale(p_token, p_idempotency_key, p_lines, p_payment_method, p_payment_reference, card.qr_code, p_discount_pct, p_discount);
    RETURN r || jsonb_build_object('points_state', CASE WHEN (r->>'claimed')::boolean THEN 'credited' ELSE 'none' END,
                                   'customer', f360.customer_masked_card(cu.id));
  END IF;

  r := public.f360_record_store_sale(p_token, p_idempotency_key, p_lines, p_payment_method, p_payment_reference, NULL, p_discount_pct, p_discount);
  SELECT * INTO sale FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid FOR UPDATE;
  IF sale.customer_id IS NULL AND sale.claimed_at IS NULL THEN                         -- not a replay already linked
    SELECT coalesce(jsonb_agg(jsonb_build_object('sku', i.sku, 'product_name', i.product_name, 'size', i.size, 'color', i.color,
             'category', p.category_key, 'quantity', i.quantity, 'unit_price', round(i.line_total / i.quantity, 2)) ORDER BY i.line_no), '[]')   -- DISCOUNT: net unit
      INTO lines
      FROM public.offline_sale_items i LEFT JOIN f360.product_variants v ON v.id = i.variant_id LEFT JOIN f360.products p ON p.id = v.product_id
      WHERE i.sale_id = sale.id;
    SELECT display_name INTO seller_name FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;
    loy := f360.loyalty_credit_or_hold(card.id, lines, sale.total, 'store', 'offline_sale', sale.id::text, 'offline_sale:' || sale.id,
      jsonb_build_object('type', 'seller', 'auth_user_id', s.auth_user_id, 'name', seller_name, 'location_id', s.location_id, 'session_id', s.id));
    -- linked to her: the claim code is closed (her points come from the hold, never twice)
    UPDATE public.offline_sales SET customer_id = cu.id, claimed_at = now(),
      points_earned = CASE WHEN loy->>'state' = 'credited' THEN coalesce((loy->>'points')::int, 0) ELSE 0 END
      WHERE id = sale.id;
  ELSE
    SELECT jsonb_build_object('state', h.status, 'points_pending', public.loyalty_pairs_for_lines(h.lines) * public.loyalty_points_per_pair())
      INTO loy FROM f360.loyalty_holds h WHERE h.idempotency_key = 'offline_sale:' || sale.id;
  END IF;
  RETURN (r - 'code') || jsonb_build_object('claimed', true, 'points_state', coalesce(loy->>'state', 'none'),
    'points', coalesce((loy->>'points_pending')::int, (loy->>'points')::int, 0), 'customer', f360.customer_masked_card(cu.id));
END $$;

-- ── grants ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION f360.store_discount_params(), f360.store_discount_approvers(), f360.store_discount_approver_names(), f360.store_lines_req(jsonb, boolean),
  f360.store_lines_gross(f360.locations, jsonb), f360.store_discount_check_pct(numeric), f360.store_discount_push(uuid[], text, text, jsonb),
  f360.store_discount_authorize(f360.seller_sessions, numeric, jsonb, numeric, jsonb), f360.store_discount_prepare(f360.seller_sessions, jsonb, numeric, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_record_store_sale(text, uuid, jsonb, text, text, text, numeric, jsonb),
  public.f360_record_store_sale_for(text, uuid, jsonb, text, text, uuid, numeric, jsonb), public.f360_shift_discount_policy(text),
  public.f360_store_discount_pin(text, jsonb, numeric, text, text), public.f360_store_discount_request(text, jsonb, numeric, text),
  public.f360_store_discount_status(text, uuid), public.f360_store_discount_inbox(), public.f360_store_discount_decide(uuid, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_record_store_sale(text, uuid, jsonb, text, text, text, numeric, jsonb),
  public.f360_record_store_sale_for(text, uuid, jsonb, text, text, uuid, numeric, jsonb), public.f360_shift_discount_policy(text),
  public.f360_store_discount_pin(text, jsonb, numeric, text, text), public.f360_store_discount_request(text, jsonb, numeric, text),
  public.f360_store_discount_status(text, uuid), public.f360_store_discount_inbox(), public.f360_store_discount_decide(uuid, boolean, text)
  TO authenticated, service_role;
