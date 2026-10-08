-- Fuxia 360 · Strategy & Board · SB0.2 — FINANCE FOUNDATION (needs 20261015000100).
-- Spec: 13_DATA_MODEL.md §2–3 & §11, 02_CEO_COCKPIT.md §3, 03_FORECAST_MODEL.md §1. Mario 2026-10-08: D9, D11, monthly close.
-- ADDITIVE, all inside f360_board. What exists after this file:
--   reporting_entities     the management scope 'fuxia' (NOT a legal entity). Legal entities (MX/CO) are supported by the
--                          model but NOT populated (D9 pending). Cali = casa matriz, PENDING BUSINESS CONFIRMATION, not inserted.
--   fiscal_periods         D11 calendar fiscal year (Jan 1 → Dec 31): 12 months + 4 quarters + 1 year per year (2026, 2027 seeded).
--                          Month status OPEN → UNDER_REVIEW → CLOSED → REOPENED → UNDER_REVIEW …; quarter/year roll up.
--   fiscal_period_events   append-only history of every status change (who, when, why, close version).
--   close_accounts         catalog of what a manual close may capture (COGS, OPEX by category, cash, tax). NO amounts.
--                          Marketing spend is NOT here: S-G0 owns marketing spend (single source of truth).
--   monthly_close_entries  manual close amounts with source + evidence + who captured + who approved (≠ capturer).
--                          Correction = void + new (pattern f360.historical_sales); never UPDATE an amount; never DELETE.
--   monthly_close_log      append-only log of every capture / approval / void.
--   close_actual_snapshots frozen photo of the close at each CLOSE (close_version), append-only.
--   metric_catalog         one vocabulary for cockpit/gates/valuation: definition, unit, source, availability TODAY.
--   budget_* / forecast_*  versioned foundation (no data, no write RPCs until SB1/SB2): approved/published versions are
--                          frozen by trigger; publishing a forecast writes an immutable snapshot.
-- Nothing here invents a number: missing sources are reported as DATA_INCOMPLETE. f360.fx_rates and
-- f360.product_cost_versions belong to the S-G0 sprint and are only REFERENCED by name (metric_catalog.depends_on).
-- Rollback: supabase/rollbacks/20261015000200_f360_board_sb0_finance_foundation.down.sql

-- ══ 1 · Reporting entities ═══════════════════════════════════════════════════
CREATE TABLE f360_board.reporting_entities (
  key                  text PRIMARY KEY CHECK (key ~ '^[a-z][a-z0-9_]*$'),
  name                 text NOT NULL,
  kind                 text NOT NULL CHECK (kind IN ('MANAGEMENT', 'LEGAL_ENTITY')),
  country              text CHECK (country IN ('MX', 'CO')),
  functional_currency  text NOT NULL REFERENCES f360.currencies(code),
  status               text NOT NULL CHECK (status IN ('ACTIVE', 'PENDING_BUSINESS_CONFIRMATION', 'INACTIVE')),
  note                 text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by_name      text NOT NULL
);
ALTER TABLE f360_board.reporting_entities ENABLE ROW LEVEL SECURITY;
INSERT INTO f360_board.reporting_entities (key, name, kind, country, functional_currency, status, note, created_by_name) VALUES
  ('fuxia', 'Fuxia Ballerinas · gestión (todo lo que opera Fuxia 360)', 'MANAGEMENT', NULL, 'MXN', 'ACTIVE',
   'Alcance de gestión, no entidad legal. Entidades legales MX/CO: pendientes (D9). Cali = casa matriz (suegra de Mario), fuera de Fuxia 360 (D7), PENDING BUSINESS CONFIRMATION — no se registra.',
   'migration 20261015000200');

-- ══ 2 · Fiscal periods (D11: calendar year) ══════════════════════════════════
CREATE TABLE f360_board.fiscal_periods (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key         text NOT NULL REFERENCES f360_board.reporting_entities(key),
  kind               text NOT NULL CHECK (kind IN ('MONTH', 'QUARTER', 'YEAR')),
  fiscal_year        int  NOT NULL CHECK (fiscal_year BETWEEN 2024 AND 2100),
  period_no          int  NOT NULL,
  period_start       date NOT NULL,
  period_end         date NOT NULL,                       -- inclusive
  status             text CHECK (status IN ('OPEN', 'UNDER_REVIEW', 'CLOSED', 'REOPENED')),  -- months only; quarter/year roll up
  close_version      int  NOT NULL DEFAULT 0,             -- +1 at every CLOSE
  submitted_by       uuid,                                -- who sent it to UNDER_REVIEW last
  status_changed_at  timestamptz,
  status_changed_by  uuid,
  exception_note     text,                                -- why it was closed with DATA_INCOMPLETE components
  UNIQUE (entity_key, kind, fiscal_year, period_no),
  CHECK ((kind = 'MONTH' AND period_no BETWEEN 1 AND 12) OR (kind = 'QUARTER' AND period_no BETWEEN 1 AND 4) OR (kind = 'YEAR' AND period_no = 1)),
  CHECK (period_start = make_date(fiscal_year, CASE kind WHEN 'MONTH' THEN period_no WHEN 'QUARTER' THEN (period_no - 1) * 3 + 1 ELSE 1 END, 1)),
  CHECK (period_end = (period_start + CASE kind WHEN 'MONTH' THEN interval '1 month' WHEN 'QUARTER' THEN interval '3 months' ELSE interval '1 year' END - interval '1 day')::date),
  CHECK ((kind = 'MONTH') = (status IS NOT NULL))
);
ALTER TABLE f360_board.fiscal_periods ENABLE ROW LEVEL SECURITY;

