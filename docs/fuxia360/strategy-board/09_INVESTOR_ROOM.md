# 09 · Investor Room

> Spec. **Solo Carolina y Mario.** No hay logins externos, enlaces públicos ni accesos de inversionistas en esta fase.
> Es una sala de preparación: aquí se arma y se versiona el material; compartirlo con un tercero es un acto fuera del sistema, registrado como evento.

## 1. Contenido

| Sección | Tipo | Fuente / regla |
|---|---|---|
| Pitch deck | documento (PDF/Slides exportado) | subido; versionado |
| Investment snapshot | ficha generada | cockpit (solo KPIs con calidad `VERIFIED`/`PARTIAL` etiquetados), plan, uso de fondos |
| Financial model | documento o vínculo a versión de forecast/escenario | referencia a `forecast_version`/`scenario` |
| Five-year plan | vínculo a `plan_version` aprobada | `05` — rótulo "Metas de dirección" |
| Cap table | vínculo a `ownership_snapshot` formal | `07` — si no existe, "No registrado"; nunca un borrador |
| Use of funds | tabla por categoría de `capital_deployments` (plan vs real) | `07` |
| Investor updates | notas periódicas versionadas | autor |
| Investor video | archivo de video | subido (bucket privado); hoy los videos de marca viven en `tools/video/` (fuera de la app) |
| Data room index | índice de todos los documentos con versión, fecha y hash | generado |

## 2. Prohibido en la sala

- **PII de clientas**: ningún nombre, teléfono, correo, dirección o lista; solo agregados (conteos, tasas). Las RPCs de la sala nunca leen columnas de PII de `public.customers`.
- **Secretos técnicos**: claves, URLs de proyecto Supabase, refs (`tgzg…`), secretos de webhooks, rutas de Vault, nombres de buckets internos, diagramas con endpoints. Lista de validación en la subida: escaneo simple de patrones (`sk_`, `eyJ`, `service_role`, `supabase.co`, `-----BEGIN`) que **bloquea** el archivo de texto y advierte en PDF.
- Datos de vendedoras/staff identificables.
- Borradores de cap table o porcentajes no aprobados.

## 3. Documentos (`investor_room_items`)

`id`, `section`, `title`, `version`, `status` (`DRAFT`, `READY`, `ARCHIVED`), `storage_path`, `sha256`, `mime`, `size`, `contains_financials boolean`, `reviewed_by uuid[]`, `created_at/by`. Nueva versión = nueva fila; nunca se sobreescribe el objeto.

`investor_room_events` (append-only): `UPLOAD`, `VIEW`, `DOWNLOAD`, `MARK_READY`, `ARCHIVE`, `SHARED_OUTSIDE` (registro manual: a quién y cuándo se envió, texto libre — sin datos de contacto del inversionista más allá del nombre de la firma).

## 4. Almacenamiento (requisito nuevo)

Auditoría: los 3 buckets de prod (`avatars`, `tryon-temp`, `product-images`) son **públicos** (prod_read 2026-10-08). Ninguno sirve.

Propuesta: bucket **privado** `board-private` (`public = false`), **sin** políticas `storage.objects` para `authenticated`. Acceso solo mediante:

1. `public.f360_board_room_upload_url(section, filename, mime, size)` → valida miembro (`INVESTOR_ROOM`) y devuelve una **signed upload URL** de vida corta. Como Postgres no firma URLs de Storage, esto requiere un componente servidor: **Route Handler de Next.js** que (a) llama primero a la RPC con la sesión de la usuaria (autoriza y registra), y (b) solo entonces firma con una credencial de servidor. **Conflicto con la convención actual:** `admin-web/src/lib/supabase/server.ts` dice "The web app never uses a service-role key". Alternativas a decidir (D9):
   - A. Política de Storage `FOR SELECT/INSERT TO authenticated USING (bucket_id='board-private' AND f360_board.is_board_member_storage(...))` con una función SECURITY DEFINER que valida allowlist — **sin** service role. Preferida.
   - B. Route Handler con service role restringido (rompe la convención; requiere aprobación explícita).
2. Descarga: signed URL de 60 s, registrada en `investor_room_events`.

## 5. UX

Lista por sección, "listo para compartir" por documento, índice exportable (CSV) del data room. Modo presentación oculta la sala completa.

## 6. RPCs
`f360_board_room_list()`, `f360_board_room_item_register(…)` (tras subir), `f360_board_room_item_status(id, status)`, `f360_board_room_download(id)` (registra y entrega ruta para signed URL), `f360_board_room_log_shared(id, recipient_label, note)`, `f360_board_room_index()` — scope `INVESTOR_ROOM`.
