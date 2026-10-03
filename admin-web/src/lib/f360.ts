import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

// ── Types returned by the f360 RPCs ─────────────────────────────────────────
export type Role = 'owner' | 'operator' | 'seller' | 'viewer';
export type Me = { display_name: string; role: Role };
export type Location = { id: string; name: string; type: string; is_authoritative: boolean; sales_sync_pending: boolean; pairs: number;
  ledger_authority?: 'legacy' | 'f360'; sellable?: boolean; starts_on?: string | null; ends_on?: string | null; incoming?: number };
export type ProductSummary = { id: string; name: string; code: string; category: string | null; category_key: string | null; from_store: boolean; image_path: string | null; regular_price: number | null; sale_price: number | null; ready: boolean; colors: { name: string; hex: string | null }[]; pairs: number };
export type Variant = { id: string; size: string; sku: string | null };
export type Media = { id: string; path: string };
export type Category = { key: string; name: string };
export type Readiness = { ready: boolean; missing: ('precio' | 'categoria' | 'descripcion' | 'color' | 'talla' | 'fotos')[] };
export type Balance = { location_id: string; size: string; on_hand: number };
export type Color = { id: string; name: string; code: string; hex: string | null; image_path: string | null; media: Media[]; variants: Variant[]; balances: Balance[] };
export type Product = {
  id: string; name: string; code: string; codes_locked: boolean; category: string | null; category_key: string | null;
  description: string | null; short_description: string | null; regular_price: number | null; sale_price: number | null;
  make_to_order?: boolean; image_path: string | null; readiness: Readiness; online_location: { id: string; name: string } | null;
  sizes: string[]; colors: Color[]; pairs: number;
};
export type EventLine = { product_id: string; product_name: string; product_image: string | null; color: string; color_hex: string | null; size: string; sku?: string | null; quantity: number; from_location: string | null; to_location: string | null };
export type InventoryEvent = { id: string; type: string; actor_name: string; note: string | null; occurred_at: string; total_pairs: number; lines: EventLine[]; replayed?: boolean; reference_type?: string | null; reference_id?: string | null };
export type LocationInventory = Location & { products: { id: string; name: string; image_path: string | null; pairs: number; colors: { name: string; hex: string | null; sizes: { size: string; on_hand: number }[] }[] }[] };
export type Home = { display_name: string; role: Role; locations: Location[]; recent: InventoryEvent[]; product_count: number;
  available_pairs: number; in_transit_pairs: number; transfers: { requested: number; in_transit: number; with_difference: number } };

// Track C · Transfers
export type TransferStatus = 'requested' | 'cancelled' | 'in_transit' | 'received' | 'with_difference' | 'closed';
export type TransferLine = { variant_id: string; product_id: string; product_name: string; color: string; color_hex: string | null; size: string; sku: string | null;
  image_path: string | null; requested: number; sent: number | null; received: number | null; returned: number; written_off: number; outstanding: number; available_at_origin: number };
export type TransferHistory = { action: 'request' | 'cancel' | 'send' | 'receive' | 'resolve'; from_status: string | null; to_status: string; actor_name: string; actor_role: string;
  at: string; lines: { label: string; quantity: number; sent?: number; action?: 'return' | 'write_off' }[]; reason: string | null };
export type Transfer = {
  id: string; number: string; status: TransferStatus; note: string | null; from: { id: string; name: string }; to: { id: string; name: string };
  requested_by_name: string; requested_at: string; sent_by_name: string | null; sent_at: string | null; received_by_name: string | null; received_at: string | null;
  cancelled_by_name: string | null; cancelled_at: string | null; closed_by_name: string | null; closed_at: string | null;
  totals: { requested: number; sent: number; received: number; returned: number; written_off: number; outstanding: number | null };
  lines: TransferLine[]; history?: TransferHistory[];
  can: { cancel: boolean; send: boolean; receive: boolean; resolve: boolean }; replayed?: boolean;
};
export type TransferView = 'requested' | 'in_transit' | 'received' | 'with_difference' | 'all';
export type TransferList = { items: Transfer[]; counts: { requested: number; in_transit: number; with_difference: number } };
export type TransferLocations = { role: Role; can_send: boolean; can_request: boolean; locations: { id: string; name: string; type: string; mine: boolean; pairs: number }[] };

