'use client';
import { useState, useTransition } from 'react';
import { spendRowsFromCsv, type ParseResult } from '@/lib/spend-csv';
import { uploadSpendAction } from './medicion-actions';

// S-G0 · D3 fallback: owner uploads an Ads Manager / template CSV. Preview first (rows, dates, spend per currency); the
// database validates again and rejects the whole file on any error. Nothing is filled in silently.
const field = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2 text-base outline-none focus:border-gold';

export function SpendUpload() {
  const [platform, setPlatform] = useState('meta');
  const [account, setAccount] = useState('');
  const [currency, setCurrency] = useState('');
  const [market, setMarket] = useState('');
  const [file, setFile] = useState<{ name: string; text: string } | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const parsed: ParseResult | null = file ? spendRowsFromCsv(file.text, { platform, account_id: account || undefined, currency: currency || undefined, market: market || undefined }) : null;

  return (
    <div className="mt-8 rounded-2xl border border-line bg-surface p-5" data-testid="spend-upload">
      <p className="text-lg text-ink">Subir gasto (CSV)</p>
      <p className="mt-1 text-sm text-ink-2">Una fila por día y anuncio. Un día sin fila = desconocido (no 0): si un día no hubo gasto, inclúyelo con 0. Queda registrado quién lo subió.</p>
      <div className="mt-3 grid gap-3 md:grid-cols-4">
        <label className="text-sm text-muted">Plataforma
          <select className={field} value={platform} onChange={(e) => setPlatform(e.target.value)}>
            <option value="meta">Meta</option><option value="google">Google</option><option value="tiktok">TikTok</option><option value="other">Otra</option>
          </select></label>
        <label className="text-sm text-muted">Cuenta (si el archivo no la trae)<input className={field} value={account} onChange={(e) => setAccount(e.target.value.trim())} placeholder="act_123…" /></label>
        <label className="text-sm text-muted">Moneda (si el archivo no la trae)<input className={field} value={currency} onChange={(e) => setCurrency(e.target.value.trim().toUpperCase())} placeholder="MXN" /></label>
        <label className="text-sm text-muted">Mercado (si el archivo no lo trae)
          <select className={field} value={market} onChange={(e) => setMarket(e.target.value)}>
            <option value="">—</option><option value="MX">MX</option><option value="CO">CO</option><option value="ROW">ROW</option><option value="UNKNOWN">Sin mercado</option>
          </select></label>
      </div>
      <input type="file" accept=".csv,text/csv" className="mt-3 text-sm" onChange={async (e) => {
        const f = e.target.files?.[0]; setMsg(null);
        setFile(f ? { name: f.name, text: await f.text() } : null);
      }} />
      {parsed ? (
        <div className="mt-3 text-sm text-ink">
          <p>{parsed.rows.length} filas · {parsed.summary.from ?? '—'} → {parsed.summary.to ?? '—'} · {Object.entries(parsed.summary.spend).map(([c, v]) => `${c} ${v.toLocaleString('es-MX')}`).join(' · ') || 'sin gasto legible'}</p>
          {parsed.errors.length ? <ul className="mt-1 list-disc pl-5 text-danger">{parsed.errors.map((x) => <li key={x}>{x}</li>)}</ul> : null}
          <button type="button" disabled={pending || parsed.errors.length > 0 || parsed.rows.length === 0}
            className="mt-3 rounded-full bg-ink px-5 py-2 text-surface disabled:opacity-40"
            onClick={() => start(async () => {
              const r = await uploadSpendAction(platform, file!.name, parsed.rows);
              setMsg(r.ok ? (r.result === 'duplicate' ? 'Este archivo ya estaba cargado: no se duplicó.' : `Cargado: ${r.rows} filas.`)
                : `${r.error}${r.errors?.length ? ' ' + r.errors.slice(0, 5).map((x) => `${x.row ? `Fila ${x.row}: ` : ''}${x.error}`).join(' · ') : ''}`);
            })}>{pending ? 'Subiendo…' : 'Subir gasto'}</button>
        </div>
      ) : null}
      {msg ? <p className="mt-2 text-sm text-ink" data-testid="spend-upload-result">{msg}</p> : null}
    </div>
  );
}