CREATE TABLE f360_board.fiscal_period_events (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  period_id      uuid NOT NULL REFERENCES f360_board.fiscal_periods(id),
  at             timestamptz NOT NULL DEFAULT clock_timestamp(),
  from_status    text, to_status text NOT NULL,
  close_version  int NOT NULL,
  by_user        uuid,
  by_name        text NOT NULL,
  reason         text,
  db_user        text NOT NULL DEFAULT current_user
);
ALTER TABLE f360_board.fiscal_period_events ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER fiscal_period_events_append_only BEFORE UPDATE OR DELETE ON f360_board.fiscal_period_events
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Periods never change shape, are never deleted, and only move along the allowed status graph; every move is logged
-- (also a direct DB update, not only the RPC). Reason comes from the RPC via the transaction-local GUC f360_board.reason.
CREATE FUNCTION f360_board.on_period_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Un periodo fiscal no se borra.'; END IF;
  IF (NEW.entity_key, NEW.kind, NEW.fiscal_year, NEW.period_no, NEW.period_start, NEW.period_end)
     IS DISTINCT FROM (OLD.entity_key, OLD.kind, OLD.fiscal_year, OLD.period_no, OLD.period_start, OLD.period_end) THEN
    RAISE EXCEPTION 'Un periodo fiscal no cambia de fechas.';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT ((OLD.status, NEW.status) IN (('OPEN', 'UNDER_REVIEW'), ('REOPENED', 'UNDER_REVIEW'), ('UNDER_REVIEW', 'OPEN'),
                                         ('UNDER_REVIEW', 'CLOSED'), ('CLOSED', 'REOPENED'))) THEN
      RAISE EXCEPTION 'Cambio de estado no permitido: % → %.', OLD.status, NEW.status;
    END IF;
    IF NEW.status = 'CLOSED' AND NEW.close_version <> OLD.close_version + 1 THEN RAISE EXCEPTION 'Cada cierre crea una versión nueva.'; END IF;
    IF NEW.status <> 'CLOSED' AND NEW.close_version <> OLD.close_version THEN RAISE EXCEPTION 'La versión de cierre solo cambia al cerrar.'; END IF;
    INSERT INTO f360_board.fiscal_period_events (period_id, from_status, to_status, close_version, by_user, by_name, reason)
      VALUES (NEW.id, OLD.status, NEW.status, NEW.close_version, auth.uid(),
              CASE WHEN auth.uid() IS NULL THEN 'sistema (' || current_user || ')' ELSE f360_board.member_name(auth.uid()) END,
              nullif(current_setting('f360_board.reason', true), ''));
  ELSIF NEW.close_version <> OLD.close_version THEN
    RAISE EXCEPTION 'La versión de cierre solo cambia al cerrar.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER fiscal_periods_guard BEFORE UPDATE OR DELETE ON f360_board.fiscal_periods
  FOR EACH ROW EXECUTE FUNCTION f360_board.on_period_change();

CREATE FUNCTION f360_board.ensure_fiscal_year(p_entity text, p_year int) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE n int;
BEGIN
  INSERT INTO f360_board.fiscal_periods (entity_key, kind, fiscal_year, period_no, period_start, period_end, status)
  SELECT p_entity, k.kind, p_year, k.no, k.s, (k.s + k.len - interval '1 day')::date, CASE WHEN k.kind = 'MONTH' THEN 'OPEN' END
  FROM (SELECT 'MONTH' kind, m no, make_date(p_year, m, 1) s, interval '1 month' len FROM generate_series(1, 12) m
        UNION ALL SELECT 'QUARTER', q, make_date(p_year, (q - 1) * 3 + 1, 1), interval '3 months' FROM generate_series(1, 4) q
        UNION ALL SELECT 'YEAR', 1, make_date(p_year, 1, 1), interval '1 year') k
  ON CONFLICT (entity_key, kind, fiscal_year, period_no) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
SELECT f360_board.ensure_fiscal_year('fuxia', 2026), f360_board.ensure_fiscal_year('fuxia', 2027);

-- ══ 3 · Close accounts (catalog only — no amounts) ═══════════════════════════
CREATE TABLE f360_board.close_accounts (
  account_key    text PRIMARY KEY CHECK (account_key ~ '^[a-z][a-z0-9_]*$'),
  label          text NOT NULL,
  component      text NOT NULL CHECK (component IN ('cogs', 'opex', 'cash', 'tax')),
  balance_kind   text NOT NULL CHECK (balance_kind IN ('FLOW', 'BALANCE')),   -- FLOW = during the month; BALANCE = at month end
  allow_negative boolean NOT NULL DEFAULT false,
  sort           int NOT NULL,
  active         boolean NOT NULL DEFAULT true
);
ALTER TABLE f360_board.close_accounts ENABLE ROW LEVEL SECURITY;
INSERT INTO f360_board.close_accounts (account_key, label, component, balance_kind, allow_negative, sort) VALUES
  ('cogs',           'Costo de lo vendido del mes (COGS)',          'cogs', 'FLOW',    false, 10),
  ('opex_rent',      'Renta de tiendas y oficina',                  'opex', 'FLOW',    false, 20),
  ('opex_payroll',   'Nómina y honorarios',                         'opex', 'FLOW',    false, 21),
  ('opex_tech',      'Tecnología y software',                       'opex', 'FLOW',    false, 22),
  ('opex_logistics', 'Envíos y logística',                          'opex', 'FLOW',    false, 23),
  ('opex_other',     'Otros gastos de operación',                   'opex', 'FLOW',    false, 24),
  ('cash_bank',      'Saldo en bancos al cierre',                   'cash', 'BALANCE', true,  30),
  ('cash_on_hand',   'Efectivo en tiendas al cierre',               'cash', 'BALANCE', false, 31),
  ('tax_paid',       'Impuestos pagados en el mes (si aplica)',     'tax',  'FLOW',    false, 40);

-- ══ 4 · Monthly close entries (void + new; who captured, who approved) ══════
CREATE TABLE f360_board.monthly_close_entries (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id          uuid NOT NULL REFERENCES f360_board.fiscal_periods(id),
  account_key        text NOT NULL REFERENCES f360_board.close_accounts(account_key),
  dimension_key      text NOT NULL DEFAULT '' CHECK (dimension_key ~ '^[a-z0-9_:-]*$'),  -- e.g. a bank account alias; '' = total
  amount             numeric(14,2) NOT NULL,
  currency           text NOT NULL REFERENCES f360.currencies(code),
  source             text NOT NULL CHECK (length(btrim(source)) >= 3),   -- "estado de cuenta BBVA sep", "factura proveedor X"
  evidence_ref       text,                                               -- document reference (private bucket comes in SB6)
  note               text,
  status             text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'voided')),
  captured_by        uuid NOT NULL,
  captured_by_name   text NOT NULL,
  captured_at        timestamptz NOT NULL DEFAULT now(),
  approved_by        uuid,
  approved_by_name   text,
  approved_at        timestamptz,
  void_reason        text,
  voided_by          uuid,
  voided_at          timestamptz,
  idempotency_key    uuid NOT NULL UNIQUE,
  CHECK (approved_by IS NULL OR approved_by <> captured_by),
  CHECK ((status = 'voided') = (voided_at IS NOT NULL AND void_reason IS NOT NULL))
);
ALTER TABLE f360_board.monthly_close_entries ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX monthly_close_entries_one_active ON f360_board.monthly_close_entries (period_id, account_key, dimension_key, currency) WHERE status = 'active';

