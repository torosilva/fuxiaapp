// What Fuxia 360 can and cannot answer today, and why (docs/fuxia360/growth/DATA_AUDIT.md).
// Screens show THIS instead of numbers until a complete, approved source is connected. Never invented values.
export type Availability = 'confiable' | 'parcial' | 'no_disponible';

export const AVAILABILITY_LABEL: Record<Availability, string> = { confiable: 'Confiable', parcial: 'Parcial', no_disponible: 'No disponible' };

export type AuditRow = { question: string; status: Availability; source: string; needs: string };

export const GROWTH_QUESTIONS: AuditRow[] = [
  { question: '¿Cuánto estamos vendiendo? (todos los canales)', status: 'no_disponible', source: 'Ecommerce completo solo en WooCommerce producción; ventas físicas fuera de la app no se registran', needs: 'Conectar historial de pedidos de Woo (decisión D-C1) y registrar ventas físicas' },
  { question: '¿Cuánto viene de nuevas vs recurrentes?', status: 'no_disponible', source: 'Requiere historial completo por clienta', needs: 'D-C1 + resolución de identidad (D-C3)' },
  { question: '¿Cuál es el AOV?', status: 'parcial', source: 'Pedidos Woo registrados por el webhook de loyalty (miembros + no emparejados) desde que se activó', needs: 'Historial completo de Woo (D-C1)' },
  { question: '¿Frecuencia de compra y tiempo para recomprar?', status: 'no_disponible', source: 'Requiere una clienta = una identidad estable en todos sus pedidos', needs: 'D-C1, D-C3, D-C4' },
  { question: '¿Qué modelos generan más revenue?', status: 'parcial', source: 'Partidas de pedidos del webhook (desde su activación); SKUs anteriores son libres', needs: 'Historial completo + mapeo de SKUs anteriores a modelos (D-G1)' },
  { question: '¿Qué modelos adquieren más clientas nuevas?', status: 'no_disponible', source: 'Requiere detectar la primera compra de cada clienta', needs: 'D-C1, D-C3' },
  { question: '¿Qué aparece en la segunda compra? ¿Qué categorías se compran juntas?', status: 'no_disponible', source: 'Requiere historial por clienta', needs: 'D-C1, D-C3' },
  { question: '¿Qué ciudades/estados generan revenue? ¿Dónde crece Fuxia?', status: 'no_disponible', source: 'Ciudad/estado solo existe en las direcciones de pedidos de Woo; no se guarda en Fuxia', needs: 'D-C1 + D-C2 (qué datos personales se guardan)' },
  { question: '¿Dónde hay clientas pero baja recompra?', status: 'no_disponible', source: 'Ubicación + historial por clienta', needs: 'D-C1, D-C2, D-C3' },
  { question: '¿Qué % del revenue viene de CRM / recompra?', status: 'no_disponible', source: 'No hay campañas ni regla de atribución', needs: 'Regla de atribución (D-G3)' },
  { question: 'Puntos y nivel de loyalty por clienta', status: 'confiable', source: 'Sistema de loyalty (miembros de la app)', needs: '—' },
  { question: 'Unidades vendidas en línea de productos Fuxia 360', status: 'confiable', source: 'Ledger de Fuxia 360 (P2.3A), solo productos nuevos, sin precio ni clienta', needs: '—' },
];

