-- Fuxia 360 · S0.2 fix — denials must be AUDITED. In 20261001000100 a denied shift start RAISEd, which rolled back
-- its own audit row. Denials (not seller, not assigned, no PIN, locked) now RETURN {ok:false} so the audit commits,
-- and the session check records rejections (location mismatch, expired, access removed). Same signatures and grants.
-- Rollback: re-apply the definitions from 20261001000100 (or roll back S0.2 entirely).

CREATE OR REPLACE FUNCTION public.f360_start_seller_shift(p_location_id uuid, p_pin text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); r f360.user_roles; c f360.seller_credentials; l f360.locations; prm jsonb := f360.seller_params();
  fails24 int; token text; sess f360.seller_sessions;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Inicia sesión con tu cuenta para iniciar turno.' USING ERRCODE = 'insufficient_privilege'; END IF;
  SELECT * INTO r FROM f360.user_roles WHERE auth_user_id = uid;
  IF r.role IS NULL OR r.role NOT IN ('seller', 'operator', 'owner') THEN
    PERFORM f360.log_seller(uid, p_location_id, 'not_seller', NULL);
    RETURN jsonb_build_object('ok', false, 'error', 'Esta cuenta no puede iniciar turno de venta.');
  END IF;
  SELECT * INTO l FROM f360.locations WHERE id = p_location_id AND status = 'active' AND sellable;
  IF l.id IS NULL OR (r.role = 'seller' AND NOT EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = uid AND a.location_id = p_location_id AND a.active)) THEN
    PERFORM f360.log_seller(uid, p_location_id, 'not_assigned', NULL);   -- checked BEFORE the PIN: no attempt consumed, nothing learned
    RETURN jsonb_build_object('ok', false, 'error', 'No tienes asignada esa ubicación.');
  END IF;
  SELECT * INTO c FROM f360.seller_credentials WHERE auth_user_id = uid FOR UPDATE;
  IF c.auth_user_id IS NULL THEN
    PERFORM f360.log_seller(uid, p_location_id, 'no_pin', NULL);
    RETURN jsonb_build_object('ok', false, 'error', 'Todavía no tienes PIN. Pídele a Carolina o Mario que te lo asignen.');
  END IF;
  IF c.hard_locked OR (c.locked_until IS NOT NULL AND c.locked_until > now()) THEN
    PERFORM f360.log_seller(uid, p_location_id, 'blocked_locked', jsonb_build_object('until', c.locked_until, 'hard', c.hard_locked));
    RETURN jsonb_build_object('ok', false, 'locked', true, 'error', CASE WHEN c.hard_locked THEN 'Tu PIN está bloqueado. Pide que lo desbloqueen.'
      ELSE format('Demasiados intentos. Intenta de nuevo en %s minutos.', ceil(extract(epoch FROM c.locked_until - now()) / 60)) END);
  END IF;
  IF p_pin IS NULL OR extensions.crypt(p_pin, c.pin_hash) <> c.pin_hash THEN
    SELECT count(*) + 1 INTO fails24 FROM f360.seller_auth_events WHERE auth_user_id = uid AND event = 'bad_pin' AND at > now() - interval '24 hours';
    UPDATE f360.seller_credentials SET failed_attempts = failed_attempts + 1,
      locked_until = CASE WHEN failed_attempts + 1 >= (prm->>'max_consecutive_failures')::int THEN now() + make_interval(mins => (prm->>'lock_minutes')::int) ELSE locked_until END,
      hard_locked = fails24 >= (prm->>'hard_lock_failures_24h')::int
      WHERE auth_user_id = uid RETURNING * INTO c;
    PERFORM f360.log_seller(uid, p_location_id, 'bad_pin', jsonb_build_object('consecutive', c.failed_attempts, 'last_24h', fails24));
    IF c.hard_locked THEN PERFORM f360.log_seller(uid, p_location_id, 'hard_locked', NULL);
    ELSIF c.locked_until > now() THEN PERFORM f360.log_seller(uid, p_location_id, 'locked', jsonb_build_object('until', c.locked_until)); END IF;
    -- COMMIT the counters and the audit (RETURN, don't RAISE: a RAISE would roll them back)
    RETURN jsonb_build_object('ok', false, 'error', CASE WHEN c.hard_locked THEN 'Tu PIN quedó bloqueado. Pide que lo desbloqueen.'
      WHEN c.locked_until > now() THEN format('PIN incorrecto. Bloqueado por %s minutos.', prm->>'lock_minutes')
      ELSE format('PIN incorrecto. Te quedan %s intentos.', (prm->>'max_consecutive_failures')::int - c.failed_attempts) END);
  END IF;
  UPDATE f360.seller_credentials SET failed_attempts = 0, locked_until = NULL WHERE auth_user_id = uid;
  -- one active shift per person: changing location = closing the previous shift (recommended behavior)
  PERFORM f360.revoke_seller_sessions(uid, NULL, 'nuevo turno');
  token := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO f360.seller_sessions (auth_user_id, location_id, token_hash, expires_at)
    VALUES (uid, l.id, f360.token_hash(token), now() + make_interval(hours => (prm->>'session_hours')::int)) RETURNING * INTO sess;
  PERFORM f360.log_seller(uid, l.id, 'shift_start', jsonb_build_object('session', sess.id));
  RETURN jsonb_build_object('ok', true, 'token', token, 'expires_at', sess.expires_at, 'idle_minutes', (prm->>'idle_minutes')::int,
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'legacy_channel_id', l.legacy_channel_id, 'ledger_authority', l.ledger_authority),
    'person', r.display_name);
END $$;

CREATE OR REPLACE FUNCTION public.f360_seller_session(p_token text, p_location_claim uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations; v_err text; v_owner uuid; v_loc uuid;
BEGIN
  BEGIN
    s := f360.require_seller_session(p_token, p_location_claim);
  EXCEPTION WHEN insufficient_privilege THEN
    v_err := SQLERRM;
    -- the gate's own writes were rolled back with the sub-block: record the denial (person + location) and persist it
    SELECT auth_user_id, location_id INTO v_owner, v_loc FROM f360.seller_sessions WHERE token_hash = f360.token_hash(coalesce(p_token, ''));
    IF v_owner = auth.uid() THEN
      IF v_err LIKE 'Tu turno venció%' OR v_err LIKE 'Ya no tienes acceso%' THEN
        UPDATE f360.seller_sessions SET revoked_at = coalesce(revoked_at, now()),
          revoke_reason = coalesce(revoke_reason, CASE WHEN v_err LIKE 'Tu turno venció%' THEN 'vencido' ELSE 'acceso retirado' END)
          WHERE token_hash = f360.token_hash(p_token);
      END IF;
      PERFORM f360.log_seller(auth.uid(), v_loc, CASE WHEN v_err LIKE 'Esa ubicación no es%' THEN 'location_mismatch' WHEN v_err LIKE 'Tu turno venció%' THEN 'expired' ELSE 'denied' END,
        jsonb_build_object('error', v_err, 'claimed', p_location_claim));
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', v_err);
  END;
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  RETURN jsonb_build_object('ok', true, 'person', (SELECT display_name FROM f360.user_roles WHERE auth_user_id = s.auth_user_id),
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'legacy_channel_id', l.legacy_channel_id, 'ledger_authority', l.ledger_authority),
    'expires_at', s.expires_at, 'last_seen_at', s.last_seen_at);
END $$;
