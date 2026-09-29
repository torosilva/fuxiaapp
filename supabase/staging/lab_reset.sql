-- S0.0A staging lab — RESET/TEARDOWN of lab fixtures (STAGING ONLY; never a migration).
-- Deletes only rows tagged as lab data: names 'STAGING %', phones in the fictional
-- +1 555 0100 xx range, codes 'STG%', Woo ids 990000000–990999999.
-- Auth users are removed separately by scripts/s00a/lab.mjs (admin API).
BEGIN;
CREATE TEMP TABLE lab_c ON COMMIT DROP AS
  SELECT id FROM public.customers WHERE phone LIKE '+1555010%' OR name LIKE 'STAGING%';
CREATE TEMP TABLE lab_card ON COMMIT DROP AS
  SELECT id FROM public.loyalty_cards WHERE customer_id IN (SELECT id FROM lab_c) OR qr_code LIKE 'STG-%';
CREATE TEMP TABLE lab_ch ON COMMIT DROP AS
  SELECT id FROM public.channels WHERE name LIKE 'STAGING%';
CREATE TEMP TABLE lab_tx ON COMMIT DROP AS
  SELECT id FROM public.transactions
  WHERE loyalty_card_id IN (SELECT id FROM lab_card) OR wc_order_id BETWEEN 990000000 AND 990999999;

DELETE FROM public.purchase_items   WHERE transaction_id IN (SELECT id FROM lab_tx);
DELETE FROM public.free_pair_rewards WHERE loyalty_card_id IN (SELECT id FROM lab_card);
DELETE FROM public.rewards          WHERE loyalty_card_id IN (SELECT id FROM lab_card);
DELETE FROM public.qr_scans         WHERE loyalty_card_id IN (SELECT id FROM lab_card);
DELETE FROM public.transactions     WHERE id IN (SELECT id FROM lab_tx);
DELETE FROM public.offline_sales
  WHERE code LIKE 'STG%' OR channel_id IN (SELECT id FROM lab_ch)
     OR customer_id IN (SELECT id FROM lab_c) OR customer_phone LIKE '+1555010%';
DELETE FROM public.inventory_change_requests WHERE channel_id IN (SELECT id FROM lab_ch);
DELETE FROM public.broadcasts WHERE sent_by_customer_id IN (SELECT id FROM lab_c) OR sent_by_name LIKE 'STAGING%';
DELETE FROM public.staff    WHERE name LIKE 'STAGING%' OR channel_id IN (SELECT id FROM lab_ch);
DELETE FROM public.channels WHERE id IN (SELECT id FROM lab_ch);
DELETE FROM public.support_tickets  WHERE customer_phone LIKE '+1555010%';
DELETE FROM public.unmatched_orders WHERE wc_order_id BETWEEN 990000000 AND 990999999;
DELETE FROM public.otp_verifications WHERE phone LIKE '+1555010%' OR phone = '+525555555555';
DELETE FROM public.pending_credits  WHERE phone LIKE '+1555010%';
DELETE FROM public.loyalty_cards    WHERE id IN (SELECT id FROM lab_card);
DELETE FROM public.customers        WHERE id IN (SELECT id FROM lab_c);   -- cascades push_tokens, wishlists, birthday_rewards, referrals
COMMIT;
