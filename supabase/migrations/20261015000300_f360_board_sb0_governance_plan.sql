-- Fuxia 360 · Strategy & Board · SB0.3 — DECISION LOG WITH CONFLICT OF INTEREST (D10B) + PLAN 2027 MAPPING (D12).
-- Needs 20261015000100 and 20261015000200. Spec: 08_BOARD_GOVERNANCE.md §2, 07_CAPITAL_OWNERSHIP.md §3, 05_FIVE_YEAR_PLAN.md §1–2.
-- ADDITIVE, inside f360_board (+ public.f360_board_* RPCs). f360.growth_* tables are READ, never changed.
--
-- D10B (Mario 2026-10-08) — workflow support only, no final legal rules:
--   · decisions carry RELATED PARTY / CONFLICT OF INTEREST flags and the interested members;
--   · conflict kinds MARIO_INVESTMENT / MARIO_OWNERSHIP / MARIO_TECH_CONTRIBUTION / MARIO_COMPENSATION make the member with
--     person_key = 'MARIO' (board_members, set by reviewed script by auth id — never by name) an interested party automatically;
--   · interested members are RECUSED (recorded) and their approve/reject attempts are refused (and recorded);
--   · approval is valid only from a non-interested member → "APPROVED BY OTHER MEMBER". Mario can never be the sole approver
--     of a Mario-related decision; Carolina can be the independent approver.
--   · D5 default (settings.decision_requires_other_member): ordinary decisions are approved by a member other than the proposer.
-- Immutability: after APPROVED/REJECTED the content is frozen by trigger; the only later change is → SUPERSEDED by a newer
-- approved decision (supersedes_id). DELETE always refused. Revisions while PROPOSED and every event are append-only.
--
-- D12 Plan 2027: the existing B4 North Star (f360.growth_plans, prod 2027 = MXN 15,000,000) is the INITIAL SOURCE.
-- To avoid two parallel plans, the Board plan year 2027 is a LINKED row (linked_source = 'f360.growth_plans'): its amount is
-- read live from growth_plans (the only editable place until a Board plan is approved — D8), with its full history from
-- f360.growth_plan_changes; the import itself is preserved as revision 1 (value + history at import time). Label: DRAFT
-- MANAGEMENT TARGET (not forecast, not actual). The five-year draft targets (2028–2031) are NOT loaded here (spec: SB3, by
-- the owners in the UI).
-- Rollback: supabase/rollbacks/20261015000300_f360_board_sb0_governance_plan.down.sql

-- ══ 1 · Decisions ═══════════════════════════════════════════════════════════
CREATE SEQUENCE f360_board.decision_number_seq;

CREATE TABLE f360_board.decisions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number                text NOT NULL UNIQUE,                    -- D-2026-001
  decided_on            date,
  title                 text NOT NULL CHECK (length(btrim(title)) >= 3),
  context               text NOT NULL DEFAULT '',
  alternatives          jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(alternatives) = 'array'),
  decision              text NOT NULL CHECK (length(btrim(decision)) >= 3),
  financial_impact      jsonb CHECK (financial_impact IS NULL OR jsonb_typeof(financial_impact) = 'object'),
  status                text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED', 'APPROVED', 'REJECTED', 'DEFERRED', 'SUPERSEDED', 'WITHDRAWN')),
  conflict_kind         text NOT NULL DEFAULT 'NONE' CHECK (conflict_kind IN ('NONE', 'MARIO_INVESTMENT', 'MARIO_OWNERSHIP', 'MARIO_TECH_CONTRIBUTION',
                                                                                  'MARIO_COMPENSATION', 'OTHER_RELATED_PARTY')),
  related_party         boolean NOT NULL DEFAULT false,
  conflict_of_interest  boolean NOT NULL DEFAULT false,
  interested_members    uuid[] NOT NULL DEFAULT '{}',
  approval_basis        text CHECK (approval_basis IN ('OTHER_MEMBER', 'APPROVED_BY_OTHER_MEMBER_RELATED_PARTY')),
  approved_by           uuid[] NOT NULL DEFAULT '{}',
  approved_at           timestamptz,
  related_object        jsonb CHECK (related_object IS NULL OR jsonb_typeof(related_object) = 'object'),
  supersedes_id         uuid REFERENCES f360_board.decisions(id),
  superseded_by_id      uuid REFERENCES f360_board.decisions(id),
  revision              int NOT NULL DEFAULT 1,
  proposed_by           uuid NOT NULL,
  proposed_by_name      text NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  idempotency_key       uuid NOT NULL UNIQUE,
  CHECK ((conflict_kind <> 'NONE') = (related_party AND conflict_of_interest)),
  CHECK (NOT related_party OR cardinality(interested_members) > 0),
  CHECK (status <> 'APPROVED' OR (cardinality(approved_by) > 0 AND approval_basis IS NOT NULL)),
  CHECK (NOT (approved_by && interested_members))                 -- an interested member is never an approver
);
ALTER TABLE f360_board.decisions ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX decisions_one_successor ON f360_board.decisions (supersedes_id) WHERE supersedes_id IS NOT NULL AND status NOT IN ('REJECTED', 'WITHDRAWN');

