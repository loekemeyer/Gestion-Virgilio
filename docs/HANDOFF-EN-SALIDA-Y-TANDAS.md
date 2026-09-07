# Traspaso — pendientes de la sesión de En Salida (2026-09-07)

> Reescrito el 07/09 al mediodía. La versión anterior de este archivo quedó vieja en
> horas: decía que los crons estaban apagados y que faltaba la acumulación, y las dos
> cosas ya están resueltas por la otra sesión.
>
> ⚠ **Dos sesiones trabajando sobre `main` a la vez.** Esta sesión venía de la v13.65
> y al volver main estaba en la v13.88. Antes de tocar nada: `git pull --rebase origin main`.
>
> **Estado al 07/09 13:20 — `main` va por `v13.92`** (commit `7361d86`). La v13.90 y la v13.91 las
> tomó esta sesión; la v13.92 la sesión de "Pipeline Gestión Virgilio pendientes" (hoja de ruta
> imprimible del camión). **El próximo bump arranca en `v13.93`.** Único cambio de esa sesión que
> toca algo compartido: se agregó `observaciones` al `select` de `gv_ppp_programacion_diaria` en
> `pppLoadProgFromSupabase` y al row de `_pppRowFromSupa` — campo nuevo, nada de lo que ya había
> cambió. Esa sesión **no toca `ppp_web_armar_tandas`**: el punto 1 de acá es todo tuyo.

---

## 1. HECHO — el pedido se engancha al camión que YA va al cliente (v13.93 + v14.05)

**El caso.** Osa Distribuidora (cod **2533**, Villa Lugano, Zona 1) tenía camión el **miércoles
9/09** — tanda `D66B`, 4,04 m³ en dos NP. Entró un pedido web del mismo cliente (0,026 m³) y el
automático lo programó para el **martes 15/09**, en un camión aparte.

**v13.93** — bloque (a2) de `gv_ppp_web_armar_pendientes`: busca **hacia atrás** (de mañana hasta
el día anterior al que el automático elegiría) el día en que el cliente ya tiene entrega, y pisa el
colchón **y** el cupo. La regla adelanta el pedido, nunca lo demora.

**v14.05** — bloque (a1), la corrección del dueño: *"sólo en caso que ya se haya pickeado (o pasos
posteriores) [tanda nueva]; si todavía ni se pickeó, el agregado se agrega a la tanda actual del
cliente"*. **El corte es "¿ya se tocó?" (EP/TP/AP/TAP), no "¿es de ISIS o es web?".** Función nueva
`gv_ppp_web_tanda_abierta_cliente`. Detalle y medición: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.ca y
§3.cb; SQL en `sql/gv_ppp_web_dia_cliente.sql` y `sql/gv_ppp_web_tanda_abierta_cliente.sql`.

**Cerrado también el 1354 de Osa.** El dueño dijo *"me da igual"*, así que se aplicó la regla. Entre
medio la v14.09 de la otra sesión renombró las tandas (`D66B` → `E09A`, `D66G` → `E09B`) y eso volvió
a separar el pedido; se reaplicó. **Hoy el miércoles 9 Osa tiene UNA sola tanda, `E09A`**: 98650
(2,710) + 98667 (1,331) de ISIS + `LK 0024` (0,026) de la web = **4,067 m³**. Verificado que no se
rompió la v14.09: ningún número de camión en dos días. Rollback:
`sql/backups/ppp_web_programacion_20260907_1354_pre_merge_d66b.sql`.

⚠ **Si otra sesión vuelve a renombrar tandas, chequear que no separe de nuevo el 1354.** El renombre
trabaja por código de tanda y no sabe de la regla v14.05.

---

## 2. HECHO — las 20 filas de `CLIENTE SIMULACIÓN` están borradas

`cod_cliente = 99999`, tandas `SIM######`, m³ = 1,000 clavado en las 20; alguien probó la
pantalla de Facturación el lunes 31/08. Verificado antes de borrar que no eran reales (0 filas
en las tres tablas de PPP, 0 eventos, 0 referencias en el código de las dos apps, 0 con
`cierre_id`). **Borradas el 07/09** con el OK del dueño; hoy `select count(*) … where
cod_cliente = '99999'` → **0**. Backup:
`sql/backups/facturacion_np_20260907_simulacion_99999.sql`. Doc: §3.bz.