CREATE TABLE f360_board.monthly_close_log (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  entry_id   uuid NOT NULL,
  period_id  uuid NOT NULL,
  action     text NOT NULL CHECK (action IN ('capture', 'approve', 'void')),
  by_user    uuid,
  by_name    text NOT NULL,
  snapshot   jsonb NOT NULL
);
ALTER TABLE f360_board.monthly_close_log ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER monthly_close_log_append_only BEFORE UPDATE OR DELETE ON f360_board.monthly_close_log
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Entries: insert/void only while the month is OPEN/REOPENED; approve only before CLOSED; amounts never edited; no DELETE.
CREATE FUNCTION f360_board.on_close_entry() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE p f360_board.fiscal_periods; act text;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Este historial no se puede modificar (f360_board.monthly_close_entries)'; END IF;
  SELECT * INTO p FROM f360_board.fiscal_periods WHERE id = NEW.period_id;
  IF p.kind <> 'MONTH' THEN RAISE EXCEPTION 'El cierre se captura por mes.'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'active' OR NEW.approved_by IS NOT NULL THEN RAISE EXCEPTION 'Una captura nueva nace activa y sin aprobar.'; END IF;
    IF p.status NOT IN ('OPEN', 'REOPENED') THEN RAISE EXCEPTION 'El mes está en revisión o cerrado: para cambiarlo hay que regresarlo o reabrirlo.'; END IF;
    act := 'capture';
  ELSE
    IF (NEW.id, NEW.period_id, NEW.account_key, NEW.dimension_key, NEW.amount, NEW.currency, NEW.source, NEW.evidence_ref, NEW.note,
        NEW.captured_by, NEW.captured_by_name, NEW.captured_at, NEW.idempotency_key)
       IS DISTINCT FROM (OLD.id, OLD.period_id, OLD.account_key, OLD.dimension_key, OLD.amount, OLD.currency, OLD.source, OLD.evidence_ref, OLD.note,
        OLD.captured_by, OLD.captured_by_name, OLD.captured_at, OLD.idempotency_key) THEN
      RAISE EXCEPTION 'Un monto capturado no se edita: anúlalo y captura uno nuevo.';
    END IF;
    IF OLD.status = 'voided' THEN RAISE EXCEPTION 'Una captura anulada no cambia.'; END IF;
    IF NEW.status = 'voided' THEN
      IF p.status NOT IN ('OPEN', 'REOPENED') THEN RAISE EXCEPTION 'El mes está en revisión o cerrado: para anular hay que regresarlo o reabrirlo.'; END IF;
      IF (NEW.approved_by, NEW.approved_at) IS DISTINCT FROM (OLD.approved_by, OLD.approved_at) THEN RAISE EXCEPTION 'Anular y aprobar son pasos distintos.'; END IF;
      act := 'void';
    ELSIF OLD.approved_by IS NULL AND NEW.approved_by IS NOT NULL THEN
      IF p.status = 'CLOSED' THEN RAISE EXCEPTION 'El mes está cerrado.'; END IF;
      act := 'approve';
    ELSE
      RAISE EXCEPTION 'Cambio no permitido en una captura de cierre.';
    END IF;
  END IF;
  INSERT INTO f360_board.monthly_close_log (entry_id, period_id, action, by_user, by_name, snapshot)
    VALUES (NEW.id, NEW.period_id, act, auth.uid(),
            CASE WHEN auth.uid() IS NULL THEN 'sistema (' || current_user || ')' ELSE f360_board.member_name(auth.uid()) END, to_jsonb(NEW));
  RETURN NEW;
END $$;
CREATE TRIGGER monthly_close_entries_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.monthly_close_entries
  FOR EACH ROW EXECUTE FUNCTION f360_board.on_close_entry();

