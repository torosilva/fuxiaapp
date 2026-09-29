


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."award_birthday_points"("p_customer_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_customer   customers%ROWTYPE;
  v_card_id    uuid;
  v_cur_points integer;
  v_new_points integer;
  v_new_tier   text;
  v_year       integer := EXTRACT(YEAR FROM now())::integer;
  v_month_now  integer := EXTRACT(MONTH FROM now())::integer;
  v_birth_month integer;
BEGIN
  SELECT * INTO v_customer FROM customers WHERE id = p_customer_id;
  IF NOT FOUND OR v_customer.birthday IS NULL THEN
    RETURN jsonb_build_object('awarded', false, 'reason', 'no_birthday');
  END IF;

  v_birth_month := EXTRACT(MONTH FROM v_customer.birthday::date)::integer;

  IF v_birth_month <> v_month_now THEN
    RETURN jsonb_build_object('awarded', false, 'reason', 'not_birthday_month');
  END IF;

  -- Verificar si ya se acreditó este año
  IF EXISTS (SELECT 1 FROM birthday_rewards WHERE customer_id = p_customer_id AND year = v_year) THEN
    RETURN jsonb_build_object('awarded', false, 'reason', 'already_awarded_this_year');
  END IF;

  -- Obtener tarjeta
  SELECT id, total_points INTO v_card_id, v_cur_points
  FROM loyalty_cards WHERE customer_id = p_customer_id LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('awarded', false, 'reason', 'no_loyalty_card');
  END IF;

  v_new_points := v_cur_points + 50;
  v_new_tier := CASE
    WHEN v_new_points >= 900 THEN 'gold'
    WHEN v_new_points >= 300 THEN 'silver'
    ELSE 'bronze'
  END;

  UPDATE loyalty_cards
  SET total_points = v_new_points,
      tier         = v_new_tier,
      updated_at   = now()
  WHERE id = v_card_id;

  INSERT INTO birthday_rewards (customer_id, year, points_awarded)
  VALUES (p_customer_id, v_year, 50);

  INSERT INTO transactions (loyalty_card_id, amount, currency, points_earned, channel, notes)
  VALUES (v_card_id, 0, 'MXN', 50, 'app', 'Bonus cumpleaños 🎂');

  RETURN jsonb_build_object('awarded', true, 'points', 50, 'new_total', v_new_points, 'tier', v_new_tier);
END;
$$;


ALTER FUNCTION "public"."award_birthday_points"("p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."award_referral_points"("p_new_customer_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_referral       referrals%ROWTYPE;
  v_card_id        uuid;
  v_new_points     integer;
  v_new_tier       text;
BEGIN
  -- Buscar referral pendiente cuyo referred_id coincida
  SELECT * INTO v_referral
  FROM referrals
  WHERE referred_id = p_new_customer_id
    AND status = 'registered'
  LIMIT 1;

  IF NOT FOUND THEN RETURN; END IF;

  -- Obtener tarjeta del referidor
  SELECT id, total_points INTO v_card_id, v_new_points
  FROM loyalty_cards
  WHERE customer_id = v_referral.referrer_id
  LIMIT 1;

  IF NOT FOUND THEN RETURN; END IF;

  v_new_points := v_new_points + 50;
  v_new_tier := CASE
    WHEN v_new_points >= 900 THEN 'gold'
    WHEN v_new_points >= 300 THEN 'silver'
    ELSE 'bronze'
  END;

  -- Actualizar tarjeta del referidor
  UPDATE loyalty_cards
  SET total_points = v_new_points,
      tier         = v_new_tier,
      updated_at   = now()
  WHERE id = v_card_id;

  -- Insertar transacción de tipo referido
  INSERT INTO transactions (loyalty_card_id, amount, currency, points_earned, channel, notes)
  VALUES (v_card_id, 0, 'MXN', 50, 'app', 'Referido exitoso');

  -- Marcar referral como recompensado
  UPDATE referrals
  SET status        = 'rewarded',
      points_awarded = 50,
      rewarded_at   = now()
  WHERE id = v_referral.id;
END;
$$;


ALTER FUNCTION "public"."award_referral_points"("p_new_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_free_pair_reward"("p_loyalty_card_id" "uuid", "p_transaction_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_pairs integer;
BEGIN
  SELECT total_pairs_count INTO v_pairs
  FROM loyalty_cards WHERE id = p_loyalty_card_id;

  -- Activar en cada múltiplo de 10 (compra 10, 20, 30...)
  IF v_pairs > 0 AND v_pairs % 10 = 0 THEN
    INSERT INTO free_pair_rewards (loyalty_card_id, trigger_transaction)
    VALUES (p_loyalty_card_id, p_transaction_id)
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;


ALTER FUNCTION "public"."check_free_pair_reward"("p_loyalty_card_id" "uuid", "p_transaction_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_expired_otps"() RETURNS "void"
    LANGUAGE "sql"
    AS $$
  DELETE FROM otp_verifications WHERE expires_at < NOW() - INTERVAL '1 hour';
$$;


ALTER FUNCTION "public"."delete_expired_otps"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fx_add_points"("p_card_id" "uuid", "p_points" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_total integer;
begin
  update public.loyalty_cards
     set total_points = coalesce(total_points, 0) + p_points
   where id = p_card_id
  returning total_points into v_total;

  return v_total;
end;
$$;


ALTER FUNCTION "public"."fx_add_points"("p_card_id" "uuid", "p_points" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fx_aplicar_creditos_pendientes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_phone   text;
  v_country text;
  r         record;
begin
  select c.phone, coalesce(c.country, 'MX')
    into v_phone, v_country
  from public.customers c
  where c.id = new.customer_id;

  if v_phone is null then
    return new;
  end if;

  for r in
    select * from public.pending_credits
    where phone = v_phone and applied_at is null
  loop
    insert into public.transactions
      (loyalty_card_id, wc_order_id, amount, currency, points_earned,
       pairs_in_order, channel, status, notes)
    values
      (new.id, null, 0, case when v_country = 'CO' then 'COP' else 'MXN' end,
       r.points, 0, 'popup', 'completed', r.motivo);

    -- La transacción sola NO mueve el saldo: hay que sumarlo.
    perform public.fx_add_points(new.id, r.points);

    update public.pending_credits
      set applied_at = now()
    where id = r.id;
  end loop;

  return new;
end;
$$;


ALTER FUNCTION "public"."fx_aplicar_creditos_pendientes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_customer_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT id FROM public.customers WHERE auth_user_id = auth.uid() LIMIT 1;
$$;


ALTER FUNCTION "public"."my_customer_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_phone"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT phone FROM public.customers WHERE auth_user_id = auth.uid() LIMIT 1;
$$;


ALTER FUNCTION "public"."my_phone"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT role FROM public.customers WHERE auth_user_id = auth.uid() LIMIT 1;
$$;


ALTER FUNCTION "public"."my_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_annual_tier_review"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_downgraded integer := 0;
  rec record;
BEGIN
  FOR rec IN
    SELECT lc.id, lc.customer_id, lc.total_points
    FROM loyalty_cards lc
    WHERE lc.tier = 'gold'
      AND lc.purchases_this_year < 3
  LOOP
    UPDATE loyalty_cards
    SET tier                = 'silver',
        purchases_this_year = 0,
        updated_at          = now()
    WHERE id = rec.id;

    INSERT INTO transactions (loyalty_card_id, amount, currency, points_earned, channel, notes)
    VALUES (rec.id, 0, 'MXN', 0, 'app', 'Revisión anual: nivel ajustado a Silver por actividad insuficiente');

    v_downgraded := v_downgraded + 1;
  END LOOP;

  -- Resetear contador anual para todos
  UPDATE loyalty_cards SET purchases_this_year = 0;

  RETURN jsonb_build_object('downgraded', v_downgraded, 'reviewed_at', now());
END;
$$;


ALTER FUNCTION "public"."run_annual_tier_review"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_update_purchase_stats"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE loyalty_cards
  SET purchases_this_year = purchases_this_year + 1,
      total_pairs_count   = total_pairs_count + COALESCE(NEW.pairs_in_order, 0),
      last_purchase_at    = NEW.created_at
  WHERE id = NEW.loyalty_card_id
    AND NEW.pairs_in_order > 0;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_update_purchase_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_loyalty_tier"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.tier := CASE
    WHEN NEW.total_points >= 900 THEN 'gold'
    WHEN NEW.total_points >= 300 THEN 'silver'
    ELSE 'bronze'
  END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_loyalty_tier"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."birthday_rewards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "year" integer NOT NULL,
    "points_awarded" integer DEFAULT 50 NOT NULL,
    "awarded_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."birthday_rewards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."broadcasts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sent_by_customer_id" "uuid",
    "sent_by_name" "text" NOT NULL,
    "segment" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "deep_link" "text",
    "recipients_count" integer DEFAULT 0 NOT NULL,
    "expo_status" integer,
    "expo_body_preview" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."broadcasts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."channel_inventory" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "channel_id" "uuid",
    "product_name" "text" NOT NULL,
    "sku" "text",
    "size" "text" NOT NULL,
    "color" "text",
    "price" numeric(10,2) NOT NULL,
    "stock" integer DEFAULT 0,
    "sold" integer DEFAULT 0,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "image_url" "text"
);


ALTER TABLE "public"."channel_inventory" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."channels" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "type" "text" NOT NULL,
    "location" "text",
    "event_date" "date",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "channels_type_check" CHECK (("type" = ANY (ARRAY['store'::"text", 'bazar'::"text"])))
);


ALTER TABLE "public"."channels" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone" "text" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "country" "text" DEFAULT 'MX'::"text",
    "wc_customer_id" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "avatar_url" "text",
    "referral_code" "text",
    "referred_by" "uuid",
    "role" "text" DEFAULT 'customer'::"text",
    "auth_user_id" "uuid",
    "birthday" "date",
    "shoe_size" "text",
    CONSTRAINT "customers_role_check" CHECK (("role" = ANY (ARRAY['customer'::"text", 'staff'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."free_pair_rewards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "loyalty_card_id" "uuid" NOT NULL,
    "trigger_transaction" "uuid",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "redemption_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "redeemed_at" timestamp with time zone,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '6 mons'::interval),
    CONSTRAINT "free_pair_rewards_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'redeemed'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."free_pair_rewards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_change_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "channel_id" "uuid" NOT NULL,
    "requested_by_staff_id" "uuid",
    "requested_by_name" "text" NOT NULL,
    "action" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "reviewed_by_customer_id" "uuid",
    "reviewed_at" timestamp with time zone,
    "rejection_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "inventory_change_requests_action_check" CHECK (("action" = ANY (ARRAY['bulk_add'::"text", 'adjust_stock'::"text", 'delete'::"text"]))),
    CONSTRAINT "inventory_change_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."inventory_change_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."loyalty_cards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid",
    "qr_code" "text" NOT NULL,
    "total_points" integer DEFAULT 0,
    "pairs_count" integer DEFAULT 0,
    "tier" "text" DEFAULT 'bronze'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_purchase_at" timestamp with time zone,
    "purchases_this_year" integer DEFAULT 0 NOT NULL,
    "total_pairs_count" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "loyalty_cards_tier_check" CHECK (("tier" = ANY (ARRAY['bronze'::"text", 'silver'::"text", 'gold'::"text"])))
);


ALTER TABLE "public"."loyalty_cards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."offline_sales" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "channel_id" "uuid",
    "staff_id" "uuid",
    "customer_phone" "text",
    "customer_id" "uuid",
    "items" "jsonb" NOT NULL,
    "total" numeric(10,2) NOT NULL,
    "points_earned" integer DEFAULT 0,
    "claimed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."offline_sales" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."otp_verifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone" "text" NOT NULL,
    "code" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "used" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "attempts" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."otp_verifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pending_credits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone" "text" NOT NULL,
    "points" integer NOT NULL,
    "motivo" "text" DEFAULT 'popup-bienvenida'::"text" NOT NULL,
    "origen" "text" DEFAULT 'popup'::"text" NOT NULL,
    "idem_key" "text",
    "email" "text",
    "country" "text" DEFAULT 'MX'::"text",
    "applied_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."pending_credits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_image_overrides" (
    "wc_product_id" integer NOT NULL,
    "image_url" "text" NOT NULL,
    "note" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."product_image_overrides" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchase_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transaction_id" "uuid",
    "sku" "text" NOT NULL,
    "product_name" "text" NOT NULL,
    "size" "text",
    "color" "text",
    "category" "text",
    "quantity" integer DEFAULT 1,
    "unit_price" numeric(10,2),
    "wc_product_id" integer
);


ALTER TABLE "public"."purchase_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "campaign_name" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "target" "text" DEFAULT 'all'::"text" NOT NULL,
    "customer_id" "uuid",
    "tokens_count" integer DEFAULT 0 NOT NULL,
    "sent_count" integer DEFAULT 0 NOT NULL,
    "failed_count" integer DEFAULT 0 NOT NULL,
    "extra_data" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "push_campaigns_target_check" CHECK (("target" = ANY (ARRAY['all'::"text", 'bronze'::"text", 'silver'::"text", 'gold'::"text", 'birthday'::"text", 'one'::"text"])))
);


ALTER TABLE "public"."push_campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "expo_token" "text" NOT NULL,
    "platform" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "push_tokens_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text"])))
);


