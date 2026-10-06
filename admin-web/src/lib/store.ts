// The online store (sales channel) this admin deployment works on — ONE place, set per deployment.
// Default keeps today's behaviour (staging4). The production admin sets NEXT_PUBLIC_F360_STORE_KEY=woo_production at the
// pase (docs/fuxia360/ops/PASE_CHECKLIST.md B7); the environment guard refuses it on a staging deployment.
// Public on purpose: it is a channel key, not a secret, and client screens (Conteo) need it.
export const STORE_KEY = process.env.NEXT_PUBLIC_F360_STORE_KEY || 'woo_staging4';

// Merging old colour products into one product per model (Mario 2026-10-06: on in production too). The database still allows it
// only where the channel's catalog is on; going live takes the old products out of the catalog (URLs keep working).
export const MERGE_ENABLED = true;
