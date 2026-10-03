-- Fuxia 360 — Apartado Gold on the web (phase 3, STAGING). Additive.
-- f360_gold_check (service_role only, used by the f360-store-reserve edge function BEFORE sending a code): does this
-- phone belong to a Fuxia customer, and is she Gold? Returns only a first name and a boolean — never points or data.
-- Rollback: supabase/rollbacks/20261007001200_f360_reserve_web.down.sql
CREATE FUNCTION public.f360_gold_check(p_phone text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c public.customers; v_tier text;
BEGIN
  SELECT * INTO c FROM public.customers WHERE phone = btrim(p_phone) ORDER BY created_at LIMIT 1;
  IF c.id IS NULL THEN RETURN jsonb_build_object('exists', false, 'gold', false); END IF;
  SELECT tier INTO v_tier FROM public.loyalty_cards WHERE customer_id = c.id ORDER BY total_points DESC NULLS LAST LIMIT 1;
  RETURN jsonb_build_object('exists', true, 'gold', coalesce(v_tier, '') = 'gold', 'first_name', split_part(btrim(c.name), ' ', 1));
END $$;
REVOKE ALL ON FUNCTION public.f360_gold_check(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_gold_check(text) TO service_role;