export const CUSTOMER_FIELDS: AuditRow[] = [
  { question: 'Identidad (cuenta verificada)', status: 'confiable', source: 'Supabase Auth (miembros de la app)', needs: '—' },
  { question: 'Teléfono / nombre / email', status: 'parcial', source: 'Clientas de la app (loyalty); compradoras sin cuenta solo en Woo', needs: 'D-C2 (qué se guarda) y D-C3 (cómo se une)' },
  { question: 'Ciudad / estado', status: 'no_disponible', source: 'Solo en direcciones de pedidos Woo', needs: 'D-C1, D-C2' },
  { question: 'Canal de adquisición', status: 'no_disponible', source: 'Solo fragmentos (referidos, popup)', needs: 'Regla de atribución (D-G3)' },
  { question: 'Pedidos en línea', status: 'parcial', source: 'Webhook de loyalty desde su activación', needs: 'D-C1' },
  { question: 'Ventas físicas', status: 'parcial', source: 'Solo las registradas en la app (QR/código)', needs: 'D-C5 y registro en tienda' },
  { question: 'Modelos, color y talla comprados', status: 'parcial', source: 'Partidas de pedidos del webhook', needs: 'D-C1, D-G1' },
  { question: 'Primera / última compra, órdenes, unidades, revenue, AOV, frecuencia', status: 'no_disponible', source: 'Requiere historial completo por clienta', needs: 'D-C1, D-C3, D-C4' },
  { question: 'Loyalty: nivel y puntos', status: 'confiable', source: 'Sistema de loyalty', needs: '—' },
  { question: 'Cancelaciones y cambios', status: 'parcial', source: 'Estado de transacciones de miembros', needs: 'D-C1 y política DW4' },
];

export const SEGMENTS: { name: string; rule: string; status: Availability; needs: string }[] = [
  { name: 'Nuevas clientas', rule: 'Primera compra en los últimos 90 días', status: 'no_disponible', needs: 'Historial completo por clienta' },
  { name: 'Recurrentes', rule: '2 o más compras en total', status: 'no_disponible', needs: 'Historial completo por clienta' },
  { name: 'VIP', rule: 'Top 10% por revenue de los últimos 12 meses (umbral editable)', status: 'no_disponible', needs: 'Revenue por clienta' },
  { name: 'Una sola compra', rule: 'Exactamente 1 compra', status: 'no_disponible', needs: 'Historial completo por clienta' },
  { name: '30 / 60 / 90 / 180+ días sin comprar', rule: 'Días desde la última compra', status: 'no_disponible', needs: 'Última compra confiable por clienta' },
  { name: 'Compradoras por modelo', rule: 'Compraron un modelo dado', status: 'parcial', needs: 'Solo pedidos del webhook; SKUs anteriores sin mapear' },
  { name: 'Compradoras por categoría', rule: 'Compraron una categoría dada', status: 'parcial', needs: 'Categoría no siempre se copió a las partidas' },
  { name: 'Compradoras por ciudad / estado', rule: 'Ciudad/estado del último pedido', status: 'no_disponible', needs: 'D-C2' },
  { name: 'High AOV', rule: 'AOV de la clienta ≥ percentil 75', status: 'no_disponible', needs: 'Historial completo' },
  { name: 'Zapatos pero nunca accesorios', rule: 'Compraron zapatos y 0 accesorios', status: 'no_disponible', needs: 'Definir "accesorios" (D-G2): hoy no existe esa categoría' },
  { name: 'Accesorios pero no zapatos', rule: 'Compraron accesorios y 0 zapatos', status: 'no_disponible', needs: 'D-G2' },
  { name: 'Potencialmente recuperables', rule: 'Recurrentes con 90–365 días sin comprar', status: 'no_disponible', needs: 'Historial completo por clienta' },
];

export const IDENTITY_DECISIONS: { id: string; question: string }[] = [
  { id: 'D-C1', question: '¿Puede Fuxia 360 leer el historial completo de pedidos de WooCommerce (solo lectura) y dónde se calcula?' },
  { id: 'D-C2', question: '¿Qué datos personales de los pedidos puede guardar Fuxia 360 (nombre, email, teléfono, ciudad/estado) y por cuánto tiempo?' },
  { id: 'D-C3', question: 'Un pedido de invitada con el mismo email/teléfono que una clienta: ¿se une solo, se sugiere, o nunca?' },
  { id: 'D-C4', question: 'Duplicados existentes de clientas: ¿revisión manual o se dejan como están?' },
  { id: 'D-C5', question: 'Ventas físicas sin QR/teléfono: ¿revenue anónimo (sin clienta)?' },
];
