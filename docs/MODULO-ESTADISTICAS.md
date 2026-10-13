# Estadísticas ISIS y Estadística Madre

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠ REGLA (2026-10-01, v25.65): STOCK Y COMPRAS — PEDIDOS en la Proyección y la pestaña EST. MADRE es el admin

- **Columna «pedidos»** del pop-up de Proyección (entre vtas y entrega) = cajas que **pidieron los clientes** en el
  mes, por fecha del pedido: `gv_pedidos_mensuales_cod` sobre `lk_pedidos_match` (web LK + Chef), con la familia
  sumada y la L como LK, igual que vtas. Un mes sin pedidos web registrados (antes de abr/26 LK, jul/26 Chef) o una
  lectura caída dice **s/d**, nunca 0.
- **«📈 Est. Madre»** (primera solapa) **no es una copia**: es `admin/admin.html#estadistica-madre` en un iframe que
  vive fuera de `#stkBody` (los re-render no lo recargan). Cambiar la Est. Madre = cambiarla en `pagina-LK-copia` y
  re-copiar el espejo `admin/`. ~~Entra con el puente `lk_bridge_vjwt` y pide el OTP si el mail no es el admin~~ →
  **desde la v25.72 entra SIN código** (ver la regla de abajo).
- `tests/proy-entregadas.cjs` · `tests/stk-est-madre-tab.cjs` · `sql/gv_pedidos_mensuales_cod_v2565.sql`.

## ⚠ REGLA (Tomás Beviglia, 2026-10-01, v25.72): la Est. Madre de Gestión entra SIN CÓDIGO — la página LK queda igual

**Tomás:** *"me pide código para ver la Est. Madre, que no me lo pida en Gestión Virgilio. La página LK dejala como
está"*. El iframe pedía el OTP cuando el puente fallaba (01/10 12:14: Gestión dio 521) o cuando el supervisor entra
con un mail que no es el admin de LK (`loekemeyer.logistica@` nunca podía).

| pieza | qué hace |
|---|---|
| iframe | `admin/admin.html?gv_em=1#estadistica-madre`; ya no deja `lk_bridge_vjwt` |
| `admin/admin.js` (sólo el espejo) | con `?gv_em=1` **dentro del iframe de Gestión** (`window.parent.sbAuth`): no busca sesión de LK, no muestra login, sólo abre la Est. Madre. El cliente de Supabase va con `fetch` propio (`_gvEmFetch`) y `window.supabaseClient = sb` |
| Edge Function **`gv-est-madre`** (proyecto LK, verify_jwt off) | recibe el JWT de **Gestión**, pregunta a `es_supervisor_virgilio()` y devuelve con service_role **sólo** products, loke_products, las ventas por mes (`get_estadistica_madre_mensual`, v25.79; antes el caché, remaps y excluidos) y el detalle de una celda. Todo lo demás 403. Fuente `admin/supabase/gv-est-madre/index.ts` |

- **No se crea ninguna sesión de admin de LK**: el Panel Web LK y la página LK siguen con su puente u OTP.
- `get_estadistica_madre_cache()` exige `admins` + `auth.uid()`: la función lee la tabla `estadistica_madre_cache`
  con la misma selección y orden.
- ⚠ **`analisis-venta-cliente.js` vuelve a declarar `var sb`** y pisa el cliente de admin.js; reusa
  `window.supabaseClient` si existe. Sin esa línea las lecturas salían directo a LK sin sesión (lo cazó el test).
- Abierto suelto (fuera del iframe de Gestión) el modo no se activa aunque traiga `?gv_em=1`.
- `tests/stk-est-madre-sin-codigo.cjs` (corre el admin real en el iframe), `tests/stk-est-madre-tab.cjs`.

## ⚠⚠ REGLA (Tomás Beviglia, 2026-10-01, v25.79): la ESTADÍSTICA MADRE es UN SOLO CUADRO — LK y Gestión

**Tomás:** *"cambiá la palabra proyección por Est Madre en toda la pestaña · los artículos correctos son los que están
en la parte de Stock de Gestión Virgilio, el resto de artículos no · la idea es que si actualizo una de las est madres
se actualice la otra, es un solo cuadro que se imprime en dos lados distintos. NUNCA puede un cuadro de est madre quedar
más actualizado que otro. Si alguien quiere cambiar uno solo NO se puede hacer"*.