export type PubState = 'borrador' | 'listo' | 'publicando' | 'publicado' | 'cambios' | 'error' | 'sin_tienda';
export type PubStep = { step: string; object_ref: string | null; action: string; woo_id: number | null; ok: boolean; message: string | null; at: string };
export type PubJob = {
  id: string; status: 'queued' | 'running' | 'succeeded' | 'partial' | 'failed'; requested_by_name: string; created_at: string;
  started_at: string | null; finished_at: string | null; attempt: number; error_message: string | null;
  summary: { woo_product_id: number | null; woo_status: string | null; variations: number; created: number; updated: number; hidden: number; stock_pushed: number; mismatches: string[] } | null;
  steps: PubStep[] | null;
};
export type Publication = {
  state: PubState; ready?: boolean; can_publish: boolean; message?: string;
  target?: { key: string; name: string; base_url: string; is_production: boolean };
  woo_product_id?: number | null; woo_status?: string | null; last_success_at?: string | null; variations_linked?: number;
  active_job?: PubJob | null; jobs: PubJob[];
};

export type SyncIssue = {
  id: string; kind: 'oversell' | 'unknown_sku' | 'sku_mismatch' | 'stock_drift' | 'push_failed' | 'cancel_after_sale' | 'refund_after_sale' | 'webhook_rejected';
  status: 'open' | 'resolved'; message: string; product_id: string | null; product_name: string | null; variant_label: string | null;
  woo_order_id: number | null; occurrences: number; created_at: string; last_seen_at: string; resolved_at: string | null;
  resolved_by_name: string | null; resolution_note: string | null; target: string;
};
export type SyncOverview = {
  issues: SyncIssue[]; open_count: number;
  last_reconciliation: { checked: number; in_sync: number; drifted: number; missing: number; at: string; by: string | null; target: string } | null;
  queue: { pending: number; failing: number; oldest: string | null };
  recent_pushes: { at: string; label: string; ok: boolean; ats: number | null; woo_before: number | null; pushed: number | null; error: string | null }[];
  recent_orders: { at: string; order: number | null; status: string | null; result: string; lines: { sku: string; qty?: number; outcome: string }[] | null }[];
};

export type ScenarioKind = 'conservador' | 'base' | 'agresivo';
export type ReportedFigure = { id: string; metric: string; period: string; value: number; scope: string; source: string;
  status: 'reportada_no_verificada' | 'verificada' | 'descartada'; note: string | null; created_by_name: string; created_at: string;
  status_by_name: string | null; status_at: string | null; status_note: string | null };
export type GrowthPlan = {
  year: number; can_edit: boolean;
  plan: { north_star: number; note: string | null; updated_by_name: string; updated_at: string } | null;
  scenarios: Partial<Record<ScenarioKind, { inputs: import('./growth-model').GrowthInputs; updated_by_name: string; updated_at: string }>>;
  reported_figures: ReportedFigure[];
  changes: { what: string; by: string; at: string }[];
};

export class AccessError extends Error {}

// Calls an f360 RPC as the logged-in user. Access problems send the user to /login with a reason.
export async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) {
    if (error.code === '42501' || /JWT|not authenticated/i.test(error.message)) {
      redirect(`/salir?motivo=${encodeURIComponent(error.message)}`);
    }
    throw new Error(error.message);
  }
  return data as T;
}