CREATE TABLE f360_board.decision_revisions (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  decision_id   uuid NOT NULL REFERENCES f360_board.decisions(id),
  revision      int NOT NULL,
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_user       uuid, by_name text NOT NULL,
  payload       jsonb NOT NULL,
  content_hash  text NOT NULL,
  UNIQUE (decision_id, revision)
);
CREATE TABLE f360_board.decision_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  decision_id   uuid NOT NULL REFERENCES f360_board.decisions(id),
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  event         text NOT NULL CHECK (event IN ('PROPOSED', 'REVISED', 'RECUSED', 'APPROVAL_REFUSED_RECUSED', 'APPROVAL_REFUSED_PROPOSER',
                                               'APPROVED', 'REJECTED', 'DEFERRED', 'WITHDRAWN', 'SUPERSEDED')),
  by_user       uuid, by_name text NOT NULL,
  note          text
);
CREATE TABLE f360_board.decision_recusals (
  decision_id   uuid NOT NULL REFERENCES f360_board.decisions(id),
  auth_user_id  uuid NOT NULL,
  member_name   text NOT NULL,
  reason        text NOT NULL,
  recused_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (decision_id, auth_user_id)
);
ALTER TABLE f360_board.decision_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.decision_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.decision_recusals ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER decision_revisions_append_only BEFORE UPDATE OR DELETE ON f360_board.decision_revisions FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TRIGGER decision_events_append_only BEFORE UPDATE OR DELETE ON f360_board.decision_events FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TRIGGER decision_recusals_append_only BEFORE UPDATE OR DELETE ON f360_board.decision_recusals FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Content frozen after a final status; the conflict-of-interest facts never change; no DELETE.
CREATE FUNCTION f360_board.on_decision_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE o jsonb; n jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Este historial no se puede modificar (f360_board.decisions)'; END IF;
  IF (NEW.id, NEW.number, NEW.proposed_by, NEW.created_at, NEW.idempotency_key, NEW.conflict_kind, NEW.related_party, NEW.conflict_of_interest,
      NEW.interested_members, NEW.supersedes_id)
     IS DISTINCT FROM (OLD.id, OLD.number, OLD.proposed_by, OLD.created_at, OLD.idempotency_key, OLD.conflict_kind, OLD.related_party, OLD.conflict_of_interest,
      OLD.interested_members, OLD.supersedes_id) THEN
    RAISE EXCEPTION 'La identidad y el conflicto de interés de una decisión no cambian.';
  END IF;
  IF OLD.status IN ('APPROVED', 'REJECTED', 'SUPERSEDED', 'WITHDRAWN') THEN
    o := to_jsonb(OLD) - 'status' - 'superseded_by_id'; n := to_jsonb(NEW) - 'status' - 'superseded_by_id';
    IF NOT (OLD.status = 'APPROVED' AND NEW.status = 'SUPERSEDED' AND OLD.superseded_by_id IS NULL AND NEW.superseded_by_id IS NOT NULL AND o = n) THEN
      RAISE EXCEPTION 'Una decisión % no se modifica: crea una nueva que la sustituya.', OLD.status;
    END IF;
  ELSIF NEW.status = 'SUPERSEDED' OR NEW.superseded_by_id IS NOT NULL THEN
    RAISE EXCEPTION 'Solo una decisión aprobada puede ser sustituida.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER decisions_guard BEFORE UPDATE OR DELETE ON f360_board.decisions FOR EACH ROW EXECUTE FUNCTION f360_board.on_decision_change();

