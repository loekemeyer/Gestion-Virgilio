# Reglas Cuarentena — Cuarentena, deuda, cliente retenido, liberar, pedido partido

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠ Regla de Luis (2026-09-17, v19.44): la REPOSICIÓN CHICA no cae en cuarentena

*"Si un cliente hizo un pedido, se le factura (tiene deuda) y en un plazo de 10 días desde la
facturación entra un pedido de ese mismo cliente de 1 item (un código nada más que pide) debería
quedar exceptuado de la cuarentena."*

**Perdona SÓLO `deuda`.** Suspendido, sin cta cte y cliente nuevo siguen reteniendo. Configurable
en `PPP_Web_Config.cuar_repo_motivos`; `limite_credito` no entra ahí (lo arma
`gv_cuarentena_limite`, no `marcar_calc`). El plazo se cuenta contra la **fecha del pedido** y el
`max(fecha)` de la factura va **topeado a esa fecha** — sin el tope entran facturas posteriores al
pedido. Los ítems salen de `lk_pedidos_match.items_string`; la factura, de `isis_lk`/`isis_ch`
(la fuente de deuda no tiene fecha). Una NP de ISIS no se exime: sin datos, retener.

⚠⚠ **El primer intento (v19.41) dejó la CUARENTENA EN 0 y se revirtió (v19.43). Dos lecciones que
valen para cualquier cambio, no sólo para esto:**

1. **Un cast protegido por un regex en la MISMA condición no protege nada.** Postgres evalúa el
   cast primero. `(p.order_id)::bigint` con `'npNNNNN'` → `22P02` y la RPC entera devuelve 400.
   Se castea el bigint **de la tabla** a texto (`lp.order_id::text = p.order_id`), nunca al revés.
   Es el mismo pozo del problema 358, que ya estaba escrito acá.
2. **Lo nuevo no puede ir adentro del `Promise.all` de lo que ya funciona.** La RPC del chip
   estaba ahí: al fallar, el `await` tiró y `cuarMarcarPedidos` entero cayó al catch, o sea que
   **ningún** pedido quedó marcado. Ahora va en su propia llamada con su propio catch, y el
   backend llama al envoltorio **`gv_cuarentena_repo_seguro`**, que atrapa cualquier excepción y
   devuelve vacío (nadie exento = todos retenidos).

**Y se prueba rompiéndolo a propósito**: con `gv_cuarentena_repo_lote` reemplazada por un `1/0`,
`marcar_calc` tiene que seguir devolviendo los retenidos (medido: 60 rota / 59 sana).

**Chequeo:** `select * from public.gv_cuarentena_repo_hoy where exento;`
`sql/gv_cuarentena_repo_chica_v1944.sql`, §3.iy.

## ⚠ Regla de Luis (2026-09-21): la CUARENTENA se mide por SUCURSAL, y Retira nunca exime

*"Para clientes que tienen múltiples sucursales, se debería llevar registro por el «a qué sucursal
se corresponde la deuda»… si un cliente tiene direcciones de entrega A y B, hace hoy un pedido
para A, se le arma, se le factura y se le envía (generándole deuda) y en ese momento, antes de
pagar, quiere hacer un pedido para sucursal B, este debería pasar sin ser retenido."*

**Las dos decisiones que cierran la regla, textuales del 21/09: «retiene, y toda la deuda viva».**

1. **Deuda que NO se pueda atribuir a una sucursal → RETIENE.** Sin atribución no hay excepción:
   es el mismo criterio que la reposición chica (*"sin datos, retener"*).
2. **La ventana es TODA la deuda viva**, no los últimos N días.
3. **Retira nunca exime.** Un cliente con una sola dirección real no convierte su Retira en
   "otra sucursal"; y al multi-sucursal, con cualquier deuda, el Retira lo retiene igual.
4. La clave de la sucursal es **`dir_key`** (`gv_dir_key(direccion, barrio)`), **no** la etiqueta
   `sucursal_entrega`: Chef trae la dirección en el 100 % de sus pedidos web y la etiqueta casi
   nunca (48 de 56 pedidos de 60 días sin ella). Por eso la regla vale para **LK y Chef**.