**Efecto medido en En Salida:** de 54 NP / 24,65 m³ pasó a **34 NP / 4,65 m³**, que es el
universo real (verificado hoy contra `gv_ppp_en_salida`).

---

## 3. HECHO — artículo 578 y el pedido 1354 de Osa

El **578 Descarozador De Aceitunas** estaba dado de baja (`list_price = 0`, `uxb = 1`) y el
pedido salía en **$0**. El dueño pasó los datos: **$1.000 por unidad, 12 por caja** (v14.03).

Estado hoy: `precios_venta` de Virgilio tiene 578 con uxb 12 y precio 1.000, y
`gv_ppp_np_valor` valúa **`LK 0024` en $60.000** (5 cajas × 12 × $1.000). Ya no vale $0.

Sigue con `active = false` en el catálogo de LK **a propósito**: activarlo lo publicaría para
todos los clientes del portal, no sólo para Osa.

**Residuo, inofensivo:** el `sheets_payload` del pedido 1354 quedó congelado con
`"uxb": 1` y `"order_total": 0` (se armó antes de la corrección) y ya viajó al Sheet. No llega a
ISIS por ahí: los crons 7 y 10 de LK (el mail de las 12:30 a compras) están **apagados** desde el
05/09 y la carga a ISIS sale del Excel que baja Gestión, que se arma de `PPP_Web_Base` — donde la
línea es sólo `578 · 5 cajas`, sin uxb. Nada que corregir; queda anotado por si alguna vez se
vuelve a prender ese mail.

---

## 4. HECHO — no rehacer

- **En Salida (v13.62)**: universo "facturada sin CRN" (de 13 a 54 NP, 0 perdidas), fecha y hora
  reales de carga, chips de estado por NP, y Recepción de Remitos embebida sólo para
  supervisores (CRN y FSS, reusando `crSendDetail` / `crSendSinSalida`). El módulo RR de arriba
  quedó intacto. Doc: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.au. Test:
  `tests/ppp-ensalida-estado.cjs` (17 chequeos).
- **El 1354 de Osa se movió a mano** de `E03A`/15-09 a **`D66G` / 09-09**, camión 66, el mismo
  día que las otras dos NP de Osa (`D66B`). Tanda propia, como lo pidió el dueño.
  Rollback: `update public."PPP_Web_Programacion" set tanda='E03A', fecha_entrega='2026-09-15' where order_id=1354;`
- **`CCR sin CCN`: AUDITADO Y CERRADO — no hay nada que arreglar.** Se había reportado como
  "el circuito se está usando mal"; **eso estaba mal dicho** y queda corregido acá.

  Los números: de **866 NP con CCR, 841 también tienen CCN**. Sólo **25 (2,9%)** tienen CCR sin
  CCN, repartidas en 8 tandas de tilde entre el 29/07 y el 04/09. O sea que el 97,1% del
  circuito se usa bien; esto es la excepción.

  Y las excepciones **se cierran solas**: de esas 25, las **17 más viejas** ya no están en En
  Salida, y las 17 figuran en la **hoja de entregados** (`gv_ppp_entregados_meta`), ninguna con
  CRN. Salieron, se entregaron, y el Excel de ISIS las absorbió. Las **8 que se ven hoy**
  (98474 del 03/09, y 98509 + 98585–98590 del 04/09) son sólo la cola reciente que el Excel
  todavía no alcanzó.

  El patrón del tilde también quedó claro: las seis de la D56D las armó **Franco Ortiz (237)**
  el 03/09 a las 14:08:49 —el mismo segundo, una tanda— y **Farias Juan Hilario (8)** les puso
  el CCR el 04/09 a las 09:54:32, las siete dentro de una décima de segundo. Eso es el botón
  **"✓ Controlar TODA la tanda"**, no gente controlando remito por remito.

  **Conclusión: es un retraso de registro, no un circuito roto.** No hace falta cambiar nada;
  a lo sumo, si molesta verlas, se les puede bajar el ruido en pantalla. El chip `CCR sin CCN`
  sigue siendo útil para detectarlas.

