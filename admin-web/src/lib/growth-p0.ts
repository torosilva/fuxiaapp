import { rpc } from '@/lib/f360';

// Growth P0 (migrations 20261104000100 / 0200): Instagram orgánico and the experiments register. Operator+ (same as the War Room).
export type IgKind = 'post' | 'carousel' | 'reel' | 'story';
export type IgDay = { date: string; reach: number | null; views: number | null; profile_views: number | null; website_clicks: number | null;
  accounts_engaged: number | null; total_interactions: number | null; follows: number | null; unfollows: number | null; followers_count: number | null;
  published: Record<IgKind, number>; ig_paid_orders: number };
export type IgMedia = { media_id: string; kind: IgKind; posted_at: string; permalink: string | null; caption: string | null; captured_on: string | null;
  reach: number | null; views: number | null; likes: number | null; comments: number | null; saves: number | null; shares: number | null;
  total_interactions: number | null; replies: number | null; profile_visits: number | null; follows: number | null; avg_watch_ms: number | null;
  paid_orders_with_evidence: number };
export type GrowthInstagram = {
  from: string; to: string; generated_at: string;
  source: { config_status: 'CONFIGURED' | 'NOT_CONFIGURED'; last_success_at: string | null; last_error: string | null; last_try_at: string | null; notes: string | null };
  daily: IgDay[];
  by_kind: { kind: IgKind; count: number; with_metrics: number; reach_avg: number | null; views_avg: number | null; saves: number | null; shares: number | null }[];
  media: IgMedia[];
  sales: { paid_orders: number; by_market: { market: string; currency: string; paid_orders: number; revenue: number }[]; with_post_evidence: number; without_post: number; rule: string };
  limitations: string[];
};
export const getGrowthInstagram = (from: string | null, to: string | null) => rpc<GrowthInstagram>('f360_growth_instagram', { p_from: from, p_to: to });

import type { ExperimentsList } from '@/lib/growth-p0-labels';
export * from '@/lib/growth-p0-labels';
export const getExperiments = () => rpc<ExperimentsList>('f360_experiments_list');
