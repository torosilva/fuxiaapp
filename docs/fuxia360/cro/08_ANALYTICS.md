# CRO · Medición (D-CRO-05)

## BLOQUEO: NEED_GTM_ACCESS · GTM-W2PZG3L5

- Producción carga **GTM-W2PZG3L5**, **Meta Pixel** y **Microsoft Clarity**. staging4 no carga ninguno.
- Mario resuelve con Carolina y Adrián quién tiene acceso al contenedor.
- **Hasta tener acceso:**
  - No se crean eventos.
  - No se toca producción.
  - No se agrega GTM a staging.

**Con acceso, en este orden:**
1. Tags.
2. Triggers.
3. Variables.
4. Eventos GA4 existentes (ecommerce: `view_item`, `add_to_cart`, `begin_checkout`, `purchase`, ¿vía plugin o GTM?).
5. Meta (Pixel/CAPI).
6. Ecommerce `dataLayer`.
7. Duplicados.
8. Consentimiento.
9. Cómo crear staging: Environment de GTM o contenedor aparte.

## Contrato de eventos → `growth/G2_MEASUREMENT_CONTRACT.md` (Measurement Contract V1)

**La tabla que vivía aquí quedó reemplazada** (2026-10-04, G2-A) por el **Measurement Contract V1**, que es la **única fuente de verdad** de la instrumentación.
- **CRO implementa** los eventos en los fragmentos del storefront **según el contrato**. Growth los consume. No hay dos instrumentaciones.
- El mapeo de los nombres anteriores a V1 está en el contrato, §9. Por ejemplo, `f360_fit_guide_open` → `f360_view_fit_guide`; `f360_made_to_order_selected` se elimina porque se deriva de `f360_select_size`.
- Contexto y salud de las fuentes: `growth/G2A_MEASUREMENT_FOUNDATION.md` (clasificación de canales, UTMs, accesos GTM y GA4, consentimiento).

**Siguen vigentes en este documento:**
- el bloqueo `NEED_GTM_ACCESS` y el orden de auditoría de arriba;
- la regla de **no** agregar GTM a staging4 ni enviar eventos a ningún destino hasta resolver el acceso y LEGAL_REVIEW_REQUIRED.

**Regla clave del contrato:** `purchase` del navegador **no** es la verdad de revenue. Commerce Facts (G1) manda.