-- ══ 5 · Close snapshots (append-only) ════════════════════════════════════════
CREATE TABLE f360_board.close_actual_snapshots (
  period_id      uuid NOT NULL REFERENCES f360_board.fiscal_periods(id),
  close_version  int NOT NULL CHECK (close_version >= 1),
  taken_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  taken_by       uuid,
  taken_by_name  text NOT NULL,
  approved_by    uuid,            -- the member who closed
  prepared_by    uuid,            -- the member who sent it to review
  payload        jsonb NOT NULL,  -- readiness per component + entry totals by account/currency
  content_hash   text NOT NULL,
  PRIMARY KEY (period_id, close_version)
);
ALTER TABLE f360_board.close_actual_snapshots ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER close_actual_snapshots_append_only BEFORE UPDATE OR DELETE ON f360_board.close_actual_snapshots
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ══ 6 · Metric catalog (one vocabulary; availability as audited 2026-10-08, 02_CEO_COCKPIT.md §2) ══
CREATE TABLE f360_board.metric_catalog (
  metric_key           text PRIMARY KEY CHECK (metric_key ~ '^[a-z][a-z0-9_]*$'),
  label                text NOT NULL,
  definition           text NOT NULL,
  unit                 text NOT NULL CHECK (unit IN ('money', 'count', 'ratio', 'pct', 'units')),
  source_kind          text NOT NULL CHECK (source_kind IN ('G1', 'CLOSE', 'DERIVED', 'GROWTH', 'LEDGER', 'CRM')),
  source_ref           text NOT NULL,
  depends_on           text[] NOT NULL DEFAULT '{}',
  availability         text NOT NULL CHECK (availability IN ('AVAILABLE', 'PARTIAL', 'MISSING')),
  availability_reason  text NOT NULL,
  sort                 int NOT NULL
);
ALTER TABLE f360_board.metric_catalog ENABLE ROW LEVEL SECURITY;
INSERT INTO f360_board.metric_catalog (metric_key, label, definition, unit, source_kind, source_ref, depends_on, availability, availability_reason, sort) VALUES
 ('revenue_net_product', 'Venta neta de producto', 'Producto cobrado − cupones − reembolsos de producto, pedidos countable, en moneda original. IVA no separado (D4 / definición de ingresos de S-G0).', 'money', 'G1', 'f360.commerce_orders.net_product + f360.historical_sales_active', ARRAY['revenue definitions (S-G0)'], 'PARTIAL', 'Ventas legacy de public.offline_sales fuera de G1; salud del canal de producción invisible (C5/F9).', 10),
 ('revenue_gross_product', 'Venta bruta de producto', 'Subtotal de producto antes de cupones (Woo items_subtotal; tienda line_total).', 'money', 'G1', 'f360.commerce_orders.product_gross', ARRAY['revenue definitions (S-G0)'], 'PARTIAL', 'Mismos huecos que la venta neta.', 11),
 ('orders', 'Pedidos', 'Pedidos countable (online + tienda). Los resúmenes históricos no tienen número de pedidos.', 'count', 'G1', 'f360.commerce_orders', '{}', 'AVAILABLE', 'Medido en G1.', 20),
 ('aov', 'Ticket promedio', 'Venta neta de producto ÷ pedidos, por moneda.', 'money', 'DERIVED', 'revenue_net_product / orders', '{}', 'PARTIAL', 'Hereda los huecos de la venta.', 21),
 ('units', 'Pares vendidos', 'Unidades de producto en pedidos countable + pares de resúmenes históricos.', 'units', 'G1', 'f360.commerce_order_lines + f360.historical_sales_active', '{}', 'PARTIAL', 'Hereda los huecos de la venta.', 22),
 ('new_customers', 'Clientas nuevas', 'Primera compra identificada en el periodo.', 'count', 'CRM', 'f360.commerce_orders.loyalty_customer_id/woo_customer_id', '{}', 'PARTIAL', 'Pedidos invitados sin identidad.', 30),
 ('repeat_customers', 'Clientas recurrentes', 'Clientas identificadas con ≥ 2 pedidos countable en la ventana.', 'count', 'CRM', 'f360.commerce_orders', '{}', 'PARTIAL', 'Depende de identidad.', 31),
 ('repeat_rate', 'Tasa de recompra', 'Recurrentes ÷ compradoras identificadas (denominador explícito).', 'pct', 'DERIVED', 'repeat_customers / identified buyers', '{}', 'PARTIAL', 'Depende de identidad.', 32),
 ('cogs', 'Costo de lo vendido', 'Costo de producto de lo vendido. Hoy solo por captura de cierre (cuenta cogs); calculado cuando exista costo unitario.', 'money', 'CLOSE', 'f360_board.monthly_close_entries[cogs]', ARRAY['f360.product_cost_versions (S-G0)'], 'MISSING', 'No hay costo en ninguna tabla; sin capturas de cierre.', 40),
 ('gross_profit', 'Utilidad bruta', 'Venta neta de producto − COGS, mismo mes y moneda.', 'money', 'DERIVED', 'revenue_net_product − cogs', '{}', 'MISSING', 'Requiere COGS.', 41),
 ('gross_margin', 'Margen bruto', 'Utilidad bruta ÷ venta neta de producto.', 'pct', 'DERIVED', 'gross_profit / revenue_net_product', '{}', 'MISSING', 'Requiere COGS.', 42),
 ('opex', 'Gastos de operación', 'Suma de cuentas opex_* del cierre del mes.', 'money', 'CLOSE', 'f360_board.monthly_close_entries[opex_*]', '{}', 'MISSING', 'Sin capturas de cierre.', 50),
 ('ebitda', 'EBITDA', 'Utilidad bruta − OPEX; solo si ambos del mismo mes están cerrados.', 'money', 'DERIVED', 'gross_profit − opex', '{}', 'MISSING', 'Requiere COGS y OPEX.', 51),
 ('cash', 'Caja', 'Saldos de caja/bancos al cierre por moneda (cuentas cash_*).', 'money', 'CLOSE', 'f360_board.monthly_close_entries[cash_*]', '{}', 'MISSING', 'Sin capturas de cierre.', 60),
 ('inventory_units', 'Inventario en pares', 'Pares en ubicaciones vendibles/bodega, sin tránsito.', 'units', 'LEDGER', 'f360.inventory_balances', '{}', 'AVAILABLE', 'Ledger F360 (saldo vivo, no foto de fin de mes).', 70),
 ('inventory_value_cost', 'Inventario a costo', 'Pares × costo unitario vigente.', 'money', 'DERIVED', 'inventory_units × unit cost', ARRAY['f360.product_cost_versions (S-G0)'], 'MISSING', 'Sin costo unitario.', 71),
 ('inventory_value_retail', 'Inventario a precio de venta', 'Pares × precio de venta (NO es costo).', 'money', 'LEDGER', 'f360.inventory_balances × f360.products.regular_price', '{}', 'AVAILABLE', 'Igual que el panel ejecutivo (rótulo "a precio de venta").', 72),
 ('marketing_spend', 'Gasto de marketing', 'Gasto pagado por canal.', 'money', 'GROWTH', 'marketing spend facts (S-G0)', ARRAY['marketing spend (S-G0)'], 'MISSING', 'Lo publica S-G0; Strategy no lo captura (una sola fuente).', 80),
 ('cac_blended', 'CAC combinado', 'Gasto de marketing ÷ clientas nuevas del periodo.', 'money', 'DERIVED', 'marketing_spend / new_customers', ARRAY['marketing spend (S-G0)'], 'MISSING', 'Requiere gasto.', 81),
 ('roas', 'ROAS', 'Venta atribuida first-party ÷ gasto pagado (nunca el ROAS de la plataforma).', 'ratio', 'DERIVED', 'attributed revenue / paid spend', ARRAY['marketing spend (S-G0)', 'measurement health (S-G0)'], 'MISSING', 'Requiere gasto y atribución.', 82),
 ('mer', 'MER', 'Venta total ÷ gasto de marketing total.', 'ratio', 'DERIVED', 'revenue_net_product / marketing_spend', ARRAY['marketing spend (S-G0)'], 'MISSING', 'Requiere gasto.', 83),
 ('tax_paid', 'Impuestos pagados', 'Impuestos pagados del mes (si aplica), captura de cierre.', 'money', 'CLOSE', 'f360_board.monthly_close_entries[tax_paid]', '{}', 'MISSING', 'Sin capturas de cierre.', 90);

