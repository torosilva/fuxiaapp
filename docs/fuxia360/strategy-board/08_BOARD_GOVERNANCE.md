# 08 · Board Governance — Consejo, Board Pack y Decision Log

> Spec. Consejo de dos (Carolina y Mario), con la estructura para crecer si algún día hay consejeros (vía scopes, `01_ACCESS_MODEL.md` §4).

## 1. Reunión de consejo (`board_meetings`)

`id`, `title`, `scheduled_at`, `held_at`, `status` (`PLANNED`, `HELD`, `CANCELLED`), `attendees uuid[]`, `period_covered` (p. ej. 2026-Q4), `board_pack_id`, `notes`.

### 1.1 Agenda (`board_agenda_items`)
`id`, `meeting_id`, `position`, `title`, `kind` (`REVIEW`, `DECISION`, `INFO`), `presenter`, `linked_object` (`gate`, `plan_version`, `forecast_version`, `scenario`, `capital_commitment`), `duration_min`.

### 1.2 Board pack (`board_packs` + secciones)
Snapshot **congelado** al emitirse (`ISSUED`), compuesto por referencias versionadas (no copias editables):

| Sección | Contenido | Fuente |
|---|---|---|
| 1. Resumen ejecutivo | texto | autor |
| 2. Cockpit del periodo | KPIs ACTUAL/BUDGET/FORECAST/VAR con calidad | `f360_board_cockpit` snapshot JSON (hash) |
| 3. Forecast y precisión | versión vigente + accuracy | `forecast_snapshots`, `11` |
| 4. Plan 5 años / gates | estado de gates, avance vs targets | `05`, `06` |
| 5. Capital | committed/funded/deployed/remaining, despliegues y resultados | `07` (omitible en modo presentación) |
| 6. Decisiones pendientes | decisiones `PROPOSED` | Decision Log |
| 7. Action items | abiertos/vencidos | `action_items` |
| 8. Riesgos | texto | autor |

Estados del pack: `DRAFT` → `ISSUED` (inmutable; `content_hash`). Corrección = nuevo pack `REVISED` con `supersedes_id`.

### 1.3 Minutas (`board_minutes`)
Versionadas: `minute_versions` (`meeting_id`, `version`, `body`, `author`, `created_at`). `APPROVED` cuando ambos asistentes aprueban; después solo se puede agregar una versión corregida con motivo (la aprobada sigue visible).

## 2. Decision Log (append-oriented, auditable)

### 2.1 Tabla `decisions`

| Campo | Tipo | Notas |
|---|---|---|
| decision_id | uuid PK | + `number` secuencial legible (D-2026-001) |
| date | date | fecha de la decisión |
| title | text | |
| context | text | por qué se decide |
| alternatives | jsonb `[{option, pros, cons}]` | |
| decision | text | lo decidido |
| status | enum | `PROPOSED`, `APPROVED`, `REJECTED`, `DEFERRED`, `SUPERSEDED`, `WITHDRAWN` |
| financial_impact | jsonb `{amount, currency, kind: capex/opex/revenue/other, period}` | puede ser NULL |
| owner | uuid | responsable de ejecutar |
| approved_by | uuid[] | |
| related_board_meeting | uuid | |
| supporting_documents | uuid[] | → documentos del bucket privado |
| supersedes_id / superseded_by_id | uuid | |
| related_object | jsonb | gate, plan, scenario, budget, capital |
| created_at / created_by | | |

### 2.2 Inmutabilidad (sin ediciones silenciosas)

- Tras `APPROVED`/`REJECTED`, los campos de contenido (`title`, `context`, `alternatives`, `decision`, `financial_impact`) quedan **congelados** por trigger (`BEFORE UPDATE` que rechaza cambios de esas columnas; solo permite pasar a `SUPERSEDED` y llenar `superseded_by_id`).
- `DELETE` rechazado siempre (`f360.reject_audit_change()`, patrón existente — `20260927010000_f360_p22_woo_publishing.sql:108-113`, mensaje genérico en `20260929000200_f360_audit_message.sql`).
- Mientras está `PROPOSED`, cada edición crea `decision_revisions` (append-only: payload completo, hash, autor, fecha). La UI muestra "revisión N de M" y diff.
- **Cambiar una decisión aprobada** = crear una decisión nueva con `supersedes_id`; la anterior pasa a `SUPERSEDED` y conserva su texto.
- Cada transición de estado → `decision_events` (append-only).

### 2.3 Quién aprueba
Decisión D5 (abierta): (a) ambos para toda decisión con `financial_impact` o de capital/cap table/gates con override; (b) cualquiera para decisiones operativas. Las decisiones donde una persona es parte interesada (p. ej. inversión de Mario) requieren la aprobación de la otra.

## 3. Action items (`action_items`)
`id`, `decision_id?`, `meeting_id?`, `title`, `owner`, `due_date`, `status` (`OPEN`, `IN_PROGRESS`, `DONE`, `DROPPED`), `result`. Cambios → `action_item_events` (append-only). Vencidos se destacan en el cockpit.

## 4. PDF / exportación

Auditoría: **no existe** infraestructura de PDF en servidor. Lo que hay: `window.print()` en `admin-web/src/app/(app)/conteo/hoja/PrintButton.tsx:3` (hoja imprimible con CSS de impresión) y CSV por Blob (`conteo/ConteoClient.tsx:146`, `productos/ConsolidatePanel.tsx:46`).

Por lo tanto: **no se construye PDF** en este módulo. El board pack tendrá una **vista imprimible** (`/estrategia/consejo/[id]/imprimir`) reutilizando el patrón de `conteo/hoja` — el navegador genera el PDF si Carolina o Mario lo desean, localmente. Advertencia en la vista: el PDF impreso sale del sistema y ya no tiene control de acceso.

## 5. RPCs
`f360_board_meetings_list/get/save`, `f360_board_pack_build(meeting_id)` (DRAFT), `f360_board_pack_issue(id)`, `f360_board_minutes_add_version`, `f360_board_minutes_approve`, `f360_board_decision_propose/revise/approve/reject/defer/supersede/withdraw`, `f360_board_decisions_list(filters)`, `f360_board_action_*` — scope `BOARD`.
