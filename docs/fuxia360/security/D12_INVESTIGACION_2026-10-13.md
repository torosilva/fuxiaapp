# D12 · Investigación por las decisiones de Mario (2026-10-13)

> Solo hubo lecturas en producción (`prod_read.sh`). **No se modificó ninguna cuenta, tienda ni flujo.**
> Las comparaciones de NIP se hicieron dentro de la base y devuelven solo verdadero o falso; ningún NIP se imprimió.

## 1. Guadalajara: sigue operando; preparar su paso a cuentas F360 (punto 3)
**Hechos (producción):**
| Dato | Valor |
|---|---|
| Canal anterior | "Guadalajara", tipo **bazar** |
| Ventas históricas | 28 ventas, $124,700, del 2026-05-18 al **2026-09-30**. 12 con clienta identificada |
| Inventario en la app anterior | 9 filas: stock 46, vendidos 41, **disponibles 5**. Última actualización 2026-09-23 |
| Solicitudes de cambio de inventario | 5 (`adjust_stock`), todas **rechazadas**; la última el 2026-09-22 |
| Personal anterior activo | Chelita Gómez (alta 2026-05-18), Paola (2026-09-22) y "Mario" (2026-09-21; sin ventas) |
| Ubicación en F360 | **no existe** |
| Vendedoras en F360 | ninguna |

**Preparación propuesta** (no se ejecuta nada; la app anterior sigue activa para Guadalajara):
1. **Ubicación F360** "Guadalajara", tipo `bazaar`, como Torreón. Necesito de Mario o Carolina el nombre exacto y si opera de forma continua o por evento.
2. **Inventario inicial:** conteo físico de los pares que están hoy en Guadalajara. La app anterior dice 5, pero su inventario no se actualiza desde el 23 de septiembre, así que no se carga por suposición. Si llega mercancía nueva para un bazar, se manda con una transferencia desde Bodega CDMX.
3. **Vendedoras:** Paola y Chelita Gómez, con `f360_admin_seller_add`: nombre, WhatsApp **real de cada una** (lo da Carolina) y un NIP nuevo. Nunca se reutiliza el anterior, que está expuesto. Cada una inicia sesión con su propio teléfono.
4. **Ensayo en staging:** crear la misma ubicación y las vendedoras con datos ficticios únicos, en coordinación con 2d y d5. Probar abrir turno, vender con y sin clienta, apartar y ajustar inventario (la operadora).
5. **Convivencia:** mientras no se decida el corte, la app anterior sigue aceptando a su personal en Guadalajara. El turno de F360 se habilita en paralelo.
6. **Pendiente de Mario:** ¿"Mario" (personal anterior de Guadalajara, sin ventas) se mantiene?

## 2. Contreras ¿= San Jerónimo Lídice? (punto 4)
| Evidencia | Contreras (app anterior) | San Jerónimo Lídice (F360) |
|---|---|---|
| Ubicación registrada | texto "Contreras 516" | sin dirección: `f360.locations` no tiene columna de dirección |
| Vida | alta 2026-09-17; **última actividad 2026-09-30** (inventario) | alta **2026-10-03**; 86 eventos del 2026-10-03 al 2026-10-13 (recepciones, transferencias y ajustes) |
| Personal | "Dulce Sur" (alta 2026-09-17; 1 venta el 2026-09-17) | "Dulce Sur", vendedora **pendiente** (alta 2026-10-09 por Carolina) |
| NIP | — | **no coincide** con el anterior (verdadero/falso dentro de la base) |
| Mercancía | 153 pares al 30-sep: Cucarrón 30, Paula 28, Mafalda 26, Ballerinas/Byl, Sueco, Flats, Mules, Botas, Slingback, Aladino… | 99 pares: Cucarrón 15 (+12 "Sueco cucarrón"), Paula 14, Byl 11, Mafalda (varios), Mules Colectiva 4, Suecos, Slingback, Aladdin… |
| Notas del ledger que mencionen Contreras, 516 o la app anterior | — | **ninguna** |

**Conclusión:**
- **Hay indicios fuertes, pero no prueba.** Coinciden la misma vendedora, la secuencia de fechas (Contreras se detiene el 30 de septiembre y San Jerónimo abre el 3 de octubre) y una mezcla de modelos parecida.
- **No hay ningún registro que las vincule:** ni transferencia, ni nota, ni `legacy_channel_id`.
- **La diferencia 153 → 99 no está explicada.**

**Para confirmar** (Carolina o Mario):
1. ¿"Contreras 516" es la dirección de la tienda San Jerónimo Lídice?
2. ¿Los 153 pares de Contreras se llevaron a San Jerónimo, en todo o en parte, y el resto a otras tiendas?

