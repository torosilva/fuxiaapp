-- Rollback of 20261013000500_f360_order_shipping.sql. Deploy the previous f360-woo-orders FIRST (it calls the function).
-- Addresses already copied to customers stay (they are the customer's ficha). The order_shipping table is NOT dropped here
-- (real order data); drop it only with Mario's explicit OK.
DROP TRIGGER IF EXISTS customers_link_order_shipping ON public.customers;
DROP FUNCTION IF EXISTS f360.customers_link_order_shipping();
DROP FUNCTION IF EXISTS public.f360_capture_order_shipping(text, jsonb);
DROP FUNCTION IF EXISTS f360.customer_address_from_orders(uuid);
