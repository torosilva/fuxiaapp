-- Fuxia 360 · pase D6 (2026-10-08) — Mercado Pago payments confirmed within 5 minutes, with or without visitors.
-- The store only learns that a card payment was approved through the Mercado Pago plugin's own check of pending orders
-- (its instant notice never reaches the store); that check is WordPress cron, which only runs when someone visits the site.
-- Test purchase #5351 (Mario): approved 08:14, store confirmed 08:18. SiteGround has no crontab over SSH, so Fuxia 360's
-- scheduler (pg_cron + pg_net) wakes the store's cron every 5 minutes. Read-only for the database; one GET to the store.
-- Rollback: SELECT cron.unschedule('f360-tienda-wp-cron');
BEGIN;
SELECT cron.schedule('f360-tienda-wp-cron', '*/5 * * * *',
  $$SELECT net.http_get('https://fuxiaballerinas.com/wp-cron.php?doing_wp_cron', timeout_milliseconds := 20000)$$);
SELECT jsonb_build_object('job', (SELECT jsonb_build_object('name', jobname, 'schedule', schedule) FROM cron.job WHERE jobname = 'f360-tienda-wp-cron'));
COMMIT;
