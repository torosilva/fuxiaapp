-- Rehearsal of 20261013000700_f360_thanks_member — NEVER commits (RAISE 'ENSAYO OK' = success).
BEGIN;
-- Fuxia 360 · CRM C9 (Mario 2026-10-08: "aun así tengan la app mandar el WhatsApp de gracias"). ADDITIVE.
-- A purchase whose points are CREDITED right away (the customer already has the app: store sale with her card / verified
-- WhatsApp, or an online order credited by woocommerce-webhook) now also queues ONE thank-you, kind 'thanks_member'
-- (template fuxia_gracias_socia: {{1}} store or "en línea", {{2}} first name, {{3}} points earned, {{4}} her total).
-- Not for a released hold (she already got the 'thanks' when she bought) and not for reversed/other rows.
-- f360_whatsapp_claim gains p_kinds so the sender only takes kinds whose template Meta has approved (the rest wait).
-- Rollback: supabase/rollbacks/20261013000700_f360_thanks_member.down.sql

ALTER TABLE f360.whatsapp_outbox DROP CONSTRAINT whatsapp_outbox_kind_check,
  ADD CONSTRAINT whatsapp_outbox_kind_check CHECK (kind IN ('thanks', 'thanks_member'));

CREATE FUNCTION f360.enqueue_thanks_on_credit() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c public.customers; card public.loyalty_cards; place text;
BEGIN
  IF NEW.reversed_at IS NOT NULL OR coalesce(NEW.points_earned, 0) <= 0 OR NEW.channel NOT IN ('store', 'web')
     OR coalesce(NEW.actor, '{}') ? 'released_hold' THEN RETURN NULL; END IF;
  SELECT * INTO card FROM public.loyalty_cards WHERE id = NEW.loyalty_card_id;
  SELECT * INTO c FROM public.customers WHERE id = card.customer_id;
  IF c.id IS NULL OR c.role IS DISTINCT FROM 'customer' OR f360.normalize_phone(c.phone) IS NULL THEN RETURN NULL; END IF;
  place := CASE
    WHEN NEW.ref_type = 'offline_sale' THEN (SELECT regexp_replace(l.name, '^Tienda\s+', '', 'i') FROM public.offline_sales s
                                             JOIN f360.locations l ON l.id = s.location_id WHERE s.id::text = NEW.ref_id)
    WHEN NEW.channel = 'web' THEN 'en línea' END;
  INSERT INTO f360.whatsapp_outbox (kind, customer_id, phone, variables, ref_type, ref_id)
    VALUES ('thanks_member', c.id, f360.normalize_phone(c.phone),
            jsonb_build_object('1', coalesce(place, 'Ballerinas'), '2', coalesce(nullif(split_part(btrim(c.name), ' ', 1), ''), 'hola'),
                               '3', NEW.points_earned::text, '4', (coalesce(card.total_points, 0) + NEW.points_earned)::text),
            'transaction', NEW.id::text)
    ON CONFLICT (kind, ref_type, ref_id) DO NOTHING;
  BEGIN PERFORM f360.whatsapp_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NULL;
END $$;
CREATE TRIGGER transactions_thanks_member AFTER INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION f360.enqueue_thanks_on_credit();

DROP FUNCTION public.f360_whatsapp_claim(int);
CREATE FUNCTION public.f360_whatsapp_claim(p_limit int DEFAULT 20, p_kinds text[] DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r jsonb;
BEGIN
  UPDATE f360.whatsapp_outbox SET result = 'expired' WHERE sent_at IS NULL AND result IS DISTINCT FROM 'expired' AND created_at <= now() - interval '3 days';
  WITH c AS (
    SELECT id FROM f360.whatsapp_outbox
    WHERE sent_at IS NULL AND attempts < 5 AND created_at > now() - interval '3 days'
      AND (p_kinds IS NULL OR kind = ANY (p_kinds))
      AND (claimed_at IS NULL OR claimed_at < now() - interval '2 minutes')
    ORDER BY created_at LIMIT least(greatest(coalesce(p_limit, 20), 1), 50) FOR UPDATE SKIP LOCKED)
  , u AS (
    UPDATE f360.whatsapp_outbox o SET claimed_at = now(), attempts = o.attempts + 1 FROM c WHERE o.id = c.id
    RETURNING o.id, o.kind, o.phone, o.variables)
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'phone', phone, 'variables', variables)), '[]') INTO r FROM u;
  RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.f360_whatsapp_claim(int, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_whatsapp_claim(int, text[]) TO service_role;
DO $$
DECLARE card uuid := (SELECT l.id FROM public.loyalty_cards l JOIN public.customers c ON c.id = l.customer_id WHERE c.auth_user_id = 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b' LIMIT 1);
  tot int := (SELECT total_points FROM public.loyalty_cards WHERE id = card); t1 uuid; t2 uuid; m jsonb; n int;
BEGIN
  -- T1 · a credited store sale (Ada's) → one thanks_member: Polanco, first name, points, new total
  INSERT INTO public.transactions (loyalty_card_id, amount, points_earned, pairs_in_order, channel, ref_type, ref_id)
    VALUES (card, 2800, 100, 1, 'store', 'offline_sale', '26df917b-42a3-4805-b4b1-be90b9d0f4c1') RETURNING id INTO t1;
  SELECT variables INTO m FROM f360.whatsapp_outbox WHERE kind = 'thanks_member' AND ref_id = t1::text;
  IF m->>'1' <> 'Polanco' OR m->>'2' <> 'Mario' OR m->>'3' <> '100' OR m->>'4' <> (tot + 100)::text THEN RAISE EXCEPTION 'T1 %', m; END IF;
  -- T2 · a released hold, a reversed row and a zero-point row → nothing
  INSERT INTO public.transactions (loyalty_card_id, amount, points_earned, pairs_in_order, channel, actor) VALUES (card, 1, 100, 1, 'store', '{"released_hold": "x"}') RETURNING id INTO t2;
  INSERT INTO public.transactions (loyalty_card_id, amount, points_earned, pairs_in_order, channel, reversed_at) VALUES (card, 1, 100, 1, 'web', now());
  INSERT INTO public.transactions (loyalty_card_id, amount, points_earned, pairs_in_order, channel) VALUES (card, 1, 0, 0, 'web');
  SELECT count(*) INTO n FROM f360.whatsapp_outbox o JOIN public.transactions t ON t.id::text = o.ref_id WHERE o.kind = 'thanks_member' AND t.loyalty_card_id = card;
  IF n <> 1 THEN RAISE EXCEPTION 'T2 %', n; END IF;
  -- T3 · web credit → "en línea"
  INSERT INTO public.transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel) VALUES (card, 999000021, 2800, 100, 1, 'web') RETURNING id INTO t2;
  IF (SELECT variables->>'1' FROM f360.whatsapp_outbox WHERE ref_id = t2::text) <> 'en línea' THEN RAISE EXCEPTION 'T3'; END IF;
  -- T4 · claim by kind: only 'thanks' requested → no thanks_member handed out
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.f360_whatsapp_claim(50, ARRAY['thanks'])) x WHERE x->>'kind' = 'thanks_member') THEN RAISE EXCEPTION 'T4'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(public.f360_whatsapp_claim(50, ARRAY['thanks_member'])) x WHERE x->>'kind' = 'thanks_member') < 2 THEN RAISE EXCEPTION 'T4b'; END IF;
  RAISE EXCEPTION 'ENSAYO OK';
END $$;
COMMIT;
