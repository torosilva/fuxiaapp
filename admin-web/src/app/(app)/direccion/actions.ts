'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { writeCall } from '@/lib/intel';

// Dirección writes (I2). The database re-checks EVERYTHING (board FINANCIAL + second factor, who may approve, required
// reasons, versioning): these actions only pass the form through and return to the page with the database's answer.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const s = (f: FormData, k: string) => String(f.get(k) ?? '').trim();
const amount = (v: string) => { const n = Number(v.replace(/[,\s$]/g, '')); return v !== '' && Number.isFinite(n) ? n : null; };
function back(path: string, r: { ok: boolean; error?: unknown }, okMsg: string, extra = ''): never {
  revalidatePath(path);
  revalidatePath('/direccion');
  const msg = r.ok ? okMsg : String(r.error ?? 'No se pudo.');
  redirect(`${path}?${extra ? `${extra}&` : ''}${r.ok ? 'ok' : 'error'}=${encodeURIComponent(msg)}`);
}

// ── Tipo de cambio ─────────────────────────────────────────────────────────────────────────────────────────────────────
export async function approveRate(f: FormData) {
  const id = s(f, 'id');
  if (!UUID.test(id)) back('/direccion/tipo-de-cambio', { ok: false, error: 'Tasa no válida.' }, '');
  const r = await writeCall('f360_fx_rate_approve', { p_id: id });
  // f360_fx_rate_approve raises 42501 for anyone who is not an fx approver → writeCall answers 'No disponible.'
  back('/direccion/tipo-de-cambio', r.ok === false && r.error === 'No disponible.' ? { ok: false, error: 'Solo quien está autorizado puede aprobar el tipo de cambio.' } : r, 'Tasa aprobada.');
}

// ── Presupuesto ────────────────────────────────────────────────────────────────────────────────────────────────────────
const year = (f: FormData) => { const y = Number(s(f, 'year')); return Number.isInteger(y) && y >= 2024 && y <= 2100 ? y : 2027; };
const P = '/direccion/presupuesto';

export async function draftBudget(f: FormData) {
  const y = year(f);
  const copy = s(f, 'copy_from');
  const r = await writeCall('f360_board_budget_draft', { p_fiscal_year: y, p_name: s(f, 'name'), p_reason: s(f, 'reason'), p_copy_from: UUID.test(copy) ? copy : null });
  back(P, r, 'Borrador creado. Ya puedes llenar los montos.', `anio=${y}${r.ok && typeof r.id === 'string' ? `&version=${r.id}` : ''}`);
}

// Grid → lines. Only cells with a number are sent; the database validates months, markets, channels and amounts.
const COLS = [['MX', 'online'], ['MX', 'store'], ['CO', 'online'], ['ROW', 'online']] as const;
export async function saveBudgetLines(f: FormData) {
  const y = year(f);
  const id = s(f, 'version');
  if (!UUID.test(id)) back(P, { ok: false, error: 'Versión no válida.' }, '', `anio=${y}`);
  const lines: { month: string; market: string; channel: string; amount: number }[] = [];
  for (let m = 1; m <= 12; m++) {
    for (const [market, channel] of COLS) {
      const raw = s(f, `c_${m}_${market}_${channel}`);
      if (raw === '') continue;
      const a = amount(raw);
      if (a === null || a < 0) back(P, { ok: false, error: `Monto no válido en ${m}/${y} (${market} ${channel}).` }, '', `anio=${y}&version=${id}`);
      lines.push({ month: `${y}-${String(m).padStart(2, '0')}-01`, market, channel, amount: a as number });
    }
  }
  const r = await writeCall('f360_board_budget_lines_set', { p_version: id, p_lines: lines });
  back(P, r, `Guardado: ${lines.length} montos.`, `anio=${y}&version=${id}`);
}

export async function validateBudget(f: FormData) {
  const y = year(f);
  const id = s(f, 'version');
  const r = await writeCall('f360_board_budget_validate', { p_version: UUID.test(id) ? id : null, p_note: s(f, 'note') || null });
  back(P, r, 'Validación comercial registrada.', `anio=${y}&version=${id}`);
}

export async function approveBudget(f: FormData) {
  const y = year(f);
  const id = s(f, 'version');
  const r = await writeCall('f360_board_budget_approve', { p_version: UUID.test(id) ? id : null });
  back(P, r, 'Presupuesto aprobado. La versión anterior queda en el historial.', `anio=${y}&version=${id}`);
}

export async function setGoal(f: FormData) {
  const from = s(f, 'from');
  const r = await writeCall('f360_board_goal_set', {
    p_goal_key: s(f, 'key'), p_label: s(f, 'label'), p_market: s(f, 'market'), p_channel: s(f, 'channel'),
    p_amount: amount(s(f, 'amount')), p_effective_from: /^\d{4}-\d{2}$/.test(from) ? `${from}-01` : null, p_reason: s(f, 'reason'),
  });
  back(P, r, 'Nueva versión de la meta guardada.', `anio=${year(f)}`);
}