ALTER TABLE "public"."push_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."qr_scans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "loyalty_card_id" "uuid",
    "store_id" "text",
    "staff_id" "text",
    "channel" "text",
    "scanned_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "qr_scans_channel_check" CHECK (("channel" = ANY (ARRAY['store'::"text", 'web'::"text"])))
);


ALTER TABLE "public"."qr_scans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."referrals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "referrer_id" "uuid" NOT NULL,
    "referred_id" "uuid",
    "referred_email" "text",
    "referred_phone" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "points_awarded" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "rewarded_at" timestamp with time zone,
    CONSTRAINT "referrals_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'registered'::"text", 'rewarded'::"text"])))
);


ALTER TABLE "public"."referrals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rewards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "loyalty_card_id" "uuid",
    "type" "text",
    "threshold_points" integer,
    "product_sku" "text",
    "description" "text",
    "redeemed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "rewards_type_check" CHECK (("type" = ANY (ARRAY['tier_upgrade'::"text", 'points_redemption'::"text", 'special'::"text"])))
);


ALTER TABLE "public"."rewards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "pin" "text" NOT NULL,
    "channel_id" "uuid",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."staff" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."support_tickets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid",
    "customer_phone" "text",
    "customer_name" "text",
    "last_messages" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "topic" "text",
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "resolved_by" "uuid",
    "notes" "text",
    CONSTRAINT "support_tickets_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'resolved'::"text"])))
);


