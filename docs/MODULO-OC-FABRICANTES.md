# OC a fabricantes que no reciben ellos mismos (Pedernera/Blistpack/Oscar)

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠⚠ REGLA (Luis, 2026-09-22, v21.20): a BLISTPACK, OSCAR y PEDERNERA **no se les manda OC**

**Luis, textual:** *"a blistpack/oscar/pedernera no se le manda OC, porque ellos fabrican acorde
a lo que le mandamos desde log/fabr"*. Y antes, sobre esos tres códigos: *"544, 560, 800 son pedernera 100%, pero no se le manda la OC a pedernera, solo
se le manda a log. Pero la recepción de mercadería es mercadería de Pedernera"*.

**Es el caso Oscar exactamente al revés**, y las dos puntas están bien: la orden se le emite a
**`Log/ Fabr`** y el que trae las cajas es **`Pedernera`**. Ninguna de las dos se "corrige".

Medido el 22/09:

| | 544 Batidor Pera | 560 Pinza Chica | 800 Pinza Chica Display |
|---|---|---|---|
| OC emitidas | **Log/ Fabr** · 6 · 2.022 cajas | **Log/ Fabr** · 4 · 168 | **0** |
| recepción | **Pedernera** · 22 · 1.866 | **Pedernera** · 7 · 259 | **0** |
| `OC_Maximos.proveedor` (quién FABRICA) | **Pedernera** (v21.23) | **Pedernera** (v21.23) | Pedernera |

⚠ **La consecuencia medible: `cantidad_recibida = 0` en las DIEZ OC.** 2.190 cajas ordenadas,
2.125 recibidas, **0 imputadas** — nueve quedaron `anulada` y una `pendiente`.
**`gv_oc_recompute_recibido(proveedor, codigo)` cruza por el par `(proveedor, código)`**, así que
con nombres distintos en las dos puntas la OC **no se cierra nunca sola**.

### ⚠⚠ Y son EXACTAMENTE estos tres: NO es un patrón de toda la tabla

**Luis, 2026-09-22, textual:** *"No siempre es la norma general de que le entrega a otro. En los
únicos que la orden sale en nombre de uno y le entrega a otro son los casos de Pedernera,
Blistpack y Oscar."*

O sea: **«la OC sale a uno y entrega otro» es una REGLA de negocio sólo para los tres fabricantes
de `GV_OC_Fabrica_Para`.** Cualquier otro código donde eso pase **es configuración mal puesta**, y
se arregla poniendo en `OC_Maximos.proveedor` al que de verdad entrega. **No se agrandan las
excepciones**: si aparece un caso nuevo, primero se mira la config, y sólo Luis decide si ese
fabricante entra a la tabla.