export const getMe = () => rpc<Me>('f360_me');
export const getHome = () => rpc<Home>('f360_home');
export const listProducts = (query?: string) => rpc<ProductSummary[]>('f360_list_products', { p_query: query ?? null });
export const getProduct = (id: string) => rpc<Product>('f360_get_product', { p_product_id: id });
export const listLocations = () => rpc<Location[]>('f360_list_locations');
export const listEvents = (opts: { limit?: number; productId?: string; locationId?: string } = {}) =>
  rpc<InventoryEvent[]>('f360_list_events', { p_limit: opts.limit ?? 50, p_product_id: opts.productId ?? null, p_location_id: opts.locationId ?? null });
export const getEvent = (id: string) => rpc<InventoryEvent>('f360_get_event', { p_event_id: id });
export const listCategories = () => rpc<Category[]>('f360_list_categories');
export const inventoryByLocation = (locationId?: string) => rpc<LocationInventory[]>('f360_inventory_by_location', { p_location_id: locationId ?? null });

export const getPublication = (productId: string) => rpc<Publication>('f360_publication_status', { p_product_id: productId });

export const getSyncOverview = (status: 'open' | 'resolved' | 'all' = 'open') => rpc<SyncOverview>('f360_list_sync_issues', { p_status: status });
export const getSyncBadge = () => rpc<number>('f360_sync_badge');

export const getGrowthPlan = (year: number) => rpc<GrowthPlan>('f360_growth_plan', { p_year: year });

export const listTransfers = (view: TransferView = 'all') => rpc<TransferList>('f360_list_transfers', { p_view: view });
export const getTransfer = (id: string) => rpc<Transfer>('f360_get_transfer', { p_transfer_id: id });
export const getTransferLocations = () => rpc<TransferLocations>('f360_transfer_locations');

// C3.3 · Ventas (read model over the authoritative sales)
export type SaleRow = { id: string; occurred_at: string; channel: 'store' | 'online'; source: string; status: 'completed'; location: string | null; seller: string;
  customer: string | null; pairs: number; total: number; payment_method: string | null; points: number; self_sale: boolean; claim_pending: boolean };
export type SalesList = { from: string; to: string; summary: { revenue: number; sales: number; pairs: number; avg_ticket: number }; items: SaleRow[];
  filters: { locations: { id: string; name: string }[]; sellers: { id: string; name: string }[]; channels: { key: string; name: string; available: boolean }[] } };
export type SaleDetail = {
  id: string; occurred_at: string; channel: string; status: string; ledger: 'f360' | 'legacy'; location: { id: string; name: string } | null; seller: string;
  customer: { name: string | null; phone: string | null } | null; total: number; payment_method: string | null; payment_reference: string | null; price_source: string | null;
  items: { line: number; product_name: string; color: string | null; size: string | null; sku: string | null; quantity: number; unit_price: number; line_total: number; price_source: string }[];
  inventory: { kind: 'f360'; event: InventoryEvent } | { kind: 'legacy'; text: string };
  loyalty: { state: 'credited' | 'self_sale' | 'pending_claim' | 'none'; points: number; pairs?: number; text: string; code?: string; transaction_id?: string; audit: { result: string; points: number; at: string }[] };
  support: Record<string, string | null>;
};
export const listSales = (f: { from?: string; to?: string; locationId?: string; sellerId?: string; channel?: string }) =>
  rpc<SalesList>('f360_list_sales', { p_from: f.from || null, p_to: f.to || null, p_location_id: f.locationId || null, p_seller_id: f.sellerId || null, p_channel: f.channel || null });
export const getSale = (id: string) => rpc<SaleDetail>('f360_get_sale', { p_sale_id: id });

// Prices per currency
export type CurrencyPrice = { code: string; name: string; symbol: string; decimals: number; is_base: boolean; active: boolean; woo_meta_key: string | null;
  amount: number | null; suggested: number | null; updated_by_name: string | null; updated_at: string | null };
