-- Rollback of 20261010000600: back to C1's FX1- prefix (NOT recommended: the published scanner ignores FX1- codes).
DROP FUNCTION public.f360_crm_access();
CREATE OR REPLACE FUNCTION f360.new_card_token() RETURNS text LANGUAGE sql VOLATILE AS
$$ SELECT 'FX1-' || upper(encode(extensions.gen_random_bytes(12), 'hex')) $$;
CREATE OR REPLACE VIEW f360.cards_with_legacy_token AS
  SELECT id AS card_id, customer_id FROM public.loyalty_cards WHERE qr_code !~ '^FX1-[0-9A-F]{24}$';