**La cadena, y por dónde NO va:**

```
comprobante del Excel de deuda -> factura de ISIS (gv_comprobante_key)
  -> GV_Cruce_FC_Asig  -> NP -> GV_NP_Sucursal -> dir_key
```

⚠ **No va por el remito.** Se probó (`GV_NP_Remito`) y rinde **101** NP contra **923** del cruce
NP↔FC, y no aporta una sola NP propia: de las 114 que tienen remito cargado, las 114 ya están en
el cruce. Luis lo frenó el mismo día: *"la idea del remito no sirve… cruzás NP con FC"*.

**Lo que hay que saber antes de tocar esto:**

- **El Excel de deuda SÍ trae el detalle por comprobante** (Crystal agrupado: col E = comprobante,
  col L = pendiente). Hasta la v20.35 el front lo leía y lo tiraba: mandaba sólo el total por
  cliente. Ahora se guarda en **`GV_Cuarentena_Deuda_Detalle`**, y desde la v20.37 **el archivo
  crudo queda en el bucket `cuarentena`** (antes no se subía a ningún lado y había que volver a
  pedírselo a quien lo bajó del ERP).
- **La dirección de una NP de ISIS vive un día.** `GV_PPP_Programacion_Diaria` tiene sólo lo
  programado (133 filas al 21/09) y después se borra: por eso existe **`GV_NP_Sucursal`**, que la
  captura cada hora (cron 97). Lo viejo no se recupera — el registro empieza el 21/09.
- **Chequeo:** `select estado_cadena, count(*) from public.gv_cuarentena_deuda_sucursal group by 1;`
  — `ok` es lo que llega a la dirección; `sin factura parseada` tiene que dar 0.

## ⚠⚠ REGLA (Thomas, 2026-09-22, v20.95): el ARMADO AUTOMÁTICO no programa CUARENTENA ni CLIENTE NUEVO sin aprobación humana

**Thomas, textual:** *"armado automatico no debería programar automaticamente clientes nuevos ni
clientes en cuarentena que no hayan sido aprobados por un humano, nunca. Si ya fueron aprobados y
se atrasa la entrega o algo asi, si se puede reprogramar automaticamente, pero primero aprobado
por humano."*

**Hasta el 22/09 la retención vivía SÓLO en el front.** Medido sobre `pg_proc`: ni
`gv_ppp_web_armar_pendientes`, ni `ppp_web_armar_tandas`, ni `gv_ppp_web_juntar_clientes`, ni
`gv_pedidos_web_excluidos` nombraban la palabra cuarentena. El armador sólo saltea lo diferido
(a0), lo retenido **a mano** en `GV_PPP_Web_Retenido` (a0b) y lo cancelado (a0c): alcanzaba con
que el pedido no tuviera fila ahí para que el cron lo programara igual.

| NP | cliente | motivo | quedó en |
|---|---|---|---|
| LK 0094/95/96 (1448) | Silvano Lucas Martin (4282) | **cliente nuevo**, pipeline en `ingresado` | E72A · 28/09 |
| CH 0004 (218) | Ierakuin Srl (1665) | **deuda $2.062.528,58** | E71A · 28/09 |

A los dos los había devuelto Vivi a mano el 18/09 (*"No pago"*) y los dos volvieron solos, sin una
fila en `GV_Cuarentena_Liberados`.

**APROBADO POR HUMANO = fila en `GV_Cuarentena_Liberados`** que levante ESE motivo. La escriben el
botón de Cuarentena y el ✅ del pipeline de Clientes nuevos (los dos vía `gv_cuarentena_liberar`).
Aprobado, el pedido vuelve a los pases normales y se reprograma solo como cualquier otro.

⚠ **El criterio de QUÉ retiene no se duplica en el armado**: lo da `gv_cuarentena_marcar_calc`, la
misma que usa la pantalla, con sus excepciones vivas (`gv_excepcion_cuarentena`, reposición chica
v19.44, mismo pedido v20.52, resta de motivos liberados v20.86). Si cambia una regla de cuarentena,
el armado la hereda sola. Medido: **Suppa (1482, deuda $836.909) NO retiene**, porque su deuda es
la factura de otra NP del **mismo** pedido.

