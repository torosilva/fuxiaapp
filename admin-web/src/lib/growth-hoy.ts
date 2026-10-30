import { rpc } from '@/lib/f360';

// Growth → Hoy, Clientas y Competencia (migrations 20261105000100 / 0200). Every number comes from the database; nothing is computed here
// except labels and percentages of numbers already returned.
export type HoyMarket = { market: 'MX' | 'CO'; currency: string; paid_14: number; paid_prev_14: number; revenue_14: number; created_14: number; paid_30: number;
  last_paid_at: string | null; days_since_last: number | null };
export type HoyAds = { market: string; spend_mxn: number | null; clicks: number; meta_purchases: number; ads_paid_orders: number; last_day: string; cost_per_sale: number | null };
export type HoyCampaign = { campaign_id: string; name: string; market: string; spend_mxn: number; clicks: number; meta_purchases: number; ads_paid_orders: number; last_day: string; active: boolean };
export type HoyFunnelRow = { period: 'actual' | 'anterior'; from: string; to: string; market: 'MX' | 'CO' | 'ROW'; channel: string; step: string; users: number };
export type HoyExperiment = { id: string; code: string; name: string; status: string; market: string; start_date: string | null; end_date: string | null;
  responsible: string; campaign_ids: string[]; live: { status: string; kpi_value: number | null; sample: number; success_met: boolean; kill_met: boolean; spend_mxn: number | null } | null };
export type HoyAlert = { level: 'alta' | 'media'; market: string | null; title: string; action: string };
export type Hoy = {
  today: string; generated_at: string; window: { from: string; to: string; prev_from: string; prev_to: string };
  markets: HoyMarket[]; channels: { market: string; channel: string; paid: number }[]; ads: HoyAds[]; campaigns: HoyCampaign[];
  instagram: { follows_7: number | null; unfollows_7: number | null; follows_prev_7: number | null; unfollows_prev_7: number | null; days_7: number; days_prev_7: number;
    followers: number | null; reach_7: number | null; website_clicks_7: number | null };
  funnel: { captured_on: string | null; rows: HoyFunnelRow[] }; experiments: HoyExperiment[];
  sources: { key: string; label: string; config_status: string; last_success_at: string | null }[]; alerts: HoyAlert[]; rules: string[];
};
export const getHoy = () => rpc<Hoy>('f360_growth_hoy');

export type Outreach = { status: 'escrito' | 'respondio' | 'compro' | 'no_interesa' | 'sin_datos'; note: string | null; by: string; at: string };
export type Buyer = { buyer: string; orders: number; first_at: string; last_at: string; days_since: number; spent: number; in_club: boolean; last_order: number;
  order_url: string | null; items: { product: string; color: string | null; size: string | null; qty: number }[]; outreach: Outreach | null };
export type Recuperar = { market: 'MX' | 'CO'; generated_at: string; buyers: Buyer[]; rule: string };
export const getRecuperar = (market: 'MX' | 'CO') => rpc<Recuperar>('f360_growth_recuperar', { p_market: market });
export const OUTREACH: Record<Outreach['status'], string> = { escrito: 'Le escribí', respondio: 'Respondió', compro: 'Volvió a comprar', no_interesa: 'No le interesa', sin_datos: 'Sin teléfono ni correo' };

export type Observation = { observed_on: string; followers_ig: number | null; active_ads_meta: number | null; ads_approx: boolean; price_text: string | null;
  channels: string | null; how_they_advertise: string | null; source: string; recorded_by_name: string };
export type Brand = { key: string; name: string; origin: string | null; url: string | null; is_self: boolean; latest: Observation | null;
  previous: { observed_on: string; followers_ig: number | null; active_ads_meta: number | null } | null };
export type Competencia = { brands: Brand[]; can_record: boolean; notes: string[] };
export const getCompetencia = () => rpc<Competencia>('f360_growth_competencia');

// GA4 default channel groups → plain Spanish.
export const CHANNEL: Record<string, string> = {
  'Paid Social': 'Anuncios en Instagram/Facebook', 'Organic Social': 'Instagram/Facebook sin pagar', Direct: 'Directo (escribió la dirección)',
  'Organic Search': 'Google sin pagar', 'Paid Search': 'Google pagado', Referral: 'Otros sitios', Email: 'Correo', Unassigned: 'Sin identificar',
  'Paid Other': 'Otros anuncios', 'Organic Shopping': 'Google Shopping sin pagar', 'Paid Shopping': 'Google Shopping pagado', 'AI Assistant': 'Asistentes de IA',
  'Organic Video': 'Video sin pagar', 'Cross-network': 'Campañas de Google', SMS: 'SMS', Display: 'Display', 'Mobile Push Notifications': 'Notificaciones',
};
export const STEPS: { key: string; label: string }[] = [
  { key: 'session_start', label: 'Entraron a la tienda' }, { key: 'view_item', label: 'Vieron un producto' }, { key: 'add_to_cart', label: 'Agregaron al carrito' },
  { key: 'begin_checkout', label: 'Empezaron a pagar' }, { key: 'purchase', label: 'Compraron' },
];