ALTER TABLE "public"."support_tickets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tier_config" (
    "tier" "text" NOT NULL,
    "min_pairs" integer NOT NULL,
    "min_points" integer NOT NULL,
    "reward_description" "text",
    "reward_sku" "text"
);


ALTER TABLE "public"."tier_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "loyalty_card_id" "uuid",
    "wc_order_id" integer,
    "amount" numeric(10,2) NOT NULL,
    "currency" "text" DEFAULT 'MXN'::"text",
    "points_earned" integer NOT NULL,
    "pairs_in_order" integer DEFAULT 0,
    "channel" "text" DEFAULT 'web'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "status" "text" DEFAULT 'completed'::"text",
    "notes" "text",
    "reversed_at" timestamp with time zone,
    "wc_status" "text",
    CONSTRAINT "transactions_channel_check" CHECK (("channel" = ANY (ARRAY['web'::"text", 'store'::"text", 'app'::"text"]))),
    CONSTRAINT "transactions_status_check" CHECK (("status" = ANY (ARRAY['processing'::"text", 'shipped'::"text", 'completed'::"text", 'cancelled'::"text", 'refunded'::"text"])))
);


ALTER TABLE "public"."transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."unmatched_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "wc_order_id" integer NOT NULL,
    "phone" "text",
    "email" "text",
    "total" numeric(10,2) NOT NULL,
    "currency" "text" DEFAULT 'MXN'::"text",
    "pairs" integer DEFAULT 0 NOT NULL,
    "points" integer DEFAULT 0 NOT NULL,
    "items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "wc_status" "text",
    "matched_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."unmatched_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wishlists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "wc_product_id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."wishlists" OWNER TO "postgres";