-- ══ 7 · Budget & forecast foundation (versioned; frozen once approved/published) ══
CREATE TABLE f360_board.budget_versions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key       text NOT NULL REFERENCES f360_board.reporting_entities(key),
  fiscal_year      int NOT NULL CHECK (fiscal_year BETWEEN 2024 AND 2100),
  name             text NOT NULL,
  number_class     text NOT NULL DEFAULT 'BUDGET' CHECK (number_class = 'BUDGET'),
  status           text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'APPROVED', 'SUPERSEDED')),
  supersedes_id    uuid REFERENCES f360_board.budget_versions(id),
  decision_id      uuid,                      -- FK added with the decision log (20261015000300)
  created_by       uuid, created_by_name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  approved_at      timestamptz, approved_by uuid[],
  content_hash     text
);
CREATE TABLE f360_board.budget_lines (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id       uuid NOT NULL REFERENCES f360_board.budget_versions(id),
  period_month     date NOT NULL CHECK (period_month = date_trunc('month', period_month)::date),
  metric_key       text NOT NULL REFERENCES f360_board.metric_catalog(metric_key),
  dim_market       text CHECK (dim_market IN ('MX', 'CO', 'ROW')),
  dim_channel      text CHECK (dim_channel IN ('online', 'store', 'historical_summary')),
  dim_location_id  uuid REFERENCES f360.locations(id),
  dim_category_key text REFERENCES f360.categories(key),
  currency         text NOT NULL REFERENCES f360.currencies(code),
  amount           numeric(14,2) NOT NULL,
  note             text
);
CREATE TABLE f360_board.forecast_versions (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_key              text NOT NULL REFERENCES f360_board.reporting_entities(key),
  name                    text NOT NULL,
  number_class            text NOT NULL DEFAULT 'FORECAST' CHECK (number_class = 'FORECAST'),
  window_start            date NOT NULL CHECK (window_start = date_trunc('month', window_start)::date),
  horizon_months          int NOT NULL DEFAULT 18 CHECK (horizon_months BETWEEN 1 AND 60),
  status                  text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'SUPERSEDED')),
  based_on_close_version  int,
  supersedes_id           uuid REFERENCES f360_board.forecast_versions(id),
  created_by uuid, created_by_name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz, published_by uuid,
  content_hash            text
);
CREATE TABLE f360_board.forecast_lines (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id       uuid NOT NULL REFERENCES f360_board.forecast_versions(id),
  period_month     date NOT NULL CHECK (period_month = date_trunc('month', period_month)::date),
  metric_key       text NOT NULL REFERENCES f360_board.metric_catalog(metric_key),
  method           text NOT NULL CHECK (method IN ('ECOM_FUNNEL', 'PAID_ACQ', 'RETAIL_TX', 'CUSTOMER_BASE', 'MANUAL', 'INVENTORY_CHAIN')),
  role             text NOT NULL DEFAULT 'total' CHECK (role IN ('total', 'decomposition')),
  dim_market       text CHECK (dim_market IN ('MX', 'CO', 'ROW')),
  dim_channel      text CHECK (dim_channel IN ('online', 'store', 'historical_summary')),
  dim_location_id  uuid REFERENCES f360.locations(id),
  dim_category_key text REFERENCES f360.categories(key),
  currency         text NOT NULL REFERENCES f360.currencies(code),
  amount           numeric(14,2),
  drivers          jsonb NOT NULL DEFAULT '{}',
  note             text,
  CHECK (method <> 'MANUAL' OR length(btrim(coalesce(note, ''))) > 0)
);
CREATE TABLE f360_board.forecast_snapshots (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  version_id    uuid NOT NULL REFERENCES f360_board.forecast_versions(id),
  taken_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  reason        text NOT NULL,
  payload       jsonb NOT NULL,
  content_hash  text NOT NULL
);
ALTER TABLE f360_board.budget_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.budget_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.forecast_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.forecast_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360_board.forecast_snapshots ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER forecast_snapshots_append_only BEFORE UPDATE OR DELETE ON f360_board.forecast_snapshots
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Versions: content is frozen outside DRAFT; only forward status moves; only DRAFT versions may be deleted.
CREATE FUNCTION f360_board.on_version_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE frozen text := CASE TG_TABLE_NAME WHEN 'budget_versions' THEN 'APPROVED' ELSE 'PUBLISHED' END;
  o jsonb := to_jsonb(OLD); n jsonb; lines jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN RAISE EXCEPTION 'Una versión % no se borra.', OLD.status; END IF;
    RETURN OLD;
  END IF;
  n := to_jsonb(NEW);
  IF OLD.status <> 'DRAFT' THEN
    -- only allowed: frozen → SUPERSEDED, nothing else changes
    IF NOT (OLD.status = frozen AND NEW.status = 'SUPERSEDED' AND (o - 'status') = (n - 'status')) THEN
      RAISE EXCEPTION 'Esta versión ya está %: no se modifica (crea una versión nueva).', OLD.status;
    END IF;
  ELSIF NEW.status NOT IN ('DRAFT', frozen) THEN
    RAISE EXCEPTION 'Un borrador solo puede pasar a %.', frozen;
  ELSIF NEW.status = frozen THEN
    IF TG_TABLE_NAME = 'budget_versions' THEN
      SELECT coalesce(jsonb_agg(to_jsonb(l) - 'id' ORDER BY l.period_month, l.metric_key, l.currency, l.id), '[]') INTO lines FROM f360_board.budget_lines l WHERE l.version_id = NEW.id;
      NEW.content_hash := encode(extensions.digest(lines::text, 'sha256'), 'hex');
    ELSE
      SELECT coalesce(jsonb_agg(to_jsonb(l) - 'id' ORDER BY l.period_month, l.metric_key, l.currency, l.id), '[]') INTO lines FROM f360_board.forecast_lines l WHERE l.version_id = NEW.id;
      NEW.content_hash := encode(extensions.digest(lines::text, 'sha256'), 'hex');
      INSERT INTO f360_board.forecast_snapshots (version_id, reason, payload, content_hash)
        VALUES (NEW.id, 'publish', jsonb_build_object('version', to_jsonb(NEW) - 'content_hash', 'lines', lines), NEW.content_hash);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER budget_versions_guard BEFORE UPDATE OR DELETE ON f360_board.budget_versions FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_change();
CREATE TRIGGER forecast_versions_guard BEFORE UPDATE OR DELETE ON f360_board.forecast_versions FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_change();

