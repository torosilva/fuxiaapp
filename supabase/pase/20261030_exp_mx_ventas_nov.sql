-- Growth → Experimentos: primer experimento de México en BORRADOR, encargado por Mario el 2026-10-30 ("esa es la idea").
-- Pasa por public.f360_experiment_save (mismas validaciones que el formulario) con la sesión de Mario como autor.
-- Queda en DRAFT: falta el ID de la campaña nueva (lo da la agencia) y la aprobación de Mario en el admin, que fija todo.
-- Cifras propuestas, no reglas de negocio: presupuesto = lo que hoy gastan las 2 campañas MX juntas (~$190/día, 20–29 oct);
-- ticket de las 3 ventas MX de octubre: $2,520 / $2,800 / $4,050.
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"d11a8d33-cae6-46a5-9d0f-bd2516e8712b","role":"authenticated"}', true);
SELECT public.f360_experiment_save(NULL, $j${
  "name": "México: una sola campaña de ventas (sin campaña de seguidores)",
  "hypothesis": "Si apagamos FUXIA_OCT_IG_SEGUIDORES y ponemos todo el presupuesto de México (~$200 MXN/día) en una sola campaña con objetivo Compra que lleve a /mx/tienda/ y a las páginas de producto con /mx/, esperamos pasar de 0 ventas pagadas con último clic en anuncios (oct) a 4 o más en 14 días, con costo por venta de $700 MXN o menos.",
  "market": "MX",
  "primary_variable": "objetivo y destino de la campaña (Compra a /mx/ en vez de seguidores)",
  "proposed_by": "ia",
  "responsible": "agencia",
  "responsible_note": "Goyo da seguimiento",
  "channel": "Meta pagado",
  "start_date": "2026-11-03",
  "end_date": "2026-11-16",
  "budget": 2800,
  "budget_currency": "MXN",
  "primary_kpi": "cost_per_paid_order",
  "success_threshold": {"op": "<=", "value": 700, "min_sample": 4},
  "kill_threshold": {"op": ">=", "value": 1400, "min_sample": 1},
  "utm_campaign": "FUXIA_NOV_MX_VENTAS"
}$j$::jsonb);
COMMIT;