ALTER TABLE ONLY "public"."birthday_rewards"
    ADD CONSTRAINT "birthday_rewards_customer_id_year_key" UNIQUE ("customer_id", "year");



ALTER TABLE ONLY "public"."birthday_rewards"
    ADD CONSTRAINT "birthday_rewards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."broadcasts"
    ADD CONSTRAINT "broadcasts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."channel_inventory"
    ADD CONSTRAINT "channel_inventory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."channels"
    ADD CONSTRAINT "channels_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_referral_code_key" UNIQUE ("referral_code");



ALTER TABLE ONLY "public"."free_pair_rewards"
    ADD CONSTRAINT "free_pair_rewards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_change_requests"
    ADD CONSTRAINT "inventory_change_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."loyalty_cards"
    ADD CONSTRAINT "loyalty_cards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."loyalty_cards"
    ADD CONSTRAINT "loyalty_cards_qr_code_key" UNIQUE ("qr_code");



ALTER TABLE ONLY "public"."offline_sales"
    ADD CONSTRAINT "offline_sales_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."offline_sales"
    ADD CONSTRAINT "offline_sales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."otp_verifications"
    ADD CONSTRAINT "otp_verifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pending_credits"
    ADD CONSTRAINT "pending_credits_idem_key_key" UNIQUE ("idem_key");



ALTER TABLE ONLY "public"."pending_credits"
    ADD CONSTRAINT "pending_credits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_image_overrides"
    ADD CONSTRAINT "product_image_overrides_pkey" PRIMARY KEY ("wc_product_id");



ALTER TABLE ONLY "public"."purchase_items"
    ADD CONSTRAINT "purchase_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_campaigns"
    ADD CONSTRAINT "push_campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_expo_token_key" UNIQUE ("expo_token");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."qr_scans"
    ADD CONSTRAINT "qr_scans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."referrals"
    ADD CONSTRAINT "referrals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rewards"
    ADD CONSTRAINT "rewards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tier_config"
    ADD CONSTRAINT "tier_config_pkey" PRIMARY KEY ("tier");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_wc_order_id_key" UNIQUE ("wc_order_id");



ALTER TABLE ONLY "public"."unmatched_orders"
    ADD CONSTRAINT "unmatched_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."unmatched_orders"
    ADD CONSTRAINT "unmatched_orders_wc_order_id_key" UNIQUE ("wc_order_id");



ALTER TABLE ONLY "public"."wishlists"
    ADD CONSTRAINT "wishlists_customer_id_wc_product_id_key" UNIQUE ("customer_id", "wc_product_id");



ALTER TABLE ONLY "public"."wishlists"
    ADD CONSTRAINT "wishlists_pkey" PRIMARY KEY ("id");



CREATE INDEX "birthday_rewards_customer_idx" ON "public"."birthday_rewards" USING "btree" ("customer_id");



CREATE INDEX "free_pair_loyalty_idx" ON "public"."free_pair_rewards" USING "btree" ("loyalty_card_id");



CREATE INDEX "idx_broadcasts_recent" ON "public"."broadcasts" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_broadcasts_segment_recent" ON "public"."broadcasts" USING "btree" ("segment", "created_at" DESC);



CREATE UNIQUE INDEX "idx_customers_auth_user_id" ON "public"."customers" USING "btree" ("auth_user_id") WHERE ("auth_user_id" IS NOT NULL);



CREATE INDEX "idx_customers_email" ON "public"."customers" USING "btree" ("lower"("email"));



CREATE INDEX "idx_icr_channel_recent" ON "public"."inventory_change_requests" USING "btree" ("channel_id", "created_at" DESC);



CREATE INDEX "idx_icr_pending_recent" ON "public"."inventory_change_requests" USING "btree" ("status", "created_at" DESC) WHERE ("status" = 'pending'::"text");



