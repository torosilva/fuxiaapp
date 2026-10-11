import { createClient } from '@/lib/supabase/server';

// Fuxia Academy (Sales, A1). Every call goes to a public.f360_academy_* RPC that decides with auth.uid() in the database:
// learner access (tester grant in A1; real sellers BLOCKED while P0-6 is open), editor, content approver (shared approval registry).
// A denied call answers {ok:false} with no data; pages answer notFound() or a neutral message.
// A1 is STAGING ONLY: the production admin deploy ships the whole branch, so this module refuses to render outside staging.
export const academyEnabled = () => process.env.NEXT_PUBLIC_F360_ENV === 'staging';

export type AcademyMe = { ok: true; sales: 'ok' | 'bloqueado' | 'none'; editor: boolean; approver: boolean; admin: boolean; aal: string; name: string;
  gates: { learner_access_enabled: boolean; certificates_enabled: boolean; points_enabled: boolean; redemptions_enabled: boolean; note: string } };
export type Block = { type: 'texto' | 'ficha' | 'ficha_talla' | 'pendiente' | 'politica'; text?: string; source?: string; code?: string };
export type Knowledge = { version: number; validated_at: string; fit?: { label?: string; advice?: string; between_sizes?: string; note?: string };
  last?: string; width?: string; toe?: string; heel_height_cm?: number; materials?: { upper?: string; lining?: string; sole?: string }; comfort?: string; care?: string };
export type ProductCard = { code: string; name: string; photo: string | null; sizes: string[] | null; colors: { name: string; photo: string | null }[] | null; knowledge: Knowledge } | null;
export type Lesson = { id: string; key: string; position: number; title: string; minutes: number; blocks: Block[]; products: Record<string, ProductCard> };
export type PracticeItem = { id: string; key: string; kind: 'opcion' | 'vf' | 'varias' | 'ordenar'; area: string; prompt: string; options: { id: string; text: string }[] };
export type HomeCourse = { id: string; key: string; title: string; summary: string | null; version: number; enrolled: boolean;
  lessons: { id: string; key: string; title: string; minutes: number; cards: number; status: 'pendiente' | 'en_curso' | 'completada'; card_index: number }[] };
export type LessonView = { ok: true; course: { id: string; title: string }; lesson: Lesson; progress: { card_index: number; status: string }; practice: PracticeItem[]; next: string | null };
export type Denied = { ok: false; error: string };

async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T | Denied> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error || !data) return { ok: false, error: 'No disponible.' };
  return data as T | Denied;
}
export const academyMe = () => rpc<AcademyMe>('f360_academy_me');
export const academyHome = () => rpc<{ ok: true; courses: HomeCourse[] }>('f360_academy_home');
export const academyLesson = (id: string) => rpc<LessonView>('f360_academy_lesson', { p_lesson: id });
export const academyFichas = () => rpc<{ ok: true; fichas: NonNullable<ProductCard>[] }>('f360_academy_fichas');
export const academyOverview = () => rpc<{ ok: true; me: AcademyMe; courses: AdminCourse[]; events: AdminEvent[] }>('f360_academy_admin_overview');
export const academyVersion = (id: string) => rpc<AdminVersion>('f360_academy_admin_version', { p_version: id });
export const academyTeam = () => rpc<{ ok: true; learners: TeamRow[] }>('f360_academy_team');

export type AdminCourse = { id: string; key: string; title: string; school: 'sales' | 'executive'; kind: string; published_version_id: string | null;
  versions: { id: string; version: number; status: string; title: string; lessons: number; items: number; comments: number; stale_products: string[] | null;
    request: { id: string; status: string; operation: string; requested_by: string; requested_at: string; expires_at: string; decided_by: string | null; self_approval: boolean } | null }[] | null };
export type AdminEvent = { at: string; action: string; by: string; reason: string | null; self: boolean; aal: string; operation: string; version: number };
export type AdminItem = { id: string; key: string; lesson_key: string | null; uses: string[]; area: string; kind: string; prompt: string; options: { id: string; text: string }[];
  answer: Record<string, unknown>; explanation: string; source: string; product_code: string | null; status: 'ok' | 'bloqueada' };
export type AdminVersion = { ok: true; version: { id: string; version: number; status: string; title: string; summary: string | null; course: { id: string; key: string; school: string };
    hash: string | null; current_hash: string };
  lessons: Lesson[]; items: AdminItem[]; comments: { lesson: string | null; item: string | null; block: number | null; body: string; by: string; at: string }[];
  request: { id: string; status: string; operation: string; requested_by: string; reason: string; requested_at: string; expires_at: string; hash: string;
    events: { action: string; by: string; reason: string | null; at: string; aal: string; self: boolean }[] } | null;
  can_edit: boolean; can_decide: boolean };
export type TeamRow = { name: string; store: string | null; course: string; version: number; enrolled_at: string; completed_at: string | null;
  lessons_total: number; lessons_done: number; practice: { answered: number; correct: number }; tester: boolean };

export const STATUS: Record<string, string> = { borrador: 'Borrador', en_revision: 'En revisión de Carolina', publicado: 'Publicado', retirado: 'Retirado' };