-- Lines: only while the parent version is DRAFT.
CREATE FUNCTION f360_board.on_version_line_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE st text; vid uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.version_id ELSE NEW.version_id END;
BEGIN
  IF TG_TABLE_NAME = 'budget_lines' THEN SELECT status INTO st FROM f360_board.budget_versions WHERE id = vid;
  ELSE SELECT status INTO st FROM f360_board.forecast_versions WHERE id = vid; END IF;
  IF st IS DISTINCT FROM 'DRAFT' THEN RAISE EXCEPTION 'La versión está %: sus líneas no se modifican.', st; END IF;
  IF TG_OP = 'UPDATE' AND NEW.version_id <> OLD.version_id THEN RAISE EXCEPTION 'Una línea no cambia de versión.'; END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER budget_lines_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.budget_lines FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_line_change();
CREATE TRIGGER forecast_lines_guard BEFORE INSERT OR UPDATE OR DELETE ON f360_board.forecast_lines FOR EACH ROW EXECUTE FUNCTION f360_board.on_version_line_change();

-- ══ 8 · Close readiness (what a close consolidates; missing source → DATA_INCOMPLETE, never a number) ══
CREATE FUNCTION f360_board.close_readiness(p_period_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE opex_n int; has_cogs boolean; has_cash boolean; has_tax boolean;
BEGIN
  SELECT count(DISTINCT e.account_key) FILTER (WHERE a.component = 'opex'), bool_or(a.component = 'cogs'), bool_or(a.component = 'cash'), bool_or(a.component = 'tax')
    INTO opex_n, has_cogs, has_cash, has_tax
    FROM f360_board.monthly_close_entries e JOIN f360_board.close_accounts a USING (account_key)
    WHERE e.period_id = p_period_id AND e.status = 'active';
  RETURN jsonb_build_array(
    jsonb_build_object('component', 'sales', 'status', 'DATA_INCOMPLETE', 'source', 'G1 Commerce Facts + historical_sales (SB1)',
                       'reason', 'Aún no conectado (SB1). Definición de ingresos: S-G0 / D4.'),
    jsonb_build_object('component', 'cogs', 'status', CASE WHEN coalesce(has_cogs, false) THEN 'AVAILABLE' ELSE 'DATA_INCOMPLETE' END,
                       'source', 'Captura de cierre (cogs); costo unitario de S-G0 cuando exista', 'reason', CASE WHEN coalesce(has_cogs, false) THEN NULL ELSE 'Sin captura de COGS.' END),
    jsonb_build_object('component', 'gross_profit', 'status', 'DATA_INCOMPLETE', 'source', 'Derivado: ventas − COGS', 'reason', 'Requiere ventas conectadas (SB1) y COGS.'),
    jsonb_build_object('component', 'opex', 'status', CASE WHEN coalesce(opex_n, 0) = 0 THEN 'DATA_INCOMPLETE' WHEN opex_n < (SELECT count(*) FROM f360_board.close_accounts WHERE component = 'opex' AND active) THEN 'PARTIAL' ELSE 'AVAILABLE' END,
                       'source', 'Captura de cierre (opex_*)', 'captured_categories', coalesce(opex_n, 0),
                       'reason', CASE WHEN coalesce(opex_n, 0) = 0 THEN 'Sin capturas de OPEX.' END),
    jsonb_build_object('component', 'marketing_spend', 'status', 'DATA_INCOMPLETE', 'source', 'Gasto de marketing de S-G0', 'reason', 'Lo publica S-G0; aún no conectado.'),
    jsonb_build_object('component', 'cash', 'status', CASE WHEN coalesce(has_cash, false) THEN 'AVAILABLE' ELSE 'DATA_INCOMPLETE' END,
                       'source', 'Captura de cierre (cash_*)', 'reason', CASE WHEN coalesce(has_cash, false) THEN NULL ELSE 'Sin saldo de caja.' END),
    jsonb_build_object('component', 'inventory', 'status', 'DATA_INCOMPLETE', 'source', 'Ledger F360 (pares) + costo S-G0',
                       'reason', 'Foto de inventario a fin de mes aún no conectada (SB1); valor a costo requiere costo unitario.'),
    jsonb_build_object('component', 'tax', 'status', CASE WHEN coalesce(has_tax, false) THEN 'AVAILABLE' ELSE 'DATA_INCOMPLETE' END,
                       'source', 'Captura de cierre (tax_paid), si aplica', 'reason', CASE WHEN coalesce(has_tax, false) THEN NULL ELSE 'Sin captura (si aplica).' END));
END $$;

-- ══ 9 · Public RPCs (FINANCIAL scope) ════════════════════════════════════════
-- Periods of a fiscal year with month statuses and the quarter/year roll-up.
CREATE FUNCTION public.f360_board_periods(p_year int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE y int := coalesce(p_year, extract(year FROM (now() AT TIME ZONE 'America/Mexico_City'))::int);
  uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_periods', y::text);
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'fiscal_year', y, 'rule', 'Año fiscal calendario: 1 de enero → 31 de diciembre (D11).',
    'months', coalesce((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'month', p.period_no, 'start', p.period_start, 'end', p.period_end,
               'status', p.status, 'close_version', p.close_version, 'exception_note', p.exception_note,
               'entries', (SELECT count(*) FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id AND e.status = 'active'),
               'pending_approval', (SELECT count(*) FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id AND e.status = 'active' AND e.approved_by IS NULL))
             ORDER BY p.period_no) FROM f360_board.fiscal_periods p WHERE p.entity_key = 'fuxia' AND p.kind = 'MONTH' AND p.fiscal_year = y), '[]'),
    'rollups', coalesce((SELECT jsonb_agg(jsonb_build_object('kind', r.kind, 'no', r.period_no, 'start', r.period_start, 'end', r.period_end,
               'months_closed', (SELECT count(*) FROM f360_board.fiscal_periods m WHERE m.entity_key = r.entity_key AND m.kind = 'MONTH' AND m.period_start BETWEEN r.period_start AND r.period_end AND m.status = 'CLOSED'),
               'months_total', (SELECT count(*) FROM f360_board.fiscal_periods m WHERE m.entity_key = r.entity_key AND m.kind = 'MONTH' AND m.period_start BETWEEN r.period_start AND r.period_end),
               'status', CASE WHEN NOT EXISTS (SELECT 1 FROM f360_board.fiscal_periods m WHERE m.entity_key = r.entity_key AND m.kind = 'MONTH' AND m.period_start BETWEEN r.period_start AND r.period_end AND m.status <> 'CLOSED') THEN 'CLOSED' ELSE 'OPEN' END)
             ORDER BY r.kind DESC, r.period_no) FROM f360_board.fiscal_periods r WHERE r.entity_key = 'fuxia' AND r.kind IN ('QUARTER', 'YEAR') AND r.fiscal_year = y), '[]'));