CREATE INDEX "idx_icr_staff_recent" ON "public"."inventory_change_requests" USING "btree" ("requested_by_staff_id", "created_at" DESC);



CREATE INDEX "idx_otp_phone" ON "public"."otp_verifications" USING "btree" ("phone");



CREATE INDEX "idx_support_tickets_customer" ON "public"."support_tickets" USING "btree" ("customer_id");



CREATE INDEX "idx_support_tickets_status_created" ON "public"."support_tickets" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_transactions_wc_order" ON "public"."transactions" USING "btree" ("wc_order_id");



CREATE INDEX "idx_unmatched_email" ON "public"."unmatched_orders" USING "btree" ("email") WHERE ("matched_at" IS NULL);



CREATE INDEX "idx_unmatched_phone" ON "public"."unmatched_orders" USING "btree" ("phone") WHERE ("matched_at" IS NULL);



CREATE INDEX "pending_credits_phone_idx" ON "public"."pending_credits" USING "btree" ("phone") WHERE ("applied_at" IS NULL);



CREATE INDEX "push_campaigns_created_at_idx" ON "public"."push_campaigns" USING "btree" ("created_at" DESC);



CREATE INDEX "push_campaigns_target_idx" ON "public"."push_campaigns" USING "btree" ("target");



CREATE INDEX "push_tokens_customer_id_idx" ON "public"."push_tokens" USING "btree" ("customer_id");



CREATE INDEX "referrals_email_idx" ON "public"."referrals" USING "btree" ("referred_email");



CREATE INDEX "referrals_referred_idx" ON "public"."referrals" USING "btree" ("referred_id");



CREATE INDEX "referrals_referrer_idx" ON "public"."referrals" USING "btree" ("referrer_id");



CREATE OR REPLACE TRIGGER "loyalty_cards_updated_at" BEFORE UPDATE ON "public"."loyalty_cards" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_aplicar_creditos_pendientes" AFTER INSERT ON "public"."loyalty_cards" FOR EACH ROW EXECUTE FUNCTION "public"."fx_aplicar_creditos_pendientes"();



CREATE OR REPLACE TRIGGER "trg_purchase_stats" AFTER INSERT ON "public"."transactions" FOR EACH ROW EXECUTE FUNCTION "public"."trg_update_purchase_stats"();



CREATE OR REPLACE TRIGGER "trg_update_tier" BEFORE INSERT OR UPDATE OF "total_points" ON "public"."loyalty_cards" FOR EACH ROW EXECUTE FUNCTION "public"."update_loyalty_tier"();



ALTER TABLE ONLY "public"."birthday_rewards"
    ADD CONSTRAINT "birthday_rewards_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."broadcasts"
    ADD CONSTRAINT "broadcasts_sent_by_customer_id_fkey" FOREIGN KEY ("sent_by_customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."channel_inventory"
    ADD CONSTRAINT "channel_inventory_channel_id_fkey" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_referred_by_fkey" FOREIGN KEY ("referred_by") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."free_pair_rewards"
    ADD CONSTRAINT "free_pair_rewards_loyalty_card_id_fkey" FOREIGN KEY ("loyalty_card_id") REFERENCES "public"."loyalty_cards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."free_pair_rewards"
    ADD CONSTRAINT "free_pair_rewards_trigger_transaction_fkey" FOREIGN KEY ("trigger_transaction") REFERENCES "public"."transactions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_change_requests"
    ADD CONSTRAINT "inventory_change_requests_channel_id_fkey" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_change_requests"
    ADD CONSTRAINT "inventory_change_requests_requested_by_staff_id_fkey" FOREIGN KEY ("requested_by_staff_id") REFERENCES "public"."staff"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_change_requests"
    ADD CONSTRAINT "inventory_change_requests_reviewed_by_customer_id_fkey" FOREIGN KEY ("reviewed_by_customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."loyalty_cards"
    ADD CONSTRAINT "loyalty_cards_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."offline_sales"
    ADD CONSTRAINT "offline_sales_channel_id_fkey" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id");



ALTER TABLE ONLY "public"."offline_sales"
    ADD CONSTRAINT "offline_sales_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."offline_sales"
    ADD CONSTRAINT "offline_sales_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id");



ALTER TABLE ONLY "public"."purchase_items"
    ADD CONSTRAINT "purchase_items_transaction_id_fkey" FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id");



ALTER TABLE ONLY "public"."push_campaigns"
    ADD CONSTRAINT "push_campaigns_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."qr_scans"
    ADD CONSTRAINT "qr_scans_loyalty_card_id_fkey" FOREIGN KEY ("loyalty_card_id") REFERENCES "public"."loyalty_cards"("id");



ALTER TABLE ONLY "public"."referrals"
    ADD CONSTRAINT "referrals_referred_id_fkey" FOREIGN KEY ("referred_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."referrals"
    ADD CONSTRAINT "referrals_referrer_id_fkey" FOREIGN KEY ("referrer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rewards"
    ADD CONSTRAINT "rewards_loyalty_card_id_fkey" FOREIGN KEY ("loyalty_card_id") REFERENCES "public"."loyalty_cards"("id");



ALTER TABLE ONLY "public"."staff"
    ADD CONSTRAINT "staff_channel_id_fkey" FOREIGN KEY ("channel_id") REFERENCES "public"."channels"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_loyalty_card_id_fkey" FOREIGN KEY ("loyalty_card_id") REFERENCES "public"."loyalty_cards"("id");



ALTER TABLE ONLY "public"."wishlists"
    ADD CONSTRAINT "wishlists_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



CREATE POLICY "Users manage their own push tokens" ON "public"."push_tokens" USING (("customer_id" IN ( SELECT "customers"."id"
   FROM "public"."customers"
  WHERE ("customers"."phone" = (("auth"."jwt"() -> 'user_metadata'::"text") ->> 'phone'::"text"))))) WITH CHECK (("customer_id" IN ( SELECT "customers"."id"
   FROM "public"."customers"
  WHERE ("customers"."phone" = (("auth"."jwt"() -> 'user_metadata'::"text") ->> 'phone'::"text")))));



CREATE POLICY "admins_all_channels" ON "public"."channels" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customers"
  WHERE (("customers"."phone" = (("auth"."jwt"() -> 'user_metadata'::"text") ->> 'phone'::"text")) AND ("customers"."role" = ANY (ARRAY['admin'::"text", 'staff'::"text"]))))));



