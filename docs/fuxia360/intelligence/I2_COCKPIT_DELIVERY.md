# I2 · Centro de Inteligencia: pantallas (entrega en STAGING)

Fecha: 2026-10-11. Solo staging (https://fuxia360-staging.vercel.app). No hay cambios en la base de datos: las pantallas leen y escriben solo con las funciones ya aprobadas en I0, I1a e I1b.

## Qué se construyó

| Pantalla | Para quién | Qué hace |
|---|---|---|
| **Dirección** `/direccion` | Mario y Carolina, con verificación en dos pasos (la misma regla que Strategy & Board) | El tablero con las 8 tarjetas del diseño (§4). Cada tarjeta tiene un sello: **Completo**, **Parcial** o **Falta fuente**. Una tarjeta en "Falta fuente" **no muestra ninguna cifra**: solo dice qué falta, por qué y de quién depende. Con "ⓘ" se ven la fuente, el periodo, la moneda, la hora de actualización y las notas. Arriba se elige la semana (anterior y siguiente) y se cambia entre "Moneda original" y "Consolidado MXN". El consolidado muestra las tasas usadas, marca la "tasa provisional (mes en curso)" y avisa lo que no tiene tasa. Abajo aparece la franja de **Fuentes**. |
| **Tipo de cambio** `/direccion/tipo-de-cambio` | Mario y Carolina. Solo quien está autorizado (Mario) ve el botón **Aprobar** | Muestra la lectura diaria más reciente ("1 USD = 18.11 MXN", "1 COP = 0.00563 MXN (≈ 178 COP por peso)"), las tasas mensuales propuestas y el historial. |
| **Presupuesto y metas** `/direccion/presupuesto` | Mario y Carolina | **Metas:** la vigente y sus versiones anteriores, cada una con su motivo. Mario puede guardar una versión nueva. **Presupuesto:** versiones (borrador, aprobado y reemplazado) y una cuadrícula de mes × (México en línea, México tiendas, Colombia en línea, Resto del mundo en línea), cada columna en la moneda de su mercado. Los pasos son: crear el borrador con su motivo, guardar los montos, la **validación comercial** de Carolina y la **aprobación** de Mario. Ninguna versión se borra. |
| **Cierre contable** `/cierre-contable` | La contadora, y también Mario y Carolina | La contadora elige el mes y captura montos (cuenta, monto, moneda, fuente y documento). Puede anular sus propias capturas no aprobadas, siempre con un motivo. También registra pagos próximos (compromisos), y puede corregirlos (se crea un registro nuevo y el original se conserva), marcarlos como pagados o cancelarlos. Mario y Carolina ven además **Aprobar** en los compromisos y un enlace para aprobar las capturas del mes en Strategy & Board (no se duplica esa aprobación). |
| Menú | | En el grupo "Dirección" aparecen **Dirección 🔒**, **Inteligencia 🔒** (la pantalla la construye otra sesión) y **Cierre contable**. En el celular aparecen en "Más". |

### La contadora
- Es una usuaria con rol `viewer` y una fila en `f360_board.finance_preparers`. Entra **solo** a Cierre contable. Desde cualquier otra página del admin (inicio, estrategia, dirección, clientes, vendedoras, inventario, growth…) **el servidor la redirige** a `/cierre-contable`. No basta con esconder enlaces: Cierre contable tiene su propio grupo de rutas y el layout principal la redirige. Su menú tiene una sola entrada.
- Necesita verificación en dos pasos, igual que el consejo (`f360_board.settings.require_aal2`). La pantalla de verificación es la misma de Strategy & Board, ahora con el nombre del área.

## Cómo verificar
1. Entra como `mario.demo@staging.invalid` y abre **Dirección**. Configura la verificación en dos pasos la primera vez. Revisa las 8 tarjetas con su sello, la tarjeta 2 con la meta de $300,000 y la nota "cálculo, no pronóstico", y las tarjetas "Falta fuente" sin cifras.
2. En **Tipo de cambio**, Mario ve **Aprobar** en cada mes propuesto y Carolina no lo ve.
3. **Presupuesto y metas:** crea un borrador de prueba solo si quieres probar el flujo, porque queda en el historial.
4. Entra como `contadora.demo@staging.invalid` (la contraseña está solo en `~/.fuxia-staging.env`). Solo ves Cierre contable y cualquier otra URL te regresa ahí.
5. Prueba automática: `set -a; . ~/.fuxia-staging.env; set +a; cd admin-web; F360_BASE_URL=https://fuxia360-staging.vercel.app npx playwright test e2e/direccion.spec.ts`.

Usuaria demo de la contadora: `scripts/f360/staging_demo_contadora.sql`. Primero se crea la cuenta de Auth con la API de administración de staging. Hay que volver a correrlo después de cada copia de producción a staging.

## Capturas (no se suben al repositorio)
`admin-web/e2e-screenshots/inteligencia/`: verificación en dos pasos, Dirección (escritorio, consolidado MXN, celular), Tipo de cambio (Mario y Carolina, celular), Presupuesto (escritorio y celular), Cierre contable (consejo y contadora, escritorio y celular).

## Riesgos y huecos
- **Hueco del backend: falta `f360_finance_access_state()`.** Hoy no existe una función que diga "esta persona es contadora" **antes** de su segundo factor. Por eso, a cualquier usuaria `viewer` sin segundo factor se le pide primero la verificación de Cierre contable. Si después la base dice que no es contadora, vuelve a sus pantallas normales de consulta. En staging no hay otras usuarias `viewer`. **Antes de producción**, revisar si hay `viewer` reales y agregar la función (solo dice 'ok' | 'mfa_required' | 'none' sobre quien llama, igual que `f360_board_access_state`). Así solo a la contadora se le pide el segundo factor.
- La seguridad está en la base (todas las funciones revisan quién llama y su segundo factor). Menús, redirecciones y botones solo ayudan a usar la pantalla.
- `f360_finance_commitment_add` no tiene llave anti-duplicado. El botón se desactiva mientras guarda, pero un doble envío desde dos pestañas crearía dos compromisos (se cancela uno con su motivo).
- La prueba automática configura la verificación de las cuentas demo y al final borra esos factores con la API de administración de staging, así las cuentas quedan como estaban.

## Cómo regresar (rollback)
En Vercel, proyecto **fuxia360-staging** → Deployments → el despliegue anterior → "Promote". No hay cambios de base de datos que revertir. Para quitar a la contadora demo, sigue el bloque "Undo" de `scripts/f360/staging_demo_contadora.sql`.
