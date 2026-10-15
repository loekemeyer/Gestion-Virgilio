# Reglas Facturacion Cobranza — Facturación, Excel ISIS, recuperar items de FC, precios, cuenta corriente, coronitas, expreso ISIS

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠ REGLA (Luis, 2026-10-15, v30.96–98): FC ANULADA POR NC NO SE CRUZA CON LA NP

ISIS no dice qué FC anula cada NC (`isis_*.comprobantes_aplicados` vacío para NC, el PDF no trae el
comprobante asociado). La NC de anulación lista **los mismos artículos con las mismas cantidades y el
mismo total**: se aparea por esa firma, como **pila** — la NC anula la **última** FC viva igual a ella
emitida antes (hora de ingesta con 3 min de margen; si no, la última sin mirar la hora). NC parcial o
de descuento (`P25%`) no iguala ninguna firma y no anula nada.

- `GV_FC_Anulada` (incremental), `gv_fc_nc_aparear(p_dias=45)` — lo llama `gv_cruce_fc_asig_refrescar`
  antes de asignar (cron `gv-cruce-fc-asig`, `7-59/30`). `gv_cruce_fc_asignacion` y
  `gv_fac_complemento_cruce` excluyen las anuladas. Conciliación: chip «⊘ refacturada ×N» / «FC anulada»
  (`gv_fc_anuladas_np`).
- Caso origen: 14/10 Muare (21 FC, 13 NC), Poy y Rosemblit; las 10 NP estaban en la FC anulada.
- **Demora medida** (141 anulaciones desde 07/2026): 70 el mismo día — 49 dentro de 0:30, todas
  dentro de 2:14 desde la FC —; 17 al día siguiente; 54 a 2 días o más (devoluciones). El cruce
  recién lo ve en la corrida siguiente del cron (hasta 0:30 más).
- Centinelas v30.97 (base), código en v30.98. `sql/gv_fc_anulada_nc_v3096.sql`. Problema 803.

## ⚠ REGLA (Luis, 2026-10-14, v30.76): COL H DEL EXCEL ISIS = DIRECCIÓN DEL PADRÓN VIVO

Luis: *"que no se condicione eso desde que manda el pedido el cliente sino que esté armado con la información
más en vivo posible"*. Caso cliente LK 4142 (Poy Ignacio, LK 0367 / LK 0368): la col H salió «Poy Ignacio —
ROJAS» en vez de «General Paz 215 - Rojas». El importador de Excel de Krikos de la página LK
(`admin-excel-krikos.js`, `vendor-import-excel.js`) arma `sucursal_entrega` = razón social + « — » +
encabezado de columna; 14 pedidos de 9 clientes desde junio.

- Al bajar el Excel, `_facXlsSucViva` **dispara `gv-sync-padron-direcciones`** (LK + Chef, ~0:04, tope 20 s,
  fail-soft) y después pide **`gv_fac_xls_sucursal(nps)`**: por NP web, la etiqueta del padrón que mejor
  matchea (`gv_destino_score`, el mismo puntaje del destino de la Programación) o la única dirección del cliente.
- **Manda el padrón.** Si no resuelve (ambiguo / sin padrón) queda la etiqueta del pedido como antes; una
  etiqueta «Razón — X» sin padrón va **vacía** y sale un aviso con la NP. Nunca se adivina (v24.76).
- La Edge Function ahora contesta CORS (la llama el navegador con la sesión del supervisor).
- Centinela `gv_fac_xls_sucursal`. `sql/gv_fac_xls_sucursal_v3076.sql` · `node tests/fac-xls-sucursal-padron.cjs`.

## ⚠ REGLA (Thomas, 2026-09-23, v21.99): AGREGAR EXPRESO ISIS — la cola NO frena ningún pedido

El cliente ahora ve con qué expreso le entregamos y lo puede cambiar desde el checkout de la
página. Cada cambio cae en el módulo **🚚 Agregar Expreso ISIS** para cargarlo a mano en ISIS.