⚠ **`gv_cuarentena_ya_programado()` marca DE MÁS**: no aplica esas excepciones, así que lista a
Suppa como retenido-y-programado cuando la Cuarentena no lo retiene. Es un centinela con falsos
positivos, no una fuente.

⚠⚠ **`gv_cuarentena_retiene_lote` es FAIL-CLOSED, al revés del patrón de la v19.44**: si no se
puede evaluar, devuelve **todo el lote** y no se programa nada. Un armado que no corre se ve
(`GV_PPP_Web_Armado_Log`, `gv_ppp_web_armado_salud`); un pedido con deuda que sale en el camión, no.
Y ojo: el `WHERE` de `gv_cuarentena_marcar_calc` termina en `(es_supervisor_virgilio() or
gv_es_supervisor_o_servicio())`, o sea que **sin permiso devuelve CERO FILAS** — leído como *"no hay
retenidos"* sería el mismo bug al revés. Por eso el chequeo de identidad se hace **antes y afuera**.

⚠ **No costó tiempo: lo bajó.** El pase va **después** del tope (a00), así evalúa a lo sumo
`armado_tope_pedidos` (120). El guard cuesta 1.041 ms sobre 218 pedidos (766 son
`gv_cuarentena_mismo_pedido_seguro`), pero el armado cuesta ~43 ms por pedido y los retenidos
dejaron de procesarse: LK con ~170 de entrada pasó de 4.515 / 5.499 / 4.951 ms a **4.327 / 4.306**.

⚠ **El alias del subselect es `_cq_r`, no `r`** — la función declara `r record` y un alias `r` la
vuelve ambigua: explota **en ejecución** con `42702`, no al crearse (pozo de la v19.56). Volvió a
morder en el primer intento y **lo cazó la prueba, no la lectura**: se corre el armador con un
retenido y un cliente sano dentro de una transacción abortada, y se prueban **las dos mitades** de
la regla (sin aprobar → sin tanda; con fila en Liberados → se programa).

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien.
`sql/gv_armado_cuarentena_v2095.sql`, §3.me.

## ⚠ REGLA (Luis, 2026-09-23, v21.47): una RESPUESTA no opina sobre lo que no PREGUNTÓ

**Luis, textual:** *"primero revisá por qué Ierakuin no está en el submódulo de cuarentena. Se
sigue escapando y seguís sin poder arreglarlo"*.

Síntoma: **`web CH 218 · Ierakuin Srl (CH 1665)`** se dibujaba en la lista normal de «Pedidos a
programar» **con el chip 🚧 «retenido en cuarentena · no se arma solo»** —que lo pinta el
backend— mientras el submódulo Cuarentena no lo tenía. Los dos lados decían cosas distintas del
mismo pedido.

**Medido:** `gv_cuarentena_marcar` devuelve ese pedido con `motivos ["deuda"]` y
**$2.062.528,58**. El backend nunca se equivocó; lo que fallaba es cómo el front aplica la
respuesta.

**La causa.** Los pedidos de **Chef llegan tarde** (otra vuelta de red: `gv_pedidos_web_np_chef_admin`
por FDW), así que `cuarMarcarPedidos` corre **dos veces por carga** (v20.98): la primera con
LK+ISIS y la segunda, cuando Chef ya está, con la lista completa. Las dos terminaban recorriendo
`_apr.pedidosTodos` —que para entonces **ya incluye a Chef**— y **borrando la marca de todo
pedido que su respuesta no nombrara**:

```js
else { if (p.cuarentena_motivos) delete p.cuarentena_motivos; … }
```

La corrida de LK **no preguntó por Chef**, así que si contesta última le borra la cuarentena al
único pedido de Chef. Es una carrera —por eso aparece y desaparece, y por eso la v20.98 parecía
haberlo arreglado—: alcanza con que la llamada de LK se reintente una vez (v20.96, los timeouts
son frecuentes) para que llegue después.

> **La regla:** una marcación toca **sólo los pedidos de su propio lote**. Lo que no preguntó no
> lo sabe, y no saber no es "no retiene".

