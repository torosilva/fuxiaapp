'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { removeUserAction, setModuleAction, setProfileAction } from './actions';

type Sensitive = { pii: boolean; board: boolean; scopes: string[] };
export type AdminUser = {
  auth_user_id: string; display_name: string; role: string; email: string | null; modules: string[]; profile: string;
  locations: { id: string; name: string }[]; sensitive: Sensitive; me: boolean;
};
export type AdminUsers = {
  users: AdminUser[];
  without_role: { auth_user_id: string; email: string; created_at: string }[];
  changes: { at: string; what: string; subject: string; by_name: string; reason: string | null; profile: string | null; module: string | null; on: boolean | null }[];
};

const PROFILES: { key: string; label: string; help: string }[] = [
  { key: 'direccion', label: 'Dirección', help: 'Todo, incluido dar permisos' },
  { key: 'operacion', label: 'Operación', help: 'Productos, precios, inventario, transferencias' },
  { key: 'marketing', label: 'Marketing', help: 'Campañas, contenido, Growth y Fuxia Skills; sin datos de clientas' },
  { key: 'agencia', label: 'Agencia', help: 'Growth y tareas; sin datos de clientas' },
  { key: 'lectura', label: 'Solo lectura', help: 'Ver tableros, sin cambios' },
];
const PROFILE_LABEL: Record<string, string> = { ...Object.fromEntries(PROFILES.map((p) => [p.key, p.label])), vendedora: 'Vendedora' };
const MODULES: { key: string; label: string }[] = [
  { key: 'growth', label: 'Growth' }, { key: 'marketing', label: 'Marketing' }, { key: 'tareas', label: 'Tareas' }, { key: 'skills', label: 'Fuxia Skills' },
];
const SCOPE_LABEL: Record<string, string> = { fx_rate: 'Aprueba tipo de cambio', budget: 'Aprueba presupuesto', close: 'Aprueba cierre', store_discount: 'Aprueba descuentos' };
const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 outline-none focus:border-gold';
const chip = 'rounded-full bg-gold-soft px-2.5 py-1 text-xs text-ink';