> ## **Cuando llega acá, el pedido YA SALIÓ con el expreso nuevo.**
> LK escribe la ficha (`customer_delivery_addresses`) en el acto y `v_pedidos_web` la lee **en
> vivo**, así que la PPP, el remito y el camión ya van al galpón correcto. Lo único que falta es
> dejarlo igual en ISIS para que la próxima factura salga bien.

**Por eso esta pantalla sin mirar una semana NO traba nada** — desincroniza ISIS, que es otra cosa.
Leerlo como un freno es el error a no cometer: la regla de Thomas es *"la prioridad es que el
cliente termine de mandar el pedido, sin ninguna limitación administrativa"*.

⚠ **La fila ROJA es la única que necesita llamar al cliente**: un expreso que no está en nuestro
padrón **y** que vino sin dirección (`falta_direccion`). La dirección es **opcional** del lado del
cliente a propósito. Las demás se cargan con lo que ya está.

⚠ **La clave de `GV_Expreso_Pendiente` es `(empresa, id)`.** El `id` es el de la tabla de LK; el
día que entre Chef sus ids son de su propio `bigserial` y pisarían filas de LK en silencio.

⚠ **Marcar "Cargado en ISIS" es de SUPERVISOR** y va por `gv_expreso_marcar`, no por un UPDATE
suelto: la tabla no tiene escritura para `anon`.

⚠ **Descartar NO revierte nada**: la ficha del cliente en la página ya quedó con ese expreso.
Sólo saca el renglón de la cola. El cartel del botón lo dice.

⚠ **La cola se lee PAGINADA** (`gvRestTodo`, y está en `DEBEN_PAGINAR`): es una cola, y una cola
crece sola si nadie la vacía. Un `limit=1000` ahí sería una expresión de deseo.

**Chequeo:** `select * from public.gv_expreso_pendiente;` — vacía = nada pendiente de ISIS ·
`node tests/exp-isis-modulo.cjs`. `sql/gv_expreso_pendiente_v2199.sql`, §3.mx.

## 🟥 REGLA (Luis, 2026-10-07, v27.89): la CUENTA CORRIENTE NO se le muestra al cliente — se valida en MODO SOMBRA

> ## **No se le muestra NADA de deuda ni de cuenta corriente al cliente, bajo ninguna circunstancia, hasta un pedido EXPLÍCITO de Thomas o Luis.**
> Comunicarle a un cliente un dato de esa magnitud mal es inaceptable (Luis).

| pieza | estado |
|---|---|
| página LK | `MOSTRAR_DEUDA_CLIENTE = false` (25/09) y **`get_mi_deuda()` de LK sin `EXECUTE` para `authenticated`/`anon`** (07/10). Rollback sólo con el pedido: `grant execute on function public.get_mi_deuda() to authenticated;` |
| página Chef | ⚠ **su `get_mi_deuda()` sigue ejecutable** por el cliente logueado (la página no la llama). Hay que revocarla en el proyecto Chef: la sesión no tiene acceso |
| validación | **modo sombra** en Gestión: mide, no muestra |

**Modo sombra** (`sql/gv_cc_sombra_v2789.sql`; el marcador interno dice `v27.88-cc-sombra`: llave, no cambiar; cron **143 `gv-cc-sombra`**, `9-59/10`, anti-solape): cada Excel de deuda nuevo
(Cuarentena) se copia a `GV_CC_Ancla` (el detalle se reemplaza en cada subida) y se compara, cliente por cliente, contra lo que
el sistema habría estimado desde el Excel anterior: `excel+isis` (ancla + facturas/NC/ND de ISIS posteriores) y
`excel+isis-banco` (− recibos de la conciliación, misma lógica que `gv_cobranza_deuda_viva_refrescar`). Un cruce está OK si
ningún cliente difiere en $1 o más (`GV_CC_Sombra_Config.tolerancia`).

- **Racha** (`gv_cc_sombra_racha`, v27.93): suma los días hábiles **cubiertos** por cruces OK seguidos — cada cruce cubre
  (corte anterior, corte nuevo]. **Un día sin Excel NO corta** (Luis: *"va a haber días donde no se sube el excel"*): lo valida
  el Excel siguiente junto con los otros días. Sólo un cruce con diferencia corta.
