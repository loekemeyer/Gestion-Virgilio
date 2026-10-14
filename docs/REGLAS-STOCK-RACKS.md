# Reglas Stock Racks — Stock, racks, góndolas, tablas vigentes de lugares, pipeline de stock, ajustes

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠⚠ REGLA (Luis, 2026-10-14, v30.42): UN RACK NO TIENE EMPRESA — la empresa viaja con el CÓDIGO

**Luis, textual:** *"La identidad del código es única para casi todos (identidad = empresa). Las únicas excepciones son el
437E, 438E, 439E y 809E. Para esos 4, cuando son producto y no insumo, se puede preguntar de qué empresa son cuando se los
va a poner en un rack"* · *"un rack es volátil: se vacía un rack de Chef y después puede ir un producto de LK o un insumo.
No debería contagiarle su estado de empresa viejo a lo nuevo"* · *"un rack vacío puede ser ocupado por cualquier cosa"*.

- **La empresa de un código** = `gv_empresa_de_articulo(cod)`. Resuelve todos los códigos con stock (14/10: 187 LK, 83 CH);
  los 4 duales dan null y **se eligen** al guardar en un rack (Mapa e Ingreso a racks: LK/CH sólo para ellos, sin valor
  por defecto; la base frena con `gv_emp_default_o_dual` si llega un dual sin empresa).
- **`GV_Lugar.empresa` de los racks es NULL** (los 210). El Mapa (`gv_rack_celda`) muestra la empresa del CONTENIDO;
  `IN` = la celda tiene insumos. Un rack vacío abre el formulario de producto y el de insumos.
- **CH en racks = depósito `racks` + empresa CH.** `racks_ch` no se escribe más desde la recepción de importados
  (el 712E se pasó el 14/10; quedó vacío). El ajuste manual de Stocks todavía ofrece `racks_ch`.
- ⚠ **`gv_articulo_empresa` NO decide la empresa de nadie**: estaba mal (95 códigos de Chef como LK) y se redefinió
  sobre la tabla buena. Para un código, `gv_empresa_de_articulo`.
- ⚠ **Las góndolas SÍ tienen empresa** y no se tocaron: es la que separa el 437E LK (F09-F12) del 437E CH (L07/L08) en
  el picking.
- `sql/gv_rack_sin_empresa_v3042.sql` (antes/ahora de cada objeto, pruebas y backup) · `tests/rack-sin-empresa.cjs`.

## ⚠ Regla de Thomas (2026-09-18, v20.17 · asentada v20.20): el EXCEDENTE va en el ORDEN DEL RECORRIDO

Probando el módulo de operarios con una tanda: *"primero le dice que pickee del excedente, eso
rompe el flujo de movimiento por las góndolas"*. Y sobre la regla que lo había puesto adelante:
***"olvidate de esa regla de excedente primero hasta nuevo aviso"***.

**La v15.41 (pedido de Luis) queda DEROGADA hasta que Thomas diga lo contrario.** No volver a
poner los pasos `art·EXC` al principio, ni "mientras tanto" ni como fallback: hoy se ordenan por
el `orden` del sector donde está el excedente y, sin ese dato, van al final.

Por qué, medido el 18/09 sobre `GV_Lugar` — y es el dato que la v15.41 no miró:

| zona | `orden` |
|---|---|
| góndola de picking (pasillos A..Ñ) | 1 – 657 |
| racks K/N/O | 706 – 717 |
| **zona P, donde se apila el excedente** | **718 – 757** |

El excedente está **después de toda la góndola**: ponerlo primero es mandar al operario al fondo
del depósito y hacerlo volver al pasillo A.

⚠ **Lo que se resigna a propósito:** si el excedente miente (el saldo dice 10 y hay 6), el paso de
góndola de ese artículo ya pasó. Era justo lo que buscaba la v15.41 y **Thomas decidió que manda el
recorrido**. Si algún día molesta, el arreglo NO es volver atrás: es que el faltante del excedente
**reabra** el paso de góndola de ese artículo. Eso tampoco se hace sin que lo pida.

Lo sostiene `tests/pk-excedente-orden.cjs` y el candado invertido de `tests/pk-deposito-pkc.cjs`
(`items.concat(excSteps)` tiene que estar, `excSteps.concat(items)` no). Problema 455.

## ⚠ REGLA: LAS TABLAS QUE VALEN — góndola, racks y empresa del artículo

**Luis, 2026-09-17:** *"fijate que estés usando las tablas actualizadas de `gv_` y escribí en
algún lado que esas son las tablas que valen para que no se vean tablas desactualizadas o
erróneas"*. Hay tablas viejas conviviendo con las vivas, con el **mismo contenido aparente**, y
leer la que no es da respuestas que suenan bien y están mal.

| Para saber… | **LA QUE VALE** | La vieja, NO usar |
|---|---|---|
| Qué artículo va en qué sector de **góndola**, y de qué empresa es el sector | **`GV_Lugar` + `GV_Lugar_Item`** → vista **`gv_lugar_articulo`** (y `gv_planimetria_celda`) | `Planimetria` ⚠ ver abajo |
| Qué hay cargado en cada **rack** | **`Movimientos_Stock`** (racks, `ubicacion` = sector) — `Racks_Planimetria` es una **VISTA** desde la v22.77 | **`Ubicaciones_Articulos`** · `Racks_Planimetria_legacy` |
| **Capacidad** de cada celda de góndola (cajas que entran) | **`GV_Lugar_Item.cajas_max`** — `Capacidad_Sector` es una **VISTA** sobre ella desde la v22.75 | `Capacidad_Sector_legacy` (la tabla vieja, sin escritura, sólo para rollback) |
| De qué **empresa** es un artículo (el dato de la columna LK/CH) | **`gv_empresa_de_articulo(cod)`** y su caché `GV_Articulo_Empresa_Cache` | `gv_articulo_empresa` (la vista rota) |

**Medido el 17/09**, que es lo que decide cuál está viva:

| tabla | filas | último movimiento |
|---|---|---|
| `GV_Lugar` / `GV_Lugar_Item` | 872 / 790 | **2026-09-16** |
| `Racks_Planimetria` | 154 | **2026-09-16** |
| `Ubicaciones_Articulos` | 872 | **2026-08-10** ← congelada hace más de un mes |
| `Planimetria` | 370 | 2026-09-11 |

Y quién las escribe: `Racks_Planimetria` la mueven `racks_plani_ingreso`, `racks_plani_descontar`,
`racks_plani_mover`, `registrar_baja_racks` y `vista_insumos` — o sea, la app. A
`Ubicaciones_Articulos` **no la escribe nadie** desde el 10/08.

### ⚠ `Planimetria` está congelada pero NO se borra

Dejó de leerse para el picking en la **v15.77** y de escribirse en la **v17.26**, así que como
fuente **no vale**. Pero tiene un rol vivo a propósito, y el código lo dice en tres lugares:
guarda los **códigos huérfanos que nunca llegaron a `GV_Lugar_Item`** (los 17 del problema 156 —
palos de amasar 231/232/233, línea Acacia, 537, 567…), y el Mapa de góndolas los **rescata de ahí
con un click** (`pmapViejaFetch` / `pmapViejaTraer`). Además la leen `gv_codigos_multigrafia` y
`vista_nc_loeke_chef`. **No usarla como fuente, no borrarla.**

**Cuánto se superpone con las `GV_`, medido el 17/09**: de los 370 pares (código, sector) de la
vieja, **335 son idénticos** a la viva. De los 25 códigos que sobran, **8 son duales escritos con
sufijo de empresa** (`437E CH`, `809E LK`… misma info, otra grafía), **1 es basura** (`LIBRE`) y
**16 son códigos reales sin lugar en `GV_Lugar_Item`**, 12 de ellos con movimientos (580E con 153,
232, 231, 233, 865ED, 702EN, 537, 567, 828, 997E, 998E, 702). **Ésos 16 son la razón por la que la
tabla no se borra** — y el motivo por el que `gv_empresa_de_articulo` la usa como **último
recurso**, filtrada (nunca un dual, nunca un pseudo-código con sufijo, nunca `LIBRE`).

`Ubicaciones_Articulos` es otra cosa: **38 días sin escribirse, 0 funciones y 0 lectores en el
front**. Ésa sí no sirve para nada vivo.

### El centinela: `gv_fuentes_lugares`

Para no tener que volver a medir esto a mano, la vista dice sola cuál está viva:

```sql
select * from public.gv_fuentes_lugares;
-- tabla · rol · última escritura · días sin escribirse · funciones y vistas que la leen
```

### Lo que costó descubrirlo

Buscando dónde estaban físicamente las cajas del **809E**, `Ubicaciones_Articulos` decía que en el
rack `AD5` había un código **`809E-QUESO`** y en `Y12` un **`809E-PIZZA`**. Los dos son **inventos
de esa tabla**: no existen como artículo ni como insumo (**0 movimientos** en `Movimientos_Stock`,
0 en el depósito `insumos`) y son los **únicos dos códigos con guion** de toda la tabla. La tabla
viva dice lo correcto: el código es `809E` y el rack de LK es **`AE11`**, no Y12.

### ⚠ Los sectores de rack van con CERO adelante: `AD05`, no `AD5`

**27 de los 29** sectores de `Racks_Planimetria` que no existían en `GV_Lugar` eran el mismo error
de tipeo: falta el cero. Se corrigieron 26 (los que tienen gemelo `rack`) el 17/09, backup en
`zz_backups."GV_Backup_RacksPlani_sectores_20260917"`. **Al cargar un rack a mano, escribir el
sector como está en `GV_Lugar`.** Chequeo:

```sql
select distinct r.sector from public."Racks_Planimetria" r
 where not exists (select 1 from public."GV_Lugar" l where l.sector = r.sector);
-- al 17/09 quedan 3 y son otro problema, no el del cero: O2, O5 (no existen en ninguna forma)
-- y Z7 (su gemelo Z07 existe pero es GÓNDOLA, no rack)
```

### ✅ La contradicción de AD06 — resuelta por el conteo del 17/09

`AD06` figuraba con dos filas: `CH / 809E / 360 cajas` (del 08/07) y `LK / 368E / 56` (del
31/08), con `GV_Lugar` diciendo que AD06 es un rack de **LK**. Luis contó: **en AD06 hay 368E,
14 MC**, y punto. Las 360 de 809E CH eran layout viejo que ya no estaba (ni en el libro de
stock: el saldo de racks eran las 336 de AD05), así que se borraron. Igual `AE11 / 809E / 8 MC`.