⚠ **Lo que SÍ se sigue limpiando:** un pedido que estaba en el lote y ya no retiene pierde la
marca, o un liberado quedaría retenido para siempre. El test muerde por los dos lados.

⚠ **Es el mismo pozo de §"una lectura ROTA no es un CERO", un paso más adelante:** ahí el cero
venía de un feed caído; acá viene de *"no pregunté"*. En los dos casos el front lo leyó como
*"no hay"*.

**Chequeo:** `node tests/apr-cuar-chef-tarde.cjs` — corre las dos marcaciones de verdad, con la
de LK contestando última. Verificado que falla contra el código anterior (*"el pedido de Chef
perdió su cuarentena"*).

## ⚠⚠ REGLA (Luis, 2026-09-24, v22.17): el freno de cuarentena vale también A MANO — y el liberado se REEVALÚA

**Caso LK 1475 · Oriental Party (LK 1618, deuda $3.222.078,75)**: el 24/09 entre 10:01:21 y
10:03:43 `gv_cuarentena_marcar` le dio **500 siete veces** al navegador; A Programar lo dibujó
sano y a las 10:03:38 se programó a mano (terminó en E92A). Nadie lo aprobó. Problema 528.

| capa | qué hace desde v22.17 |
|---|---|
| **servidor** | `gv_ppp_web_tanda_programar` y `gv_ppp_web_tanda_reusar` llaman a `gv_cuarentena_retiene_lote` (el MISMO criterio del armador, fail-closed): retenido sin aprobar → error `CUARENTENA: …`; no se pudo evaluar → error *"no se programó nada, probá de nuevo"* |
| **front** | `aprGenerarTanda` no programa un pedido web cuya cuarentena no se pudo VERIFICAR (`p._cuarOk`, lo pone la marcación sólo en los pedidos de su lote). Sin marca no hay "no retiene": hay "no sé" |
| **liberar** | `gv_cuarentena_liberar` borra la fila de `GV_PPP_Web_Retenido`: aprobado, el pedido **olvida la tanda de la que lo sacaron** y el armador lo reprograma con la lógica normal. En cuarentena el chip dice *"↻ al aprobarlo se reprograma"*, no *"vuelve a E92A"* |

⚠ **Olvidar la tanda es SÓLO para el pedido limpio** (v22.18, Luis: *"que no queden datos del picking
o del armado que después distorsionen"*): si al sacarlo ya estaba pickeado o armado
(`ya_pickeada`/`ya_armada` de la tabla, que acá SÍ es la foto correcta: la del pedido) o tiene
`Entregas_Virgilio` vivas, la memoria **queda**, el armador lo sigue salteando y decide una persona.

⚠ **Las NP de ISIS no tienen el freno del servidor** (el armador tampoco las evalúa): sólo web. No
entran más NP de ISIS nuevas (Luis, 24/09), así que no se extiende.
**Chequeo:** `select * from public.gv_reglas_perdidas;` · `node tests/apr-cuar-freno-manual.cjs` ·
`node tests/apr-fit.cjs`. `sql/gv_cuarentena_freno_manual_v2217.sql`.

## ⚠ REGLA (Luis, 2026-10-01, v25.49): en CUARENTENA, la factura de MENOS DE 5 DÍAS corridos no es deuda

Vale para todos los clientes, en la retención (`gv_cuarentena_deuda_pedido` → `gv_cuarentena_marcar_calc`, y el
armador la hereda) y en la alerta de lo ya programado (`gv_cuarentena_ya_programado`, CTE `_rec5`). Se mide por la
**fecha de cada comprobante** (la del reporte de deuda o, si no, la que tomó el parser de ISIS): la deuda más vieja
del mismo cliente **sigue reteniendo**. Un comprobante sin fecha cuenta (retiene). Medido el 01/10: la alerta de
programados pasó de 10 a 0 (Jazquel y Bazar y Cia, toda su deuda del 30/09); Oriental Party (deuda del 08/09) sigue.
`sql/gv_cuarentena_deuda_5dias_v2545.sql` (backup de las definiciones en `zz_backups."GV_Backup_CuarDeuda5_defs_20261001"`).

## ⚠ REGLA (Luis, 2026-09-25, v22.46): el PEDIDO PARTIDO por importados es UNO — cuarentena y cliente nuevo

**Luis:** *"si bien se parte en dos pedidos para poder programarse, realmente surge de un mismo pedido
del cliente"* · *"es solamente un pedido para tema del límite de los 3 primeros pedidos"* · *"todo lk y ch"*.

La página parte el pedido cuando trae importados sin stock: la parte que espera reingreso es otro
`order_id` con `lk_pedidos_match.pedido_origen` = el original (LK: `orders.sheets_payload`; Chef:
`chef_orders_cache.sheets_payload`, las dos viajan por `sync_pedidos_match_virgilio`).

| qué | cómo |
|---|---|
| aprobar una parte aprueba todo el pedido | `gv_cuarentena_liberados_familia` (Liberados + herencia por `pedido_origen`, las dos direcciones), leída por `gv_cuarentena_marcar_calc` (MATERIALIZADA una vez) y `gv_cuarentena_ya_programado` |
| la parte diferida NO se programa sola si el cliente está retenido | pase **(a0d2)** del armador: `v_dif` pasa por `gv_cuarentena_retiene_lote`. Antes (b2) lo programaba sin mirar: LK 1546 (Solia) → F01A |
| cuenta como 1 pedido para los 3 de cliente nuevo | LK `gv_clientes_nuevos_calc`: una fecha de factura que es **sólo** de artículos de una parte diferida no suma (`hijo_it` / `fecha_hijo` / `corr`) |
| **o quedan las dos partes en cuarentena o ninguna** (v22.47) | la reposición chica (v19.44) NO exime a un pedido partido: la parte diferida suele tener 1 código y zafaba sola |
| en Cuarentena es **UNA fila** (v22.47) | `cuarAgrupar` + `gv_pedidos_partidos()`: chip 🧩 *N pedidos (1 partido)*, m³ sumado, «Enviar» apunta al original y aprueba todo. `tests/apr-cuar-pedido-partido.cjs` |

⚠ **Caso Solia: la cuarentena NO la causó el partido.** La deuda de $3.421.315,29 es de facturas
del 17/08 y 10/09 (NP 98427/28, 98613/14). Lo que estaba mal es que la mitad diferida se programó
sola sin aprobación.

⚠ **No meter una función con `= any(...)` dentro del lateral de Liberados**: se probó y la
marcación pasó de 366 ms a 10 s (timeout 8 s). Va la vista materializada.

⚠ En LK, **`chef_customers` es FDW** (+2 s por lectura): usar `chef_customers_cache`.

`sql/gv_pedido_partido_cuarentena_v2246.sql`, `sql/gv_clientes_nuevos_calc_hijo_v2246_LK.sql`.

## ⚠⚠ REGLA (Vivi, 2026-09-23, v22.03): estar PROGRAMADO no garantiza la caja — si no hay stock, no se cobra

**Vivi, textual:** *"si ya no hay stock del 323E, no debo cobrarselo. esa logica no la tenes ya
explicada?"*. La tenía (regla v20.41: el importado sin stock no entra en el monto) y **no estaba
corriendo**.

`gv_clientes_nuevos_valor_lote` y `gv_clin_composicion` reparten los importados escasos con un
greedy por `(fecha_pedido, hora, order_id)`, y le hacían un **atajo** al pedido que ya figura en
`gv_demanda_programada_pendiente`: *"sus cajas ya se contaron en `_prog`, no compite"* → `falta = 0`.

> **El atajo supone que lo PROGRAMADO entra en lo DISPONIBLE. Cuando no entra, la reserva es
> ficticia y el sistema dice "tiene stock" con la góndola vacía.**

**Medido el 23/09 sobre `web LK 1448`** (Silvano, LK 4282, cliente nuevo en cuarentena): sus 3 NP
están en la vista con `tanda = ''` y `fecha_entrega` **NULL** — o sea **desprogramadas** — y aún así
disparaban el atajo. Los **17** importados salían con `cajas_falta = 0` y `valor_importados = 0,00`,
y **7 estaban sobrevendidos**:

| código | disponible | programado |
|---|---:|---:|
| 035E · 323E · 970E · 971E | **0** | 8 · 10 · 3 · 4 |
| 590E | 3 | 64 |
| 583E | 5 | 17 |
| 584E | 15 | 28 |

**Cómo queda:** si de un código hay menos disponible que programado, se reparte lo que hay entre
**toda** la demanda programada por su `prioridad` — que ordena por fecha de entrega, y **la NP sin
fecha va ÚLTIMA**, que es justo el caso del cliente nuevo retenido — y cada pedido se queda con su
parte. Lo que no cubre es `cajas_falta`, sale con `importe = 0,00` y **no se cobra**.

⚠ **Cuando lo programado SÍ entra en lo disponible, `cubiertas = cajas` y el resultado es
idéntico al de hoy**: el cambio muerde sólo en el sobreventa. Verificado con 529E y 812E del mismo
pedido, que siguen en `falta 0`.

⚠ **`cubiertas` queda NULL, no 0, cuando ese código del pedido no tiene fila en la vista** (una NP
ya facturada mientras otra sigue viva). Ahí **no se asume faltante**: cae al greedy normal contra
`libre`. Un `coalesce(..., 0)` habría dicho *"no hay"* sin haber medido nada.

⚠ **El valor_lote llevaba además el doble conteo que la v21.96 ya le había sacado a la
composición.** `order_items` de LK trae **dos filas** para 323E (2+1) y dos para 590E (3+3), y sin
agregar por código antes del greedy cada mitad mide a su hermana como `tomado_antes` — o sea el
pedido peleando contra sí mismo. Ahora las dos funciones tienen su `_itg`.

**Impacto medido**, sobre los 7 pedidos web desprogramados de hoy: **$2.218.883** que dejan de
cobrarse por adelantado (1451 455.881 · 1343 445.041 · 1347 440.940 · 1474 397.637 · 1448 343.730 ·
1482 71.705 · 1349 63.949). Costo como `authenticated`: composición **297 ms**, valor_lote **279 ms**
(el timeout de ese rol es 8 s).

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien (3 centinelas:
`_vl_progalloc`, `_cp_progalloc`, `_vl_itg`). Probado rompiéndolo a propósito en transacción
abortada: *antes 0 perdidas · con la regla borrada 1 · la nombra sí*.
`sql/gv_clin_falta_programado_sobrevendido_v2203.sql`.

## ⚠ REGLA (Luis, 2026-10-07, v28.41): A PROGRAMAR — el aviso de «programados que deberían estar en cuarentena» es un bloque PROPIO

Orden: **Pedidos a programar → 🚨 CLIENTES PROGRAMADOS QUE DEBERÍAN ESTAR EN CUARENTENA → 🐊 Cuarentena → Clientes nuevos**,
los cuatro colapsables. El aviso (`aprColCuarYaProg` / `cuarYaProgHtml`, clave `vir_cuaryp_colapsado`) salió de adentro de
Cuarentena: borde de peligro negro/amarillo, una tarjeta por pedido (cliente, NP, sale día + tanda, «SALE EN N DÍAS», pidió,
picking, motivo con monto) y **sólo 3 botones: ✅ Aprobar · 🐊 Sacarlo a cuarentena · 📖 Comentarios** (los mismos
`cuarYpAprobar` / `cuarYpCuarentena` / `cuarComAbrirIdx`). Sin casos, no se dibuja. Cuarentena va con color y textura de
pantano (`.apr-col-pantano`, la tabla sobre fondo claro) y Clientes nuevos rosa bebé con textura (`.apr-col-clin`). Sólo visual.
`tests/apr-cuarentena.cjs`, `tests/cuar-yaprog-fecha-pedido.cjs`, `tests/pipe-clientes-nuevos.cjs`.

## ⚠ REGLA (Luis, 2026-10-07, v28.49): «🐊 SACARLO A CUARENTENA» mira la TANDA ENTERA — armado viaja sin día, en proceso no se puede

**Luis:** *"Esperemos a que la tanda entera esté armada. Absolutamente nada en proceso"* · *"que no se imprima papel de
cuarentena ni nada"* · *"si no tenía nada armado que se programe automáticamente … si estaba armado, que se quede y salte un
cartel que diga que se tiene que revisar y asignar manualmente"*.

| la tanda (entera, `gv_ppp_estado_grupo`) | qué hace `gv_cuarentena_devolver` (NP web) |
|---|---|
| **en proceso** (pickeo o armado empezado sin TAP) | **no se puede**: `EN_PROCESO:` y el botón queda deshabilitado |
| **sin empezar** | como antes: `gv_ppp_web_desprogramar` (pierde tanda y día) |
| **armada o facturada** | todas las NP del pedido salen solas a una **tanda nueva SIN DÍA** con su registro (TP/TAP, Entregas, porción de a_facturar), por `gv_ppp_pedido_mover(…, gv_ppp_espera_fecha())`; queda una fila en **`GV_Cuarentena_Armado`** |

- **No se imprime ningún papel.** El aviso dice que hay que separar sus cajas del pallet.
- Armado sacado → chip ámbar **«📦 armado · <tanda> sin día»** en A Programar y en Cuarentena (`gv_cuarentena_armado_lista`).
- **Aprobado sin nada armado** → lo programa el armador como siempre. **Aprobado y armado** → NO se programa solo: cartel
  *«ESTABA ARMADO… asignale el día A MANO»* y se programa soltándolo en un día (`gv_cuarentena_armado_asignar_dia`, conserva
  el código; sin aprobación frena con `CUARENTENA:`).
- Sacar un armado y darle día lo puede hacer **cualquier supervisor** que ya usa el botón (`es_supervisor_virgilio`; Luis D1, v28.50): señal local `gv.cuar_mover` → `gv_ppp_pedido_mover`. `sql/gv_cuarentena_sacar_cualquiera_v2850.sql`.
- Centinelas 367-369. `sql/gv_cuarentena_sacar_armado_v2845.sql`, `tests/cuar-sacar-armado.cjs`.


## ⚠ REGLA (Luis, 2026-10-14, v30.38): el pedido que SALE de cuarentena se programa SOLO, también si estaba ARMADO
**Luis:** *"si un pedido sale de cuarentena, que se programe automaticamente siguiendo la reglas establecidas en caso de
que sea posible (que no espere ser posicionado manualmente por un humano)"*.
- **Medido antes del cambio:** de los 44 aprobados del 24/09 al 14/10 **sin** armado, los 44 se programaron solos en
  ≤ 0:05 (el armador, cron 73). Lo único que esperaba a una persona era el **armado sacado a cuarentena** (v28.49).
- Ahora, aprobado ese pedido, **`gv_cuarentena_armado_auto`** le da el día con la **misma regla del armador**
  (`gv_ppp_web_dia_grupo`: grupo de zonas por día, plazo, día menos cargado) y lo mueve con
  `gv_cuarentena_armado_asignar_dia` (conserva tanda, picking y armado).
- **"Si es posible"**: súper, zona no automática o un guard que frena → queda como antes, con el cartel de asignarlo
  **a mano** y el motivo.
- Corre al aprobar (`cuarLiberarConfirmar`, muestra el resultado) y en el cron **`gv-cuarentena-armado-auto`** cada
  0:10 (✅ del pipeline, herencia de pedido partido, reintento). `gv_cuarentena_liberar` **no se tocó** (centinelas 146/154).
- Centinelas 457-458. `sql/gv_cuarentena_armado_auto_v3038.sql`, `tests/cuar-sacar-armado.cjs`.
- ⚠ **Más de 30 días en cuarentena** (v30.41, Luis D2): el armador sólo lee pedidos de `ventana_dias` (30). La Edge
  `gv-ppp-web-tandas-diarias` v46 pregunta `gv_cuarentena_liberados_viejos` (aprobados, sin tanda, pedido de hace 31 a
  120 días) y vuelve a leer con ventana ancha **sólo esos**. `sql/gv_cuarentena_liberados_viejos_v3041.sql`.