END $$;

-- One month's close: entries (with who captured/approved), readiness, history, snapshots.
CREATE FUNCTION public.f360_board_close_get(p_period_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_get', p_period_id::text); p f360_board.fiscal_periods;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO p FROM f360_board.fiscal_periods WHERE id = p_period_id AND kind = 'MONTH';
  IF p.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Mes no encontrado.'); END IF;
  RETURN jsonb_build_object('ok', true,
    'period', jsonb_build_object('id', p.id, 'year', p.fiscal_year, 'month', p.period_no, 'start', p.period_start, 'end', p.period_end, 'status', p.status,
                                 'close_version', p.close_version, 'submitted_by', f360_board.member_name(p.submitted_by), 'submitted_by_me', p.submitted_by = uid,
                                 'exception_note', p.exception_note),
    'accounts', (SELECT jsonb_agg(jsonb_build_object('key', a.account_key, 'label', a.label, 'component', a.component, 'balance_kind', a.balance_kind, 'allow_negative', a.allow_negative) ORDER BY a.sort)
                 FROM f360_board.close_accounts a WHERE a.active),
    'currencies', (SELECT jsonb_agg(code ORDER BY code) FROM f360.currencies),
    'entries', coalesce((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'account_key', e.account_key, 'dimension_key', e.dimension_key, 'amount', e.amount, 'currency', e.currency,
                 'source', e.source, 'evidence_ref', e.evidence_ref, 'note', e.note, 'status', e.status,
                 'captured_by', e.captured_by_name, 'captured_by_me', e.captured_by = uid, 'captured_at', e.captured_at,
                 'approved_by', e.approved_by_name, 'approved_at', e.approved_at, 'void_reason', e.void_reason, 'voided_at', e.voided_at)
                 ORDER BY e.status, e.captured_at) FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id), '[]'),
    'readiness', f360_board.close_readiness(p.id),
    'events', coalesce((SELECT jsonb_agg(jsonb_build_object('at', v.at, 'from', v.from_status, 'to', v.to_status, 'version', v.close_version, 'by', v.by_name, 'reason', v.reason) ORDER BY v.id)
                 FROM f360_board.fiscal_period_events v WHERE v.period_id = p.id), '[]'),
    'snapshots', coalesce((SELECT jsonb_agg(jsonb_build_object('version', s.close_version, 'taken_at', s.taken_at, 'by', s.taken_by_name, 'hash', s.content_hash) ORDER BY s.close_version)
                 FROM f360_board.close_actual_snapshots s WHERE s.period_id = p.id), '[]'));
END $$;

-- Capture one manual close amount (sensitive write; idempotent by key; server validates account, currency, sign, state).
CREATE FUNCTION public.f360_board_close_entry_add(p_idempotency_key uuid, p_period_id uuid, p_account_key text, p_amount numeric,
  p_currency text, p_source text, p_evidence_ref text DEFAULT NULL, p_note text DEFAULT NULL, p_dimension_key text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_entry_add', p_period_id::text,
    jsonb_build_object('k', p_idempotency_key, 'a', p_account_key, 'amt', p_amount, 'c', p_currency));
  a f360_board.close_accounts; e f360_board.monthly_close_entries;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Falta la llave de idempotencia.'); END IF;
  SELECT * INTO e FROM f360_board.monthly_close_entries WHERE idempotency_key = p_idempotency_key;
  IF e.id IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'replayed', true, 'id', e.id); END IF;
  SELECT * INTO a FROM f360_board.close_accounts WHERE account_key = p_account_key AND active;
  IF a.account_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Cuenta de cierre no válida.'); END IF;
  IF p_amount IS NULL OR (p_amount < 0 AND NOT a.allow_negative) OR p_amount <> round(p_amount, 2) OR abs(p_amount) >= 1e12 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Monto no válido.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.currencies WHERE code = p_currency) THEN RETURN jsonb_build_object('ok', false, 'error', 'Moneda no válida.'); END IF;
  IF length(btrim(coalesce(p_source, ''))) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Indica la fuente (p. ej. "estado de cuenta BBVA").'); END IF;
  BEGIN
    INSERT INTO f360_board.monthly_close_entries (period_id, account_key, dimension_key, amount, currency, source, evidence_ref, note,
                                                  captured_by, captured_by_name, idempotency_key)
      VALUES (p_period_id, a.account_key, lower(coalesce(p_dimension_key, '')), p_amount, p_currency, btrim(p_source), nullif(btrim(p_evidence_ref), ''),
              nullif(btrim(p_note), ''), uid, f360_board.member_name(uid), p_idempotency_key)
      RETURNING * INTO e;
  EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Ya hay un monto activo para esa cuenta y moneda: anúlalo primero.');
    WHEN foreign_key_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'Mes no encontrado.');
    WHEN raise_exception OR check_violation THEN RETURN jsonb_build_object('ok', false, 'error', 'No se pudo guardar: ' || SQLERRM);
  END;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_close_entry_add', e.id::text, jsonb_build_object('period', p_period_id, 'account', a.account_key));
  RETURN jsonb_build_object('ok', true, 'id', e.id);
END $$;

-- Void a capture (correction = void + new). Reason required.
CREATE FUNCTION public.f360_board_close_entry_void(p_entry_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_entry_void', p_entry_id::text);
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica por qué se anula.'); END IF;
  BEGIN
    UPDATE f360_board.monthly_close_entries SET status = 'voided', void_reason = btrim(p_reason), voided_by = uid, voided_at = now()
      WHERE id = p_entry_id AND status = 'active';
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'Captura no encontrada o ya anulada.'); END IF;
  EXCEPTION WHEN raise_exception THEN RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_close_entry_void', p_entry_id::text);
  RETURN jsonb_build_object('ok', true);
END $$;