ALTER TABLE f360_board.budget_versions ADD CONSTRAINT budget_versions_decision_fk FOREIGN KEY (decision_id) REFERENCES f360_board.decisions(id);

CREATE FUNCTION f360_board.decision_event(p_id uuid, p_event text, p_uid uuid, p_note text DEFAULT NULL) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  INSERT INTO f360_board.decision_events (decision_id, event, by_user, by_name, note) VALUES (p_id, p_event, p_uid, f360_board.member_name(p_uid), p_note)
$$;

CREATE FUNCTION f360_board.decision_json(d f360_board.decisions, p_uid uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', d.id, 'number', d.number, 'title', d.title, 'context', d.context, 'alternatives', d.alternatives, 'decision', d.decision,
    'financial_impact', d.financial_impact, 'status', d.status, 'decided_on', d.decided_on, 'revision', d.revision,
    'conflict_kind', d.conflict_kind, 'related_party', d.related_party, 'conflict_of_interest', d.conflict_of_interest,
    'interested', (SELECT coalesce(jsonb_agg(f360_board.member_name(x)), '[]') FROM unnest(d.interested_members) x),
    'recused', (SELECT coalesce(jsonb_agg(r.member_name ORDER BY r.member_name), '[]') FROM f360_board.decision_recusals r WHERE r.decision_id = d.id),
    'i_am_recused', p_uid = ANY (d.interested_members),
    'approval_basis', d.approval_basis, 'approved_by', (SELECT coalesce(jsonb_agg(f360_board.member_name(x)), '[]') FROM unnest(d.approved_by) x),
    'approved_at', d.approved_at, 'proposed_by', d.proposed_by_name, 'proposed_by_me', d.proposed_by = p_uid,
    'supersedes', (SELECT s.number FROM f360_board.decisions s WHERE s.id = d.supersedes_id),
    'superseded_by', (SELECT s.number FROM f360_board.decisions s WHERE s.id = d.superseded_by_id), 'created_at', d.created_at)
$$;

-- Propose (sensitive write). For MARIO_* kinds the member with person_key MARIO is added as interested automatically.
CREATE FUNCTION public.f360_board_decision_propose(p_idempotency_key uuid, p_title text, p_decision text, p_context text DEFAULT '',
  p_conflict_kind text DEFAULT 'NONE', p_interested_members uuid[] DEFAULT '{}', p_financial_impact jsonb DEFAULT NULL,
  p_alternatives jsonb DEFAULT '[]', p_supersedes_id uuid DEFAULT NULL, p_related_object jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decision_propose', NULL,
    jsonb_build_object('k', p_idempotency_key, 'kind', p_conflict_kind, 'sup', p_supersedes_id));
  d f360_board.decisions; mario uuid; interested uuid[]; kind text := coalesce(p_conflict_kind, 'NONE'); x uuid; prev f360_board.decisions;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Falta la llave de idempotencia.'); END IF;
  SELECT * INTO d FROM f360_board.decisions WHERE idempotency_key = p_idempotency_key;
  IF d.id IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'replayed', true, 'decision', f360_board.decision_json(d, uid)); END IF;
  IF kind NOT IN ('NONE', 'MARIO_INVESTMENT', 'MARIO_OWNERSHIP', 'MARIO_TECH_CONTRIBUTION', 'MARIO_COMPENSATION', 'OTHER_RELATED_PARTY') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Tipo de conflicto no válido.');
  END IF;
  interested := ARRAY(SELECT DISTINCT unnest(coalesce(p_interested_members, '{}')));
  FOREACH x IN ARRAY interested LOOP
    IF NOT EXISTS (SELECT 1 FROM f360_board.board_members WHERE auth_user_id = x AND active) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Parte interesada no válida: debe ser miembro del consejo.');
    END IF;
  END LOOP;
  IF kind LIKE 'MARIO\_%' THEN
    SELECT auth_user_id INTO mario FROM f360_board.board_members WHERE person_key = 'MARIO';
    IF mario IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'No se puede registrar: falta identificar a Mario en el consejo (person_key).'); END IF;
    IF NOT (mario = ANY (interested)) THEN interested := interested || mario; END IF;
  ELSIF kind = 'OTHER_RELATED_PARTY' AND cardinality(interested) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Indica qué miembro tiene el interés.');
  ELSIF kind = 'NONE' AND cardinality(interested) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Si hay una parte interesada, marca el tipo de conflicto.');
  END IF;
  IF p_supersedes_id IS NOT NULL THEN
    SELECT * INTO prev FROM f360_board.decisions WHERE id = p_supersedes_id;
    IF prev.status IS DISTINCT FROM 'APPROVED' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo se sustituye una decisión aprobada.'); END IF;
  END IF;
  BEGIN
    INSERT INTO f360_board.decisions (number, title, context, alternatives, decision, financial_impact, conflict_kind, related_party, conflict_of_interest,
                                      interested_members, related_object, supersedes_id, proposed_by, proposed_by_name, idempotency_key)
      VALUES (format('D-%s-%s', extract(year FROM (now() AT TIME ZONE 'America/Mexico_City'))::int, lpad(nextval('f360_board.decision_number_seq')::text, 3, '0')),
              btrim(p_title), coalesce(btrim(p_context), ''), coalesce(p_alternatives, '[]'), btrim(p_decision), p_financial_impact, kind, kind <> 'NONE', kind <> 'NONE',
              interested, p_related_object, p_supersedes_id, uid, f360_board.member_name(uid), p_idempotency_key)
      RETURNING * INTO d;
  EXCEPTION WHEN check_violation OR unique_violation OR not_null_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Datos de la decisión incompletos o no válidos.');
  END;
  INSERT INTO f360_board.decision_revisions (decision_id, revision, by_user, by_name, payload, content_hash)
    VALUES (d.id, 1, uid, f360_board.member_name(uid), to_jsonb(d) - 'idempotency_key', encode(extensions.digest((to_jsonb(d) - 'idempotency_key')::text, 'sha256'), 'hex'));
  PERFORM f360_board.decision_event(d.id, 'PROPOSED', uid);
  FOREACH x IN ARRAY d.interested_members LOOP
    INSERT INTO f360_board.decision_recusals (decision_id, auth_user_id, member_name, reason)
      VALUES (d.id, x, f360_board.member_name(x), 'Parte relacionada / conflicto de interés: ' || kind);
    PERFORM f360_board.decision_event(d.id, 'RECUSED', x, kind);
  END LOOP;
  PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_propose', d.id::text, jsonb_build_object('kind', kind));
  RETURN jsonb_build_object('ok', true, 'decision', f360_board.decision_json(d, uid));