CREATE POLICY "admins_all_inventory" ON "public"."channel_inventory" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customers"
  WHERE (("customers"."phone" = (("auth"."jwt"() -> 'user_metadata'::"text") ->> 'phone'::"text")) AND ("customers"."role" = ANY (ARRAY['admin'::"text", 'staff'::"text"]))))));



CREATE POLICY "admins_all_staff" ON "public"."staff" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customers"
  WHERE (("customers"."phone" = (("auth"."jwt"() -> 'user_metadata'::"text") ->> 'phone'::"text")) AND ("customers"."role" = 'admin'::"text")))));



CREATE POLICY "admins_staff_all_sales" ON "public"."offline_sales" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customers"
  WHERE (("customers"."phone" = (("auth"."jwt"() -> 'user_metadata'::"text") ->> 'phone'::"text")) AND ("customers"."role" = ANY (ARRAY['admin'::"text", 'staff'::"text"]))))));



CREATE POLICY "anon_insert_offline_sales" ON "public"."offline_sales" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "anon_read_active_channels" ON "public"."channels" FOR SELECT TO "anon" USING (("active" = true));



CREATE POLICY "anon_read_active_staff" ON "public"."staff" FOR SELECT TO "anon" USING (("active" = true));



CREATE POLICY "anon_read_inventory" ON "public"."channel_inventory" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_offline_sales" ON "public"."offline_sales" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_own_sales" ON "public"."offline_sales" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_update_inventory_sold" ON "public"."channel_inventory" FOR UPDATE TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "auth read channel_inventory" ON "public"."channel_inventory" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "auth read channels" ON "public"."channels" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "auth read offline_sales" ON "public"."offline_sales" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "auth read staff" ON "public"."staff" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "auth read support_tickets" ON "public"."support_tickets" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



ALTER TABLE "public"."birthday_rewards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."broadcasts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "broadcasts admin read" ON "public"."broadcasts" FOR SELECT USING (("public"."my_role"() = 'admin'::"text"));



CREATE POLICY "cards self insert" ON "public"."loyalty_cards" FOR INSERT WITH CHECK (("customer_id" = "public"."my_customer_id"()));



CREATE POLICY "cards self read" ON "public"."loyalty_cards" FOR SELECT USING (("customer_id" = "public"."my_customer_id"()));



ALTER TABLE "public"."channel_inventory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."channels" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "channels admin write" ON "public"."channels" USING (("public"."my_role"() = 'admin'::"text")) WITH CHECK (("public"."my_role"() = 'admin'::"text"));



ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customers self insert" ON "public"."customers" FOR INSERT WITH CHECK (("auth_user_id" = "auth"."uid"()));



CREATE POLICY "customers self read" ON "public"."customers" FOR SELECT USING ((("auth_user_id" = "auth"."uid"()) OR ("referred_by" = "public"."my_customer_id"())));



CREATE POLICY "customers self update" ON "public"."customers" FOR UPDATE USING (("auth_user_id" = "auth"."uid"())) WITH CHECK (("auth_user_id" = "auth"."uid"()));



CREATE POLICY "customers_read_own_sales" ON "public"."offline_sales" FOR SELECT TO "authenticated" USING (("customer_phone" = (("auth"."jwt"() -> 'user_metadata'::"text") ->> 'phone'::"text")));



ALTER TABLE "public"."free_pair_rewards" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "icr insert with valid staff or admin/staff role" ON "public"."inventory_change_requests" FOR INSERT WITH CHECK ((("public"."my_role"() = ANY (ARRAY['admin'::"text", 'staff'::"text"])) OR (("requested_by_staff_id" IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."staff"
  WHERE (("staff"."id" = "inventory_change_requests"."requested_by_staff_id") AND ("staff"."active" = true)))))));