**Y apareció la misma contradicción en AD05**: tenía `emp = CH` pero las 28 MC que hay adentro
son **809E de Loekemeyer**. Se aplicó el criterio de Luis para el 396 en P39 (*"la góndola está
mal asignada, ajustala"*): **AD05 pasó a LK**, el artículo no se movió. v19.33,
`sql/gv_conteo_809e_v1933.sql`.

⚠ **Y el que muerde: `809` y `809E` son artículos DISTINTOS, los dos de Chef.** El `809` es el
secundario, vive en la góndola **M16**; el `809E` de Chef está en **M14**. Contar las cajas de
M16 como 809E le habría sumado 9 al código equivocado. Lo frenó Luis en el momento.

### ⚠ Un código DUAL no tiene empresa: `gv_empresa_de_articulo` contesta **NULL**

Los 4 de `codigos_duales` (437E, 438E, 439E, 809E) viven en las **dos** góndolas: la empresa la
dice de qué pila salió la caja, o sea el **pedido**, no el artículo. Hasta la v19.30 la función
devolvía **`'LK'`** para 437E/438E/439E, porque la góndola hoy los tiene de un solo lado — falso, y
el tipo de respuesta que suena bien y está mal. El trigger nunca se la comió (chequea
`codigos_duales` **antes** de llamarla), pero cualquier otro llamador sí. Ahora el guard está
adentro de la función y del refresco del caché. Chequeo:

```sql
select cod, public.gv_empresa_de_articulo(cod) from public.codigos_duales;
-- las 4 tienen que dar NULL
```

### ⚠ Y un DUAL **no es el mismo artículo de los dos lados: cambia el PACKAGING**

**Luis, 2026-09-21:** *"No son el mismo artículo por más que tengan el mismo código. Cambia el
packaging, por eso está dividido así."*

Es la pregunta que se hace sola al mirar el generador de OC, porque los números invitan a
equivocarse. Medido ese día:

| código | stock lado LK | stock lado CH | se pide (CH) |
|---|---|---|---|
| 437E | 286 (189 en racks) | 14 | 145 |
| 809E | 349 | 113 | 126 |
| 438E | 117 | 3 | 86 |
| 439E | 15 | 8 | 10 |

Leído como si fuera un solo artículo, eso parece **357 cajas que se compran teniendo 767 del otro
lado**, o sea un traslado de góndola disfrazado de compra. **No lo es.** Son dos productos
distintos con el mismo número: la caja de Loekemeyer no sirve para un pedido de Chef.

**Entonces:** el generador está haciendo lo correcto al pedir por separado, y **nunca hay que
proponer "trasladar de la góndola LK a la de Chef" para ahorrarse la compra**. La única
consecuencia del código compartido es la de siempre: la empresa la da de qué pila salió la caja
(el pedido), no el artículo.

### ⚠ RACKS: una fuente por dato (Luis, 25/09, v22.77)

| dato | dónde vive |
|---|---|
| qué posiciones hay y si están reservadas | `GV_Lugar` (tipo `rack`, `uso` pedidos / cajas / bastidor) |
| cuántas cajas de cada código hay en cada posición | **`Movimientos_Stock`**, depósito racks / racks_ch, **`ubicacion` = sector** |
| cajas por master (para mostrar MC) | `GV_Rack_CxM` |
| lo que la planimetría vieja decía y el stock no respalda | `GV_Rack_Revisar` → «🔎 a contar» en el Mapa |

`Racks_Planimetria` es una **vista** con las mismas columnas (+ `fuente` stock / a_contar, `motivo`). Escriben
`racks_plani_ingreso` / `_nacional` / `_mover`, `registrar_baja_racks` (la baja lleva la posición y dispara los
avisos de rack libre / sin stock) y `gv_rack_posicion_guardar`; `racks_plani_descontar` quedó sin efecto a propósito.
El stock sin posición se ve en `gv_rack_sin_ubicar` y se ubica desde el Mapa (`gv_rack_ubicar`).

⚠ **`ubicacion` en `Movimientos_Stock` es texto libre en los otros depósitos** (NP en a_facturar, góndola en
terminado, textos de insumos). En racks vale sólo lo que `gv_rack_sector()` reconoce como posición de `GV_Lugar`.

La migración movió **0 cajas** del total de racks (14.094 antes y después): 111 ajustes en 42 códigos con `ref = 'ubicar racks · v22.76'`
que suman 0 por código. Quedaron **21 a contar** y 7 códigos sin posición (505I 1.139, 546 360, 513 260, 816E 120…).
Insumos en racks (523C, 546V, 102E, 522S, 1000900) quedan «a contar» hasta el paso de alias de ubicación de insumos.
Rollback: `sql/gv_racks_canon_v2277.sql`. Lo sostiene `tests/pmap-racks.cjs`.

⚠⚠ **El CONTEO del Mapa no se SUMA a lo sin posición** (Marianela, 30/09, v25.15: *"el conteo está bien, lo que
suma está mal"*). `gv_rack_posicion_guardar`, si lo contado es MAYOR a lo que tenía la posición, primero **traslada**
lo sin posición del mismo código (es la misma mercadería) y sólo el resto entra como ajuste. Antes lo sumaba: 505I
quedó en 2614 con 1475 contadas, 056E +84, 816E +120 (corregidos a mano ese día). Marcador `sinpos-mapa-3009`,
centinela id 260, problema 648. `sql/gv_rack_posicion_guardar_sinpos_v2515.sql`.
Y ese día se dieron de alta **O02** y **O05** (racks LK que no existían) y **Z07 pasó de góndola a rack** (su celda
del 363E era falsa: la góndola del 363E es J04). Problema 646. Al contar en una posición que el Mapa no conoce,
se da de alta en `GV_Lugar`, no se carga en otra.

## ⚠⚠ REGLA (Luis, 2026-10-13, v29.78): UN RACK SE PUEDE PARTIR — `Y25-1`, `Y25-2`, `Y25-3`…

**Luis:** *"algunos racks tienen mucho espacio que estamos desaprovechando … si alguien guarda algo a un
rack que ya esta ocupado por otro codigo, promptee para decir de que lado lo dejan … que separe ese rack
en Izq y Der (basicamente, una subdivision de racks)"* · *"pongamos la posibilidad de, por ejemplo,
Y25-1, Y25-2, Y25-3"*.

> ## Un rack puede estar **DIVIDIDO en N partes** (1 a 9, numeradas de **izquierda a derecha**) y la
> ## **DIRECCIÓN** de una parte es **`Y25-2`**. Sin partir (N = 1) la dirección sigue siendo `Y25`.

**Antes de esto el sistema PROHIBÍA el segundo código** (`gv_rack_pos_chequear` devolvía `ocupado:<cod>` y
frenaba el ingreso) y el conteo del Mapa **borraba** lo que hubiera en la posición que no fuera el código
que se estaba guardando. Medido al 13/10: 258 racks activos, 89 posiciones con stock, **0 con dos códigos**.

| la pregunta | la función | para qué |
|---|---|---|
| ¿cuál es EL RACK? | **`gv_rack_sector(txt)`** — pela la parte (`Y25-2` → `Y25`) | AGRUPAR y validar: es el **cuello único** por donde 18 funciones y 12 vistas siguen contando por rack **sin tocarlas** |
| ¿cuál es la DIRECCIÓN? | **`gv_rack_pos(txt)`** | lo que se **ESCRIBE** en `Movimientos_Stock.ubicacion` |
| ¿qué parte pide el texto? | `gv_rack_lado(txt)` → 1..9 (null si el rack no está partido) | |
| ¿en cuántas partes está? | `gv_rack_subs(txt)` ← **`GV_Lugar.gv_sub`** | la subdivisión es **del RACK**, no del movimiento |
| ¿falta decir la parte? | `gv_rack_falta_parte(txt)` · `gv_rack_dir(txt)` (todo junto, para el front) | |

- **La parte viaja DENTRO del texto de la dirección**, así que **ninguna función cambió de firma**: entra por
  el mismo argumento de siempre. Acepta `Y25-2`, `Y25 2`, `Y25/2`, `Y25 izq` (= 1) y `Y25 der` (= 2); se
  muestra siempre el número.
- **Partir / unir: `gv_rack_partir(sector, partes, parte_actual, motivo, legajo)`** — la llama **el operario**
  desde Ingreso a racks cuando se topa con un rack ocupado (es lo que pidió Luis: que lo decida en el
  momento, parado frente al rack), y el supervisor desde el Mapa (**✂ Partir**). Lo que ya estaba **sin
  parte se muda a la parte que él indique**; unir frena si más de una parte tiene mercadería. Queda en
  **`GV_Rack_Particion`**.
- ⚠ **EL PUNTO QUE EVITA PERDER UNA CAJA:** en un rack partido **todo movimiento lleva la parte**
  (trigger `aa_gv_racks_ajuste_sin_posicion` → **`RACKS_FALTA_PARTE`**). Sin eso las cajas quedan «en el
  rack, sin parte»: el Mapa muestra una parte fantasma y Bajar de racks no sabe de dónde sacarlas.
- ⚠ **`gv_rack_posicion_guardar` vacía SÓLO su parte** (`gv_rack_pos(m.ubicacion) = v_sec`). Con el criterio
  por rack, contar la izquierda **borraba el stock de la derecha**: es el único lugar que podía destruir
  stock ajeno.
- ⚠ **`Racks_Planimetria.sector` pasa a ser la DIRECCIÓN** (+ columnas `rack`, `parte`, `partes`), y lo
  mismo `gv_rack_celda` (+ `pos_rack`, `parte`, `partes`). Por eso el front casi no cambió: los chips de
  Bajar de racks, las posiciones de Stocks → Ajustar y las celdas del Mapa ya tratan la posición como un
  **string opaco**. Lo que necesita el RACK usa la columna `rack`. ⚠ El `id` de la vista es un hash que
  **incluye la parte**, o dos partes del mismo código tendrían el mismo id y PostgREST devolvería una sola.
- **Front**: Ingreso a racks ofrece **✂ en 2 / 3 / 4 partes** y pregunta en qué parte está lo que ya había
  (`_irOcupadoHtml` / `irPartir`); si el rack ya está partido ofrece las partes libres. Bajar de racks y
  Stocks → Ajustar / Fijar / Stock inicial piden la parte (`gv_rack_dir`); 📥 Recibir de Importación ofrece
  una opción por parte. El Mapa dibuja **una celda por parte** y tiene ✂ Partir / unir.
- ⚠ **Medido antes de aplicar nada: con 0 racks partidos todo se comporta EXACTAMENTE como antes** — la
  huella de `gv_rack_sector` sobre los 2.645 textos de ubicación reales no cambió
  (`c82ba953f63ab26f7de76c42abc2f05f`) y las dos vistas devolvieron las mismas filas y el mismo md5
  (259 y 304). Es forward-facing por construcción: no hay nada que migrar.
- Los insumos **no se parten** (siguen con su nomenclador `AD`/`AT`, que son filas propias de `GV_Lugar`).

**Chequeo:** `select * from public.gv_reglas_perdidas;` (16 centinelas) ·
`select sector, rack, parte, partes, cod_art, innercajas, estado from public."Racks_Planimetria" where partes > 1;` ·
`select * from public."GV_Rack_Particion" order by id desc;` · `node tests/rack-subposicion.cjs`.
`sql/gv_rack_subposicion_v2978.sql` (rollback en la cabecera y al final). ⚠ Los objetos de la base, los
16 centinelas y los marcadores internos dicen **v29.78** (la versión con que se aplicaron): es la llave de
idempotencia, **no cambiarla**; la app salió en la v29.94 porque otras sesiones se adelantaron.

## ⚠ REGLA (Luis, 2026-09-29, v24.33): las CAJAS PEDIDAS se cuentan IGUAL en Stocks que en OCs

**Luis, textual:** *"si lo comprometido no es stock disponible, esta bien. pero se tiene que
contemplar igual en OCs que en Stocks. eso es lo que estoy diciendo"* · *"el neto adelante y el
pickeado en el tooltip"*.

> ⚠⚠ **v30.14 (Thomas, 13/10/2026) REVIERTE «el neto adelante»: la CELDA muestra el TOTAL (658),
> no el neto.** Textual: *"tanto afuera como adentro en las cajas en cualquier circunstancia o
> estado tiene que figurar"* → *"658, y cuando entro, veo el desglose y el estado de cada una"*.
> **Cambia sólo el número de la celda** (`_pn.tot` en vez de `_pn.neto`, y el orden va por `tot`);
> el desglose por estado (a cubrir · pickeadas TP · picking s/TP · total) sigue en el tooltip y en
> el pop-up, y el Excel lleva las dos columnas («a cubrir» = neto, «Ped. total» = tot).
> ⚠ **El NETO no se toca: sigue manejando la compra** (`gv_stock_pedidas_neto.neto`, el generador
> de OC lee `.neto`). La regla de abajo sobre QUÉ se compra no cambia. `tests/stk-pedidas-neto.cjs`.

Stocks decía **251** cajas pedidas del 501 y OCs decía **225**. No era redondeo: son **dos columnas
de la MISMA fila** de `vista_stock_procesada` con dos criterios —`cajas_pedidas` (toda la demanda
viva) y `cajas_pedidas_familia` (sin las NP cuya tanda ya tiene **TP**, la regla v19.85 de Thomas)—
y cada pantalla leía una.

> **El criterio de OCs es el bueno y NO se toca.** Una caja ya pickeada está separada para su
> pedido: no es demanda a comprar, igual que no es stock disponible. La que contaba de más era
> Stocks. Los 26 del 501 no son los 18 de «Pickeados» (el depósito `separar_pedidos`): son dos
> conjuntos distintos, y por eso el número no cerraba mirándolos de a uno.

| dónde | qué muestra |
|---|---|
| celda **Cajas Pedidas** | el **total** (v30.14 Thomas; antes el neto) — el desglose por estado va al tocar |
| tooltip | `N a cubrir` · `N ya pickeadas (tanda con TP)` · `N con el picking empezado sin TP, siguen contando` · `N pedidas en total` |
| Excel de la tabla | «a cubrir» = neto **y** «Ped. total» = tot, más TP y s/TP |

Lo resuelve **`gv_stock_pedidas_neto`** (`cod, familia, es_secundario, total, neto, con_tp,
en_curso, fam_*`). `total = neto + con_tp`, y `sum(total)` coincide **exacto** con
`sum(cajas_pedidas)` de la matview (13.132,3334): si eso deja de dar igual, la vista se desfasó.
Impacto: 109 códigos, 13.132,33 → 11.279,33 cajas. **Cero en la compra**: el generador ya usaba
el neto.

⚠ **UN objeto nuevo y nada existente tocado**, a propósito: la matview **no** se puede reemplazar
(su `DROP CASCADE` arrastra `gv_importados_stock_dep` y, en 2.º nivel, `gv_importados_ordenes` —
lo que dejó Importados en 404 en la v16.20 y la v16.33), y `refresh_stocks_carga_rapida()` la
editan varias sesiones.

⚠⚠ **Y `cajas_pedidas` NO se toca**: sostiene `visible_en_stock`. Cambiándola, 9 códigos quedaban
en 0 pedidos y **5 desaparecían del listado** (198E, 951E, 952E, 953E, 970E) por tener stock 0 —
el pozo de la v20.95.

⚠ **La lectura va PAGINADA (`gvRestTodo`, y está en `DEBEN_PAGINAR`): una fila por código con
demanda viva, 237 al 29/09, y eso crece con el catálogo.** Lo cazó `tests/rest-tope-1000.cjs` en
la primera corrida de la suite, con el `limit=1000` puesto.

⚠ **La lectura va EN PARALELO y sin `await`** (Luis: *"hace la carga en paralelo, evalua para
evitar timeouts"*): la tabla se dibuja con el total y se redibuja cuando llega el neto. Con su
propio catch — si falla, la pantalla queda como la v24.32 y la celda muestra el total, nunca 0
(*"no pude leer"* no es *"no hay"*). Medido como `authenticated`: **550 / 548 / 555 ms** contra los
8.000 del timeout del rol. El techo de 20 s del fetch es para la **red** colgada; la base corta sola.

⚠ **El primer intento (`sql/gv_stock_pedidas_neto_v2402.sql`) NO se ejecutó y está borrado.**
Parchaba `refresh_stocks_carga_rapida()` con un `LEFT JOIN LATERAL` contra una función
set-returning, que **no se inlinea** (`SET search_path`) y se habría corrido **una vez por fila**:
367 × 682 ms ≈ **4 minutos por refresco, cada 2**. Es el pozo de `gv_destino_score` (v20.62) y
`gv_espejo_np_pasa` (v20.78) otra vez. Se midió la consulta suelta **antes** de aplicarlo.

⚠ **La familia agrupa por (principal, EMPRESA)**, no por el código pelado: sin el sufijo en el
`partition by`, `437E LK` y `437E CH` caían en la misma bolsa y son dos productos distintos.

⚠ **`fmtCajas` es local de `stkBodyStocks`**: `_stkPedTitle` es global y no la ve. Y `_pedNetoOf`
es **global a propósito** — la usan la tabla y el Excel, que son dos funciones distintas; con una
copia en cada scope los dos números se desfasan, que es justo el bug que esto arregla.

**Chequeo:** `select (select sum(total) from public.gv_stock_pedidas_neto) vista,
(select sum(cajas_pedidas) from public.vista_stock_procesada) matview;` — iguales ·
`node tests/stk-pedidas-neto.cjs` (verificado que falla con 6 chequeos en rojo contra el index
anterior). **Rollback, una línea:** `drop view if exists public.gv_stock_pedidas_neto;`
`sql/gv_stock_pedidas_neto_v2404.sql`.

## ⚠ Regla del dueño (2026-09-18, v19.85): lo COMPROMETIDO no es stock disponible

**Thomas, 2026-09-18:** *"lo comprometido (separar_pedidos y a_facturar) no debería contar como
stock disponible para la cuenta de 'lo que tenemos - lo que nos falta'"*.

El `stock` de **`vista_generador_oc`** es el **DISPONIBLE**:

```
terminado + a_guardar + racks + excedente + para_envasar + racks_ch      ← cuenta
separar_pedidos + a_facturar                                            ← NO cuenta
```

**Por qué, y es la parte que importa:** `total = maximo + pedidos - stock`, y el CTE `pend_np`
**excluye** las NP cuya tanda ya tiene **TP**. O sea que el pedido pickeado deja de compensar
como demanda — mientras su mercadería seguía sumando como disponible, porque el picking la mueve
a `separar_pedidos` / `a_facturar` pero no la saca del depósito. **La misma caja tratada de dos
maneras incompatibles en las dos puntas de la resta**, y siempre para el mismo lado: se pedía de
menos. Medido al corregirlo: **1.205 cajas comprometidas, +816 de a pedir en 64 códigos**, ninguno
a la baja. Problema 428, §3.jq.

⚠ **Esto NO cambia el módulo Stocks ni ninguna otra pantalla**: lo comprometido sigue existiendo y
se sigue viendo donde corresponde. Cambia **sólo** la cuenta del generador de OC.

⚠ **Y destapó un negativo viejo**: el **256** (Mate Madera Cerámica) tiene 2 cajas comprometidas
contra 1 de saldo total, así que su disponible da **−1** — un sobre-pickeo que ya estaba en el
libro y que el stock total tapaba. El `greatest(0, …)` lo contiene. **No se tocó el dato.**

> **La regla general, que vale para cualquier resta:** si un lado saca un hecho, el otro tiene
> que sacarlo también. El bug no estaba en ninguna de las dos mitades leída sola — las dos eran
> defendibles por separado.

**Chequeo:** `select * from public.gv_reglas_perdidas;` — el centinela `COALESCE\(s\.fin_dep`
vive ahí. `sql/gv_generador_oc_stock_disponible_v1985.sql`.

## ⚠ REGLA (Luis, 2026-09-22, v21.14): la góndola es de 4 filas — **A y P son las únicas de 5**

**Luis, textual:** *"solo las góndolas A y P son de 5 filas, el resto está organizado en filas de
a 4… que por ejemplo ahí las H las muestre de a 4 filas y no 5"*.

El Mapa de góndolas dibujaba **todas** con módulos de 5 (`PMAP_ALTO = 5`), así que la H salía en
**12 columnas de 5** cuando en el depósito son **15 de 4**: la celda que el operario veía arriba a
la izquierda no era la que tiene enfrente.

Hoy la altura la da `pmapAlto(g)`: **`PMAP_ALTO_X = { A: 5, P: 5 }`**, default **4**. Al agregar
una góndola de 5 filas va ahí, no se toca el default.

**Y la numeración cierra con eso** (medido el 22/09 sobre `gv_planimetria_celda`): cada góndola
tiene su `celda` corrida de 1 a N sin huecos y **N es divisible por SU altura** —
`A = 85 = 17×5`, `P = 40 = 8×5`, `B/D/F/H/J/L/M/Ñ = 60 = 15×4`, `C/E/G/I = 20 = 5×4` —, así que
el corte cae siempre donde tiene que caer. `Y` y `Z` tienen **una celda suelta cada una** (Y29,
Z07) y van por el default.

**Chequeo:** `node tests/pmap-gondolas.cjs` — verifica que A corta en `1–5` y F en `1–4`, y que
F13 queda **abajo de la 4.ª columna**, no arriba de la 3.ª. Verificado que falla con el 5 fijo.

## ⚠⚠ REGLA (Luis, 2026-10-13, v30.13): LA GÓNDOLA DE UN CÓDIGO DISCONTINUADO SE LIBERA

**Luis, con el A64 en la mano:** *"figura en el mapa de gondolas que esta asignado al 548 pero ese es un
código discontinuo. ahora tiene un cartel de que va 565 pero tambien esta discontinuo. La idea es muy
simple: si una gondola esta asignada a un codigo discontinuo (o mejor dicho, cuando se dictamina que un
codigo esta discontinuo…), esa gondola se tiene que liberar"* · *"hay algunos articulos que conviven en
una misma gondola (dos codigos diferentes, una gondola). Revisa que esto no rompa nada."*

> ## **La celda NO se borra: se le saca EL CÓDIGO.** `GV_Lugar_Item` es (sector, cod), así que una celda
> ## compartida pierde sólo al discontinuado y los otros siguen; sale **«libre»** cuando no le queda ninguno.

| pieza | qué hace |
|---|---|
| **`gv_cod_discontinuado(cod)`** | la ÚNICA fuente del dictamen: `a_mano` (`Articulos_Discontinuados`) · `baja` (`GV_Codigo_Baja`) · `sin_compra` (`OC_Maximos.activo = false`) · null. Es el mismo criterio del chip «Ocultar discontinuos» de Stocks, que lo sigue duplicando en el front |
| **`gv_gondola_discontinuada`** | una fila por (celda, código) con el motivo, el stock, la demanda y la **acción**: `liberar_ya` · `liquidar_primero` · `tiene_demanda` · `secundario_revisar` |
| **`gv_gondola_liberar(sector, cod, clase, por, forzar)`** | saca ese código de esa celda con backup en **`GV_Lugar_Liberado`**; **sin `forzar` frena** (`NO_VACIA`) si hay cajas o demanda. Llama a `gv_lugar_item_sacar`, que ya existía |
| **`gv_gondola_reponer(id)`** | deshace una liberación (vuelve el código **y su capacidad**) |
| **`gv_gondola_liberar_auto(simular, cod)`** | el automático: libera SÓLO lo que está en cero absoluto. Lo disparan el **trigger `zz_gv_disc_liberar_gondolas`** del alta en `Articulos_Discontinuados` (el dictamen) y el cron **158 `gv-gondola-liberar`** (05:23 ART), que es la red para lo que se vacía después |
| `gv_planimetria_celda` | +3 columnas AL FINAL: `discontinuado`, `disc_accion`, `celda_liberable`. El **Mapa** marca la celda (código **tachado** + borde rojo + la leyenda con palabras), el modal dice el motivo y tiene **🧹 Liberar**, y arriba va el aviso con **«Liberar las N que están en cero»** |

### ⚠ Las tres cosas que esto NO rompe, y por qué

1. **Una celda con cajas adentro NO se libera sola.** Decir «libre» con las 81 cajas del 587T adentro manda
   al pickeador a una celda que el mapa no reconoce y dispara `gv_mapa_stock_sin_lugar`. Queda marcada
   **«liquidar primero»** y se libera cuando queda en cero (o a mano, con el aviso de cuántas hay).
2. **Convivir ya estaba estructurado**: no hizo falta ningún modelo nuevo. Medido el 13/10: **41 celdas
   tienen 2+ códigos** (hasta 5 en M35 y M36), o sea que en la góndola M de Chef convivir es la norma.
   Probado: dictaminar el 337 dejó E15 con **sólo el 312**.
3. ⚠⚠ **`OC_Maximos.activo = false` NO siempre es «discontinuado»: en un SECUNDARIO significa «no se
   compra»**, porque su proyección se vuelca al principal (regla v22.72) y por eso su E.M. es 0 **por
   construcción** — mirar «E.M. 0» no prueba que no se venda. El **574** está `activo=false` con proveedor
   Lucho y es el que VENDE de su familia (regla v22.68). Un secundario que no está marcado a mano queda en
   `secundario_revisar` y **no se libera solo**: son 3 de los 43 (338, 574, 809).

**Medido el 13/10, antes de escribir:** 689 items de góndola en 636 celdas (49 vacías) · **43 ocupados por
un código discontinuado** (24 a mano, 19 sólo por OC) · **21 con cajas** (587T 81, 755 70, 759 57+57, 332 33,
335 30, 502T 24, 717 24…) · **23 con demanda viva** (591 con 8 pedidas y 27 de E.M., 396, 332, 338, 809…) ·
**12 en cero absoluto**, que son las que el automático libera, y **4 celdas** quedan enteras libres
(A64, J40, J41, L59). A64/548 es el caso puro: `activo=false`, sin stock, sin E.M., sin pedidos.

**Chequeo:** `select accion, count(*) from public.gv_gondola_discontinuada group by 1;` ·
`select * from public.gv_gondola_liberar_auto(true);` (qué liberaría, sin tocar nada) ·
`select * from public."GV_Lugar_Liberado" order by id desc;` (lo liberado, con su `reponer`) ·
`select * from public.gv_reglas_perdidas;` · `node tests/pmap-discontinuado.cjs` (corre la pantalla;
verificado que falla contra el index anterior). `sql/gv_gondola_discontinuado_v3003.sql` (rollback al pie),
centinelas 447-451. ⚠ Los objetos de la base, los 5 centinelas y los marcadores internos dicen **v30.03**
(la versión con que se aplicaron): es la llave de idempotencia, **no cambiarla**; la app salió en la v30.13
porque otras sesiones se adelantaron.

## ⚠ REGLA (Luis, 2026-10-13, v29.69): el código SIN GÓNDOLA en el Mapa se lo PREGUNTA AL OPERARIO

**Luis:** *"si el modulo de pickeo los promptea a pickear un codigo para el que no tiene registro de
lugar (en que gondola esta) y el que pickea lo agarra, debería preguntarle de que gondola lo agarro
y debería aparecerle la sugerencia al admin para ajustar gondolas de la misma forma que le aparece
para ajustar stock."*

Mismo circuito que el conteo de góndola del picking (CG, v28.58):

| paso | qué pasa |
|---|---|
| picking | el paso de un código sin celda en `GV_Lugar_Item` sale con el aviso **📍 no tiene góndola en el Mapa**; al confirmar («✓ Puse» o «Faltan» con 1+ caja) pregunta **«¿De qué góndola lo sacaste?»** |
| evento | **PKG** = `COD|lo que escribió|TANDA`, sin `ts_inicio` (no abre tarea). Dedup `pkg_<legajo>_<tanda>_<cod>` |
| landing del admin | cuadro **«Góndolas sin cargar en el Mapa»** (`#gsAside`, a la derecha; el de conteos queda a la izquierda) con el código, la celda, quién y cuándo, si esa celda ya tiene otro código y si el código ya tiene celda |
| ✓ | `gv_gondola_sugerida_resolver` → **`gv_lugar_item_guardar`**: da de alta la celda (pide capacidad; vacío = sin capacidad). **✕** descarta y el Mapa no se toca |

⚠ **La pregunta va DESPUÉS de registrar el pick**: el PKC se manda igual, así que si el celular muere
en la pregunta lo pickeado no se pierde. Y se puede saltear («No sé»): **no frena el picking**, y no
vuelve a preguntar por ese código en esa tanda (se guarda en el avance, sobrevive a reabrirlo).

⚠ **Lo que el operario escribe NO se inventa**: `gv_gondola_sector` devuelve sólo una celda que
existe en `GV_Lugar` (`f9` → **F09**, `m 13` → **M13**); lo que no matchea queda como «dicho» y el
cuadro lo muestra en rojo para que el supervisor lo corrija a mano.

**Cuánto es**, medido el 13/10 sobre 60 días: **25 códigos sin celda y 131 líneas de picking**
(231/232/233, 567, 565, 998E…), unas 2 por día. No es ruido.

⚠ **Al agregar un evento de detalle como PKG hay que sumarlo a `COLA_AUTO` y a los `isUpsert` de
`index.html`**, o la cola lo trata como una tarea del operario.

### D3 (Luis): en el Análisis Productivo se MARCAN los anómalos — y sólo en pantalla

*"solo en pantalla, hace que sea mas claro el detalle, descripcion, analisis y que haya algo para
marcar los anomalos"*. **Nada de Telegram.**

- Arriba del detalle va una **conclusión en una frase** (`_anConclusion`, armada con lo que ya trajo
  la base): *"El picking lo hizo X en 1:04, un 61 % MÁS de lo esperado para una tanda de dificultad
  alta… Hay 2 cosas para mirar de cerca"*. Los avisos van bajo el rótulo **«Qué se encontró»**.
- Barra con **🚩 Anómala · ✓ Revisada · ✕ Sacar marca** (con nota). Vive en `GV_Analisis_Marca`
  (`gv_analisis_marcar` / `gv_analisis_marcas`), una fila por tanda, y la puede poner el supervisor
  o un legajo habilitado.
- En la lista: chip 🚩/✓ y los filtros **Todas · Con avisos · 🚩 Marcadas**.
- **D4 (Luis): el botón lleva badge** — `gv_analisis_badge(14)`: tandas de los últimos 14 días con un
  aviso DURO y **sin marcar** (ni anómala ni revisada). Se apaga marcándolas. Va en el botón del panel
  (`#anBadge`) y en el de la botonera de Juan (`#anBadgeOp`). ⚠ Una lectura rota **no lo apaga**: lo deja
  como estaba — un 0 que no es un 0 real es peor que no mostrar nada. Al 13/10: 11 pendientes.
- ⚠ Las marcas se leen **aparte** de la lista: si esa lectura falla, la pantalla se ve igual (sin los
  banderines), y no hubo que tocar `gv_analisis_tanda`, que tiene centinela.

**Chequeo:** `select * from public.gv_gondola_sugerida_pendientes();` ·
`select public.gv_gondola_sector('f9');` → `F09` · `node tests/pk-gondola-sugerida.cjs` ·
`node tests/analisis-productivo.cjs`. `sql/gv_gondola_sugerida_v2969.sql`.

## ⚠⚠ `trg_normalizar_empresa_stock()` LA TOCAN VARIAS SESIONES — traer la viva antes de tocarla

**Problema 390, 17/09.** Dos sesiones de Claude editaron esa función el mismo día. La segunda
hizo `CREATE OR REPLACE` **partiendo de una copia anterior** a la regla de la v19.26, y la borró
sin que nada avisara. Costó **4 tandas con el picking duplicado** (D72A 228 filas, E11B 24, D72C
y 98648|CP 2 cada una), con **+287 cajas fantasma en Pickeados y −265 en góndola**.

**Por qué el índice único no lo frenó:** `mov_stock_pipeline_dedup` incluye
`COALESCE(empresa,'')`. Con la regla vieja (por NP) **D72A se etiquetó CH** —se factura por Chef,
NP 44609— mientras el picking original del 14/09 estaba en **LK**, porque sus 38 artículos son de
Loekemeyer. Distinta empresa = distinta fila para el `ON CONFLICT` = duplicado.

**Antes de hacerle un `CREATE OR REPLACE` a esa función** (o a cualquiera del stock):

```sql
-- 1. traer la definicion VIVA y agregarle el cambio ENCIMA. Nunca partir de una copia propia.
select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure);
-- 2. despues, probar con un INSERT de verdad (leer la funcion no alcanza):
insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
values ('501','separar_pedidos',0,'ajuste','__PRUEBA__','t','CH');   -- tiene que quedar LK
delete from public."Movimientos_Stock" where ref = '__PRUEBA__';
-- 3. y el centinela, que tiene que dar TRUE:
select p.prosrc ~ 'gv_empresa_de_articulo' as tiene_la_regla_del_articulo
  from pg_proc p join pg_trigger t on t.tgfoid = p.oid where t.tgname = 'zz_normalizar_empresa';
```

**Las tres reglas que tienen que convivir en esa función, y ninguna puede pisar a la otra:**

| regla | qué hace |
|---|---|
| **v19.42** (problema 378) | un NPD sin picking en esa tanda → `RETURN NULL` (si no, deja Pickeados en negativo) |
| **v19.26** (Luis, 16/09) | código **NO dual** → manda el **ARTÍCULO**, no el pedido. Va **antes** de la herencia por tanda |
| **v18.99** | en un dual, la NP puede venir de los **dos lados** del pipe, con guard de largo 4-6 |

**Chequeo de que no volvió a pasar:** `select * from public.gv_stock_empresa_fantasma;` vacía, y
esta consulta en 0 — caza el duplicado que el índice único no ve, porque compara **sin** la empresa:

⚠ **Ese centinela cambió en la v19.77 (problema 416): ahora sólo marca el split de etiqueta de
verdad** (`fantasma = least(positivo, negativo)`). Antes disparaba con **cualquier** saldo
negativo de una sola empresa —donde no hay ninguna caja fantasma— y por eso vivía en rojo. Los
sobre-pickeos comunes van a **`gv_stock_negativos`**, que ya los lista con descripción.

⚠ **Y hay un tercer duplicado que ninguno de los dos veía**, porque el `ref` es **otro**: el que
deja el renombre de tanda. `select * from public.gv_stock_picking_duplicado;` — vacía = todo
bien. El 18/09 marcó 4 tandas (D71B/E40A, E03F/E12R, E11B/E41A, E03G/E44A): **+461 cajas en
Pickeados, −443 en góndola**. Causa: `gv_ppp_tanda_renombrar` no renombra los eventos **PKC**
(la tanda va en el campo 1 y `gv_evento_tanda` devuelve NULL) ni los `ref` con pipe
(`tanda|NP`, `NP|CP`), así que el cron 68 vuelve a insertar el picking con el código viejo.
§3.jj, problemas 417, 420 y 421.

⚠ **Y un CUARTO, que es el que ve el agujero en vez del duplicado:**
`select * from public.gv_stock_tanda_pickeado_negativo;` — vacía = todo bien. Marca la tanda
cuyo **Pickeados quedó negativo**, con el motivo: *"armada sin picking propio"* (pickeado 0 y el
armado igual drenó — la firma del renombre), *"drenaje mayor que el picking"*, o —desde la
v20.32— *"el picking cierra: lo negativo lo dejó un ajuste manual"*.

⚠ **Y cuenta los ajustes que nombran la tanda en TEXTO LIBRE, no sólo los que traen el código
pelado de `ref`** (v20.32, problema 459). Un ajuste manual se anota con `ref = 'D53A'`, pero su
**reversión** se anota con texto (`ajuste manual | Revierte ajuste D53A: …`): contando uno y no el
otro, D53A vivía en rojo con el depósito sano, y los negativos de D20E y E10A no los veía nadie.
El código que sale del texto libre **se valida contra `GV_Tandas_Codigos_Usados`**, o el regex
inventa tandas.

**Va POR TANDA a propósito.** `gv_stock_negativos` agrega por código sin mirar la tanda, así que
el saldo positivo de otra tanda **tapa el agujero**: el 18/09 el hueco de E12K eran **34 códigos
/ 46 cajas** y en pantalla se veían **7**. Y a medida que se armaban otras tandas se consumía ese
colchón y aparecían códigos nuevos en rojo sin que se hubiera roto nada — el cartel prendía y
apagaba solo. Por tanda el número es estable y dice **dónde**.
`sql/gv_stock_tanda_pickeado_negativo_v2032.sql`, §3.kd y §3.kr.

```sql
select count(*) from (
  select 1 from public."Movimientos_Stock" where tipo in ('picking','separado','facturado')
   group by upper(btrim(ref)), upper(btrim(cod_art)), deposito, tipo
  having count(*) > 1 and count(distinct coalesce(empresa,'')) > 1) z;
```

## ⚠ REGLA: el `ref` del pipeline de stock NO se renombra a ciegas — se FUSIONA

**2026-09-18, problema 407.** Mover la tanda **E12A** (pickeada y armada) al lunes 21/09 desde
«📅 Cambiar de día» devolvía el error crudo de Postgres:

```
duplicate key value violates unique constraint "mov_stock_pipeline_dedup"
```

`gv_ppp_tanda_renombrar` hacía `update "Movimientos_Stock" set ref = <tanda nueva>` **a ciegas**, y
ese índice es **único** por `(ref, cod_art, empresa, deposito, tipo)` para
`picking/separado/facturado` — es el guard que impide el doble picking (problema 390). Si la tanda
destino ya tiene el mismo artículo pickeado, choca: **fusionar dos tandas armadas era imposible**,
aunque la pantalla lo ofrezca. Medido: E12A chocaba con 126 filas de E12E, 120 de E12F, 84 de E12K.

**Lo que corresponde es sumar los `delta`, y no es una licencia:** ese `delta` es el total pickeado
de la tanda para ese artículo y lo escribe `reconciliar_stock_articulo_rt` desde los eventos PKC;
como los eventos también se renombran, el reconciliador va a recalcularlo como la suma de las dos.
El saldo del depósito no se mueve ni una caja (medido: 0 saldos cambiados).

⚠ **Primero el DELETE de la fila vieja, después el UPDATE que suma.**
`trigger_actualizar_saldo_stock` recalcula el saldo del código desde cero pero corre
**AFTER INSERT OR UPDATE y NO en DELETE**: al revés, `stocks_carga_rapida` queda inflado.

⚠ **Y un código de tanda está TOMADO si tiene stock, aunque no figure en ninguna programación.**
`gv_ppp_web_codigo_tomado` sólo miraba las programaciones, así que «➕ Tanda nueva» podía reciclar
un código con movimientos viejos (353 al 18/09, más E01G de la serie viva). Ahora mira también
`Movimientos_Stock` — escrito como `upper(btrim(m.ref))`, **sin `coalesce`**, o no entra por el
índice y pasa de 0,1 ms a 49 ms de seq scan en un loop de hasta 400 vueltas.

**Chequeo:** `select * from public.gv_reglas_perdidas;` (las dos reglas tienen su centinela) y

```sql
select count(*) from (
  select 1 from public."Movimientos_Stock" where tipo in ('picking','separado','facturado')
   group by upper(btrim(ref)), upper(btrim(cod_art)), deposito, tipo
  having count(*) > 1 and count(distinct coalesce(empresa,'')) > 1) z;   -- 0
```

`sql/gv_ppp_tanda_fusion_stock_v1969.sql`, §3.jh.

## ⚠ REGLA: el guard del PEDIDO SUELTO no se le aplica a la TANDA ENTERA

**Luis, 2026-09-21 (v20.30, problema 458).** Son dos movimientos distintos y el sistema tiene que
tratarlos distinto:

| qué se mueve | ¿se puede si está pickeada? | por qué |
|---|---|---|
| **una NP sola**, a otra tanda | **NO** — `gv_np_mover_guard` la frena | las cajas viven en la pila de la TANDA: quedarían huérfanas (caso Martinelli, v20.01) |
| **la tanda entera**, a otro código o fusionada | **SÍ** | `gv_ppp_tanda_renombrar` se lleva el stock con ella y lo fusiona |
| **una NP sola cuya tanda YA SALIÓ SIN ELLA** y cuya pila cierra en cero | **SÍ** (v20.72) | no hay una sola caja que pueda quedar huérfana: lo pickeado ya drenó al facturarse y lo que queda es un bulto esperando el camión |

⚠⚠ **El tercer caso cierra un callejón que dejó un pedido 3 días parado** (v20.72, Thomas 21/09,
problema 472): `gv_ppp_tanda_mover` frena la tanda que salió en parte y **manda a mover la NP sola**,
y el guard frenaba exactamente eso con *"avisá a sistemas"*. Caso **LK 0027 (Albalandia)**: E03C
salió el 17/09 con 4 de sus 5 NP y el quinto quedó sin CCR, sin CCN y sin CRN. Lo resuelve
**`gv_np_mover_exento_salida(np, tanda)`**, con **tres** condiciones necesarias: la tanda ya salió ·
esta NP no · la pila cierra en cero. **Con saldo vivo sigue frenando** — ahí el motivo de la v20.01
vale igual.

⚠ **Al medir la pila de una tanda, contar los `ref` COMPUESTOS.** El drenaje del facturado se anota
como `<tanda>|<NP>` (`E03C|LK 0027`): filtrando `ref = 'E03C'` a secas da **+182** y parece que hay
stock vivo cuando cierra en cero. Van los tres: `= <tanda>`, `<tanda>|%` y `%|<tanda>`.

**Y el caso se ve solo**, que es lo que faltaba — Albalandia no aparecía en ninguna pantalla:
`select * from public.gv_pedido_quedo_sin_salir;` — vacía = ningún bulto quedó atrás; dice hace
cuántos días salió el resto y si se puede reprogramar sin tocar el stock. §3.lq.

Hasta la v20.30 el guard se disparaba en los dos casos, así que **"📅 Cambiar de día" con código
nuevo o fusión estaba bloqueado en 10 de las 12 tandas vivas** —incluida D69H, la que el centinela
de camión mezclado marcaba para que la arreglara Marianela— con el cartel *"avisá a sistemas"*.
Cambiar el día **sin** tocar el código sí andaba, y por eso no saltaba siempre.

Lo resuelve `p_tanda_entera`, que viaja `gv_ppp_tanda_mover` → `gv_ppp_nps_mover_a` → el guard y
exime **sólo las NP de esa tanda**: una NP de otra tanda pickeada se sigue frenando.

⚠ **No es un `p_forzar` ni un "saltear el guard".** Si aparece la tentación de agregar un booleano
que lo apague, es la señal de que se está por reabrir el pozo de las 92 cajas huérfanas.

**Chequeo** (las cuatro reglas tienen centinela): `select * from public.gv_reglas_perdidas;` —
vacía = todo bien. `sql/gv_mover_tanda_entera_v2030.sql`, §3.kq.

## ⚠ REGLA (Luis, 2026-09-23, v21.52): al facturar un DUAL, la caja sale de la pila donde ESTÁ

Caso **438E de Chef con «a facturar» en −1**: tanda D47B, pedido CH 0030. El armado anotó
`438E` **sin la L**, así que al facturar `stockSalidaFacturadoNP` tomó la empresa del pedido (CH)
y descontó de la pila de Chef, con la caja en la de LK. El guard `zzz_facturado_no_negativo`
no lo frenó porque mide la pila **sin empresa** (a propósito, v19.49) y LK tenía saldo.

Hoy ese mismo guard, en un código de `codigos_duales`, **cambia la empresa del descuento a la
otra** si la que viene no tiene saldo en esa tanda y la otra sí. No se tocó
`trg_normalizar_empresa_stock`. Centinela `v_otra` en `GV_Reglas_Centinela`.
`sql/gv_facturado_dual_pila_v2152.sql`.

⚠ Al corregir a mano la empresa de un movimiento, el caché `stocks_carga_rapida` se recalcula
**sólo para la empresa nueva**: la vieja hay que refrescarla aparte (un `update` sin cambios sobre
otro movimiento de esa empresa).

## ⚠ REGLA (Luis, 2026-09-22, v20.95): un código BUSCADO se muestra aunque esté en 0

**Luis, textual:** *"838E NO APARECE en la vista de stocks"*.

La tabla de Stock esconde a propósito las filas que están en 0 en **todos** los sectores y sin
pedidos — son ruido al mirar la tabla entera. Pero ese filtro (`_stkHasAny`) se aplicaba
**también al buscar**, así que tipear el código entero no traía nada. Eran **46 códigos**, **21
con proyección viva** (838E: capacidad 35, proyección 34,17 caj/mes, comprado por Log/ Fabr).

> **Una fila que no sale no se distingue de un código que no existe.** El 0 es la respuesta
> —*"no hay"*—, no un motivo para callarse.

⚠ El comentario de arriba del filtro **ya decía** *"con búsqueda sí se muestran (para poder
encontrarlos)"* y el código hacía lo contrario. Un comentario que contradice a su propio bloque
es una señal, no un adorno: el que se equivocó casi siempre es el código.

⚠ **Sin buscar el filtro SIGUE valiendo**, o vuelve el ruido de las filas todo-cero.
`tests/stk-buscar-cero.cjs` muerde por los dos lados.

### ⚠⚠ Y la otra mitad, que es la contraria: un código que NO EXISTE no se dibuja (v21.76)

**Luis, 23/09:** *"si busco 865 me muestra el 865 pelado (que no existe), ¿se puede poner un
filtro para que no muestre esos?"*.

> **No es lo mismo un 0 que un fantasma.** La v20.95 dice que un código que EXISTE y está en
> cero **se muestra**, porque el 0 es la respuesta. Acá no hay respuesta que dar: el código no
> es una cosa.

**De dónde salía el 865, medido:** de **dos filas de `Movimientos_Stock`** — un ajuste manual
del 18/08 a las 10:32 (−1) y su reversión a las 10:57 (+1). Alguien tipeó `865` en vez de
`865E` y lo corrigió 25 minutos después. Pero **el universo de stock se arma desde los
MOVIMIENTOS, no desde un maestro de artículos**, así que el código quedó vivo en la pantalla
para siempre: cada error de tipeo en un ajuste deja un fantasma permanente. Eran **19** al
23/09, entre ellos `VASTIDOR`, `H201 PART`, `N° 74` y `FLEJES LOEKEMEYER·0.80 X 64`.

El criterio **no mira el saldo para decidir**: mira si el código existe
(`gv_stock_cod_conocido`, que consulta **siete** maestros). El saldo entra sólo como guard,
para no esconder nunca algo con una caja, un pedido, proyección, capacidad o FC pendiente.

⚠ **Los siete maestros hacen falta los siete.** Con `vista_nombres_articulos` sola se escondían
también **991E, 993E, 996E, 997E y 998E** — que no están ahí pero sí en `vista_uxb_articulo`, y
que se pickean de verdad (el 998E el 22/09). Esconderlos habría sido el pozo de la v20.95.

⚠ **El front NO se tocó**: `_stkSaldosFromView` ya respetaba `visible_en_stock === false` con su
propio guard de saldo y pedidos en cero. El mecanismo estaba; faltaba que alguien marcara estos
códigos. Se marca en **`refresh_stocks_carga_rapida()`**, no en `vista_stock_procesada`: ésa es
una matview y cambiarla obliga a DROP + CASCADE, que ya se llevó puesta `gv_importados_ordenes`
dos veces (v16.20 y v16.33).

**Chequeo:** `select * from public.gv_stock_codigos_fantasma;` — dice cada uno con sus
movimientos y el motivo (*"ajuste mal tipeado que ya se revirtió"*). Al 23/09: **19 filas, 0
con saldo**. `node tests/stk-codigo-inexistente.cjs` (verificado que falla si el flag vuelve a
`true`). `sql/gv_stock_codigos_fantasma_v2176.sql`.

⚠ **Hallazgo aparte, NO es de este cambio:** el **439E** (Colador Pasta) ya venía oculto por la
regla vieja del dual partido —base pelada con stock 0— y tiene **proyección 27 caj/mes y
capacidad 66**. El guard del front sólo exige stock y pedidos en cero, así que hoy no se ve.
Queda reportado; no se tocó.

## ⚠ REGLA (Thomas, 2026-09-30, v25.28): un ajuste a un código que NO EXISTE se confirma antes — en la app y en el chat

**Thomas:** *"si alguien te dice «restale 40 al 999FT» que la sesión le diga «no existe ese código, lo creo y le pongo -40?»"*.
Caso **365ED**: se tipeó en vez de 865ED (13:57), se grabó −47 y quedó un fantasma en negativo; se cargó bien a las 14:00.

- **App** (Stocks → Ajustar / Fijar): `_stkCodExisteConfirmar` pregunta a `gv_stock_cod_conocido` (los siete maestros).
  No existe → *"No existe el código X. ¿Lo creo y le pongo −40?"*; sin respuesta de la base también pregunta
  ("no pude leer" no es "existe"). `tests/stk-ajuste-cod-inexistente.cjs`.
- **Sesión de Claude**: antes de un `insert` a `Movimientos_Stock` con un código que dio el usuario, correr
  `select public.gv_stock_cod_conocido('<cod>')`; si da `false`, preguntar con esas palabras y esperar el «sí».
- ⚠ Antes de revertir un movimiento, mirar si **otra sesión ya lo revirtió**: el −47 del 365ED lo había revertido
  otra sesión a las 14:01 y la reversión de las 15:27 lo dejó en +47 (se anuló en el acto).

## ⚠ REGLA (Luis, 2026-09-28, v23.00): una COPIA que se reescribe con upsert tiene que PODAR lo que la fuente ya no trae

Caso (problema 578): `PPP_Web_Base` —la lista de picking de cada NP web— se escribía sólo con
upsert (`merge-duplicates` / `on conflict do update`). El upsert **suma y pisa, nunca saca**: si un
artículo salía de la NP después de programada (corte de diferido del 24/09, pedido 1524), quedaba en
las dos NP y E37A pickeó 954E y 956E de más. Hoy las tres escrituras llaman a
`gv_ppp_web_base_podar`: saca lo que la NP ya no trae **sólo si la tanda no empezó**; lo de una tanda
empezada queda en `gv_ppp_web_base_sobrante` (vacía = todo bien) y todo lo borrado en
`GV_PPP_Web_Base_Podado`.

> **Al escribir un sync con upsert, la pregunta es: si en la fuente algo DESAPARECE, ¿quién lo
> borra acá?** Si la respuesta es "nadie", la copia miente para siempre.

Barrido del 28/09: `ppp_web_resync` ya borra la NP entera que desaparece (tanda sin empezar);
`sync-precios-venta` tiene `reconcileStale`; `gv-sync-padron-direcciones` **no borra** (8 direcciones
de LK viejas del 14/09, ninguna con NP programada). `sql/gv_ppp_web_base_podar_v2300.sql`.

## ⚠ REGLA (Thomas, 2026-09-30, v24.68): BAJAR DE RACKS — posición obligatoria y conteo a ciegas que aprueba un supervisor

- **Sin posición de rack no se registra la bajada** (`rkbConfirmar`). Las posiciones se muestran de MENOR a mayor: se vacía primero la que menos tiene y se libera el lugar. Si el código no tiene posición en el Mapa, el operario la escribe.
- **Lo que entra en góndola** = capacidad (`Capacidad_Sector`) − lo que hay; «Bajar lo que entra». Lo que no entra va a **EXCEDENTE** (campo `excedente` de `registrar_baja_racks`, movimiento `-x`), avisado antes.
- **Conteo a ciegas** después del código: cuántas quedaron en la posición y cuántas hay en la góndola ya acomodada (`conteo_rack` en cajas, `conteo_gondola`). Se guarda en **`GV_Rack_Conteo`**; si no coincide con el sistema queda **pendiente** + Telegram, y **no mueve stock hasta que lo apruebe un supervisor** (Stock → Racks → «🔎 Conteos a aprobar», `gv_rack_conteo_resolver`: ajuste por la diferencia contada; rechazar no toca nada).
- `sql/gv_rack_conteo_v2468.sql`, `tests/racks-propuesta.cjs`.

- **v25.76 (Luis, 01/10): «Bajar de Racks» es su PROPIO módulo y baja a A GUARDAR.** Salió del chooser de Guardado a
  Góndola («De los racks» ya no está) y es un botón chico debajo de MG (`#row3b`, `selectOption("RKBM")`). Manda
  `destino: 'a_guardar'` a `registrar_baja_racks` (marcador `v25.74-aguardar`): racks − / **a_guardar** +, sin excedente
  ni conteo de góndola (el conteo a ciegas del rack sigue). Sin el campo (celulares viejos, supervisor) va a terminado
  como antes. Después se guarda con MG → «Lo que llegó». `sql/gv_baja_racks_a_guardar_v2574.sql`, `tests/racks-propuesta.cjs`.
  **v25.78 (Luis): el botón es «BR» (sin emoji, data-code `RKBM`), chico en las secundarias junto a CR/RR/RC/IR.**

## ⚠ REGLA (Luis, 2026-09-30, v25.18): «⟳ Refrescar ya» en Stocks — el SALDO ya es en vivo, lo que espera es lo DERIVADO

**Luis:** *"pone un boton en la tabla de stocks que permita refrescarla «por la fuerza». 2 minutos es un monton"* ·
*"esto no estaba en vivo entonces?"*.

| dato de la tabla de Stocks | cuándo se actualiza |
|---|---|
| saldo por depósito (góndola, excedente, pickeados, a facturar…) | **en vivo**: `trigger_actualizar_saldo_stock` reescribe la fila de `stocks_carga_rapida` en cada movimiento y el realtime (`stkSubscribeRealtime`) la parchea en pantalla |
| cajas pedidas, proyección, capacidad, FC s/salida, altas/bajas de códigos | **hasta 2 min** (cron 55 → `gv_refresh_stock_si_cambio`), porque salen de la matview |

El botón adelanta lo segundo. El refresco completo tarda **~7,4 s** (matview 1,7 + carga_rapida 5,7) y
`authenticated` corta a los **8 s**, así que **el navegador NO lo corre**: `gv_stock_refrescar_ya()` (supervisor)
agenda un job de pg_cron de **un disparo** (`'2 seconds'`, corre como postgres sin timeout) que **se borra a sí
mismo primero** y llama a `gv_refresh_stock_si_cambio(0, false)`; si el lock 5768 está tomado, espera y reescribe
la derivada igual. La pantalla mira `gv_stock_refresco_ultimo()` cada 1,5 s y reabre Stocks **conservando solapa y
búsqueda**. Medido: ~9 s del click a la tabla nueva. Doble click → `en_curso`, no agenda dos.

⚠ Hacer TODO en vivo (lo derivado incluido) no es viable: cambia por pedidos, capacidad y proyección, que son otras
tablas, y reescribir la derivada cuesta 7 s por cambio.
`sql/gv_stock_refrescar_ya_v2518.sql`, `tests/stk-refrescar-ya.cjs`.

## ⚠ REGLA (Marianela, 2026-09-30, v25.20): la cola offline de stock se reintenta FILA POR FILA — y «Fijar» lee el saldo del servidor

**Marianela:** *"El operario 104 hizo un movimiento de góndola a Cervantes por el art 328E de 48 cajas y no impactó, ¿por qué?"*

- **La cola `vir_stock_pend` se mandaba en UN POST**, y el insert es una transacción: una sola fila que el server
  rechaza hacía fallar el lote entero en cada recarga, y todo lo de atrás quedaba trabado **para siempre** en ese
  celular. Medido el 30/09: el del legajo 104 reintentaba ~20 veces por día un guardado del 599E que ya había
  entrado el 21/09 (400 del candado de A guardar), y atrás quedó la salida a Cervantes del 328E (48 cj).
- Hoy `stockFlushPend` va fila por fila: ok → sale · 409 duplicado (ya estaba) → sale · 400/422 de datos → sale y
  queda en **`vir_stock_rech`** (localStorage) · red / 5xx / permisos → queda. Lo que se encole mientras tanto no se pierde.
- ⚠ **Cuando el celular trabado se actualiza, lo atrasado ENTRA SOLO**, con fecha de hoy. Antes de cargar a mano un
  movimiento "que no impactó", mirar si no llegó con la actualización: si no, se duplica.
- **«Fijar» (ajuste admin) calculaba el saldo con `_stk.movs`**, que se carga en segundo plano (el libro entero):
  antes de que llegara veía 0, decía "ya es 0" y no grababa (566E). Ahora pregunta a `gv_saldos_por_clave`; sin
  lectura no fija nada.
- **Cómo se ve una cola trabada:** edge logs con POST `/rest/v1/Movimientos_Stock` en 400/409 repetidos desde la
  misma IP/celular; el `raise` del trigger está en `postgres_logs`, y el legajo sale cruzando la hora contra
  `Registros_Produccion_Virgilio.created_at`.
- `tests/stock-cola-por-fila.cjs` (verificado que falla contra la v25.15).

## ⚠ REGLA (Luis, 2026-10-05, v26.86): guardar en una GÓNDOLA SIN LUGAR no se frena — AVISA por Telegram

D1 = no se bloquea el guardado. Cron **132** `gv-alerta-gondola-llena` (`3-58/5`) → `gv_alerta_gondola_llena_telegram()`:
cada movimiento que suma a `terminado` (guardado, baja_racks, recepcion_imp) que deja la góndola del código (dual: por
empresa) más de **5 %** por encima de `Capacidad_Sector` (D3, v26.87) manda UN Telegram (quién, cuántas, góndola vs capacidad). Dedup en
`GV_Alerta_Gondola_Llena`. Sin capacidad cargada no avisa. Probar sin mandar: `select * from
public.gv_alerta_gondola_llena_telegram(true);`. Centinela 322. `sql/gv_alerta_gondola_llena_v2686.sql`.

## ⚠ REGLA (Luis, 2026-10-09, v29.05): un AJUSTE de RACKS lleva la POSICIÓN — Stock → Ajustar / Fijar / Stock inicial

Caso 606 (09/10): un ingreso a racks X22 se cargó como **606** siendo **606E** (pedido PI B260601), y la corrección desde
Stock → Ajustar restó −10 **sin posición**: X22 siguió con +10 y la alerta «bajado de racks sin decir de qué posición»
quedó viva. Pasó 6 veces desde el 25/09 (desde la v22.77 el stock de racks vive por posición).

- **Front** (`_stkRackPosElegir`): con depósito Racks / Racks CH, Ajustar y Fijar piden la posición (casilla «Posición rack»
  o prompt con las posiciones que tiene el código), la validan contra el Mapa (`gv_rack_sector`) y, al restar más de lo que
  tiene esa posición, avisan. **Fijar en racks fija LA POSICIÓN**, no el total. Stock inicial en racks: `CÓDIGO CANTIDAD POSICIÓN`.
  Sin posición o sin poder verificarla, no graba.
- **Base**: trigger `aa_gv_racks_ajuste_sin_posicion` (legajo `0` = panel, tipo ajuste/inicial) → `RACKS_SIN_POSICION`.
  Rollback: `alter table public."Movimientos_Stock" disable trigger aa_gv_racks_ajuste_sin_posicion;`
- Datos 09/10: 606 vuelto a 0; 606E = 130 cajas (13 MC) en X22, imputadas al pedido PI B260601 (1.560 u, llegado) con
  `gv_imp_imputar_ingreso_racks`.
- `sql/gv_racks_ajuste_sin_posicion_v2905.sql`, centinela 379, `tests/stk-ajuste-racks-posicion.cjs`.

## ⚠ REGLA (Luis, 2026-10-09, v29.15; la base dice v29.13, llave): SALIDA A CERVANTES sale de GÓNDOLA o A GUARDAR — NUNCA de racks

- Insumos y Productos Movimiento → 🚚 Salida a Cervantes: pestañas **Góndola** (`terminado`) y **A guardar** (`a_guardar`), en cajas.
- **Para mandar una MC que está en racks**: «BR · Bajar de racks» (baja a A guardar, p. ej. 1 MC = 12 cajas) y después se manda
  desde A guardar. Retira la pestaña Racks de la v29.12 (caso 958E del 09/10: JM mandó 1 MC desde AD10 con la MC mal cargada en 13).
- Lo sostiene la base: trigger `aa_gv_salida_cervantes_no_racks` → `SC_DESDE_RACKS` (centinela v29.13).
  `sql/gv_salida_cervantes_no_racks_v2913.sql`, `tests/sc-racks-unidad.cjs`.

## ⚠⚠ REGLA (Luis, 2026-10-13, v30.01): los modos de INGRESO A RACKS son «Ingreso directo» y «Desde A guardar»

**Luis:** *"el problema es que no hay una forma clara para mandar mercadería de A guardar a Racks"* ·
*"Importado y nacional se tiene que renombrar a «Ingreso directo» o «Desde A guardar»"*.

> ## **El modo se llama por lo que HACE, no por el origen de la mercadería.**
> **📦 Ingreso directo** = entra al depósito ahora, **crea stock nuevo**. · **📥 Desde A guardar** =
> ya está en el depósito, **lo mueve** (descuenta de A guardar o de Excedente).

| | antes | ahora |
|---|---|---|
| botones | 📦 Importación · 🏠 Nacional | **📦 Ingreso directo · 📥 Desde A guardar** |
| valor interno | `import` / `nacional` | **igual** (lo usan `racks_plani_ingreso` y `racks_plani_ingreso_nacional`): no se toca |

- **Y avisa**: en «Ingreso directo», un código que YA tiene cajas en A guardar (o en Excedente) saca
  *«⚠ Este código ya tiene N cajas en A guardar. Si son esas mismas cajas, esto NO es un ingreso
  directo: se contarían dos veces»* con el botón **📥 Moverlas desde A guardar**, que pasa al otro
  modo con el código y el origen puestos. **No frena**: lo decide el operario (`_irAvisoAGuardar`,
  `irDesdeAGuardar`; el saldo sale de `_ir.saldos`, que ya se carga al abrir el módulo).

**Lo que costó, el 13/10:** el **934E** (1 master, 12 cajas, Y07, 14:40) y el **606E** (10 cajas,
X22, 10:00) se cargaron por Importación cuando esas cajas ya estaban en A guardar: racks sumó y
A guardar quedó igual, o sea **el stock contado dos veces**, y nada avisó — lo vio Luis en Stocks.
Corregido con un ajuste (`CORR IR 146592538`, A guardar 934E −12 → 0; racks queda en 180, que es lo
que hay). El movimiento de racks NO se toca: la mercadería está en Y07.

**Cómo se encuentra otro igual** — un IR que no descontó nada y dejó saldo vivo en A guardar:

```sql
select m.id, m.creado, m.cod_art, m.delta, m.ref, m.legajo
  from public."Movimientos_Stock" m
 where m.deposito = 'racks' and m.tipo = 'ingreso' and m.ref like 'ingreso a racks %'
   and m.creado >= now() - interval '30 days'
   and exists (select 1 from public."Movimientos_Stock" x
                where x.deposito = 'a_guardar' and upper(btrim(x.cod_art)) = upper(btrim(m.cod_art))
                group by 1 having sum(x.delta) > 0)
 order by m.creado desc;
```

**Chequeo:** `node tests/ir-codigo-candado.cjs` (bloque **H**: el aviso, que no frena, que el botón
cambia de modo con el código puesto, y los dos rótulos nuevos; verificado que falla contra la v30.00).

## ⚠ REGLA (Luis, 2026-10-13, v29.67 + v29.77 + v29.78, D2): en INGRESO A RACKS el CÓDIGO SE ELIGE — se sugiere mientras se escribe

**Luis:** *"956E · va a terminar en AB10 · el operario lo puso mal · ponele candado"* y, después del candado:
*"mas que candado, solo debería dar opciones de poner un codigo ya existente. a medida que se escribe se sugiere
el codigo"*. El 13/10 09:34 el legajo 104 escribió la **posición** `AB3` en el campo del **código** y entraron
**60 cajas de un código fantasma** en AB03 (eran **956E** y las volvió a cargar bien en **AB10** a las 09:37). El
09/10 había pasado lo mismo con «606», que era 606E.

> ## **El campo Código del modo Importación BUSCA: el código sale de la LISTA, no del teclado.**

| lo que escribe el operario | qué hace el módulo (v29.77) |
|---|---|
| parte del código o del **nombre** (`956`, `cuchara`) | **sugiere** los códigos que existen (🚢 = importado); hay que **tocar** el que corresponde — una coincidencia parcial no elige sola |
| el código entero, exacto (`956E`, y `26` = `026`) | se elige solo: tipear el código completo sigue andando sin tocar la lista |
| `606` (el caso del 09/10) | la lista le sugiere el **606E**, que es el que existe |
| nada que coincida | ⚠ *«No hay ningún código que coincida»* + **«✎ Cargar «XXX» igual (código nuevo)»**, y ahí el candado PREGUNTA antes de crearlo |

- La lista sale de **`gv_stock_cod_lista()`** (lectura, anon, 689 códigos / 155 importados / 321 ms al 13/10):
  el **MISMO universo** que ya decide el candado `gv_stock_cod_conocido`, así la pantalla **no puede sugerir un
  código que después el candado rechaza**. Deja afuera los dados de baja (`GV_Codigo_Baja`) y los **insumos puros**
  —`A1` es insumo **y** posición de rack, justo la confusión que esto cierra—; el insumo importado (**323ES**) entra
  porque está en `Importados`. Devuelve el código **como lo escriben los maestros** (`026`, no `26`), que es como se
  escribe en `Movimientos_Stock` / `GV_Lugar_Item` / `Importados` / `OC_Maximos`.
- ⚠ **Si esa lectura falla, el campo queda libre con el candado de la v29.67** y nada más: *«no pude leer»* no es
  *«ese código no existe»*.
- `irSetCod` **ya no cuelga de ningún input** (queda como setter programático): un código que no está en el universo
  queda marcado como **código nuevo**, el mismo estado que deja el «usar igual», así el candado lo pregunta.

### El candado de la v29.67 sigue abajo de todo (y es lo único que frena a AB3)

| lo tipeado | qué hace el módulo |
|---|---|
| código que existe (`gv_stock_cod_conocido`, los 7 maestros) | sigue como siempre |
| **POSICIÓN de rack** que no es un código (`gv_rack_sector`: AB3 → AB03, W1 → W01) | **no se carga, y SIN CARTEL** (Luis, v29.78: *«No tiene que avisar que es una posicion, simplemente no tiene que dejar»*): no está en la lista, no se ofrece «usar igual» y «Revisar carga» queda deshabilitado |
| código **dado de baja** (`gv_codigo_baja_de`: 865ED → 865E) | bloquea y dice cuál va |
| no existe y no es posición | **pregunta** (no bloquea): *«No existe el código X. ¿Lo creo y le cargo N cajas en SEC?»* |
| no se pudo verificar | pregunta: *«no pude leer» no es «existe»* |

- Es el mismo candado de **Stocks → Ajustar / Fijar** (v25.28) con el aviso de posición que este caso pide
  (`_irCodChk` / `_irCodGuard`, cache por código, chequeo con debounce al tipear + candado en `irRevisar`).
- ⚠ **Solo en modo IMPORTACIÓN**, que es donde el código se TIPEA: en **Nacional** sale de la lista de stock real
  (y su clave trae el sufijo de empresa, `438E LK`, que `gv_stock_cod_conocido` no conoce: daría falso rojo).
- ⚠ **La posición bloquea sólo si ADEMÁS el código no existe**: `A1` es rack de insumos **y** código de verdad
  (medido 13/10: `gv_rack_sector('A1')` = A1 y `gv_stock_cod_conocido('A1')` = true).
- ✅ **El dato de AB3 se corrigió el 13/10** (D3): ajuste inverso `-60` en AB03 (mov **146068820**, `ref 'CORR IR 145833325'`,
  backup `zz_backups."GV_Backup_MovStock_AB3_20261013"`). AB3 queda en **0** y **AB03 libre** en el Mapa; las 60 reales siguen en
  **AB10** (132). El movimiento original NO se borra. Problema **758** de la auditoría, cerrado con este commit.
- ⚠ **Con la lista puesta, `AB3` ya no puede quedar elegido tipeando** (no está en el universo): lo único que se
  ve es el *«No hay ningún código que coincida»* **sin** el botón de «usar igual» (`_irChkMal` sigue usando
  `gv_rack_sector` para decidirlo, pero ya no lo dice). El candado sólo se alcanza forzando el código
  (`irSetCod`) y ahí frena sin cartel. **Se prueban las dos capas.**
- Centinelas 403 y 404 · `sql/gv_stock_cod_lista_v2977.sql` (rollback: `drop function public.gv_stock_cod_lista();`) ·
  `tests/ir-codigo-candado.cjs` (corre la pantalla; verificado que falla con **14 chequeos en rojo** contra la v29.73
  y con 10 contra la v29.66).

## ⚠ REGLA (Luis, 2026-10-13, v29.58): en BAJAR DE RACKS la capacidad del DUAL es POR EMPRESA — y sin capacidad se ordena por E.M.

El orden por urgencia de Bajar de racks (v25.89, `(góndola + A guardar − pedido) ÷ capacidad`, menor primero)
tenía dos agujeros, medidos el 13/10 sobre los 57 códigos con stock en racks:

1. **El dual iba último.** `vista_saldos_stock` emite la clave CON sufijo (`437E LK`) y `ocgFetchCapacidad` indexa
   el código **pelado** (`437E`): no matcheaba, `prio = Infinity`. Eran 3 filas vivas (437E LK con **225 cajas en
   racks**, 438E LK 78, 809E CH 336) con la góndola a medio llenar. La capacidad por empresa **ya estaba** en
   `Capacidad_Sector` (437E: LK 120 / CH 48): faltaba cruzar **(cod, empresa)**. Lo hacen `rkbFetchCapacidad()`
   (devuelve `pelada` y `porEmp`, nunca pegadas) y **`_rkbCapDe(cod, capObj)`**. Para un código no dual da
   exactamente lo mismo que antes.
2. **Sin `cajas_max` cargada van al final, y entre ésos manda la ESTADÍSTICA MADRE** (`gv_proyeccion_articulo`,
   mayor a menor): sin capacidad no hay hueco que medir, así que primero lo que más se vende. Al 13/10 son 3
   (**505I con 1.475 cajas en racks** y la góndola en 0 — su celda del Mapa no tiene capacidad —, 938E 228 sin
   celda, AB3 60) y **ninguno está en `gv_proyeccion_articulo`**, así que hoy la E.M. de los tres es 0 y
   desempata el código: el orden entre ellos sólo cambia cuando alguno tenga venta.

⚠ **El ratio mide «qué tan vacía está la celda», no cuántas cajas entran.** El 606E queda 6.º con prio 0,00
teniendo **218 de hueco** y 120 en racks, detrás del 361E (hueco 41, cap 32). **Luis lo decidió así el 13/10** (*"está bien que pese un pedido de esa forma, dejalo así"*): el
objetivo es que ninguna celda se quede sin mercadería para el picking, y el pedido pesa sobre el tamaño de SU
celda. **No volver a proponer el orden por hueco en cajas** (`min(cap − góndola − A guardar + pedido, racks)`),
que es la otra lectura y quedó descartada.

⚠⚠ **v29.64 (D5, Luis 13/10: *"que no lo saque, que pueda evaluar individualmente a cada uno"*): el mismo
`_rkbCapDe` en GUARDADO A GÓNDOLA, en «¿QUÉ BAJAR PRIMERO?» y en su BADGE.** Los tres cruzaban la capacidad
con `capMap[_ocgNorm(a.cod)]`, o sea el código **pelado** contra una clave de saldo que para los duales trae
el sufijo: el dual quedaba con `cap = 0` y, en «¿Qué bajar primero?», el `if (cap <= 0) return null` de los
urgentes **lo borraba de la pantalla y del badge** (el 437E LK con 225 cajas en racks y la góndola de LK a 72
no aparecía nunca). Hoy los tres llaman a `rkbFetchCapacidad()` + `_rkbCapDe(a.cod, capObj)`, así que **cada
empresa del dual se evalúa por separado** y para un código no dual el número es idéntico al de antes.
En MG, además, las **cajas × MC y las celdas de góndola** se buscan con sufijo y se caen al pelado (son del
ARTÍCULO, iguales en las dos empresas): sin eso el dual no mostraba el hint de MC ni sus celdas. **La DEMANDA
no cae al pelado**: `ocgDemanda(true)` ya la emite por empresa (`pkCodEmpresa`) y el fallback le daría a cada
empresa los pedidos de las dos.

⚠ **Capacidad en más de una empresa son SÓLO 5 códigos** (medido 13/10): los 4 duales y el **606E** (LK + IN),
que por eso sigue midiéndose con la suma pelada (218) — `porEmp` guarda únicamente LK y CH.

⚠ **D6 (Luis, 13/10): el 505I queda al final y la capacidad la carga Luis a mano** (*"cerralo así después se
la asigno manualmente"*). Tiene **1.475 cajas en racks** con la góndola en 0 porque su celda del Mapa no tiene
`cajas_max`. No cargarla desde una sesión.

**Chequeo:** `node tests/rkb-orden-urgencia.cjs` · `node tests/mg-prioridad.cjs` · `node tests/qbp-liquidar.cjs`
— los tres corren la pantalla y miden que el 437E LK tome **120** (el de LK), no los 168 de las dos empresas
sumadas, y que no se caiga de la lista. Verificado que los tres fallan contra el index anterior.

## ⚠ REGLA (Luis, 2026-10-13, v29.64, D11): el GUARDADO A GÓNDOLA puede entrar A MEDIAS — y queda así

**Luis, textual:** *"d11 no, dejalo así"*. Medido en la auditoría del módulo de operarios: un guardado (MG)
son **dos filas sueltas** (`a_guardar −N` / `terminado +N`, cada una con su `client_id`, el mismo `creado`) y la
cola del celular las manda **fila por fila** (v25.20). El guard `trg_guardado_no_negativo` rechaza con
`raise exception` (23514) **sólo la pata de `a_guardar`** cuando el saldo quedaría negativo; la cola la descarta
como «400 de datos» y **la pata de góndola entra igual**, así que la góndola queda inflada y nada avisa.

**Riesgo asumido:** puede volver a pasar y el saldo del código queda por encima de lo físico hasta el próximo
conteo. **Cuánto pasó en toda la historia: 1 vez, 1 caja** — 599E, 30/09/2026 15:51:29, legajo 104, movimiento
id 104074491, `terminado +1` sin su `a_guardar −1` (góndola 599E = 40, físico 39). El guard está bien: lo que
falla es que las dos patas viajan por separado. **No volver a proponer el arreglo sin que Luis lo pida.**

✅ **La caja del 599E se corrigió el 13/10** (D12, Luis: *"d12 si, corregila"*): ajuste `terminado −1` con
`ref = 'CORR MG 104074491'` (mov 145964321). Góndola 599E 40 → **39**, igual al caché `stocks_carga_rapida`. El
movimiento original NO se borra: la corrección va como ajuste aparte.

Cómo se ve si vuelve a pasar: un `guardado` de `terminado` sin su par de `a_guardar` con el mismo `creado`, sin
su ajuste de corrección:

```sql
select m.cod_art, m.creado, m.legajo, m.delta
  from public."Movimientos_Stock" m
 where m.tipo = 'guardado' and m.delta > 0
   and not exists (select 1 from public."Movimientos_Stock" x
                    where x.tipo = 'guardado' and x.deposito = 'a_guardar'
                      and x.cod_art = m.cod_art and x.creado = m.creado and x.legajo = m.legajo)
   and not exists (select 1 from public."Movimientos_Stock" c
                    where c.ref = 'CORR MG ' || m.id::text)
 order by m.creado desc;
```

Al 13/10 queda **1 fila y es de antes del módulo actual**: 542, 22/07/2026, `legajo` y `client_id` en NULL (una
carga de panel, no del celular).

⚠⚠ **El 542 del 22/07 NO SE TOCA Y NO SE PREGUNTA MÁS** (Luis, 13/10: *"542 olvidate, fue hace un montón así que
seguramente ya se ajustó. Que vos y que cualquier otra sesión dejen de preguntarlo"*). Es de hace tres meses y el
conteo ya lo ajustó. **Ninguna sesión lo vuelve a reportar ni a ofrecer corregirlo**: al correr la consulta de arriba,
esa fila se ignora.

## ⚠ REGLA (Luis, 2026-10-13, v29.69): una BAJA DE RACKS que no se guarda queda colgada — y el reconteo del rack la DUPLICA

Caso **606E**: el 09/10 15:55 el legajo 104 bajó **10 cajas de X22** a «A guardar» y nunca las guardó (entre esa fecha
y el 13/10 no hay un solo MG del 606E). El 13/10 10:00 se recontó X22 (**130 cajas**, +10 de ingreso) y se bajaron las
130, que se guardaron enteras a las 10:36. Resultado: A guardar quedó con **10 cajas que ya estaban contadas adentro de
las 130**. Luis, 13/10: *"las 130 eran lo único que había, no hay 10 cajas sueltas en ningún lado (a guardar, góndolas,
racks, nada)"*.

> **Una baja de racks (BR) sin su guardado (MG) deja saldo vivo en «A guardar». Si después se recuenta ese rack, ese
> saldo pasa a contar dos veces.** El conteo del rack no sabe que esas cajas ya habían salido en la base.

✅ Corregido el 13/10 (Luis: *"corregilas"*): ajuste **`a_guardar −10`** con `ref = 'CORR BR 132730592'` (mov
146068819). No va a `terminado`: las cajas no existen aparte, estaban dentro de las 130 ya guardadas. A guardar del
606E = **0** en movimientos y en el caché; `gv_stock_negativos` sin el 606E. El `baja_racks` original NO se borra.

**Cómo encontrar otro caso igual** — código con saldo vivo en «A guardar» cuyo último movimiento es un `baja_racks`
(no un guardado), sin su ajuste de corrección:

```sql
select m.cod_art, m.empresa, sum(m.delta) a_guardar,
       (array_agg(m.tipo order by m.creado desc))[1] ultimo_tipo,
       max(m.creado)::date desde
  from public."Movimientos_Stock" m
 where m.deposito = 'a_guardar'
 group by 1,2 having sum(m.delta) > 0
 order by 3 desc;
```

⚠ **Un saldo en «A guardar» no es un error por sí mismo**: es mercadería bajada o recibida esperando guardarse. Lo que
hay que mirar es si ese rack se recontó después de la baja. **La corrección va con el «sí» del dueño**, porque la
pregunta («¿esas cajas están físicamente?») sólo la puede contestar el depósito.

⚠⚠ **NO se avisa cuando una baja queda sin guardar: Luis dijo que NO** (13/10, D16: *"no lo armes"*). Se le ofreció un
aviso (Telegram o cartel) para el BR que al día siguiente sigue sin su MG, y lo bajó. **No volver a proponerlo.** El
caso se encuentra con la consulta de arriba, a mano.


## Conteo 809E CH y 935E (Luis, 2026-10-13, v30.24)

- **809E de Chef: góndolas M13, M14, M15 y M16** (M16 compartida con el 809 nacional). AD05 se bajó entera a
  góndola: racks 0, góndola **366 cajas** (sólo 809E; el 809 sigue con 9). Ajuste `conteo_809e_ch_20261013_*`;
  la celda AD05 / 809E se sacó del Mapa (backup `zz_backups."GV_Backup_LugarItem_809E_20261013"`).
- **935E en AB09: 2 MC (24 cajas)**, no 5: ajuste −36 (`conteo_935e_ab09_20261013`).