END $$;

-- Revise a PROPOSED decision (proposer only). Every revision is kept (payload + hash).
CREATE FUNCTION public.f360_board_decision_revise(p_id uuid, p_title text, p_decision text, p_context text DEFAULT '',
  p_financial_impact jsonb DEFAULT NULL, p_alternatives jsonb DEFAULT '[]') RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decision_revise', p_id::text); d f360_board.decisions;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO d FROM f360_board.decisions WHERE id = p_id FOR UPDATE;
  IF d.id IS NULL OR d.status <> 'PROPOSED' THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo se revisa una decisión propuesta.'); END IF;
  IF d.proposed_by <> uid THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo quien la propuso puede revisarla.'); END IF;
  BEGIN
    UPDATE f360_board.decisions SET title = btrim(p_title), decision = btrim(p_decision), context = coalesce(btrim(p_context), ''),
        financial_impact = p_financial_impact, alternatives = coalesce(p_alternatives, '[]'), revision = revision + 1
      WHERE id = p_id RETURNING * INTO d;
  EXCEPTION WHEN check_violation OR not_null_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Datos de la decisión incompletos o no válidos.');
  END;
  INSERT INTO f360_board.decision_revisions (decision_id, revision, by_user, by_name, payload, content_hash)
    VALUES (d.id, d.revision, uid, f360_board.member_name(uid), to_jsonb(d) - 'idempotency_key', encode(extensions.digest((to_jsonb(d) - 'idempotency_key')::text, 'sha256'), 'hex'));
  PERFORM f360_board.decision_event(d.id, 'REVISED', uid, 'revisión ' || d.revision);
  PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_revise', d.id::text);
  RETURN jsonb_build_object('ok', true, 'decision', f360_board.decision_json(d, uid));
END $$;

