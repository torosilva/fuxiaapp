-- Fuxia 360 · pase G8 — Mario (2026-10-06): the account ending …1363 is NOT his. Remove every Fuxia 360 access from it.
-- Owners: Carolina (…4188) and Mario Silva (…2939) only; they are the only "ver datos de clientas". Adrián: viewer when he has an account.
BEGIN;
DELETE FROM f360.customer_pii_viewers WHERE auth_user_id = '31608810-988e-42d5-b2fb-381eef07d68b';
DELETE FROM f360.location_assignments WHERE auth_user_id = '31608810-988e-42d5-b2fb-381eef07d68b';
DELETE FROM f360.user_roles WHERE auth_user_id = '31608810-988e-42d5-b2fb-381eef07d68b';
COMMIT;