export type Currency = { code: string; name: string; symbol: string; decimals: number; is_base: boolean; woo_meta_key: string | null; active: boolean; sort: number };
export type CurrencyList = { currencies: Currency[]; suggestions: { currency: string; base: number; amount: number }[] };
export const getProductPrices = (id: string) => rpc<CurrencyPrice[]>('f360_product_prices', { p_product_id: id });
export const listCurrencies = () => rpc<CurrencyList>('f360_list_currencies');

export const canWrite = (role: Role) => role === 'owner' || role === 'operator';
/** Who may ask for merchandise to be moved (a seller only for her assigned locations — checked in the database). */
export const canRequestTransfer = (role: Role) => role === 'owner' || role === 'operator' || role === 'seller';

// Track D · D2 — homologation of the legacy Woo catalog (operator+)
export type HomologationStatus = 'propuesto' | 'confirmado' | 'requiere_revision' | 'conflicto' | 'sin_correspondencia';
export type HomologationRow = {
  woo_variation_id: number; woo_product_id: number; woo_product_name: string; woo_parent_sku: string | null; woo_category: string | null;
  woo_size: string | null; woo_color: string | null; woo_regular_price: number | null; sold_all: number; sold_90d: number;
  proposed_model: string | null; proposed_product_id: string | null; proposed_color: string | null; proposed_size: string | null;
  confidence: 'alta' | 'media' | 'baja' | null; proposal_reason: string | null; status: HomologationStatus; human_locked: boolean;
  note: string | null; decided_by_name: string | null; decided_at: string | null;
  confirmed: { variant_id: string; product_id: string; product_name: string; color: string; size: string; sku: string | null } | null;
};
export type HomologationSummary = { variations: number; woo_products: number; propuesto: number; confirmado: number; requiere_revision: number;
  conflicto: number; sin_correspondencia: number; models_proposed: number; models_confirmed: number; coverage_pct: number; snapshot_at: string | null };
export type Homologation = {
  target: { key: string; name: string; is_production: boolean }; can_edit: boolean; summary: HomologationSummary;
  categories: Category[]; models: { id: string; name: string; category_key: string | null; published: boolean; colors: string[] }[]; rows: HomologationRow[];
};
export const getHomologation = (target = 'woo_staging4') => rpc<Homologation>('f360_legacy_homologation', { p_target_key: target });
export type LegacySource = { color_id: string; color: string; woo_product_id: number; woo_product_name: string; target_key: string; target_name: string; base_url: string; variations: number };
export const getLegacySources = (productId: string) => rpc<LegacySource[]>('f360_legacy_sources', { p_product_id: productId });
export type ArchiveState = { status: 'active' | 'archived'; blockers: string[]; last_change: { to: string; by: string; at: string; reason: string } | null };
export const getArchiveState = (productId: string) => rpc<ArchiveState>('f360_product_archive_state', { p_product_id: productId });

// Track D · D3 — opening physical count
export type OpeningStatus = 'preliminar' | 'congelado' | 'aprobado' | 'cargado' | 'cancelado';
export type OpeningLineStatus = 'pendiente' | 'contado_1' | 'doble_ok' | 'diferencia' | 'recontado' | 'recontar';
export type OpeningSummary = { lines: number; pendiente: number; contado_1: number; doble_ok: number; diferencia: number; recontado: number; recontar: number;
  final_lines: number; final_pairs: number; out_of_scope: number; unlisted_open: number; unlisted_pairs: number };
export type OpeningState = { count: null | { id: string; status: OpeningStatus; location: string; target: { key: string; name: string };
  started_by: string; started_at: string; frozen_by: string | null; frozen_at: string | null; reconciled_at: string | null;
  approved_by: string | null; approved_at: string | null; approval_note: string | null; cancelled_at: string | null; cancel_reason: string | null };
  summary?: OpeningSummary; blockers?: string[] };
export type OpeningSize = { variant_id: string; size: string; sku: string | null; status: OpeningLineStatus; in_scope: boolean; woo_variations: number[] | null;
  count1: number | null; count1_by: string | null; count1_done: boolean; count2: number | null; count2_by: string | null; recount: number | null; recount_by: string | null;
  final_qty: number | null; affected: { woo_sold: number; moves: number } | null; woo_managed: boolean | null; woo_stock: number | null; difference: number | null };