-- Approve / reject / defer / withdraw. Approve & reject: never by an interested (recused) member; ordinary decisions by a
-- member other than the proposer (D5 default). Refusals are RETURNED (not raised) so their event + log persist.
CREATE FUNCTION public.f360_board_decision_act(p_id uuid, p_action text, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decision_act', p_id::text, jsonb_build_object('action', p_action));
  d f360_board.decisions; s f360_board.settings; prev f360_board.decisions;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_action NOT IN ('APPROVE', 'REJECT', 'DEFER', 'WITHDRAW') THEN RETURN jsonb_build_object('ok', false, 'error', 'Acción no válida.'); END IF;
  SELECT * INTO s FROM f360_board.settings WHERE id;
  SELECT * INTO d FROM f360_board.decisions WHERE id = p_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Decisión no encontrada.'); END IF;
  IF d.status NOT IN ('PROPOSED', 'DEFERRED') THEN RETURN jsonb_build_object('ok', false, 'error', 'Esta decisión ya no está abierta.'); END IF;
  IF p_action = 'WITHDRAW' THEN
    IF d.proposed_by <> uid THEN RETURN jsonb_build_object('ok', false, 'error', 'Solo quien la propuso puede retirarla.'); END IF;
    UPDATE f360_board.decisions SET status = 'WITHDRAWN' WHERE id = d.id RETURNING * INTO d;
    PERFORM f360_board.decision_event(d.id, 'WITHDRAWN', uid, p_note);
  ELSE
    IF uid = ANY (d.interested_members) THEN
      PERFORM f360_board.decision_event(d.id, 'APPROVAL_REFUSED_RECUSED', uid, p_action);
      PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_act:refused_recused', d.id::text);
      RETURN jsonb_build_object('ok', false, 'recused', true,
        'error', 'Tienes un conflicto de interés en esta decisión (parte relacionada): debe resolverla otra persona del consejo.');
    END IF;
    IF p_action IN ('APPROVE', 'REJECT') AND NOT d.related_party AND s.decision_requires_other_member AND d.proposed_by = uid THEN
      PERFORM f360_board.decision_event(d.id, 'APPROVAL_REFUSED_PROPOSER', uid, p_action);
      PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_act:refused_proposer', d.id::text);
      RETURN jsonb_build_object('ok', false, 'error', 'Quien propone no aprueba: debe resolverla otra persona del consejo.');
    END IF;
    IF p_action = 'APPROVE' THEN
      UPDATE f360_board.decisions SET status = 'APPROVED', approved_by = ARRAY[uid], approved_at = now(),
          decided_on = (now() AT TIME ZONE 'America/Mexico_City')::date,
          approval_basis = CASE WHEN related_party THEN 'APPROVED_BY_OTHER_MEMBER_RELATED_PARTY' ELSE 'OTHER_MEMBER' END
        WHERE id = d.id RETURNING * INTO d;
      PERFORM f360_board.decision_event(d.id, 'APPROVED', uid, coalesce(p_note, d.approval_basis));
      IF d.supersedes_id IS NOT NULL THEN
        UPDATE f360_board.decisions SET status = 'SUPERSEDED', superseded_by_id = d.id WHERE id = d.supersedes_id AND status = 'APPROVED' RETURNING * INTO prev;
        IF prev.id IS NULL THEN RAISE EXCEPTION 'La decisión sustituida ya no está aprobada.'; END IF;
        PERFORM f360_board.decision_event(prev.id, 'SUPERSEDED', uid, 'por ' || d.number);
      END IF;
    ELSIF p_action = 'REJECT' THEN
      UPDATE f360_board.decisions SET status = 'REJECTED', decided_on = (now() AT TIME ZONE 'America/Mexico_City')::date WHERE id = d.id RETURNING * INTO d;
      PERFORM f360_board.decision_event(d.id, 'REJECTED', uid, p_note);
    ELSE
      UPDATE f360_board.decisions SET status = 'DEFERRED' WHERE id = d.id RETURNING * INTO d;
      PERFORM f360_board.decision_event(d.id, 'DEFERRED', uid, p_note);
    END IF;
  END IF;
  PERFORM f360_board.log_write(uid, 'BOARD', 'f360_board_decision_act:' || lower(p_action), d.id::text);
  RETURN jsonb_build_object('ok', true, 'decision', f360_board.decision_json(d, uid));
END $$;

CREATE FUNCTION public.f360_board_decisions(p_limit int DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('BOARD', 'f360_board_decisions');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'decisions', coalesce((SELECT jsonb_agg(f360_board.decision_json(d, uid) ORDER BY d.created_at DESC)
    FROM (SELECT * FROM f360_board.decisions ORDER BY created_at DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 500))) d), '[]'));
END $$;

