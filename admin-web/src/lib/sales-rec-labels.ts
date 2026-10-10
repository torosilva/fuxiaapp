// Conciliación de Ventas — labels (no server imports, safe for client components).
export const DECISIONS: Record<string, string> = {
  venta_confirmada: 'Venta confirmada', no_se_concreto: 'No se concretó', duplicado: 'Duplicado', prueba: 'Prueba', reembolso: 'Reembolso',
  requiere_investigacion: 'Requiere investigación',
};
export const REC_STATE: Record<string, { label: string; cls: string }> = {
  pendiente_discrepancia: { label: 'Discrepancia sin revisar', cls: 'bg-danger-soft text-danger' },
  pendiente: { label: 'Por revisar', cls: 'bg-gold-soft text-gold-strong' },
  cambio_despues: { label: 'Cambió después de revisar', cls: 'bg-danger-soft text-danger' },
  en_investigacion: { label: 'En investigación', cls: 'bg-gold-soft text-gold-strong' },
  conflicto: { label: 'Conflicto', cls: 'bg-danger-soft text-danger' },
  revisado: { label: 'Revisado', cls: 'bg-success-soft text-success' },
  sin_novedad: { label: 'Sin novedad', cls: 'bg-surface-2 text-muted' },
};
// Financial evidence = what Woo / the gateway recorded. A human decision never changes it.
export const FINANCIAL: Record<string, string> = {
  SIN_COBRO: 'Sin cobro registrado',
  PAGO_REGISTRADO_WOO: 'Woo registró pago · pasarela sin consultar',
  COBRO_CON_TRANSACCION: 'Pago con transacción de la pasarela (según Woo)',
  PAGO_SIN_TRANSACCION: 'Woo registró pago sin transacción de pasarela',
  CONTRADICTORIA: 'Evidencia contradictoria',
  REEMBOLSADO: 'Reembolsado',
  REEMBOLSO_PARCIAL: 'Reembolso parcial',
  NO_EXISTE_EN_WOO: 'El pedido ya no existe en WooCommerce',
};
export const FLAG_NAME: Record<string, string> = {
  NO_CONCRETADO: 'No se concretó', REINTENTO_PAGADO: 'Reintentó y pagó', PAGO_Y_CANCELADO: 'Pagado y cancelado', PAGADO_SIN_EVIDENCIA: 'Pagado sin evidencia',
  EVIDENCIA_CONTRADICE: 'Evidencia contradice', POSIBLE_PRUEBA: 'Posible prueba', POSIBLE_DUPLICADO: 'Posible duplicado', REEMBOLSO: 'Reembolso',
  NO_EXISTE_EN_WOO: 'Ya no está en Woo',
};
export const GATEWAY: Record<string, string> = {
  approved: 'Aprobado', rejected: 'Rechazado', pending: 'Pendiente', refunded: 'Reembolsado', transaction_only: 'Solo número de transacción',
  no_evidence: 'Sin evidencia', order_missing: 'Pedido inexistente en Woo',
};
export const WOO_STATUS: Record<string, string> = {
  completed: 'Completado', processing: 'Procesando', cancelled: 'Cancelado', failed: 'Fallido', pending: 'Pendiente de pago', refunded: 'Reembolsado',
  'on-hold': 'En espera', 'checkout-draft': 'Borrador',
};