**Hasta confirmar:** no se vincula `legacy_channel_id` ni se suman inventarios. Esto también resuelve la duda del ">700" de la conciliación del 11 de octubre.

## 3. Devoluciones: cómo funcionan hoy y cómo se conservarían en F360 (punto 5)
**Hoy** (registros de producción y código):
- **La app anterior no tiene devoluciones:** no hay pantalla, función ni estado de venta; 0 ventas con total ≤ 0. Lo único que hay son las solicitudes de inventario (`adjust_stock`), y en Guadalajara están todas rechazadas.
- **En F360, la venta de tienda tampoco tiene devolución.**
  - El ledger sí tiene el tipo `RETURN`, pero se usa solo para "regresar al origen" una transferencia; hay 1 caso, por error de captura.
  - Las devoluciones físicas, si las hubo, se registraron como **ajuste de entrada** sin referencia a la venta: hay 255 ajustes "Ajuste · entrada" y ninguno menciona devolución o cambio.
- **Puntos:** no hay función para revertirlos (`loyalty_apply` solo acredita). Una corrección de puntos solo se puede hacer a mano con `admin-points`, solo admin.
- **Hallazgo relacionado:** hay un ajuste con la nota "vendido semana 5-10 oct". Son ventas registradas como ajuste de salida, no como venta: no generan puntos, no quedan en ventas y no tienen clienta.

**Qué falta para conservar el flujo en F360:**
- No se cambia nada todavía, y **la regla de negocio la define Mario.** Necesito saber cómo se hace hoy en las tiendas:
  - ¿se aceptan cambios de talla o modelo?
  - ¿hay reembolso?
  - ¿en cuántos días?
  - ¿con ticket o código?
  - ¿quién autoriza?
  - ¿qué pasa con los puntos de la clienta?
- **Propuesta técnica** cuando la regla exista:
  - una devolución ligada a la venta original (`offline_sales.id`), por artículo;
  - en el ledger, `RETURN` hacia la ubicación;
  - la reversión de puntos la calcula el servidor con la misma regla de `loyalty_apply`;
  - auditada y con el mismo patrón de autorización que los descuentos de tienda (`f360_store_discount_*`).
  - El cambio de talla se registraría como devolución más venta nueva en un mismo evento atómico.
- Mientras tanto, la recomendación operativa es seguir como hoy, pero que el ajuste lleve en la nota "devolución de venta <código>".

## 4. Valeria de Polanco: ¿qué cuenta de F360 es? (punto 6)
| Registro | "Valeria" (app anterior) | Valeria García (F360) | Valeria Pérez (F360) |
|---|---|---|---|
| Alta | personal anterior **2026-09-27** | vendedora 2026-10-09 | vendedora 2026-10-09 |
| Cuenta de la app (`auth.users`) | — | desde **2026-05-02** (clienta anterior) | desde **2026-09-27** |
| Rol en la app (`customers.role`) | — | `customer` | **`staff`** |
| Último ingreso | — | 2026-10-09 | 2026-10-11 |
| Actividad | 1 venta anterior (2026-10-05) | 0 ventas F360; 0 turnos. Mencionada en un ajuste: "salida valeria garcia" | 0 ventas F360; **1 turno** |
| NIP anterior = NIP F360 | — | no | no |

**Lectura:**
- **Los indicios apuntan a Valeria Pérez:** su cuenta se creó el **mismo día** que el personal anterior "Valeria" y tiene el rol `staff` de la app anterior.
- **No es concluyente:** el nombre del sistema anterior no trae apellido, el NIP no coincide y no hay una venta que las una.
- **No se modificó ninguna cuenta.**
- **Confirmación pedida:** Carolina, ¿quién vendió la venta del 5 de octubre en Polanco con el NIP "Valeria"?

## 5. `test_sellers_admin` (punto 7)
- **Propietario:** el módulo de vendedoras se creó en el commit `13acf12` (2026-10-08), en una sesión que **ya no está activa**. Hoy solo están vivas fuxiaapp-d5 (Academy) y fuxiaapp-2d (copia de staging), y ninguna es dueña del módulo.
- **Corrección pendiente:** reemplazar las identidades reales de la prueba (nombre "Carolina Munoz" y teléfono) por identidades ficticias únicas. Por ejemplo, `zz-sa-<sufijo>` con un teléfono `+1555019…`. Se corre solo en staging, envuelta en BEGIN…ROLLBACK.
- **Mario debe decir a quién se asigna:** a una sesión nueva o a esta.