-- ══ 2 · Plan versions (TARGETS) with the B4 Plan 2027 link ═══════════════════
CREATE TABLE f360_board.plan_versions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key       text NOT NULL REFERENCES f360_board.reporting_entities(key),
  name             text NOT NULL,
  horizon          text NOT NULL CHECK (horizon IN ('ANNUAL', 'FIVE_YEAR')),
  number_class     text NOT NULL DEFAULT 'TARGET' CHECK (number_class = 'TARGET'),
  target_label     text NOT NULL DEFAULT 'DRAFT MANAGEMENT TARGET' CHECK (target_label = 'DRAFT MANAGEMENT TARGET'),
  status           text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PROPOSED', 'APPROVED', 'SUPERSEDED')),
  origin           text NOT NULL CHECK (origin IN ('IMPORTED_B4', 'BOARD')),
  supersedes_id    uuid REFERENCES f360_board.plan_versions(id),
  decision_id      uuid REFERENCES f360_board.decisions(id),
  created_by       uuid, created_by_name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  note             text
);
CREATE TABLE f360_board.plan_years (
  version_id       uuid NOT NULL REFERENCES f360_board.plan_versions(id),
  year             int NOT NULL CHECK (year BETWEEN 2024 AND 2100),
  theme            text,
  revenue_target   numeric(14,2) CHECK (revenue_target > 0),       -- own value (Board plans); NULL when linked
  currency         text NOT NULL DEFAULT 'MXN' REFERENCES f360.currencies(code),
  linked_source    text CHECK (linked_source IN ('f360.growth_plans')),
  linked_key       text,
  assumptions      text,
  PRIMARY KEY (version_id, year),
  CHECK ((linked_source IS NULL) = (linked_key IS NULL)),
  CHECK (NOT (linked_source IS NOT NULL AND revenue_target IS NOT NULL))   -- one source per number: linked rows never copy the amount
);
CREATE TABLE f360_board.plan_revisions (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  version_id    uuid NOT NULL REFERENCES f360_board.plan_versions(id),
  revision      int NOT NULL,
  at            timestamptz NOT NULL DEFAULT clock_timestamp(),
  by_user       uuid, by_name text NOT NULL,
  reason        text NOT NULL,
  payload       jsonb NOT NULL,
  content_hash  text NOT NULL,
  UNIQUE (version_id, revision)
);
ALTER TABLE f360_board.plan_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.plan_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.plan_revisions ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER plan_revisions_append_only BEFORE UPDATE OR DELETE ON f360_board.plan_revisions FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Plans: content frozen outside DRAFT (approved → only SUPERSEDED); never deleted once proposed; years only in DRAFT.
CREATE FUNCTION f360_board.on_plan_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE st text;
BEGIN
  IF TG_TABLE_NAME = 'plan_versions' THEN
    IF TG_OP = 'DELETE' THEN
      IF OLD.status <> 'DRAFT' OR EXISTS (SELECT 1 FROM f360_board.plan_revisions WHERE version_id = OLD.id) THEN RAISE EXCEPTION 'Un plan con historia no se borra.'; END IF;
      RETURN OLD;
    END IF;
    IF OLD.status <> 'DRAFT' AND NOT (
         (OLD.status = 'PROPOSED' AND NEW.status IN ('APPROVED', 'DRAFT')) OR (OLD.status = 'APPROVED' AND NEW.status = 'SUPERSEDED'))
       OR (OLD.status <> 'DRAFT' AND (to_jsonb(OLD) - 'status' - 'decision_id') <> (to_jsonb(NEW) - 'status' - 'decision_id')) THEN
      RAISE EXCEPTION 'Este plan ya está %: no se modifica (duplica a un borrador nuevo).', OLD.status;
    END IF;
    RETURN NEW;
  END IF;
  SELECT status INTO st FROM f360_board.plan_versions WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.version_id ELSE NEW.version_id END;
  IF st IS DISTINCT FROM 'DRAFT' THEN RAISE EXCEPTION 'El plan está %: sus años no se modifican.', st; END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER plan_versions_guard BEFORE UPDATE OR DELETE ON f360_board.plan_versions FOR EACH ROW EXECUTE FUNCTION f360_board.on_plan_change();
CREATE TRIGGER plan_years_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.plan_years FOR EACH ROW EXECUTE FUNCTION f360_board.on_plan_change();