> ## **La Est. Madre es UN archivo: `admin/est-madre.js` de este repo, publicado por GitHub Pages.**
> La página LK (`loekemeyer.com/admin.html`) y el espejo de Gestión (Panel Web LK y la pestaña EST. MADRE) lo bajan
> de la **misma URL** (`https://loekemeyer.github.io/Gestion-Virgilio/admin/est-madre.js?t=<ahora>`). El HTML de la
> página, el CSS y la lógica viven ahí; cada `admin.js` sólo trae el cargador `abrirEstadisticaMadre`, idéntico.

| qué | de dónde |
|---|---|
| **filas** | `stocks_carga_rapida` de Gestión (clave pública), las mismas de Stocks: sin las ocultas vacías (`visible_en_stock = false` y sin stock ni pedidos). Al 01/10: **353** (antes 586, con `026L`, `CARTONERIA`, `DTOXERROR`…) |
| **Est Madre** (caj/mes) | `proy_cajas_mes` de esa misma tabla = la columna de Stocks: cajas enteras, el principal suma a sus secundarios, el secundario muestra «→ principal» y no rankea; los duales son dos filas (LK / CH) |
| **meses** | cajas facturadas por mes y empresa: **`get_estadistica_madre_mensual()`** (LK, solo lectura, en vivo, 1,7 s), mismo criterio que el motor de la Est Madre (regla L, sin interco, remaps, sin administrativos). Cada fila = lo que vendió ESE código (en un dual, esa empresa) |
| detalle por celda / disruptivas | igual que antes (movidos tal cual). Disruptivas lee `order_items` de LK: desde Gestión no anda (ya no andaba) |

- **Ninguna fila dice «Proyección»**: es «Est Madre».
- **Una lectura que falla NO se reemplaza** por el caché viejo ni por ceros: se dice que falló. El caché
  `estadistica_madre_cache` sigue (lo lee el portal), pero esta pantalla ya no.
- ⚠ **La página LK de producción es manual (SolidCP)**: hasta subir `admin.html` + `admin.js` + `css/admin.css` de
  `pagina-LK-copia`, loekemeyer.com muestra la tabla vieja. Desde esa subida, todo cambio de `est-madre.js` llega
  a los dos con el push a `main` de este repo (GitHub Pages).
- ⚠ **El cargador es el mismo en los dos repos**: `tests/est-madre-unica.cjs` (acá y en `pagina-LK-copia`) tiene su
  huella md5 y falla si alguno vuelve a tener una Est. Madre propia. Cambiar el cargador = cambiarlo en los dos y
  actualizar la huella en los dos tests, en el mismo pedido.
- **Gestión entera lee la Est. Madre única** (v25.84): el último lector de la cruda `proyeccion_madre` era el aviso de
  rotación de `recepcion.js`; ahora lee `gv_proyeccion_articulo` y un secundario rota lo de su principal. La cruda sólo la leen
  `gv_proyeccion_articulo` y la copia `GP2.est_madre` (trigger `fn_est_madre_sync`; pasarla a la única es decisión de GP2).
- **Switch Cajas / Unidades** (v25.81, Tomás): unidades = cajas × uxb de `vista_uxb_articulo` de Gestión (la de Stocks); sin uxb
  dice «s/uxb» y no suma al total (al 01/10: 4 de 353 — 1546903, 581T, 633E, 637E). Si el uxb no se puede leer, el modo unidades
  queda apagado. El Excel sigue el switch y lleva siempre la columna UxB. El ranking es siempre el de cajas (el de Stocks).
- `sql/get_estadistica_madre_mensual.sql` (en `pagina-LK-copia`), `tests/stk-est-madre-sin-codigo.cjs`.

## ⚠ REGLA (Luis, 2026-10-02, v26.16 · v26.20): 📑 ESTADÍSTICAS ISIS — ventas y pedidos por artículo sin entrar a ISIS