- **CORTE del Excel** (v27.93, `gv_cc_sombra_corte`): el Excel es la deuda al CIERRE de un día, no a la hora de la subida.
  Corte = fecha ISIS más nueva de los comprobantes que trae. Todo lo de fecha <= corte YA está adentro (renglón, imputado o
  anulado: FC + NC del mismo día que se cancelan no aparecen); se suma sólo lo de fecha > corte, FC/ND/NC por igual
  (`gv_cc_sombra_estimar(text,text,date)`; la de `timestamptz` quedó sin llamador). Corrige las dos causas de la prueba del 07/10.
- Con **20** (`racha_objetivo`) `gv_cc_sombra_tick` abre **UNA tarea por empresa** en el Planify de **Luis (52)**: «Implementar
  cuenta corriente en página LK/CHEF» (`GV_CC_Sombra_Aviso`). **La tarea no prende nada**: implementar sigue pidiendo el pedido explícito.
- Lectura: `select * from public.gv_cc_sombra_estado;` y el detalle por cliente en `GV_CC_Cruce_Detalle` (sólo service/MCP).
- Primeras anclas: LK y Chef del 07/10 11:11/11:13. Los Excel anteriores se perdieron (sólo quedan los `.xls` del bucket `cuarentena`).
- **Causas ya vistas en la prueba del 07/10** (son las que hay que cerrar para llegar a 0): (1) el Excel de las 11:11 NO trae la
  factura de Matiz emitida esa mañana (FC 0004-36161, $8.179.600) — el corte del Excel no es la hora de la subida; (2) una FC +
  su NC de anulación del mismo día cuentan la FC y no la NC (regla de `deuda_viva`: la NC del día del ancla se saltea) →
  Cencosud $21.190 y Garbarino $20.778 de más.

Centinelas 349 y 350. `tests/cc-sombra-no-mostrar.cjs`.

## ⚠ CONCEPTO (Luis, 2026-09-30, v24.72): «TENER CORONITA» = plazo preferencial dentro del descuento de CONTADO

**Luis:** *"trato preferencial de algunos clientes en términos de plazos para cobrarles que los
consideramos dentro del descuento de contado … internamente Thomy les dice que «tienen coronita»"*.

> **Un cliente con coronita cobra el −25 % de CONTADO aunque pague después de los 14 días de la
> escala, hasta SU plazo** (20, 30 o 60 días). No es otro escalón: es el contado estirado.

- **Dónde vive:** `public.cobranzas_excepciones` (una fila por cliente; `deudor_id` = **CUIT**,
  `cod_cliente` = `LK 288 / CH 271`, `escalon='contado'`, `dias` = plazo, `dto` = 0,25,
  `autorizado_por` = Thomas). Se cruza **por CUIT del padrón**, no de la factura (v23.18). La lee el
  agente de cobranzas (`gv_cobranza_imputar`) para no marcar como «descontado de más» a quien tiene coronita.
- **Dónde se ve:** Cobranzas → **📐 Escala**, debajo de la escala, con buscador (`cbzCoronitasHtml`,
  `cobranzas.js`). Al 30/09: **175 clientes** — 153 a 20 días, 3 a 30, 19 a 60 (los «30/60» de la
  planilla quedaron en 60). Fuente: planilla de Thomas del 28/09 (el `motivo` guarda el texto original).
- **Alta / cambio:** es un `insert`/`update` en esa tabla (lo autoriza Thomas), no un deploy.
- `tests/cbz-coronitas.cjs`.
- ⚠⚠ **«30/60» NO es un plazo de 60 días** (Luis, 30/09): el cliente paga **la MITAD a los 30 días y la
  otra mitad a los 60**, y mantiene el −25 %. Hoy esas coronitas (20 al 30/09, Solia incluida: CUIT
  30540036353, LK 151 / CH 151, id 178) están cargadas como `dias = 60` y el agente (`gv_cobranza_imputar`,
  `v_dias <= v_dias_contado`) les da el 25 % a **cualquier** pago hasta el día 60 — **también a quien paga todo
  a los 60**, que por la regla no lo gana. **Está a propósito así hasta que Luis vea cómo se implementa**
  (D27, 30/09: *"quiero ver cómo se implementa"*): no tocar el agente sin mostrarle antes la propuesta. La
  forma de reconocerlas es el `motivo` con «30/60».