**Los 19 códigos que quedaban los revisa y los configura Luis, uno por uno** (22/09: *"lo
configuro yo, los 22 artículos que me pasaste, y lo damos por cerrado con eso"*). **Claude no los
toca.** Medido ese día contra `vista_generador_oc` —que es lo que se va a emitir, no lo que se
emitió—: **5 ya están bien** (550, 584E, 234, 609, 580: la config ya dice el que entrega y las OC
viejas a otro nombre son restos que se limpian solos), **1 no tiene proveedor** (583E, que por eso
no se puede comprar) y **13 hay que mirarlos**.

**El 591 (Despolvillador de Yerba) ya está cerrado: DISCONTINUADO** (Luis, 22/09: *"no se va a
recibir más ni va a salir en OC"*). `activo = false`, `proveedor = null` y el motivo en la
descripción; backup en `zz_backups."GV_Backup_OCMaximos_591_20260922"`. Verificado **como `anon`**,
que es la identidad del celular: sale de la lista de compra, del buscador de códigos activos de
Recepción (el «+» de Log/ Fabr lee `OC_Maximos where activo`) y del botón de Tierra Nativa — los
tres en **0**. Sus 6 OC (119 cajas, del 12/08 al 16/09) ya estaban **todas `anulada` con 0
recibido**, así que no quedó ninguna viva que cancelar.

⚠ **Discontinuar acá NO lo saca de la página.** En LK `products.active` sigue en `true` y sin
badge: el cliente lo sigue pidiendo. Al 22/09 hay **7 NP programadas** con 591 (22/09 al 02/10)
contra **13 cajas de stock** — salen con lo que hay. Si además hay que dejar de venderlo, es otro
cambio, en el proyecto de LK.

⚠ **La medición se hace contra `vista_generador_oc`, NO contra `OC_Maximos` a secas ni contra las
OC ya emitidas.** El 550 es el ejemplo: sus OC salieron a **Poly** hasta el 16/09 y hoy la config
dice **Garcia**, o sea que ya está corregido y lo que se ve es historia. Mirando sólo las OC
emitidas, un código ya arreglado sigue apareciendo como problema para siempre.

**El número era 22, no 25.**

> **Se retira el "25 pares" del barrido anterior: estaba CONTAMINADO.** Cruzaba por **número de
> código** y **Basconia compra ACERO EN KILOS** (rubro `Flejes`, unidad `Kg`), con códigos que
> chocan con los de artículo terminado: su `0635` es *"Arandela Gde/Chica Afila (77 x 1,25)"*, no
> el artículo 635. Basconia tiene **una sola tanda, del 13/07, 10 líneas, 7.650 Kg**, y **cero
> entregas** en `Entregas Tallerista Virgilio`: **no entra en esto por ningún lado**, ni tiene
> nada que ver con 544/560/800.

El barrido que vale filtra **`rubro = 'Art Term'` y `unidad = 'Cajas'`**, y deja afuera los alias
que `gv_prov_match` ya resuelve (`Martin C` = Martin, `Carlos E` = Carlos, `Pettofrezza` = Rafael)
y los tres fabricantes de `GV_OC_Fabrica_Para`. Al 22/09: **22 pares · 19 códigos · 4.654 cajas de
OC sin imputar**. Los que pesan:

| código | OC a | entrega | cajas OC | qué dice la config |
|---|---|---|---:|---|
| 510 | Carlos E | Log/ Fabr | 1.250 | el de la OC |
| 550 | **Poly** | Garcia (256) · Log/ Fabr (21) | 1.007 | **Garcia — ninguno de los dos** |
| 583E | Garcia | Log/ Fabr | 599 | el de la OC |
| 505 | Garcia | **Lucho (3.221)** · Log/ Fabr (98) | 274 | el de la OC |
| 584E | Garcia | Log/ Fabr | 222 | el de la OC |
| 103 | Martin C | Log/ Fabr | 186 | el de la OC |
| 922 · 911 · 224 · 223 | Pintos | Log/ Fabr | 275 | el de la OC |
| 123 | Lucho ↔ Garcia (los dos sentidos) | Garcia / Lucho | 179 | Garcia |
| 609 | German | Rafael | 151 | el de la OC |
| 591 | Tierra Nativa | Log/ Fabr | 119 | el de la OC |
| 580 | Carlos E | Log/ Fabr | 119 | el de la OC |
| 760 | Poly | Garcia | 99 | el de la OC |
| 234 | Tierra Nativa | Log/ Fabr | 94 | **el que entrega** |
| 519 · 719 | Log/ Fabr | Lucho | 39 | el de la OC |
| 355 | German ↔ Pettofrezza | Rafael / German | 31 | Pettofrezza |

**Ninguno se tocó**, y quedaron para Luis. El barrido, para volver a correrlo, y la consulta que
arma la lista de trabajo (código · qué emitiría hoy · quién viene entregando · estado) están en
`sql/gv_oc_maximos_544_560_v2123.sql`.

> **Son dos datos distintos y los dos son ciertos:** quién **fabrica y entrega** (así se carga en
> Recepción, y está bien) y a quién se le **emite la orden** (siempre `Log/ Fabr`, que es el que
> les manda el material). **Ninguno se "corrige" con el otro** — y en particular `OC_Maximos` NO
> se toca: su `proveedor` sigue diciendo quién fabrica, que es lo que el dueño pidió conservar el
> 15/09 (*"dejalo ahí"*). Lo que faltaba es la pieza que los relaciona.

**La pieza es `GV_OC_Fabrica_Para`** (fabricante → quién recibe la OC), con las tres filas que
dictó Luis. Al 22/09 **el dato y el centinela están aplicados; las dos mitades del arreglo NO**
— son dato real y las autoriza el dueño. Están escritas, con su medición, en
`sql/gv_oc_fabrica_para_v2120.sql`:

1. **que la OC salga a nombre de quién la recibe** — un solo lugar, `gv_oc_generar_pendientes`,
   por donde escriben el generador manual **y** el automático (cron 50).
2. **que la recepción del fabricante impute contra la OC de `Log/ Fabr`** — el mecanismo **ya
   existe**: `gv_norm_prov_keys` devuelve un **array** de claves y `gv_prov_match` las compara
   todas contra todas (así está resuelto hoy `pettofrezza → rafael`, hardcodeado adentro de dos
   funciones). Se le suma esta tabla como fuente y ese alias se migra ahí.
   ⚠ **Fusiona los dos nombres a efectos de imputación.** Riesgo medido: sólo **3 códigos** tienen
   entregas de los dos por separado desde el 01/06 — 506 (Log/ Fabr 3.439 vs Blistpack 203), 659
   (42 vs 8) y 764 (49 vs 8). ⚠ Y recalcula `cantidad_recibida` y `estado`: va con backup.

### ✅ v21.23: `OC_Maximos` de 544 y 560 → Pedernera (Luis: *"si, corregí 544 y 560 a Pedernera"*)

Hasta la v21.22 convivían **las dos configuraciones para el mismo fabricante**: de los 7 códigos
que fabrica Pedernera, la config decía `Pedernera` en 5 (115, 561, 800, 801, 802) y `Log/ Fabr`
en 2 (**544 y 560**). Medido sobre las entregas desde el 01/06, Pedernera entregó 115, 544, 560 y
802 — o sea que los dos que decían `Log/ Fabr` son suyos igual.

**Esto NO cambia a quién se le emite la OC**: `OC_Maximos.proveedor` dice **quién FABRICA** (regla
del dueño del 15/09, caso Oscar: *"dejalo ahí"*) y la emisión la resuelve `gv_oc_emite_a()`.
Verificado: los 7 códigos dicen `Pedernera` en la config y los 7 siguen emitiendo a `Log/ Fabr`.

Backup `zz_backups."GV_Backup_OCMaximos_20260922"` (clave `cod`, única: 360/360).
`sql/gv_oc_maximos_544_560_v2123.sql`.

**Chequeo:** `select * from public.gv_oc_proveedor_no_recibe_oc;` — vacía = todo emitido a quién
corresponde. Al 22/09 marca **225 cajas en 12 líneas** por salir mal en la próxima corrida:
Blistpack **177** (10 códigos, casi todos bombillas, más Manga Repostera) y Pedernera **48**
(561 Pinza Larga y 801 Pinza Grande Alambre).

### ⚠⚠ LAS TRES CAPAS, y la del medio es la que usa el operario todos los días

**Luis, textual:** *"Cuando pedernera entrega, el operario de GV debe poner pedernera y anotar ahí
lo que reciben. En el celular del operario de GV debe figurar la OC de las cajas a entregar"*.

| capa | a nombre de quién | dónde |
|---|---|---|
| se **emite** la OC | `Log/ Fabr` | `gv_oc_generar_pendientes` |
| se **entrega** | el fabricante | `Entregas Tallerista Virgilio` |
| el **botón del celular** | **el fabricante** | `oc_vigentes_por_proveedor` |

**Antes (medido llamando la RPC con cada nombre): `Pedernera` devolvía CERO** — el operario tocaba
el botón del que le estaba entregando y no veía ninguna OC — mientras el **560**, que trae
Pedernera, aparecía bajo **`Log/ Fabr`**. Y sin OC a la vista se pierde el control de cantidad:
`opState.ocOk` queda en false y el margen del +20 % no se exige.

**Las tres mitades aplicadas en la v21.22**, acotadas a `GV_OC_Fabrica_Para` (Luis: *"2 no
necesariamente, tengo que ver caso x caso"* — el resto de la tabla **no** se tocó):

1. **Al emitir**: `gv_oc_emite_a()` dentro de `gv_oc_generar_pendientes`, el **único** lugar por
   donde escriben el generador manual y el cron 50.
2. **Al imputar**: `gv_oc_recompute_recibido` suma las claves de los fabricantes a `pkeys`. El
   mecanismo **ya existía** (es un array, y `gv_prov_match` compara todas contra todas: así estaba
   resuelto `pettofrezza → rafael`). Impacto medido: **6 filas, todas 544 y 560** — 776 cajas del
   544 imputadas en 5 OC anuladas y el 560 completo (57/57) pasando a **recibida**. Ninguna OC de
   otro proveedor se movió. Backup: `zz_backups."GV_Backup_OrdenesCompra_20260922"`.
3. **El botón**: `gv_oc_codigo_del_fabricante` dice qué códigos entrega cada uno, y
   `oc_vigentes_por_proveedor` se lo suma al fabricante y se lo saca al que recibe la orden.

⚠⚠ **Y el botón NO puede derivarse de `OC_Maximos.proveedor` a secas, porque ese campo está
MEZCLADO.** De los 4 códigos que Pedernera entregó desde el 01/06 (115, 544, 560, 802 · 2.355
cajas) la config dice **Pedernera en 2 y `Log/ Fabr` en los otros 2**. Derivarlo sólo de ahí mueve
**11 líneas de OC** que son config vieja y no esta regla: 515/615/635 (Basconia → Carlos E, 1.800
cajas), 222 y 910 (Maspoli → Pintos), 234, 618, 725. Por eso la vista une **config ∪ lo que viene
entregando**, y sólo para los tres fabricantes de la tabla.

⚠⚠⚠ **Y mordió la trampa de la v20.45.** `GV_OC_Fabrica_Para` nació con RLS sin policy y
`oc_vigentes_por_proveedor` es **INVOKER**: medido, **postgres veía 1 código y el operario 0**.
No da error — da menos filas, y probarlo desde el MCP no prueba nada porque el MCP entra como
`postgres`. Se le puso policy de **SELECT** (es config de proveedores: 3 filas con nombres); la
escritura sigue revocada. **Toda RPC nueva que el celular llame se prueba con
`set local role anon`, no desde el MCP.**

**La prueba que vale, corrida como `anon`** (OC del 561 emitida, transacción abortada):

```
boton PEDERNERA: 561 (pend 41)          <- la OC donde el operario la necesita
boton LOG/ FABR: 255                    <- sigue con lo suyo, sin el 561
Garcia (control): 113, 323, 439E, 839   <- sin cambios
```

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien ·
`select * from public.gv_oc_codigo_del_fabricante order by 2,3;`
`sql/gv_oc_fabrica_para_v2122.sql`.

### ⚠ Lo que NO va: la excepción de la doble OC (v21.14, aplicada y revertida el mismo día)

Una lectura anterior del pedido —*"deberían generar OCs por el total (100%) para fab y para
carlos"*— se implementó como `OCG_DOBLE_100`: dos OC por código, una a `Log/ Fabr` y otra a
`Carlos E`. **El dato la desmintió**: en toda la historia de `Ordenes_Compra` esos códigos tienen
**cero OC a `Carlos E`** y cero a Pedernera. El único rastro de un Carlos son **3 filas de
recepción de mayo-junio a nombre de `AGUIRRE CARLOS RODOLFO`** (260 cajas de 544), muertas desde
el **04/06**, justo antes de que empezara Pedernera el 10/06. `Carlos E` y `Carlos` son entidades
distintas de `Pedernera` en `Talleristas_Contacto` — no es un alias.

**Se revirtió entero** (la constante, el armado de subs, la marca `dupProv`, el `Math.max` de la
vista y el texto de la celda Tallerista). Si vuelve a aparecer la idea de una lista hardcodeada de
códigos con doble OC, **es la señal de que falta el alias de entrega**, que es otra cosa.