## 4.b HECHO — el recordatorio de faltantes (v14.01)

`FAC_OPERADORA_EMAIL = "loekemeyer.n8n@gmail.com"` — el mismo mail con el que entra el dueño como
supervisor. Por eso el recordatorio "⏰ Es hora de completar los faltantes" **le llega a él**
(camino 2 de `cpRecordCheck`), no sólo a la operadora.

**Los cinco defectos quedaron arreglados en la v14.01.** Test: `tests/cp-recordatorio.cjs`,
10 chequeos, verdes. Relevamiento completo del circuito: `docs/CIRCUITO-FALTANTES.md`.

| era | ahora |
|---|---|
| sólo piso 15:30 → disparaba hasta las 23:59 | ventana 15:30–18:00 (`CP_RECORD_MAX`) |
| sólo miraba lunes-a-viernes | además chequea `GV_Dias_No_Habiles` (feriados) |
| avisaba aunque no hubiera nada que completar | primero carga los faltantes; si son 0, no molesta |
| marcaba "ya avisé" **antes** de abrir el modal | lo marca **después**; si falla, mañana reintenta |
| sin red igual quemaba el aviso del día | sin red no avisa ni marca |

**Sin explicar (y sin consecuencia hoy):** el dueño reportó que le disparó un lunes ~10:20. El
filtro de hora es lo primero que corre y se probó en V8 barriendo las 24 h. Hipótesis vivas: un
`index.html` viejo cacheado, o el reloj del dispositivo corrido. Con la ventana nueva, aunque se
repita, el impacto es menor.

---

## 4.c PENDIENTE — lo único que queda

1. **El mismo recordatorio vive también en el repo de Producción** (commit `e15b682`, bloque
   idéntico). Son dominios distintos con `localStorage` separados, así que quien tenga las dos
   apps instaladas lo recibe **dos veces**. Hay que sacarlo de allá o dar de baja esa app —
   **desde este repo no se puede pushear a Producción**.
2. **73 filas huérfanas en `Faltantes_Tareas`** (estado `pendiente`, del 24/07 al 04/09; sólo 1 en
   `completado`). Las creaba el circuito de coordinación en vivo, que está apagado
   (`FALT_POPUP_ENABLED = false`, v6.15), y las cerraba el popup que ya no existe. **No las lee
   ninguna pantalla viva**, sólo ensucian la tabla. Decidir: limpiarlas, o volver a prender el
   popup si se lo quiere usar.
3. **El dedup del recordatorio sigue en `localStorage`**, o sea una vez por dispositivo, no por
   persona. Se dejó a propósito: con la ventana de 2 h 30 y el "no avisa si no hay nada", el ruido
   desapareció. Si alguna vez molesta, la alternativa es una tabla `GV_*`.

Volumen real de faltantes hoy (07/09): **5 líneas, 1 NP (98542 · Pro Tatiana Ethel · D57B),
10 cajas**.

## 5. Correcciones a la versión anterior de este archivo

Lo que decía y ya no vale:

- ~~"Los crons 71 y 73 están apagados"~~ → **prendidos** desde la v13.67, después de que
  `ppp_web_armar_tandas` v7 hiciera que la tanda acumule entre corridas.
- ~~"Falta implementar que la tanda acumule hasta 0,80"~~ → **hecho** (v13.67), y el tope pasó
  de 0,80 a **1,00** en la v13.86.
- ~~"El pedido 1352 de Muller sigue vivo"~~ → **borrado**, en LK y en Virgilio.
- ~~"Basura en `bot_customer_whatsapps`"~~ → la tabla se **vació** (commit 55bb0a0): las 5 filas
  eran WhatsApp de prueba.
- ~~"La NP web debería ser el número de pedido (v12.92)"~~ → **la v13.70 lo revirtió a propósito**:
  la NP web es un contador propio, un número por bloque, sin sufijo (`LK 0001`…). `LK 0024` para
  el pedido 1354 es lo correcto.