## ⚠⚠ REGLA (Luis, 2026-09-25, v22.66): los PRECIOS se cambian en la fuente de la PÁGINA, nunca en `precios_venta*`

**Luis:** *"deberíamos cambiarlo de las tablas que toma la página tocando lógica. Anotá que cualquier
cambio a precios se tiene que hacer así para que otra sesión no labure al pedo"*.

`precios_venta` (LK) y `precios_venta_chef` (Chef) son **ESPEJOS**: los reescribe la Edge Function
`sync-precios-venta` (cron **66**, cada 15 min) desde el catálogo de productos de cada página, y lo que
no está en el catálogo **se borra** (`reconcileStale`). Un `insert`/`update` a mano ahí **dura hasta la
próxima corrida**. Y `precios_venta_chef` además decide **de qué empresa es un artículo**
(`gv_articulo_empresa`, `gv_mov_empresa_resuelta`, `vista_nombres_articulos`): meter un código de LK ahí
lo pasa a Chef en todo Gestión.

> **Un precio se cambia en la tabla de productos de la página (proyecto LK `kwkclwhmoygunqmlegrg` /
> Chef `nkhzocgdpwtgrmwleihr`) o tocando la LÓGICA que lo resuelve — nunca cargándolo en el espejo.**

Caso que lo originó (25/09): 439E, 809, 838E y 865ED se facturan por Chef (Dorinka, TdF) con precio de
la **lista LK** y no están en el catálogo de Chef. **Se dejó así** (Luis). Dorinka además tiene lista
especial (−33 % a +29 % contra lista Chef), así que su factura no sirve de precio de lista.

## ⚠ REGLA (Luis, 2026-09-28, v23.59): Facturación va POR DÍA (plegable) — y LK + CH juntas bajan 2 Excel

La tabla del Facturador se agrupa por **fecha de entrega**, como la Programación de la PPP: una cabecera por
día (las sin fecha al final) con su casilla, que marca **sólo las NP web de ese día**; marcar varios días suma (v23.61: tocar la cabecera pliega el día; queda plegado entre refrescos)
sus NP. **No hay casilla global.** Si la selección tiene NP de **LK y de CH**, sale el aviso amarillo y el botón
dice *«2 archivos LK + CH»*; al bajar salen **dos Excel**, uno por ISIS (la división ya existía por `isisEmp`:
una NP LK de Tierra del Fuego va al de CH). `facXlsDia`, `facXlsMezcla`, `tests/fac-por-dia.cjs`.

## ⚠ REGLA (Luis, 2026-09-25, v22.53): ♻ RECUPERAR ITEMS DE FC — completar la facturación de una NP ya facturada

**Luis:** *"que se pueda completar la facturación de un pedido ya facturado en caso de que ingrese
mercadería entre la facturación y la entrega al cliente"*. Botón verde **♻ Recuperar pedido** en el
encabezado de Facturación.

| paso | cómo |
|---|---|
| lista | `gv_fac_recuperar_lista(p_dias)`: NP facturadas, buscador por varias palabras, filtro LK/CH, días y «sólo con faltantes» |
| detalle | `gv_fac_recuperar_detalle(np)`: por código **faltó al facturar** (reconstruido), **completado después** (CP), ya complementado, **pendiente** (tope). Lo completado después viene tildado |
| ✔ Marcar como facturado | ya se facturó **a mano** en ISIS antes (el confirm lo dice). Graba el lote modo `marcado` |
| ⬇ Excel ISIS | `_facXlsArmar(nps, {lineas, cab})` con **sólo** los códigos marcados. Graba el lote modo `excel` **antes** de bajar |
| cruce | `gv_fac_complemento_cruce()` (corre con el cron 90) busca la factura de cada lote: mismo cliente, ±10 días, cajas ±15 %, todos los códigos en la factura. Queda en `GV_Fac_Complemento_Doc` |