-- Import the existing B4 Plan 2027 (if present in this database) as a LINKED draft target. History preserved in revision 1.
DO $$
DECLARE g f360.growth_plans; v uuid; payload jsonb;
BEGIN
  SELECT * INTO g FROM f360.growth_plans WHERE plan_year = 2027;
  IF g.plan_year IS NULL THEN RAISE NOTICE 'No B4 plan for 2027 in this database: nothing imported.'; RETURN; END IF;
  INSERT INTO f360_board.plan_versions (entity_key, name, horizon, origin, created_by_name, note)
    VALUES ('fuxia', 'Plan 2027 · North Star (desde Growth B4)', 'ANNUAL', 'IMPORTED_B4', 'migration 20261015000300',
            'Importado (D12, Mario 2026-10-08). El monto se lee en vivo de f360.growth_plans (única fuente editable hasta que un plan del consejo se apruebe, D8).')
    RETURNING id INTO v;
  INSERT INTO f360_board.plan_years (version_id, year, currency, linked_source, linked_key) VALUES (v, 2027, g.currency, 'f360.growth_plans', '2027');
  payload := jsonb_build_object('imported_from', 'f360.growth_plans', 'growth_plan', to_jsonb(g),
    'growth_scenarios', (SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.kind), '[]') FROM f360.growth_scenarios s WHERE s.plan_year = 2027),
    'history', (SELECT coalesce(jsonb_agg(to_jsonb(c) - 'by_user' ORDER BY c.id), '[]') FROM f360.growth_plan_changes c WHERE c.plan_year = 2027));
  INSERT INTO f360_board.plan_revisions (version_id, revision, by_name, reason, payload, content_hash)
    VALUES (v, 1, 'migration 20261015000300', 'Importación inicial del Plan 2027 de Growth B4 (D12)', payload, encode(extensions.digest(payload::text, 'sha256'), 'hex'));
END $$;

-- Plans with resolved targets: linked rows read growth_plans LIVE (+ its change history); always labelled DRAFT MANAGEMENT TARGET.
CREATE FUNCTION public.f360_board_plans() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_plans');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'label', 'DRAFT MANAGEMENT TARGET — no es pronóstico ni resultado real',
    'plans', coalesce((SELECT jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'horizon', v.horizon, 'status', v.status, 'origin', v.origin,
        'number_class', v.number_class, 'target_label', v.target_label, 'created_at', v.created_at, 'note', v.note,
        'revisions', (SELECT count(*) FROM f360_board.plan_revisions r WHERE r.version_id = v.id),
        'years', (SELECT coalesce(jsonb_agg(jsonb_build_object('year', y.year, 'theme', y.theme, 'currency', y.currency,
            'revenue_target', CASE WHEN y.linked_source = 'f360.growth_plans' THEN (SELECT g.north_star FROM f360.growth_plans g WHERE g.plan_year::text = y.linked_key) ELSE y.revenue_target END,
            'source', coalesce(y.linked_source, 'f360_board.plan_years'),
            'imported_value', (SELECT (r.payload->'growth_plan'->>'north_star')::numeric FROM f360_board.plan_revisions r WHERE r.version_id = v.id AND r.revision = 1),
            'source_history', CASE WHEN y.linked_source = 'f360.growth_plans' THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('what', c.what, 'before', c.before->'north_star',
                  'after', c.after->'north_star', 'by', c.by_name, 'at', c.at) ORDER BY c.id), '[]') FROM f360.growth_plan_changes c WHERE c.plan_year::text = y.linked_key AND c.what = 'north_star') END)
          ORDER BY y.year), '[]') FROM f360_board.plan_years y WHERE y.version_id = v.id))
      ORDER BY v.created_at) FROM f360_board.plan_versions v), '[]'));
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_board_decision_propose(uuid, text, text, text, text, uuid[], jsonb, jsonb, uuid, jsonb),
  public.f360_board_decision_revise(uuid, text, text, text, jsonb, jsonb), public.f360_board_decision_act(uuid, text, text),
  public.f360_board_decisions(int), public.f360_board_plans() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_decision_propose(uuid, text, text, text, text, uuid[], jsonb, jsonb, uuid, jsonb),
  public.f360_board_decision_revise(uuid, text, text, text, jsonb, jsonb), public.f360_board_decision_act(uuid, text, text),
  public.f360_board_decisions(int), public.f360_board_plans() TO authenticated;