CREATE POLICY "icr read open" ON "public"."inventory_change_requests" FOR SELECT USING (true);



CREATE POLICY "inventory staff write" ON "public"."channel_inventory" USING (("public"."my_role"() = ANY (ARRAY['admin'::"text", 'staff'::"text"]))) WITH CHECK (("public"."my_role"() = ANY (ARRAY['admin'::"text", 'staff'::"text"])));



ALTER TABLE "public"."inventory_change_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "items self read" ON "public"."purchase_items" FOR SELECT USING (("transaction_id" IN ( SELECT "t"."id"
   FROM ("public"."transactions" "t"
     JOIN "public"."loyalty_cards" "lc" ON (("lc"."id" = "t"."loyalty_card_id")))
  WHERE ("lc"."customer_id" = "public"."my_customer_id"()))));



ALTER TABLE "public"."loyalty_cards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."offline_sales" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "offline_sales own by phone" ON "public"."offline_sales" FOR SELECT USING ((("auth"."role"() = 'authenticated'::"text") AND (("customer_id" = "public"."my_customer_id"()) OR ("customer_phone" = "public"."my_phone"()))));



CREATE POLICY "offline_sales staff insert" ON "public"."offline_sales" FOR INSERT WITH CHECK (("public"."my_role"() = ANY (ARRAY['admin'::"text", 'staff'::"text"])));



CREATE POLICY "offline_sales staff update" ON "public"."offline_sales" FOR UPDATE USING (("public"."my_role"() = ANY (ARRAY['admin'::"text", 'staff'::"text"]))) WITH CHECK (("public"."my_role"() = ANY (ARRAY['admin'::"text", 'staff'::"text"])));



ALTER TABLE "public"."otp_verifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "overrides public read" ON "public"."product_image_overrides" FOR SELECT USING (true);



ALTER TABLE "public"."pending_credits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_image_overrides" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."purchase_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "push self all" ON "public"."push_tokens" USING (("customer_id" = "public"."my_customer_id"())) WITH CHECK (("customer_id" = "public"."my_customer_id"()));



ALTER TABLE "public"."push_campaigns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."push_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."qr_scans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read_active_channels" ON "public"."channels" FOR SELECT TO "authenticated" USING (("active" = true));



CREATE POLICY "read_inventory" ON "public"."channel_inventory" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."referrals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rewards" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rewards self read" ON "public"."rewards" FOR SELECT USING (("loyalty_card_id" IN ( SELECT "loyalty_cards"."id"
   FROM "public"."loyalty_cards"
  WHERE ("loyalty_cards"."customer_id" = "public"."my_customer_id"()))));



ALTER TABLE "public"."staff" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "staff admin write" ON "public"."staff" USING (("public"."my_role"() = 'admin'::"text")) WITH CHECK (("public"."my_role"() = 'admin'::"text"));



CREATE POLICY "staff_read_own" ON "public"."staff" FOR SELECT TO "authenticated" USING (("active" = true));



ALTER TABLE "public"."support_tickets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tier_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transactions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tx self read" ON "public"."transactions" FOR SELECT USING (("loyalty_card_id" IN ( SELECT "loyalty_cards"."id"
   FROM "public"."loyalty_cards"
  WHERE ("loyalty_cards"."customer_id" = "public"."my_customer_id"()))));



ALTER TABLE "public"."unmatched_orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users own their wishlist" ON "public"."wishlists" USING (("customer_id" = ( SELECT "customers"."id"
   FROM "public"."customers"
  WHERE ("customers"."phone" = (( SELECT "users"."email"
           FROM "auth"."users"
          WHERE ("users"."id" = "auth"."uid"())))::"text")
 LIMIT 1)));



CREATE POLICY "wishlist self all" ON "public"."wishlists" USING (("customer_id" = "public"."my_customer_id"())) WITH CHECK (("customer_id" = "public"."my_customer_id"()));



ALTER TABLE "public"."wishlists" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."loyalty_cards";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";











































































































































































