-- Fuxia 360 · pase E12 (2026-10-08) — undo transfer T-000800 (Amsterdam 264 → Bodega CDMX, 9 pairs Paula Café 36–40, "en camino").
-- Mario: "fue un error de Carolina, quítalo". Transfers are never deleted (the ledger keeps every move), so it is undone with the
-- same functions the admin uses, as Mario (owner):
--   1 · f360_receive_transfer with 0 pairs on every line → status 'with_difference' (nothing reaches Bodega CDMX);
--   2 · f360_resolve_transfer_difference 'return' for every line → the 9 pairs go back from "en camino" to Amsterdam 264 and the
--       transfer closes, with the reason recorded.
-- Guards: T-000800 must still be in transit, from Amsterdam 264 to Bodega CDMX, with exactly 9 pairs sent and none received.
-- Fixed idempotency keys: re-running is a no-op. Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);
DO $$
DECLARE t f360.transfers; v_from text; v_to text; v_sent int; v_recv int; v_lines jsonb; v_ret jsonb; r jsonb;
BEGIN
  SELECT * INTO t FROM f360.transfers WHERE number = 'T-000800';
  IF t.id IS NULL THEN RAISE EXCEPTION 'ABORT: T-000800 not found'; END IF;
  SELECT name INTO v_from FROM f360.locations WHERE id = t.from_location_id;
  SELECT name INTO v_to FROM f360.locations WHERE id = t.to_location_id;
  SELECT sum(coalesce(sent_qty, 0)), sum(coalesce(received_qty, 0)) INTO v_sent, v_recv FROM f360.transfer_lines WHERE transfer_id = t.id;
  IF t.status <> 'in_transit' OR v_from <> 'Amsterdam 264' OR v_to <> 'Bodega CDMX' OR v_sent <> 9 OR v_recv <> 0 THEN
    RAISE EXCEPTION 'ABORT: T-000800 is not what was reviewed (status %, % → %, sent %, received %)', t.status, v_from, v_to, v_sent, v_recv;
  END IF;

  SELECT jsonb_agg(jsonb_build_object('variant_id', variant_id, 'quantity', 0)),
         jsonb_agg(jsonb_build_object('variant_id', variant_id, 'quantity', sent_qty, 'action', 'return'))
    INTO v_lines, v_ret FROM f360.transfer_lines WHERE transfer_id = t.id AND coalesce(sent_qty, 0) > 0;

  r := public.f360_receive_transfer('e12a0000-0000-4000-8000-000000000800', t.id, v_lines);
  IF r->>'status' <> 'with_difference' THEN RAISE EXCEPTION 'ABORT: receive gave %', r->>'status'; END IF;
  r := public.f360_resolve_transfer_difference('e12b0000-0000-4000-8000-000000000800', t.id, v_ret,
         'Error de captura (Carolina): la transferencia no era necesaria. Los pares regresan a Amsterdam 264. Mario 2026-10-08.');
  IF r->>'status' <> 'closed' THEN RAISE EXCEPTION 'ABORT: resolve gave %', r->>'status'; END IF;
  RAISE NOTICE 'T-000800 → % (returned %)', r->>'status', r->'totals'->>'returned';
END $$;
COMMIT;