Panel supervisor → **📑 Estadísticas ISIS — ventas y pedidos** (`openEstadisticasIsis`, `estadisticas.js`): mes o
rango, y baja los 4 .xls de los manuales **29** (ventas por artículo → costos) y **31** (pedidos por artículo →
Estadística Madre), LK y CH, **ya configurados como dicen los manuales** (v26.20, Luis: *"que las configures de la
forma que indica el word"*): Excel 97, Arial 10, código todo dígitos como NÚMERO (026 → 26; 026L queda texto).

| archivo | cómo sale | qué se hace después |
|---|---|---|
| Ventas (manual 29) | sin las columnas F, D y C de ISIS ni «Total General» ni pie: A..I = Artículo · Descripción · Bonificación · Cantidad · Máx · Prom · Mín · Total · % | se copia **A2:D** a Costos (paso 22) |
| Pedidos (manual 31) | sin I, J y K: A..H = Div · Artículo · Desc · Med · Cajas · Bonif · Med · Unidades; hoja **«LK Sep-26»** | la Est. Madre hace BUSCARV sobre B:H (col 7 = unidades, col 4 = cajas) |

| reporte | fuente | ¿igual a ISIS? |
|---|---|---|
| Ventas | `gv_isis_estad_ventas` = facturas + NC de ISIS ya parseadas (`isis_lk` / `isis_ch`) | **Sí**: sept/26 CH 163/163 y LK 183/184, totales exactos. Única diferencia: ISIS separa 55219 / 55219ZZ y la factura impresa dice 55219 |
| Pedidos | `gv_isis_estad_pedidos` = **sólo los pedidos web del PIPELINE de Gestión** (`lk_pedidos_match`) por fecha del pedido | **No**: ISIS sólo tiene lo cargado al facturar y no está en la base (sept/26 LK: ISIS 11.068 cajas, pipeline 23.367) |

- Precio de ventas = línea × (1−dto1)(1−dto2) × factor del importe (facturas E traen el 2 % adentro) × (1 − descuento
  del documento) × **tipo de cambio si la factura es «Son Dolar»** (Chef → LK), redondeado a 2. Una línea cargada por
  CAJA (982E, 123L) suma por caja. Líneas con cantidad 0 (Pago-25%, DtoSuper…) afuera; un artículo que neto da 0 sale.
- Pedidos: unidades = cajas × UxB; **sin UxB la celda queda vacía**, nunca las cajas disfrazadas de unidades (838 / 838L).
- **Pipeline** (Luis, 02/10: *"solo va a ser para los pedidos web de nuestro pipeline"*): pedido desde
  `PPP_Web_Config.gestion_desde` (03/09; lo de antes se cargó en ISIS por el mail), sin `GV_Web_Cancelados` ni
  `GV_Pedidos_Anulados`, sin clientes de prueba. Lo que espera en A Programar o Cuarentena **cuenta** (el cliente lo
  pidió). Sept/26: LK 26.291 → 23.367 cajas (14 pedidos del 01-02/09 + 4 anulados), CH 2.725 → 2.655.
- ⚠ **Una RPC vacía o con error NO baja nada** (sin sesión el guard devuelve 0 filas: un Excel vacío pegado en Costos
  diría que el mes no vendió). Lo dice en la tabla.
- `sql/gv_isis_estadisticas_v2616.sql`, `tests/isis-estadisticas.cjs` (layout configurado celda por celda, el rojo leído del BIFF, pantalla y descarga).
- Decidido por Luis (02/10), no volver a proponer: lo que espera en A Programar / Cuarentena **cuenta**; el 55219 va en
  **una** fila; los pedidos de ISIS **no se importan** (ISIS sólo los tiene al facturar: siempre van desfasados).

### Pedidos DISRUPTIVOS (v26.20): la fila va en ROJO y NEGRITA, con el detalle en la columna I

**Luis:** *"un pedido disruptivo es cuando el pedido de un cliente difiere en un ±50 % al promedio de los pedidos de
ese cliente en los últimos 12 meses. No es promedio de los 12 meses"* · *"toma el dato de facturación y contempla
facturación hasta que tengamos 12 meses de data de pedidos"*.

- **`gv_isis_estad_pedidos_disruptivos(emp, desde, hasta)`**: por cada pedido del período, el promedio de los pedidos
  ANTERIORES de ese cliente para ese artículo en los 12 meses previos (ventana por pedido, no por mes). Disruptivo =
  `|pedido / promedio − 1| > 0,5`; **sin pedidos previos = INCORPORACIÓN**. Piso de 10 cajas (el pedido o su promedio),
  el mismo de las Disruptivas de la Est. Madre.
- **Decidido por Luis (02/10), no volver a proponer**: la **incorporación se marca** en rojo con su comentario, porque lo
  pide el manual 31 (*"pintarlo de rojo el número, ponerle negrita e insertar un comentario … que cantidad de unidades
  fueron pedidas como incorporación y … que cliente"*). Se marca **sólo** el ±50 % y la incorporación, con el **piso de 10
  cajas tal cual**: no subirlo aunque marque 26-37 % de los artículos (*"solo marca lo que te dije"*).
- **Historia**: pedidos web desde que existen (LK 30/03/2026, Chef 29/06/2026) y, antes de eso, las **facturas de ISIS**
  (una factura = un pedido; no el día, que junta sucursales). Cuando la web tenga 12 meses (~marzo 2027 LK) las facturas
  salen solas de la ventana. Web y facturas no se mezclan en el mismo tramo (contaría dos veces).
- **Columna I** (después de la última): `★ Incorporación: Coto (LK 801) pidió 240 u (20 cj) el 10/09` · `▲ +499%: Matiz SA
  (LK 4263) pidió 1.000 u (1.000 cj) el 23/09 · prom. 167 u (167 cj) en 3 ped. (2 por factura ISIS) desde 02/10/25`;
  incorporaciones primero, hasta 5 por artículo y «+N más».
- **El rojo NO lo escribe SheetJS** (community no escribe estilos): `eiXlsBytes` parchea el stream «Workbook» del BIFF —
  marca las celdas con formatos marcadores, agrega un FONT rojo y negrita y corre el puntero de BOUNDSHEET. ⚠ **Para un
  stream de más de 4 KB, CFB devuelve el contenido como Array, no Uint8Array**: sin normalizarlo el parche fallaba en
  silencio y la hoja salía sin rojo (lo cazó el caso de 400 artículos del test).
- ⚠ **Si los disruptivos no se pueden leer, el archivo de pedidos NO se baja**: saldría sin marcar y nadie sabría que faltan.
- Medido sept/26: LK 143 pedidos → **53 de 201** artículos en rojo (108 promedian con facturas); CH 44 → **35 de 95**.
- `sql/gv_isis_estad_disruptivos_v2620.sql` (rollback a la versión sólo-web, `_v2617`, en la cabecera).

## ⚠ REGLA (Luis, 2026-10-06, v27.36): Estadísticas ISIS vive en la pestaña 📈 EST. MADRE — plantillas subidas y bajada por mes

**Dos sectores (Luis, v27.43 «está horrible»)**: (1) **Ver la tabla**, en `admin/est-madre.js` (vale para LK y Gestión): buscar · meses a mostrar · Cajas/Unidades · «⬇ Descargar E.M.» (baja los meses mostrados); se fueron «Mes a descargar», «Descargar Disruptivas» y «Actualizar» (los disruptivos van en la bajada de pedidos). (2) **Importar / exportar**, en la barra de Gestión: Subir Est. Madre · Subir Costos · meses (varios) · casillas Pedidos LK / Pedidos CH / Facturación LK / Facturación CH · «⬇ Descargar seleccionados» (Facturación LK + CH tildadas = un solo archivo en una columna). **v27.44 (Luis: «inentendible… más grande, sin el texto de abajo, los meses con un calendario»)**: tres pasos grandes lado a lado — 1 Subir (el estado LK/CH de cada planilla va DENTRO de su botón) · 2 Meses (calendario: año con ‹ › y los 12 meses en 4×3, varios a la vez, futuros apagados) · 3 Descargar. Sin renglón de leyenda abajo: sólo aparece el mensaje del resultado.

El botón «📑 Estadísticas ISIS» salió del panel supervisor (`openEstadisticasIsis` queda en `estadisticas.js` sin
puerta). Arriba del iframe de la Est. Madre (Stock y Compras) va la barra `#emBar` (`emBarPintar`, en
`estadisticas.js`; **`admin/est-madre.js` no se toca**, es compartido con la página LK):

| botón | qué hace |
|---|---|
| ⬆ Subir Estadística Madre | lee «Loeke Madre…» (col «Cod Nuevo Isis») y «Chef Madre / Chef Master»; saltea copias «(2)» y «por menor vta». **Manda el COD ART** (Luis, v27.38: *"es lo que trackeamos"*): si la hoja tiene «Cod.Art.» (Chef: B y D) se usa ésa, no «Cod. Isis», que guarda códigos viejos de ISIS en los discontinuados |
| ⬆ Subir Costos | bloques «Loeke» / «Chef» de «Aportes Gastos» (celda con «Uni x mes…» al lado), sin cortar en una fila en blanco |
| ⬇ Bajar por mes | meses elegidos → Pedidos LK / Pedidos CH (orden Est. Madre) o **Facturación LK + CH en UNA columna** (como «Aportes Gastos»: bloque Loeke, el blanco, «Chef» y su bloque; se copia y pega una vez). Una columna por mes, del más nuevo al más viejo, **en unidades** |

- **v27.48 (Luis): lo de importar/exportar es un POP-UP que abre el botón «VIVI»** de la barra de la Est. Madre
  (`emViviAbrir` / `emViviCerrar`; X arriba a la derecha, Escape o clic afuera lo cierran). El botón vive en
  `admin/est-madre.js` escondido y sólo se muestra dentro del iframe de Gestión (la página LK no lo ve). Se sacaron el
  texto de abajo del título y el «N artículos de Stocks · …»: el status sólo dice lo que falla. En el .xlsx bajado el
  **código va CENTRADO** sea texto (026) o número (207), como en las planillas (cellXfs 10/11).
- Se guarda el ORDEN, el TIPO de cada código (505 número, '026' texto) y los renglones en blanco / títulos, para
  pegar al lado sin correr filas: tabla **`GV_Est_Plantilla`** (`gv_est_plantilla_guardar` / `_leer`, sólo supervisor).
- **LK suma lo de Chef con L** (031 = 031 LK + 031L Chef), igual que el BUSCARV + SUMAR.SI de las dos planillas.
  Medido ago/26 contra el «costo lk final»: 248 de 249 iguales. El 598E NO es error de Gestión: el Excel de ISIS pegado en
  Costos le sumó al 598E las 180 u del 599E y las 24 del 599EZ (2.328 + 180 + 24 = 2.532) y dejó esas dos filas en blanco;
  las facturas tienen cada línea con su código.
- **Colores de la Est. Madre** (su formato condicional, Luis 06/10): **celeste** = el mes pasa la E.Madre × 1,3 · **amarillo** =
  pasa la E.Madre. La E.Madre de cada código («E.Madre Uni x Mes» col I / «Est Madre Uni» col J) se captura al subir; sin E.Madre, sin color.
- Disruptivo (regla v26.20): **letra roja negrita** (no pisa el fondo) y el detalle como **comentario**.
  .xlsx con estilos reescribiendo `styles.xml` (`emXlsxBytes`). Sin UxB: 0 con comentario.
- **Para qué**: la de cobranzas sube la Est. Madre y Costos, baja y pega al lado de su columna. Por eso cada fila (blancos, títulos, Krea en 0) va donde está en su planilla.
- Código vendido SIN fila en la planilla → al código base si la planilla lo tiene (727EN → 727E, 865ED → 865E, 599EZ → 599E): la factura dice la variante y la estadística de ISIS el base. Con eso, Costos ago/26 da igual a «Aportes Gastos» en 373 de 374 filas (falta sólo el 598E). Lo que queda sin lugar (v27.40, Luis): **se avisa ANTES de bajar** (confirm con la lista) y va **al FONDO de la lista, con la fila entera en NARANJA** y la nota «No está en la planilla (Loeke/Chef): ubicarlo a mano», para que lo pasen a mano. Vale para Est. Madre y Costos (ej. ago/26: LK 599E / 599EZ).
- **Decidido por Luis (06/10), no volver a preguntar**: las NC por unidades sueltas **se siguen restando** como en ISIS
  (026 sep/26 = 165 cajas − 3 u de la NC a Coto + 36 u de 026L de Chef = 5.973 u; sale del parser de ISIS), y un código
  vendido que no tiene fila en la planilla (599E / 599EZ en Costos LK) va **al fondo en naranja**, como está.
- Una RPC vacía o con error no baja nada. `sql/gv_est_plantilla_v2736.sql`, `tests/est-madre-mes.cjs`.
