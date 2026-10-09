-- Fuxia 360 · safety net for the WhatsApp login (2026-10-09: Reyna signed in but her account was not linked to the seller row
-- Carolina created → the app sent her to "crear perfil" → "Error creando perfil" because her number already existed).
-- public.f360_link_my_account(): called by the app right after sign-in when it finds no profile for the session. It links the
-- caller's account to the customers row of THE SAME WhatsApp — the number is already proven: whatsapp-otp only creates or
-- opens the account <digits>@fuxia.app after a correct code — and only when that row has no account yet. Linking fires the
-- existing triggers (seller activation, held points release) exactly as the login would have. Nothing else is touched.
-- Rollback: DROP FUNCTION public.f360_link_my_account();
CREATE FUNCTION public.f360_link_my_account() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); em text; ph text; cid uuid;
BEGIN
  IF uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_session'); END IF;
  IF EXISTS (SELECT 1 FROM public.customers WHERE auth_user_id = uid) THEN RETURN jsonb_build_object('ok', true, 'result', 'already_linked'); END IF;
  SELECT email INTO em FROM auth.users WHERE id = uid;
  IF em IS NULL OR em !~ '^[0-9]{10,15}@fuxia\.app$' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_whatsapp_account'); END IF;
  ph := '+' || split_part(em, '@', 1);
  UPDATE public.customers SET auth_user_id = uid
    WHERE id = (SELECT id FROM public.customers WHERE auth_user_id IS NULL
                  AND (phone = ph OR f360.normalize_phone(phone) = f360.normalize_phone(ph)) ORDER BY created_at LIMIT 1)
    RETURNING id INTO cid;
  RETURN jsonb_build_object('ok', true, 'result', CASE WHEN cid IS NULL THEN 'no_profile' ELSE 'linked' END);
END $$;
REVOKE ALL ON FUNCTION public.f360_link_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_link_my_account() TO authenticated;
