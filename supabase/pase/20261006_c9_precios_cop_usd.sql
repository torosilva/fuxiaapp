-- Fuxia 360 · pase C9 — COP / USD prices for the live models that had none (INCIDENT 2026-10-06: /co/ charged the MXN number as COP).
-- Approved by Mario 2026-10-06 ("si"): each model takes the price its OLD store products already charged in Colombia / USA
-- (most used value when they differed). Ibiza and Suecos leopardo have no old price → left for Carolina (the guard keeps them
-- 'Consultar precio'). Done through the SAME functions the admin uses, as Mario: audited in f360.price_changes, then a store
-- re-sync is requested per model (the publisher writes _price_cop / _price_usd; the queue runs when Productos is opened).
-- Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);
CREATE TEMP TABLE c9 (product_id uuid, modelo text, cop numeric, usd numeric) ON COMMIT DROP;
INSERT INTO c9 VALUES
  ('35a2360e-5367-4d7c-a3e9-a35b3d7d4074', 'Ballerinas BYL puntudo', 400000, 150),
  ('77588b0a-063c-4055-b3ff-ad11feb76b52', 'Ballerinas mocasines', 400000, 150),
  ('e0655e18-4abd-486f-bc31-4c674deaa360', 'Ballerinas resorte taches', 400000, 150),
  ('fb29e937-e45b-48ea-87e7-7e2a87655341', 'Botas cortas', 550000, 300),
  ('9f9ce25f-2b26-4156-9643-1f9f86cbc779', 'Croc', 420000, 180),
  ('0eac5ca1-a199-47d5-9ed2-80db1f91a323', 'Cucarron single', 400000, 150),
  ('079d6d3f-09bb-48ac-b7c3-d7ff9e92785a', 'Loafer suede', 420000, 180),
  ('cd6b57ca-efc6-485b-9bc6-b5a35b3e0764', 'Mafalda Láser', 400000, 150),
  ('9a598030-a4ee-48f8-951e-1aa1f01fee56', 'Mule punta afilada con tacon', 420000, 190),
  ('43938e4a-6b97-4947-a695-c95062d3ad01', 'Mules Colectiva', 420000, 150),
  ('53de5bbe-90d3-4010-8c96-6f9135d923bd', 'Paula gamuza', 420000, 150),
  ('d551c78b-5d80-4446-9109-5027b99a1001', 'Peep toe', 420000, 190),
  ('4d75dd61-f9dd-4603-9d7d-2bc83fccfe48', 'Plataforma araña', 420000, 190),
  ('a82d936b-177a-4fbe-a883-ab9becb01415', 'Plataforma entrelazada', 420000, 190),
  ('a9d514ed-5d2b-46bb-92af-9f5d2efc30d9', 'Plataforma Marcela', 420000, 190),
  ('b720fd76-1ab2-43b7-9391-5321b7dd20e2', 'Plataforma moño', 420000, 190),
  ('0878044c-7751-4eea-9f59-0d034e0f1ad7', 'Plataforma tiras amarrar', 420000, 190),
  ('c3329390-d3a0-4308-8397-4854dc753c60', 'Plataforma trenza ancha', 420000, 190),
  ('939f418d-fea1-4191-85ea-0bb6cea1d287', 'Sandalia 8', 420000, 170),
  ('1844635f-cce8-4a32-87f2-1912a216063d', 'Sandalia 8 trenzada', 420000, 170),
  ('0974ad84-87ad-411a-ab1d-5da442c62e4a', 'Sandalia de cuadros', 420000, 170),
  ('02808220-9bac-49db-b8d1-909ba753daec', 'Sandalia flat doble tira trenzada', 420000, 170),
  ('9d4b4adf-4924-4797-a4bc-7f86f998a363', 'Sandalia flor', 420000, 170),
  ('c3249968-8421-4281-86da-6ecb253b82e0', 'Sandalia plana de espiral', 400000, 170),
  ('bd4447a3-dd55-4ba1-9819-9d55f206720a', 'Sandalia tacon grueso flecos', 420000, 190),
  ('bc9b3f4d-a1e3-410b-b717-d2d5871aeae6', 'Sandalia trapecio', 400000, 170),
  ('d976b3c9-2f65-44b3-97b0-ad2c425b2325', 'Sandalias gladiadora', 420000, 170),
  ('a5224213-d9c0-4a91-b091-9988471cd819', 'Sandalias moneditas', 420000, 170),
  ('73f85b49-2564-4f71-a7fb-7b68f29e77ce', 'Sandalias tiras amarrar', 420000, 170),
  ('1b935a2e-fdb8-44dc-aa48-4de27ba260b7', 'Slingback flat mesh', 420000, 170),
  ('6da71118-76f3-438e-8eb4-4ef4c6fe95ed', 'Slingback punta afilada', 420000, 190),
  ('301e0802-12fb-4b1c-aebf-cd5165902398', 'Slingback punta afilada taches', 420000, 180),
  ('6708b8a6-4d28-49a5-99c4-94ef15156c20', 'Tacon grueso estoperoles', 420000, 190),
  ('2b11ac40-2b69-43ca-b0a7-754c830baee8', 'Tacon mule cruzado', 420000, 190),
  ('5573df27-d90a-4b74-863b-1d354789da54', 'Tacon PR', 420000, 190),
  ('0b83d45c-df74-4a39-83f8-85062a5cb6a8', 'Tacon RMX', 420000, 190),
  ('18642a4f-8f79-4ad6-a352-f3b35c848931', 'Tacon RMX Hebilla', 420000, 190),
  ('a0135e07-0cc6-4605-9c67-4d9e05d7e834', 'Tres puntadas', 400000, 170),
  ('028ff55c-7bbd-4570-98b6-8eff0263223e', 'Wedge cruzada', 420000, 190),
  ('8877ebbd-c821-4859-a6af-145655e5dd87', 'Wedge fleco', 420000, 190);
-- never overwrite a price someone already set
SELECT public.f360_set_product_price(product_id, 'COP', cop) FROM c9 WHERE NOT EXISTS (SELECT 1 FROM f360.product_prices pp WHERE pp.product_id = c9.product_id AND pp.currency_code = 'COP');
SELECT public.f360_set_product_price(product_id, 'USD', usd) FROM c9 WHERE NOT EXISTS (SELECT 1 FROM f360.product_prices pp WHERE pp.product_id = c9.product_id AND pp.currency_code = 'USD');
CREATE TEMP TABLE c9_sync (modelo text, resultado text) ON COMMIT DROP;
DO $$ DECLARE x record; BEGIN
  FOR x IN SELECT * FROM c9 LOOP
    BEGIN PERFORM public.f360_request_publish(x.product_id, gen_random_uuid(), 'woo_production'); INSERT INTO c9_sync VALUES (x.modelo, 'en cola');
    EXCEPTION WHEN OTHERS THEN INSERT INTO c9_sync VALUES (x.modelo, 'NO: ' || SQLERRM); END;
  END LOOP; END $$;
SELECT jsonb_build_object('precios_cop', (SELECT count(*) FROM f360.product_prices pp JOIN c9 USING (product_id) WHERE pp.currency_code = 'COP'),
  'precios_usd', (SELECT count(*) FROM f360.product_prices pp JOIN c9 USING (product_id) WHERE pp.currency_code = 'USD'),
  'en_cola', (SELECT count(*) FROM c9_sync WHERE resultado = 'en cola'), 'no', (SELECT jsonb_agg(modelo || ' → ' || resultado) FROM c9_sync WHERE resultado <> 'en cola')) AS resumen;
COMMIT;