export function UsersPanel({ data }: { data: AdminUsers }) {
  const staff = data.users.filter((u) => u.role !== 'seller');
  const sellers = data.users.filter((u) => u.role === 'seller');
  return (
    <>
      <div className="mt-8 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface" data-testid="users">
        {staff.map((u) => <UserRow key={u.auth_user_id} u={u} />)}
      </div>

      {sellers.length > 0 && (
        <p className="mt-4 text-sm text-ink-2">
          {sellers.length === 1 ? 'Hay 1 vendedora' : `Hay ${sellers.length} vendedoras`}; se dan de alta y se cambian en{' '}
          <Link href="/vendedoras" className="underline">Vendedoras</Link> (WhatsApp y PIN).
        </p>
      )}

      <AddUser accounts={data.without_role} />

      <section className="mt-10" data-testid="user-changes">
        <h2 className="font-display text-3xl text-ink">Últimos cambios</h2>
        {data.changes.length === 0 ? <p className="mt-2 text-ink-2">Todavía no hay cambios.</p> : (
          <ul className="mt-3 divide-y divide-line rounded-3xl border border-line bg-surface text-sm">
            {data.changes.map((c, i) => {
              const who = data.users.find((u) => u.auth_user_id === c.subject)?.display_name ?? 'Persona dada de baja';
              const what = c.what === 'profile' ? `perfil → ${PROFILE_LABEL[c.profile ?? ''] ?? c.profile}`
                : c.what === 'module' ? `${c.on ? 'activó' : 'quitó'} ${MODULES.find((m) => m.key === c.module)?.label ?? c.module}`
                : c.what === 'removed' ? 'dio de baja' : 'cambió el rol';
              return (
                <li key={i} className="px-5 py-3">
                  <span className="text-ink">{c.by_name}</span> <span className="text-ink-2">{what} de</span> <span className="text-ink">{who}</span>
                  {c.reason && <span className="text-ink-2"> · “{c.reason}”</span>}
                  <span className="block text-xs text-muted">{new Date(c.at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' })}</span>
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </>
  );
}

function Sensitive({ s }: { s: Sensitive }) {
  const items = [s.pii && 'Datos de clientas', s.board && 'Board', ...s.scopes.map((x) => SCOPE_LABEL[x] ?? x)].filter(Boolean) as string[];
  if (items.length === 0) return null;
  return <div className="mt-2 flex flex-wrap gap-1.5">{items.map((t) => <span key={t} className={chip} title="Se cambia solo con un pase revisado">🔒 {t}</span>)}</div>;
}

function UserRow({ u }: { u: AdminUser }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [profile, setProfile] = useState(u.profile);
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<{ ok: true } | { ok: false; error: string }>, done: string) => start(async () => {
    const r = await fn();
    setMsg(r.ok ? { ok: true, text: done } : { ok: false, text: r.error });
    if (r.ok) { setReason(''); router.refresh(); }
  });
  const viewer = u.role === 'viewer';
  return (
    <div className="px-5 py-4" data-testid={`user-${u.auth_user_id}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-lg text-ink">{u.display_name}{u.me && <span className="ml-2 text-sm text-muted">(tú)</span>}</p>
          <p className="text-sm text-ink-2">{PROFILE_LABEL[u.profile] ?? u.profile}{u.email ? ` · ${u.email}` : ''}</p>
          {viewer && u.modules.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1.5">{u.modules.map((m) => <span key={m} className="rounded-full border border-line px-2.5 py-1 text-xs text-ink-2">{MODULES.find((x) => x.key === m)?.label ?? m}</span>)}</div>
          )}
          <Sensitive s={u.sensitive} />
        </div>
        <button type="button" onClick={() => { setOpen(!open); setMsg(null); }} className="rounded-full border border-line px-4 py-2 text-sm text-ink">
          {open ? 'Cerrar' : 'Editar'}
        </button>
      </div>

      {open && (
        <div className="mt-4 rounded-2xl border border-line bg-bg p-4">
          <p className="text-sm text-ink-2">Perfil</p>
          <div className="mt-2 flex flex-wrap gap-2">
            {PROFILES.map((p) => (
              <button key={p.key} type="button" title={p.help} disabled={u.me && p.key !== 'direccion'} onClick={() => setProfile(p.key)}
                className={`rounded-full px-4 py-2 text-sm disabled:opacity-40 ${profile === p.key ? 'bg-ink text-surface' : 'border border-line text-ink'}`}>{p.label}</button>
            ))}
          </div>
          <p className="mt-1 text-xs text-muted">{PROFILES.find((p) => p.key === profile)?.help}</p>

          {viewer && profile === u.profile && (
            <>
              <p className="mt-4 text-sm text-ink-2">Módulos</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {MODULES.map((m) => {
                  const on = u.modules.includes(m.key);
                  return (
                    <button key={m.key} type="button" disabled={pending || reason.trim().length < 5}
                      onClick={() => run(() => setModuleAction({ userId: u.auth_user_id, module: m.key, on: !on, reason }), `${m.label} ${on ? 'quitado' : 'activado'}.`)}
                      className={`rounded-full px-4 py-2 text-sm disabled:opacity-40 ${on ? 'bg-gold text-ink' : 'border border-line text-ink'}`}>{on ? '✓ ' : ''}{m.label}</button>
                  );
                })}
              </div>
            </>
          )}

          <label className="mt-4 block text-sm text-ink-2">Motivo del cambio (obligatorio, queda en la bitácora)
            <input aria-label="Motivo del cambio" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} className={input} />
          </label>
          {msg && <p className={`mt-3 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
          <div className="mt-4 flex flex-wrap gap-2">
            <button type="button" disabled={pending || profile === u.profile || reason.trim().length < 5}
              onClick={() => run(() => setProfileAction({ userId: u.auth_user_id, profile, name: u.display_name, reason }), 'Perfil actualizado.')}
              className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar perfil'}</button>
            {!u.me && (
              <button type="button" disabled={pending || reason.trim().length < 5}
                onClick={() => run(() => removeUserAction({ userId: u.auth_user_id, reason }), 'Acceso quitado.')}
                className="rounded-full border border-danger px-5 py-2.5 text-sm text-danger disabled:opacity-40">Dar de baja</button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function AddUser({ accounts }: { accounts: AdminUsers['without_role'] }) {
  const router = useRouter();
  const [f, setF] = useState({ userId: accounts[0]?.auth_user_id ?? '', name: '', profile: 'agencia', reason: '' });
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const add = () => start(async () => {
    const r = await setProfileAction(f);
    setMsg(r.ok ? { ok: true, text: `${f.name} ya tiene acceso como ${PROFILE_LABEL[f.profile]}.` } : { ok: false, text: r.error });
    if (r.ok) { setF({ ...f, name: '', reason: '' }); router.refresh(); }
  });
  return (
    <section className="mt-10 rounded-3xl border border-line bg-surface p-5" data-testid="add-user">
      <h2 className="font-display text-3xl text-ink">Dar acceso a alguien</h2>
      {accounts.length === 0 ? (
        <p className="mt-2 text-sm text-ink-2">
          La persona primero entra una vez a Fuxia 360 con su correo. Después aparece aquí para darle su perfil.
        </p>
      ) : (
        <>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <label className="text-sm text-ink-2">Cuenta
              <select aria-label="Cuenta" value={f.userId} onChange={(e) => setF({ ...f, userId: e.target.value })} className={input}>
                {accounts.map((a) => <option key={a.auth_user_id} value={a.auth_user_id}>{a.email}</option>)}
              </select></label>
            <label className="text-sm text-ink-2">Nombre<input aria-label="Nombre" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} className={input} /></label>
            <label className="text-sm text-ink-2">Perfil
              <select aria-label="Perfil" value={f.profile} onChange={(e) => setF({ ...f, profile: e.target.value })} className={input}>
                {PROFILES.map((p) => <option key={p.key} value={p.key}>{p.label}</option>)}
              </select></label>
            <label className="text-sm text-ink-2">Motivo<input aria-label="Motivo del alta" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} maxLength={300} className={input} /></label>
          </div>
          {msg && <p className={`mt-3 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
          <button type="button" disabled={pending || !f.userId || !f.name.trim() || f.reason.trim().length < 5} onClick={add}
            className="mt-4 rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Dar acceso'}</button>
        </>
      )}
    </section>
  );
}
