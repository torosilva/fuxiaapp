-- Fuxia 360 · CRM C1 fix + Clientas screen support. STAGING.
-- 1. Card QR prefix: C1 issued opaque tokens 'FX1-<24 hex>'. The PUBLISHED app's scanner only accepts codes starting with
--    'FX-' (fuxia-native/components/QRScanner.tsx:25), so new cards could not be scanned in store (found by the F1 audit,
--    docs/fuxia360/ops/PASE_F1_MIGRATIONS_AUDIT.md). New format: 'FX-' + 24 uppercase hex — still opaque (no phone, no id),
--    distinguishable from the legacy phone-derived 'FX-<8 digits>-<base36>-00'. Existing FX1- cards (if any) are rotated.
-- 2. f360_crm_access(): tells the admin whether the person may see customers' personal data (customer_pii_viewers).
-- Rollback: supabase/rollbacks/20261010000600_f360_crm_card_prefix_access.down.sql
CREATE OR REPLACE FUNCTION f360.new_card_token() RETURNS text LANGUAGE sql VOLATILE AS
$$ SELECT 'FX-' || upper(encode(extensions.gen_random_bytes(12), 'hex')) $$;

CREATE OR REPLACE VIEW f360.cards_with_legacy_token AS
  SELECT id AS card_id, customer_id FROM public.loyalty_cards WHERE qr_code !~ '^FX-[0-9A-F]{24}$';

DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT id FROM public.loyalty_cards WHERE qr_code ~ '^FX1-' LOOP
    PERFORM f360.rotate_card_token(c.id, 'C1 prefix fix: FX1- → FX- (scanner compatibility)', NULL);
  END LOOP;
END $$;

CREATE FUNCTION public.f360_crm_access() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer');
BEGIN
  RETURN jsonb_build_object('pii_viewer', EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = auth.uid()),
    'customers', (SELECT count(*) FROM public.customers WHERE role = 'customer'));
END $$;
REVOKE ALL ON FUNCTION public.f360_crm_access() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_crm_access() TO authenticated;