GRANT ALL ON FUNCTION "public"."award_birthday_points"("p_customer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."award_birthday_points"("p_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."award_birthday_points"("p_customer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."award_referral_points"("p_new_customer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."award_referral_points"("p_new_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."award_referral_points"("p_new_customer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_free_pair_reward"("p_loyalty_card_id" "uuid", "p_transaction_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_free_pair_reward"("p_loyalty_card_id" "uuid", "p_transaction_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_free_pair_reward"("p_loyalty_card_id" "uuid", "p_transaction_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_expired_otps"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_expired_otps"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_expired_otps"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fx_add_points"("p_card_id" "uuid", "p_points" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."fx_add_points"("p_card_id" "uuid", "p_points" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fx_add_points"("p_card_id" "uuid", "p_points" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."fx_aplicar_creditos_pendientes"() TO "anon";
GRANT ALL ON FUNCTION "public"."fx_aplicar_creditos_pendientes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fx_aplicar_creditos_pendientes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."my_customer_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."my_customer_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."my_customer_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."my_phone"() TO "anon";
GRANT ALL ON FUNCTION "public"."my_phone"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."my_phone"() TO "service_role";



GRANT ALL ON FUNCTION "public"."my_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."my_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."my_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."run_annual_tier_review"() TO "anon";
GRANT ALL ON FUNCTION "public"."run_annual_tier_review"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_annual_tier_review"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_update_purchase_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_update_purchase_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_update_purchase_stats"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_loyalty_tier"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_loyalty_tier"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_loyalty_tier"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "service_role";
























GRANT ALL ON TABLE "public"."birthday_rewards" TO "anon";
GRANT ALL ON TABLE "public"."birthday_rewards" TO "authenticated";
GRANT ALL ON TABLE "public"."birthday_rewards" TO "service_role";



GRANT ALL ON TABLE "public"."broadcasts" TO "anon";
GRANT ALL ON TABLE "public"."broadcasts" TO "authenticated";
GRANT ALL ON TABLE "public"."broadcasts" TO "service_role";



GRANT ALL ON TABLE "public"."channel_inventory" TO "anon";
GRANT ALL ON TABLE "public"."channel_inventory" TO "authenticated";
GRANT ALL ON TABLE "public"."channel_inventory" TO "service_role";



GRANT ALL ON TABLE "public"."channels" TO "anon";
GRANT ALL ON TABLE "public"."channels" TO "authenticated";
GRANT ALL ON TABLE "public"."channels" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."free_pair_rewards" TO "anon";
GRANT ALL ON TABLE "public"."free_pair_rewards" TO "authenticated";
GRANT ALL ON TABLE "public"."free_pair_rewards" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_change_requests" TO "anon";
GRANT ALL ON TABLE "public"."inventory_change_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_change_requests" TO "service_role";



GRANT ALL ON TABLE "public"."loyalty_cards" TO "anon";
GRANT ALL ON TABLE "public"."loyalty_cards" TO "authenticated";
GRANT ALL ON TABLE "public"."loyalty_cards" TO "service_role";



GRANT ALL ON TABLE "public"."offline_sales" TO "anon";
GRANT ALL ON TABLE "public"."offline_sales" TO "authenticated";
GRANT ALL ON TABLE "public"."offline_sales" TO "service_role";



GRANT ALL ON TABLE "public"."otp_verifications" TO "anon";
GRANT ALL ON TABLE "public"."otp_verifications" TO "authenticated";
GRANT ALL ON TABLE "public"."otp_verifications" TO "service_role";



GRANT ALL ON TABLE "public"."pending_credits" TO "anon";
GRANT ALL ON TABLE "public"."pending_credits" TO "authenticated";
GRANT ALL ON TABLE "public"."pending_credits" TO "service_role";



GRANT ALL ON TABLE "public"."product_image_overrides" TO "anon";
GRANT ALL ON TABLE "public"."product_image_overrides" TO "authenticated";
GRANT ALL ON TABLE "public"."product_image_overrides" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_items" TO "anon";
GRANT ALL ON TABLE "public"."purchase_items" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_items" TO "service_role";



GRANT ALL ON TABLE "public"."push_campaigns" TO "anon";
GRANT ALL ON TABLE "public"."push_campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."push_campaigns" TO "service_role";



GRANT ALL ON TABLE "public"."push_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."qr_scans" TO "anon";
GRANT ALL ON TABLE "public"."qr_scans" TO "authenticated";
GRANT ALL ON TABLE "public"."qr_scans" TO "service_role";



GRANT ALL ON TABLE "public"."referrals" TO "anon";
GRANT ALL ON TABLE "public"."referrals" TO "authenticated";
GRANT ALL ON TABLE "public"."referrals" TO "service_role";



GRANT ALL ON TABLE "public"."rewards" TO "anon";
GRANT ALL ON TABLE "public"."rewards" TO "authenticated";
GRANT ALL ON TABLE "public"."rewards" TO "service_role";



GRANT ALL ON TABLE "public"."staff" TO "anon";
GRANT ALL ON TABLE "public"."staff" TO "authenticated";
GRANT ALL ON TABLE "public"."staff" TO "service_role";



GRANT ALL ON TABLE "public"."support_tickets" TO "anon";
GRANT ALL ON TABLE "public"."support_tickets" TO "authenticated";
GRANT ALL ON TABLE "public"."support_tickets" TO "service_role";



GRANT ALL ON TABLE "public"."tier_config" TO "anon";
GRANT ALL ON TABLE "public"."tier_config" TO "authenticated";
GRANT ALL ON TABLE "public"."tier_config" TO "service_role";



GRANT ALL ON TABLE "public"."transactions" TO "anon";
GRANT ALL ON TABLE "public"."transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."transactions" TO "service_role";



GRANT ALL ON TABLE "public"."unmatched_orders" TO "anon";
GRANT ALL ON TABLE "public"."unmatched_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."unmatched_orders" TO "service_role";



GRANT ALL ON TABLE "public"."wishlists" TO "anon";
GRANT ALL ON TABLE "public"."wishlists" TO "authenticated";
GRANT ALL ON TABLE "public"."wishlists" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































