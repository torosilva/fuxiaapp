'use client';
import { useEffect, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { IconCheck, IconClock, IconX } from '@/components/icons';
import type { Publication, PubJob, PubStep } from '@/lib/f360';
import { fecha } from '@/lib/format';
import { publishAction, setStoreVisibilityAction } from '../../actions';

const STEP_LABEL: Record<string, string> = {
  preflight: 'Revisión', terms: 'Colores y tallas', media: 'Fotos', product: 'Producto', variations: 'Variaciones', stock: 'Existencias', verify: 'Verificación',
};
const JOB_LABEL: Record<PubJob['status'], string> = {
  queued: 'En cola', running: 'Publicando…', succeeded: 'Publicado', partial: 'Incompleto', failed: 'No se pudo publicar',
};

// "Tienda en línea": one button, honest states, retry that never duplicates, and the full history.
export function PublishPanel({ productId, pub, isOwner, publisherReady }: { productId: string; pub: Publication; isOwner: boolean; publisherReady: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // One key per intent: a double click or a network retry of the SAME click reuses it (the database dedupes).
  const [key, setKey] = useState(() => crypto.randomUUID());

  const run = () => start(async () => {
    setError(null); setConfirming(false);
    const r = await publishAction(productId, key);
    setKey(crypto.randomUUID());
    if (!r.ok) setError(r.error);
    router.refresh();
  });

  const [liveConfirm, setLiveConfirm] = useState(false);
  const live = pub.woo_status === 'publish';
  const setVisibility = (status: 'publish' | 'draft') => start(async () => {
    setError(null); setLiveConfirm(false);
    const r = await setStoreVisibilityAction(productId, status);
    if (!r.ok) setError(r.error);
    router.refresh();
  });

  const busy = pending || pub.state === 'publicando';
  const last = pub.jobs[0];
  const inStore = !!pub.woo_product_id;
  // a change waiting in the queue counts as "updating": the store updates by itself (no button)
  const waiting = pub.jobs.some((j) => j.status === 'queued' || j.status === 'running');
  const updating = busy || (inStore && waiting);
  useEffect(() => {   // while the store is updating, refresh the page every few seconds until it says "al día"
    if (!inStore || !updating) return;
    const t = setInterval(() => router.refresh(), 5000);
    return () => clearInterval(t);
  }, [inStore, updating, router]);

  // ── Models already in the store: one honest status, no buttons for routine work (Mario 2026-10-07) ──
  if (inStore && publisherReady) {
    const failed = !updating && pub.state === 'error';
    const pendingByHand = !updating && pub.state === 'cambios';   // the automatic sync could not start (e.g. not an owner)
    return (
      <section id="tienda" className="mt-12 scroll-mt-6">
        <h2 className="font-display text-3xl text-ink">Tienda en línea</h2>
        <div className={`mt-4 rounded-3xl border p-5 md:p-6 ${failed ? 'border-danger/30 bg-danger-soft' : updating || pendingByHand ? 'border-gold/40 bg-gold-soft' : 'border-success/30 bg-success-soft'}`}
          data-testid="publish-panel" data-state={updating ? 'publicando' : pub.state}>
          {updating ? (
            <p className="flex items-center gap-2 text-lg text-ink"><IconClock className="size-5 animate-pulse" />Actualizando la tienda… se hace solo, puedes seguir trabajando o cerrar la página.</p>
          ) : failed ? (
            <div className="text-danger">
              <p className="flex items-center gap-2 text-lg"><IconX />No se pudo actualizar la tienda</p>
              <p className="mt-1 text-sm" data-testid="publish-error">{last?.error_message ?? 'Error de sincronización.'}</p>
            </div>
          ) : pendingByHand ? (
            <p className="text-ink">Hay cambios que todavía no están en la tienda.</p>
          ) : (
            <p className="flex items-center gap-2 text-lg text-success"><IconCheck />En la tienda · al día · {live ? <strong>visible para las clientas</strong> : 'oculto (borrador)'}</p>
          )}
          {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
          {isOwner && !updating && (failed || pendingByHand) && (
            <button type="button" onClick={run} className="mt-4 rounded-2xl bg-ink px-6 py-3.5 text-surface">{failed ? 'Reintentar' : 'Subir a la tienda'}</button>
          )}
          {isOwner && !updating && !live && (
            liveConfirm ? (
              <div className="mt-4 rounded-2xl border border-gold/40 bg-surface p-4" data-testid="go-live-confirm">
                <p className="text-ink">Se va a <strong>mostrar a las clientas</strong> en {pub.target?.name ?? 'la tienda'}.</p>
                <div className="mt-3 flex gap-3">
                  <button type="button" onClick={() => setVisibility('publish')} className="rounded-2xl bg-ink px-6 py-3.5 text-surface">Sí, publicar en vivo</button>
                  <button type="button" onClick={() => setLiveConfirm(false)} className="rounded-2xl px-4 text-muted">Cancelar</button>
                </div>
              </div>
            ) : <button type="button" onClick={() => setLiveConfirm(true)} className="mt-4 rounded-2xl bg-success px-6 py-3.5 text-surface" data-testid="go-live">Publicar en vivo</button>
          )}
        </div>
        <details className="mt-4 rounded-2xl border border-line bg-surface p-4 text-sm text-ink-2" data-testid="store-more">
          <summary className="cursor-pointer text-ink-2">Más opciones de la tienda</summary>
          {isOwner && live && !updating && (
            <button type="button" onClick={() => setVisibility('draft')} className="mt-3 rounded-2xl border border-line bg-surface px-5 py-3 text-ink" data-testid="hide-from-store">Ocultar de la tienda</button>
          )}
          {pub.target && <p className="mt-3">Tienda: {pub.target.name} · producto #{pub.woo_product_id}
            {' · '}<a className="text-gold-strong hover:underline" target="_blank" rel="noreferrer" href={`${pub.target.base_url}/wp-admin/post.php?post=${pub.woo_product_id}&action=edit`}>Abrir en WooCommerce</a></p>}
          {pub.jobs.length > 0 && <History jobs={pub.jobs} />}
        </details>
      </section>
    );
  }
  const firstTime = !pub.woo_product_id;
  const label = pub.state === 'error' ? 'Reintentar' : pub.state === 'cambios' ? 'Sincronizar cambios' : firstTime ? 'Publicar como borrador' : 'Sincronizar de nuevo';

  const box = {
    borrador: 'border-line bg-surface',
    listo: 'border-line bg-surface',
    publicando: 'border-gold/40 bg-gold-soft',
    publicado: 'border-success/30 bg-success-soft',
    cambios: 'border-gold/40 bg-gold-soft',
    error: 'border-danger/30 bg-danger-soft',
    sin_tienda: 'border-line bg-surface',
  }[busy ? 'publicando' : pub.state];

  return (
    <section id="tienda" className="mt-12 scroll-mt-6">
      <h2 className="font-display text-3xl text-ink">Tienda en línea</h2>
      <div className={`mt-4 rounded-3xl border p-5 md:p-6 ${box}`} data-testid="publish-panel" data-state={busy ? 'publicando' : pub.state}>
        {busy ? (
          <p className="flex items-center gap-2 text-lg text-ink"><IconClock className="size-5 animate-pulse" />Publicando en {pub.target?.name ?? 'la tienda'}… esto tarda unos segundos.</p>
        ) : pub.state === 'sin_tienda' ? (
          <p className="text-ink-2">{pub.message ?? 'No hay una tienda en línea configurada.'}</p>
        ) : pub.state === 'borrador' ? (
          <p className="text-ink-2">Completa lo que falta (arriba) para poder publicarlo.</p>
        ) : pub.state === 'listo' ? (
          <p className="text-ink">Listo para publicar. Se crea <strong>oculto</strong>: nadie lo ve en la tienda hasta que decidas mostrarlo.</p>
        ) : pub.state === 'publicado' ? (
          <div className="text-success">
            <p className="flex items-center gap-2 text-lg"><IconCheck />Publicado en {pub.target?.name ?? "la tienda"}, {live ? <strong>EN VIVO (lo ven las clientas)</strong> : 'oculto (borrador)'} — {pub.variations_linked} variaciones</p>
            {last && <p className="mt-1 text-sm">Última sincronización: {last.requested_by_name}, {fecha(last.finished_at ?? last.created_at)}. Todo coincide con Fuxia 360.</p>}
          </div>
        ) : pub.state === 'cambios' ? (
          <p className="text-ink">Cambiaste el producto después de publicarlo. <strong>Sincroniza</strong> para que la tienda quede igual.</p>
        ) : (
          <div className="text-danger">
            <p className="flex items-center gap-2 text-lg"><IconX />No se pudo publicar</p>
            <p className="mt-1 text-sm" data-testid="publish-error">{last?.error_message ?? 'Error de sincronización.'}</p>
            <p className="mt-1 text-sm text-ink-2">Reintentar es seguro: continúa donde se quedó y nunca duplica productos ni variaciones.</p>
          </div>
        )}

        {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}

        {!publisherReady && pub.state !== 'borrador' && (
          <div className="mt-4 rounded-2xl border border-line bg-surface p-4 text-ink-2" data-testid="publish-unavailable">
            <p className="font-medium text-ink">Publicación WooCommerce disponible próximamente en este ambiente.</p>
            <p className="mt-1 text-sm">El flujo ya está validado contra WooCommerce local y se habilitará aquí cuando conectemos la tienda de pruebas.</p>
          </div>
        )}

        {publisherReady && isOwner && pub.can_publish && !busy && pub.state !== 'borrador' && pub.state !== 'sin_tienda' && (
          confirming ? (
            <div className="mt-4 rounded-2xl border border-line bg-surface p-4">
              <p className="text-ink">Se creará <strong>1 producto oculto</strong> con todos sus colores y tallas, fotos, precio y existencias de {pub.target?.name ?? 'la tienda'}.</p>
              <div className="mt-3 flex gap-3">
                <button type="button" onClick={run} className="rounded-2xl bg-ink px-6 py-3.5 text-surface">Sí, publicar como borrador</button>
                <button type="button" onClick={() => setConfirming(false)} className="rounded-2xl px-4 text-muted">Cancelar</button>
              </div>
            </div>
          ) : (
            <button type="button" onClick={() => (firstTime && pub.state === 'listo' ? setConfirming(true) : run())}
              className={`mt-4 rounded-2xl px-6 py-3.5 ${pub.state === 'publicado' ? 'border border-line bg-surface text-ink' : 'bg-ink text-surface'}`}>{label}</button>
          )
        )}
        {publisherReady && isOwner && pub.woo_product_id && !busy && pub.state !== 'publicando' && (
          live ? (
            <button type="button" onClick={() => setVisibility('draft')} className="mt-4 ml-3 rounded-2xl border border-line bg-surface px-6 py-3.5 text-ink" data-testid="hide-from-store">Ocultar de la tienda</button>
          ) : liveConfirm ? (
            <div className="mt-4 rounded-2xl border border-gold/40 bg-gold-soft p-4" data-testid="go-live-confirm">
              <p className="text-ink">Se va a <strong>mostrar a las clientas</strong> en {pub.target?.name ?? 'la tienda'}.</p>
              {!!pub.legacy_products && <p className="mt-2 text-danger">Ojo: este modelo todavía tiene <strong>{pub.legacy_products} producto{pub.legacy_products > 1 ? 's' : ''} viejo{pub.legacy_products > 1 ? 's' : ''} visible{pub.legacy_products > 1 ? 's' : ''}</strong> en la tienda. Si lo publicas en vivo se verán los dos hasta hacer la unión (redirecciones).</p>}
              <div className="mt-3 flex gap-3">
                <button type="button" onClick={() => setVisibility('publish')} className="rounded-2xl bg-ink px-6 py-3.5 text-surface">Sí, publicar en vivo</button>
                <button type="button" onClick={() => setLiveConfirm(false)} className="rounded-2xl px-4 text-muted">Cancelar</button>
              </div>
            </div>
          ) : (
            <button type="button" onClick={() => setLiveConfirm(true)} className="mt-4 ml-3 rounded-2xl bg-success px-6 py-3.5 text-surface" data-testid="go-live">Publicar en vivo</button>
          )
        )}
        {publisherReady && !isOwner && pub.state !== 'sin_tienda' && <p className="mt-3 text-sm text-muted">Solo una dueña puede publicar en la tienda.</p>}

        {pub.woo_product_id && (
          <details className="mt-4 text-sm text-ink-2">
            <summary className="cursor-pointer">Detalle técnico</summary>
            <p className="mt-2">Tienda: {pub.target?.name} · producto #{pub.woo_product_id} ({pub.woo_status === 'draft' ? 'borrador, no visible' : pub.woo_status})</p>
            {pub.target && publisherReady && <a className="mt-1 inline-block text-gold-strong hover:underline" target="_blank" rel="noreferrer" href={`${pub.target.base_url}/wp-admin/post.php?post=${pub.woo_product_id}&action=edit`}>Abrir en WooCommerce</a>}
          </details>
        )}
      </div>

      {pub.jobs.length > 0 && <div className="mt-6"><History jobs={pub.jobs} /></div>}
    </section>
  );
}

function History({ jobs }: { jobs: PubJob[] }) {
  return (
    <div className="mt-4">
      <h3 className="text-base text-ink">Historial de publicación</h3>
      <ul className="mt-3 space-y-2" data-testid="publish-history">
        {jobs.map((j, i) => (
          <li key={j.id} className="rounded-2xl border border-line bg-surface p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-ink"><JobDot status={j.status} />{JOB_LABEL[j.status]} · {j.requested_by_name}</p>
              <p className="text-sm text-muted">{fecha(j.finished_at ?? j.created_at)}</p>
            </div>
            {j.summary && j.status !== 'failed' && (
              <p className="mt-1 text-sm text-ink-2">{j.summary.variations} variaciones · {j.summary.created} creadas · {j.summary.updated} actualizadas · existencias enviadas: {j.summary.stock_pushed}</p>
            )}
            {j.error_message && <p className="mt-1 text-sm text-danger">{j.error_message}</p>}
            {i === 0 && j.steps && j.steps.length > 0 && (
              <details className="mt-2">
                <summary className="cursor-pointer text-sm text-gold-strong">Ver los {j.steps.length} pasos</summary>
                <ol className="mt-2 space-y-1 text-sm">
                  {j.steps.map((s, k) => <StepRow key={k} s={s} />)}
                </ol>
              </details>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

function JobDot({ status }: { status: PubJob['status'] }) {
  const c = status === 'succeeded' ? 'bg-success' : status === 'failed' || status === 'partial' ? 'bg-danger' : 'bg-gold';
  return <span className={`mr-2 inline-block size-2.5 rounded-full align-middle ${c}`} />;
}

function StepRow({ s }: { s: PubStep }) {
  return (
    <li className={`flex gap-2 ${s.ok ? 'text-ink-2' : 'text-danger'}`}>
      <span className="w-28 shrink-0 text-muted">{STEP_LABEL[s.step] ?? s.step}</span>
      <span className="font-mono text-xs leading-5">{s.object_ref ?? ''}</span>
      <span>{s.action}{s.woo_id ? ` #${s.woo_id}` : ''}{s.message ? ` — ${s.message}` : ''}</span>
    </li>
  );
}
