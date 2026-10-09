import { createClient } from '@/lib/supabase/server';

// Pendientes de la semana (Q4 board). Read through its own RPCs; never redirects by itself, so it also works for the agency,
// which has NO Fuxia 360 role (every other RPC refuses it).
export type WeeklyMe = { ok: boolean; person_key?: 'AGENCIA' | 'CAROLINA' | 'MARIO' | null; name?: string | null; team?: boolean; can_edit_metrics?: boolean };
export type WeeklyCard = {
  person_key: 'AGENCIA' | 'CAROLINA' | 'MARIO'; name: string; role_line: string; mine: boolean;
  commitment: string | null; done: string | null; numbers: Record<string, number | null>; status: 'si' | 'parcial' | 'no' | null;
  updated_by: string | null; updated_at: string | null;
};
export type WeeklyBoard = {
  me: { person_key: WeeklyCard['person_key'] | null; team: boolean; can_edit_metrics: boolean };
  goal: { target: number; online_pairs: number; plan_to_date: number; weeks_left: number };
  weeks: { id: string; label: string; current: boolean; filled: boolean }[];
  week: { id: string; label: string; title: string; focus: string; target_pairs: number; in_goal: boolean; online: { site: number; dm: number; total: number } };
  cards: WeeklyCard[];
  metrics: { values: Record<string, number | null>; decision: string | null; updated_by: string; updated_at: string } | null;
};

export async function weeklyMe(): Promise<WeeklyMe> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_weekly_me');
  if (error || !data) return { ok: false };
  return data as WeeklyMe;
}

export async function weeklyBoard(week?: string): Promise<WeeklyBoard | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_weekly_board', { p_week: week ?? null });
  if (error) return null;
  return data as WeeklyBoard;
}