⚠ **«Faltó al facturar» se reconstruye**: `cp_reducir_faltante_cap` (Completar Pedido) **suma a
`cajas_entregadas`** y resta de `cajas_falto`, así que después de un CP la fila ya no dice lo que se
facturó. Se descuenta lo que CP sumó **después de `facturado_at`** (`Movimientos_Stock` tipo `cp` a
`a_facturar`, `ref` = NP).

⚠ **El cruce principal se enteró**: la factura de un complemento **no es candidata** para la NP, y lo
que CP sumó después de facturar se descuenta del `cajas_ent` contra el que compara (en un CTE: por
subselect pasó de 1,6 s a > 60 s). Conciliación muestra el chip **♻ +N cj** en la NP.

⚠ **No mueve stock**: lo físico va por Completar Pedido, que ya drena `a_facturar` si la NP estaba
facturada. **No toca `Facturacion_NP`** (una fila por NP): los complementos viven en `GV_Fac_Complemento`.

`sql/gv_fac_recuperar_pedido_v2253.sql`, `tests/fac-recuperar-pedido.cjs` (el marcador interno de las funciones dice `v22.52-compl`: es la llave de idempotencia, no cambiarlo).

⚠ **v22.59 (Luis): cada botón abre el cartel «¿Querés que saquemos de góndola los artículos
seleccionados?» SÍ / NO** (✕ = no se hace nada). **SÍ** descuenta de góndola (`terminado`) **aunque quede
en negativo**; el movimiento va `tipo='ajuste'`, `ref='<NP>|FCC'` y `descripcion` *"Sale de góndola:
facturado con «Recuperar items de FC»…"*. **NO exige escribir por qué** (backend: `p_motivo_no_stock`, si
falta da error) y queda en `GV_Fac_Complemento.stock_detalle.motivo_no`. Lo completado con Completar
Pedido después de facturar ya drenó y **no se descuenta dos veces**. Candado `pg_advisory_xact_lock` por
NP + freno de doble clic. `sql/gv_fac_recuperar_stock_v2259.sql` (reemplaza la `_v2258`). **El aviso de Telegram de
stock negativo SE DEJA** (Luis): para estos movimientos dice el motivo y el stock en A guardar / Racks /
Excedente, *"registren el movimiento si salió de ahí"* (`sql/gv_fac_recuperar_aviso_negativo_v2261.sql`).

## ⚠ REGLA (Thomas, 2026-09-30, v25.40): el SECUNDARIO sin stock se cambia SOLO por el principal en la NP web

**Thomas:** *"los pedidos nuevos se manejan primero desde Gestión y recién al final llegan a ISIS: la corrección
la puede hacer el programa, no una persona"*. Antes el panel 🔀 «Corregir códigos» pedía cambiar la NP en ISIS
y tocar «✓ Ya lo cambié».

- **`gv_web_np_sec_auto(p_simular)`** (cron `gv-np-sec-auto`, jobid 119, `2-59/5 9-23 * * *`) usa el criterio
  del panel (`vista_correcciones_pedido_rich.sec_cubre = false`) y cambia la línea en `PPP_Web_Base`
  (333 → 948E); si la NP ya trae el principal, suma. **No toca**: tanda EMPEZADA (sigue el panel), NP armada o
  facturada, familia de otra empresa, **cajas que no dan enteras** (el UxB cambia: 332 de a 24 → 945E de a 12,
  se convierte por unidades). **La L se conserva** (333L → 948EL).
- El registro es **`GV_NP_Cambio_Codigo`**. La Edge Function `gv-ppp-web-tandas-diarias` (v44) lo aplica al
  rearmar la NP cada 5 min — sin eso el pedido de la página devolvía el 333 y el podado sacaba el 948E. Si no
  puede leer la tabla, NO escribe la foto.