export type OpeningView = 'conteo1' | 'conteo2' | 'reconteo' | 'reporte';
export type OpeningSheet = { view: OpeningView; me: string; models: { product_id: string; model: string; colors: { color: string; hex: string | null; sizes: OpeningSize[] }[] }[];
  unlisted: { id: string; description: string; size: string | null; quantity: number; found_by: string; found_at: string; status: 'abierto' | 'resuelto'; resolution: string | null; resolved_by: string | null }[] };
export const getOpeningState = () => rpc<OpeningState>('f360_opening_state', { p_count_id: null });
export const getOpeningSheet = (id: string, view: OpeningView) => rpc<OpeningSheet>('f360_opening_sheet', { p_count_id: id, p_view: view });
export const getColorRemoveState = (colorId: string) => rpc<{ blockers: string[] }>('f360_color_remove_state', { p_color_id: colorId });
export type ChannelState = { target: string; links: number; queue: number; last_push: string | null; opening_loaded: boolean;
  visibility: { woo_product_id: number; pending: 'ocultar' | 'mostrar' | null; last: { kind: 'ocultar' | 'mostrar'; status: 'pendiente' | 'hecho' | 'error'; by: string; at: string; error: string | null } | null }[] };
export const getChannelState = (target = 'woo_staging4') => rpc<ChannelState>('f360_legacy_channel_state', { p_target_key: target });
export type LegacyChannel = { id: string; name: string; type: string; active: boolean; legacy_pairs: number };
export const listLegacyChannelsAvailable = () => rpc<LegacyChannel[]>('f360_legacy_channels_available');

// Apartado Gold + entrega inmediata (phase 1-2)
export type Reservation = { id: string; location_id: string; store: string; variant_id: string; product: string; color: string; color_hex: string | null; size: string; sku: string | null;
  customer: string; phone_last4: string; channel: 'app' | 'web' | 'tienda'; status: 'activa' | 'vendida' | 'vencida' | 'cancelada';
  created_at: string; expires_at: string; closed_at: string | null; closed_by: string | null; closed_reason: string | null };
export const listReservations = (locationId?: string) => rpc<Reservation[]>('f360_reservations', { p_location_id: locationId ?? null, p_days: 7 });

// Sobre pedido (Mario 2026-10-03): online orders of a size without stock, to be made and shipped in 5–7 business days.
export type MadeToOrder = { id: string; order: number; store: string; product: string; color: string; size: string; sku: string; quantity: number;
  status: 'pendiente' | 'en_proceso' | 'enviado' | 'cancelado'; created_at: string; updated_at: string; updated_by: string | null; note: string | null; ship_by: string | null };
export const listMadeToOrder = () => rpc<MadeToOrder[]>('f360_made_to_order_list', { p_days: 90 });

// "Lo hacemos a la medida" (Mario 2026-10-03): requests left through Hilo's chat on the product page.
export type CustomRequest = { id: string; product: string; product_id: string | null; color: string; size: string | null; store_size: string | null; foot_cm: number | null;
  name: string; phone: string; note: string | null; country: string | null; status: 'nueva' | 'contactada' | 'cotizada' | 'cerrada' | 'descartada'; created_at: string; updated_by: string | null };
export const listCustomRequests = () => rpc<CustomRequest[]>('f360_custom_requests_list', { p_days: 90 });

// Stores are warehouses too (Mario 2026-10-03): online orders a store has to ship.
export type StoreShipment = { id: string; order: number; store: string; label: string; quantity: number; status: 'por_enviar' | 'enviado'; created_at: string; shipped_at: string | null; shipped_by: string | null };
export const listStoreShipments = () => rpc<StoreShipment[]>('f360_online_store_shipments', { p_days: 30 });
