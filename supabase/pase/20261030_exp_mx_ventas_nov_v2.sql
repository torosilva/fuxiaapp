-- EXP-2026-002 (borrador): Mario 2026-10-30 decide MANTENER la campaña de seguidores (comparación con Regina Romero, ~$4 por seguidor neto).
-- La campaña de ventas se suma, no la reemplaza, y apunta a quien ya interactuó con Instagram (seguidoras → compradoras).
-- Gasto total MX quedaría ~$270/día ≈ el de octubre ($8,304 en 23 días). Sigue en DRAFT hasta el ID de campaña y la aprobación de Mario.
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"d11a8d33-cae6-46a5-9d0f-bd2516e8712b","role":"authenticated"}', true);
SELECT public.f360_experiment_save('5582b6ff-29b0-4deb-aeab-7138e5d79490', $j${
  "name": "México: campaña de ventas a quien ya interactuó con Instagram",
  "hypothesis": "Si sumamos una campaña con objetivo Compra (~$200 MXN/día) dirigida a mujeres en México que interactuaron con @fuxia en Instagram en los últimos 60 días, y la llevamos a /mx/tienda/ y a producto con /mx/, esperamos pasar de 0 ventas pagadas con último clic en anuncios (oct) a 4 o más en 14 días, con costo por venta de $700 MXN o menos. La campaña de seguidores sigue igual.",
  "primary_variable": "audiencia: interacción con Instagram 60 días + objetivo Compra a /mx/",
  "audience": "Mujeres MX que interactuaron con la cuenta de Instagram (60 días)"
}$j$::jsonb);
COMMIT;