- Red en la base: el trigger `trg_gv_ppp_web_base_np_cambio` descarta el secundario ya cambiado (lo mandan
  crudo `pppGuardarWeb` y `gv_ppp_web_tanda_programar`) y `gv_ppp_web_base_podar` sabe que el principal ES esa
  línea. Sin eso, en una tanda empezada quedaban los dos códigos: doble picking.
- Interruptor `PPP_Web_Config.np_sec_auto_activo` (0 = sólo simula). Rollback de UN cambio: borrar su fila.
- ⚠ Los marcadores internos dicen `v25.39-…` (llave de idempotencia): no cambiarlos.
- `select * from public.gv_web_np_sec_auto(true);` — qué cambiaría. `sql/gv_np_secundario_auto_v2540.sql`,
  `tests/np-sec-auto.cjs`.

## ⚠ REGLA (Luis, 2026-10-05, v26.69): Entregados dice cuándo LLEGÓ el pedido · Stocks e Insumos bajan a Excel

- **📥 dd/mm** en cada NP de Pedidos Entregados = la fecha en que el cliente mandó el pedido (web: `lk_pedidos_match`
  fecha + hora; ISIS: «Fecha Recep» de la PPP / base de pedidos), **no** la de programación. Forward-facing:
  `GV_NP_Fecha_Pedido` + cron `gv-np-fecha-pedido` (59 * * * *). Las NP de ISIS anteriores al 23/06 no tienen el dato:
  van sin chip, no se inventa. Aplicado el 05/10 (Luis, SQL Editor; cron jobid 130): 1.007 de 1.473
  entregados con fecha. El front suma además las fuentes vivas (lo de la última hora).
- **⬇ Excel** en Stocks baja lo que muestra la tabla (las filas salen de `stkBodyStocks` → `_stk._xl`; no volver a
  escribir una segunda cuenta en `stkDescargarExcel`). **⬇ Excel de insumos** en Insumos = «Todos los insumos» con sus
  filtros. Revierte el «se sacó Descargar Excel» de la v8.93: lo pidió Luis.
- **La barra de Stocks va SIN emojis y con el texto en DOS renglones** (Luis, v26.72: *"sacá emojis y meteles el texto en
  doble fila"*): todos los chips usan el molde `_stkChip2` (alto 38, letra 11,5); el estado prendido lo dice el color, no
  ☐/☑. Al agregar un botón a esa barra, va con ese molde.
- `tests/stk-excel-stock-insumos.cjs`, `tests/ppp-ent-fecha-pedido.cjs`.


## ⚠ REGLA (Luis, 2026-10-14, v30.42): la factura ANTICIPADA también cruza con su NP

La ventana del cruce FC ↔ NP (`gv_cruce_fc_asignacion`, cron **90** `gv-cruce-fc-asig`, a los :07 y :37)
va desde **la fecha más temprana entre salida y envío a facturar − 3** hasta **la más tardía + 3**. Antes
arrancaba en salida − 3 y toda NP facturada más de 3 días antes de salir quedaba «sin factura» (LK 0421:
FC 14/10, salida 04/11; 72 de 98 NP afectadas desde mayo). Centinela 463.
`sql/gv_cruce_fc_asignacion_v3042.sql`.

## ⚠ REGLA (Luis, 2026-10-14): Matiz 552xx y 702EN — NO PREGUNTAR, NO TOCAR

- **Artículos 552xx (Matiz SA)**: hoy **cada caja = 1 unidad** (`uxb = 1`). Las NP viejas que se cargaron en
  cajas de 24 / 6 (98109 con 55215, 97889 con 55219) dan diferencia en Conciliación: **es historia, no se corrige
  ni se reporta**. Luis: *"no lo jodas"*.
- **702EN no tiene que existir**: es un código viejo. Que no tenga uxb en el maestro está bien; no se carga.
  El que vale es **702E** (12 por caja): medido el 14/10, 46 de 56 NP de Chef cruzan exactas y las otras 10
  (44467–44508) se facturaron como 702EN con las mismas unidades.
- **No volver a proponer** cargar uxb para estos códigos ni preguntar por ellos.
