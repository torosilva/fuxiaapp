# 07 · Capital & Ownership

> **Solo diseño.** Este documento **no** contiene ni presupone porcentajes, valuaciones, términos legales ni estructura societaria.
> Ningún dato se precarga. Los campos legales se llenan solo con documentos firmados y la decisión registrada.

## 1. Situación conocida (a registrar tal cual, sin interpretar)

| Hecho | Estado a registrar |
|---|---|
| Mario está **evaluando** una inversión en efectivo de MXN 500,000 | `commitment.status = EVALUATING`. **No** COMMITTED, **no** FUNDED |
| Aportación de tecnología de Mario (Fuxia 360 / plataforma) | `contribution.kind = TECHNOLOGY`, `valuation_status = PENDING_VALUATION`, `agreement_status = PENDING_AGREEMENT`, monto = **NULL** |
| Porcentaje de Mario | **Desconocido / no acordado.** No se asume 15% ni ningún otro valor. `ownership_snapshots` vacío |

No existe en el repositorio ninguna tabla de capital, socios o instrumentos (búsqueda en prod 2026-10-08: sin columnas de `cash/budget/expense…`; ningún esquema más allá de `public`, `f360` y los de Supabase).

## 2. Entidades

### 2.1 Partes y cap table
- `cap_parties`: `id`, `kind` (`PERSON`, `ENTITY`), `display_name`, `role_note`, `created_at`. Sin RFC/CURP/domicilio en esta fase (no se necesitan para el tablero; si se necesitan, van en el documento firmado, no en filas).
- `legal_entities`: `id`, `name`, `country` (MX/CO), `currency`, `notes` — decisión D7 (¿una o dos entidades?).
- `ownership_instruments`: `id`, `entity_id`, `kind` (`COMMON`, `PREFERRED`, `SAFE`, `CONVERTIBLE_NOTE`, `LOAN`, `OPTION`, `OTHER`), `terms_summary`, `document_id`, `status` (`DRAFT`, `SIGNED`, `CANCELLED`).
- `ownership_snapshots` (append-only, formal): `id`, `entity_id`, `as_of`, `holdings jsonb [{party_id, instrument_id, units, pct}]`, `basis` (`FULLY_DILUTED`, `ISSUED`), `document_id` (acta/contrato), `decision_id`, `approved_by[]`. **Solo se crea con documento firmado y decisión aprobada por ambos.** Mientras esté vacío, la pantalla dice "Cap table formal no registrado".
- `capital_rounds`: `id`, `name`, `entity_id`, `instrument_kind`, `target_amount`, `currency`, `status` (`IDEA`, `OPEN`, `CLOSED`, `CANCELLED`), `decision_id`.

### 2.2 Compromisos, aportaciones y préstamos
`capital_commitments`: `id`, `party_id`, `round_id?`, `kind` (`CASH`, `TECHNOLOGY`, `IN_KIND`, `LOAN`), `amount` (nullable), `currency`, `status`, `valuation_status`, `agreement_status`, `document_id?`, `notes`.

Estados del dinero (`status`):

| Estado | Significado |
|---|---|
| `EVALUATING` | En consideración. No cuenta en ningún total de capital |
| `COMMITTED` | Compromiso firmado/aprobado, aún sin depositar |
| `FUNDED` | Dinero recibido (evidencia: comprobante) |
| `DEPLOYED` | Parte usada (suma de `capital_deployments`) |
| `REMAINING` | Derivado = FUNDED − DEPLOYED (no se guarda) |

`capital_movements` (append-only): cada cambio de estado o monto (`from_status`, `to_status`, `amount`, `evidence_document_id`, `by`, `at`, `reason`). Los totales COMMITTED/FUNDED/DEPLOYED/REMAINING se derivan de movimientos, nunca se teclean.

### 2.3 Despliegue de capital (`capital_deployments`)

| Campo | Tipo |
|---|---|
| id | uuid |
| commitment_id | uuid (de qué dinero sale; requiere FUNDED) |
| amount, currency | numeric, text |
| date | date |
| category | `Growth`, `Inventory`, `Content`, `Technology`, `Operations`, `Working Capital`, `Store Expansion`, `Other` |
| initiative_id | FK `plan_initiatives` (opcional) |
| approved_by | uuid[] |
| expected_result | text (y opcional `expected_metric_key` + `expected_value` del catálogo del cockpit) |
| actual_result | text (+ `actual_value` leído del cockpit con `sources[]`) |
| notes | text |
| created_at / created_by | |

Corrección = movimiento inverso + nuevo registro con motivo (sin UPDATE de monto).

### 2.4 Documentos
`capital_documents` → objetos del bucket privado `board-private` (`09_INVESTOR_ROOM.md` §4). Tipos: `TERM_SHEET`, `AGREEMENT`, `RECEIPT`, `VALUATION_REPORT`, `MINUTES`, `OTHER`. Hash SHA-256 guardado; versiones nuevas no reemplazan.

## 3. Permisos

- Scope `CAP_TABLE` (ambos). Escrituras de `ownership_snapshots`, `ownership_instruments.status=SIGNED`, `capital_commitments` → `COMMITTED`/`FUNDED`: **doble aprobación** (prepara uno, aprueba el otro) — decisión D5. Conflicto de interés evidente: Mario es a la vez parte y aprobador; por eso cada cambio sobre un compromiso de Mario requiere aprobación de **Carolina** (regla propuesta, D5).
- Modo presentación oculta todo este módulo.
- Nunca visible a operator/seller/agencias/inversionistas.

## 4. Lo que la pantalla NO hace

- No calcula % de nadie a partir de montos (eso requiere valuación y términos acordados).
- No muestra "valor de la participación de Mario" (ver `10_VALUATION_TRACKER.md` §4).
- No convierte la aportación de tecnología en monto.

## 5. RPCs

`f360_board_capital_overview()` (totales derivados por estado, por categoría), `f360_board_party_*`, `f360_board_commitment_record(…)`, `f360_board_commitment_transition(id, to_status, evidence_doc, reason)`, `f360_board_commitment_approve(id)` (segundo miembro), `f360_board_deployment_record(…)`, `f360_board_deployment_result(id, actual_result…)`, `f360_board_ownership_snapshot_propose(…)`/`_approve(id)` — scope `CAP_TABLE`, todas con access log e idempotency key.