-- Approve every pending capture of the month that the caller did NOT capture (who captures ≠ who approves).
CREATE FUNCTION public.f360_board_close_entries_approve(p_period_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_close_entries_approve', p_period_id::text); n int; own int;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  BEGIN
    UPDATE f360_board.monthly_close_entries SET approved_by = uid, approved_by_name = f360_board.member_name(uid), approved_at = now()
      WHERE period_id = p_period_id AND status = 'active' AND approved_by IS NULL AND captured_by <> uid;
    GET DIAGNOSTICS n = ROW_COUNT;
  EXCEPTION WHEN raise_exception THEN RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
  SELECT count(*) INTO own FROM f360_board.monthly_close_entries WHERE period_id = p_period_id AND status = 'active' AND approved_by IS NULL AND captured_by = uid;
  IF n > 0 THEN PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_close_entries_approve', p_period_id::text, jsonb_build_object('approved', n)); END IF;
  RETURN jsonb_build_object('ok', true, 'approved', n, 'pending_own', own,
    'note', CASE WHEN own > 0 THEN 'Tus propias capturas las aprueba otra persona del consejo.' END);
END $$;

-- Move a month along OPEN → UNDER_REVIEW → CLOSED (→ REOPENED → UNDER_REVIEW …). Closing freezes a snapshot.
CREATE FUNCTION public.f360_board_period_transition(p_period_id uuid, p_to_status text, p_reason text DEFAULT NULL, p_exception_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_period_transition', p_period_id::text, jsonb_build_object('to', p_to_status));
  p f360_board.fiscal_periods; s f360_board.settings; ready jsonb; incomplete int; totals jsonb; payload jsonb; pending int;
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  SELECT * INTO s FROM f360_board.settings WHERE id;
  SELECT * INTO p FROM f360_board.fiscal_periods WHERE id = p_period_id AND kind = 'MONTH' FOR UPDATE;
  IF p.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Mes no encontrado.'); END IF;
  IF p_to_status = 'REOPENED' AND length(btrim(coalesce(p_reason, ''))) < 10 THEN RETURN jsonb_build_object('ok', false, 'error', 'Reabrir un mes cerrado requiere un motivo claro.'); END IF;
  IF p_to_status = 'OPEN' AND length(btrim(coalesce(p_reason, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Explica qué falta corregir.'); END IF;
  IF p_to_status = 'CLOSED' THEN
    IF p.status <> 'UNDER_REVIEW' THEN RETURN jsonb_build_object('ok', false, 'error', 'Primero hay que mandar el mes a revisión.'); END IF;
    IF s.close_requires_second_member AND p.submitted_by = uid THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Otra persona del consejo debe aprobar el cierre.');
    END IF;
    SELECT count(*) INTO pending FROM f360_board.monthly_close_entries WHERE period_id = p.id AND status = 'active' AND approved_by IS NULL;
    IF pending > 0 THEN RETURN jsonb_build_object('ok', false, 'error', format('Hay %s capturas sin aprobar.', pending)); END IF;
    ready := f360_board.close_readiness(p.id);
    SELECT count(*) INTO incomplete FROM jsonb_array_elements(ready) x WHERE x->>'status' <> 'AVAILABLE';
    IF incomplete > 0 AND length(btrim(coalesce(p_exception_note, ''))) < 10 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Faltan datos (DATA INCOMPLETE): para cerrar así, escribe la excepción.', 'readiness', ready);
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('account', account_key, 'currency', currency, 'amount', total) ORDER BY account_key, currency), '[]') INTO totals
      FROM (SELECT account_key, currency, sum(amount) total FROM f360_board.monthly_close_entries WHERE period_id = p.id AND status = 'active' GROUP BY 1, 2) t;
    payload := jsonb_build_object('period', jsonb_build_object('year', p.fiscal_year, 'month', p.period_no), 'close_version', p.close_version + 1,
      'readiness', ready, 'entry_totals', totals, 'exception_note', nullif(btrim(p_exception_note), ''),
      'entries', (SELECT coalesce(jsonb_agg(to_jsonb(e) - 'idempotency_key' ORDER BY e.id), '[]') FROM f360_board.monthly_close_entries e WHERE e.period_id = p.id AND e.status = 'active'));
  END IF;
  PERFORM set_config('f360_board.reason', coalesce(btrim(p_reason), ''), true);
  BEGIN
    UPDATE f360_board.fiscal_periods SET status = p_to_status,
        close_version = CASE WHEN p_to_status = 'CLOSED' THEN close_version + 1 ELSE close_version END,
        submitted_by = CASE WHEN p_to_status = 'UNDER_REVIEW' THEN uid ELSE submitted_by END,
        exception_note = CASE WHEN p_to_status = 'CLOSED' THEN nullif(btrim(p_exception_note), '') ELSE exception_note END,
        status_changed_at = now(), status_changed_by = uid
      WHERE id = p.id;
  EXCEPTION WHEN raise_exception OR check_violation THEN RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;
  PERFORM set_config('f360_board.reason', '', true);
  IF p_to_status = 'CLOSED' THEN   -- after the status change succeeded: the frozen photo of this close version
    INSERT INTO f360_board.close_actual_snapshots (period_id, close_version, taken_by, taken_by_name, approved_by, prepared_by, payload, content_hash)
      VALUES (p.id, p.close_version + 1, uid, f360_board.member_name(uid), uid, p.submitted_by, payload, encode(extensions.digest(payload::text, 'sha256'), 'hex'));
  END IF;
  PERFORM f360_board.log_write(uid, 'FINANCIAL', 'f360_board_period_transition', p.id::text, jsonb_build_object('from', p.status, 'to', p_to_status));
  RETURN jsonb_build_object('ok', true, 'status', p_to_status, 'close_version', CASE WHEN p_to_status = 'CLOSED' THEN p.close_version + 1 ELSE p.close_version END);
END $$;

-- The metric vocabulary with today's availability (no values).
CREATE FUNCTION public.f360_board_metric_catalog() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360_board.require_board_member('FINANCIAL', 'f360_board_metric_catalog');
BEGIN
  IF uid IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true, 'metrics', (SELECT jsonb_agg(to_jsonb(m) - 'sort' ORDER BY m.sort) FROM f360_board.metric_catalog m));
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360_board FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_board_periods(int), public.f360_board_close_get(uuid),
  public.f360_board_close_entry_add(uuid, uuid, text, numeric, text, text, text, text, text), public.f360_board_close_entry_void(uuid, text),
  public.f360_board_close_entries_approve(uuid), public.f360_board_period_transition(uuid, text, text, text), public.f360_board_metric_catalog() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_periods(int), public.f360_board_close_get(uuid),
  public.f360_board_close_entry_add(uuid, uuid, text, numeric, text, text, text, text, text), public.f360_board_close_entry_void(uuid, text),
  public.f360_board_close_entries_approve(uuid), public.f360_board_period_transition(uuid, text, text, text), public.f360_board_metric_catalog() TO authenticated;
