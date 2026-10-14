# Reglas Insumos — Insumos: recibir / entregar, origen, marca, remito, alta de códigos, espejo a GP2

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠⚠ REGLA (Luis, 2026-10-14, v30.86; la base dice v30.81, llave): ENTREGAR = Cervantes / Otros · cajas de GP2 · todo insumo que entra va a TRÁNSITO

**Luis:** *"entregar insumos … tienen que salir dos opciones: Cervantes y Otros. Si aprietan Otros que tengan que
especificar a quiénes"* · *"la lista de recibir/entregar cajas les muestre todas"* las de GP2 · *"Todo insumo que
ingresa a partir de ahora a Virgilio va a ir a un lugar que se va a llamar transito … No quiero que esto se cree
solo en el front"*.

| qué | cómo |
|---|---|
| 📤 Entregar → **Cervantes** | destino fijo «Cervantes», directo al remito que sale (obligatorio, v30.12) |
| 📤 Entregar → **Otros** | *¿A quién se lo entregás? (obligatorio)* en texto; arriba, los **inyectores habilitados** como botones. Retira «Envío a inyectores / Envío a otros» (v21.74). **Las bolsas sólo salen a un inyector** (D9 sigue): elegir el botón del inyector es lo que las habilita |
| cajas | RI y EI muestran las cajas de **GP2 Sector Caja** (`gv_gp2_componentes_ri`, categoría `cajas`). Una que Virgilio no tiene se da de alta al tocarla (`gv_insumo_desde_gp2`) |
| lugar | `GV_Lugar` tipo **`transito`**: `AGUARDAR` (A guardar) y `TRANSITO` (Tránsito). `gv_insumo_sector` los reconoce como posición válida |
| recepción | el front graba `ubicacion='TRANSITO'`; el trigger **`aa_gv_insumo_recepcion_transito`** pone TRANSITO a toda `recepcion_insumo` que llegue sin ubicación (los importados de `gv_imp_recibir` van a su rack y no se tocan) |
| saldo de Tránsito | **v30.87 (Luis: *"TODO INSUMO QUE INGRESA, INGRESA A TRANSITO. quería que dejaras de buscar el lugar donde estaba el insumo y cargarle más ahí"*)**: Tránsito es un **saldo** = `sum(delta)` de los movimientos de insumos con `ubicacion='TRANSITO'`. Lo recibido **no** se suma al lugar que ya tenía el insumo. Se retira el `zz_gv_insumo_transito_ubicar` de la v30.81 (anotaba TRANSITO sólo al que no tenía lugar) |
| salir de Tránsito | **📍 Ubicar** en la pestaña (supervisor): **`gv_transito_ubicar(cod, unidad, cantidad, posición)`** escribe dos movimientos tipo **`transito_ubicar`** (−TRANSITO / +posición; el total no cambia) y suma la cantidad a esa posición en `Insumos_Ubicaciones`. No deja ubicar más de lo que hay en tránsito ni a TRANSITO / AGUARDAR |
| Mapa | pestaña **🚚 Tránsito** (vista `gv_transito_celda`): A guardar = depósito `a_guardar` en cajas; Tránsito = el saldo de arriba, por código y unidad |

- **Cajas: 17 en GP2 Sector Caja** (v30.87, Luis: *"dalas de alta en la parte de virgilio de GP2 … que nunca les falte
  ningún código para recibir/enviar (tengan o no stock)"*). A las 11 de siempre se sumaron **Nº 5, 8, 14, 27, 28 y «P»**,
  las que `GP2.uni_x_articulo_x_caja` usaba sin componente: componente en sector 11 con código **provisorio `CJ<n>`**
  (no tienen lugar en Cervantes), inventario en 0 en *Sector Caja* (11) y *Sector Caja en Virgilio* (77), el insumo
  `Caja Nº n` / `Caja P` en Virgilio y su fila en `insumo_equivalencia`. `sql/gv_cajas_gp2_alta_v3087.sql`.
- **D2 (Luis): no** — los 19 insumos con stock y sin lugar no se pasan a TRANSITO. Forward-facing.
- `sql/gv_transito_v3081.sql` + `sql/gv_transito_saldo_v3087.sql` (centinelas `gv_insumo_recepcion_transito`, `gv_insumo_sector`, `gv_transito_ubicar`) ·
  `tests/ins-envio-tipo.cjs` · `tests/ins-transito-cajas.cjs`.

## ⚠⚠ REGLA (Luis, 2026-10-14, v30.37): un insumo en 0 LIBERA su rack — la posición NO queda guardada

**Luis:** *"si un rack se queda en 0 stock que figure libre"* y, sobre dejar la posición guardada para cuando vuelva
el stock: *"eso está mal"*. Un rack es **volátil**: se vacía y después entra otro producto (LK, CH) o un insumo.

- Trigger `zz_gv_insumo_liberar_rack` → `gv_insumo_liberar_rack_sin_stock(cod)`: sin saldo > 0 en ninguna unidad,
  se borran las posiciones de **rack** del insumo (las celdas `IN-` de SC/SP no). Queda en `Insumos_Historial`.
- **Rack partido** (v30.38, Luis: *"W04-1 pasa a ser W04 y todo sigue"*): cuando una parte se vacía y queda una sola
  ocupada, el rack vuelve a ser uno (`gv_rack_unir_si_queda_una`, trigger `zz_gv_rack_unir`). `sql/gv_rack_unir_v3038.sql`.
- ⚠ Pendiente sin hacer (Luis: *"de momento no"*): la **empresa del rack** (`GV_Lugar.empresa`) se «contagia» a lo
  que entra después (el Mapa muestra `coalesce(lugar, movimiento)` y `gv_imp_recibir` decide racks_ch / insumo por
  ella). No limpiarla sin que lo pida. `sql/gv_insumo_liberar_rack_v3037.sql`.

## ⚠ REGLA (Luis, 2026-10-14, v30.81): un LUGAR TEMPORAL se saca solo cuando su insumo sale

**Luis:** *"que haya un trigger para que se borre automatico cuando salga"* (IN-H0: 1 cajón de I6 que se entrega).

- `GV_Lugar.gv_temporal = true` marca el lugar. Trigger `zz_gv_lugar_temporal` (AFTER INSERT en `Movimientos_Stock`,
  deposito insumos) → `gv_lugar_temporal_liberar(cod)`: si el insumo queda sin saldo > 0, se saca su posición en
  los lugares temporales y, si el lugar queda vacío (sin posiciones ni `GV_Lugar_Item`), el `GV_Lugar` también.
  Queda en `Insumos_Historial`. Los lugares NO temporales no se tocan.
- Probado en transacción abortada (−1 cajón I6 → IN-H0 desaparece). Centinela `gv_temporal`. `sql/gv_lugar_temporal_v3081.sql`.
- ⚠ Connector: un `execute_sql` con la palabra «borra» (o notas largas en un UPDATE) se colgó 60 s sin llegar a la
  base, varias veces el 14/10. Con el texto corto entra.

## ⚠⚠ REGLA (Luis, 2026-10-14, v30.30): HAY TRES ESPIRALES — `1000900`, `H201Part` y `007` NO se mezclan

**Luis, textual:** *"hay varias espirales. las que estan en y04 ahora son las 1000900. en AD4 hay unas que se llaman
H201part ... que no se mezclen"* · *"si ayer se unifico algo que quede marcadamente separado ahora"*.

| insumo | qué es | rack | vínculo GP2 | cuenta para importación |
|---|---|---|---|---|
| `1000900` | Espiral Chino | Y04 | D1 | sí, como 1000900 |
| `H201Part` | Espiral Chino TN | AD04 | **ninguno** | **no** (se sacó el map al 1000900) |
| `007` | Espiral Chef | Z02 | **ninguno** | **no** (Luis 14/10: *"son 3 espirales diferentes"*) |

- El 13/10 se cargaron **156 cajas de Y04 como H201Part**: eran del 1000900. El 14/10 quedó H201Part 24.000 u
  (AD04) y 1000900 78.000 u (Y04). **No volver a mapear H201Part a 1000900 ni a D1** porque «parezcan» lo mismo.
- El **`546P` pasó a llamarse `1546903`** (bastidor corta queso, X13). La equivalencia con GP2 quedó en UNA fila.
- **v30.31**: `Mgo Pelador Ergonomico` pasó a llamarse **`PEP1`** (mango pelador negro calado sin grabar, N01 → GP2 PEP1).
  El **440E de X21/X23 es PRODUCTO**, no insumo: salió de insumos y entró a racks con su posición.
- Conteo completo, verificación y rollback: `sql/gv_conteo_insumos_racks_v3030.sql`.

## ⚠ REGLA (Thomas, 2026-09-30, v24.69): un insumo con MC SALE siempre en MC — el stock queda en unidades

*"Lo mínimo que se le manda es 1 MC… no bajan uni sueltas. Siempre por MC."* En Entrega de insumos (a Cervantes o bajado de racks), un insumo con MC en `Insumos_Factores` abre fijo en MC (`_insSaleMC`). El movimiento se guarda en la unidad BASE y la descripción dice lo cargado (`· cargado 3 MC × 4000`). Lo sostiene también el trigger **`gv_insumo_unidad_base`** (BEFORE INSERT, deposito `insumos`), que convierte cualquier carga en MC que llegue sin convertir. Los movimientos viejos en MC no se tocaron: la pantalla de insumos ya los suma con el factor. `sql/gv_insumo_unidad_base_v2469.sql`, `tests/ins-sale-mc.cjs`.

## ⚠ REGLA (Luis, 2026-10-09, v29.22): INSUMOS del operario — RECIBIR arranca por la CATEGORÍA; a un INYECTOR sólo van las BOLSAS

- **📥 Recibir insumos**: lo primero es **«¿Qué recibís?»** con las categorías de `Insumos_Categorias` **menos importados**
  (`INS_RI_SIN`, `insRecibirCat`). Después siguen la ubicación y la documentación de siempre; las OC de bolsas de GP2 sólo
  aparecen si la categoría es plásticos. El modal abre en esa categoría y en RI **no hay importados** (ni en «+ Agregar insumo»).
- **📤 Envío a inyectores**: elegido el inyector, el modal muestra **sólo las bolsas plásticas** (`_insEsBolsaIny`: categoría
  plástico, código real, con ubicación en el Mapa, sin TMP-), sin «‹ Atrás» ni buscador (`_ins.soloBolsas`). Al 09/10 son 9
  (ABS, AI, EBA, NY c/Carga 25%, NY Recup, NY Virgen, PE Polie, PP 2630, PS PE). Una bolsa nueva aparece cuando se le da ubicación.
- `tests/ins-ri-cat-bolsas.cjs`.

## ⚠⚠ REGLA (Luis, 2026-10-13, v29.89): el ORIGEN de una recepción de insumos es una LISTA CERRADA por categoría — y hay UN SOLO «Enviar»

(el `.sql`, los centinelas 416-418 y los comentarios del código dicen **v29.82**: es la versión con la que se aplicaron, la llave — no cambiarla.)

**Luis:** *"quiero que el menu sea reducido dependiendo de que es lo que estan recibiendo"* · *"tienen que
apretar «enviar» dos veces … ¿hace falta que sea asi?"*.

> ## **No se escribe de dónde vino: se ELIGE de los que pueden traer eso.** Y la lista **NO vive en el front**:
> sale de **`gv_insumo_origenes(categoria)`**, que la arma con GP2 menos **`GV_Insumo_Origen_Excluido`**.

| categoría | de dónde salen los botones | al 13/10 |
|---|---|---|
| 🧪 **Bolsas plásticas** | `proveedor_insumo` rubro *Sector Bolsas Plásticas* **que entrega en Virgilio** (`entrega_en is null`) | Indarnyl · Beta Plásticos · Santa Rosa Plásticos |
| 📦 **Cajas** | `proveedor_insumo` rubro *Sector Caja* | Corrugadora del Plata · Recicor |
| 🧩 **Partes plásticas** | los **inyectores** (`ubicacion` tipo `inyector`) **+ Cervantes** | Cervantes · Kollplast · Pat Bet Plast · Pettofrezza Rafael |
| 🧵 **Flejes** | `componente.proveedor` del sector Fleje **+ Cervantes** | Cervantes + 8 (Altrak, Aperam, Basconia, Brawin, Hermac, JL Metales, Resortes Charcas, Szapiro) |
| **SC y SP** | **no se pregunta**: siempre **Cervantes**, siempre **remito** | — |

- **SC y SP se saltean las DOS preguntas** (Luis: *"no entregan con factura nunca, solo remito, siempre es
  Cervantes, que ni pregunte"*): el origen queda fijo y la documentación **arranca en el N° de remito**, sin el
  paso Remito / Factura / los dos. El «‹ Atrás» de ahí vuelve a las **categorías**, no a un paso que no existe.
- **Flejes**: con **Cervantes** se ven **todos**; con un **proveedor**, sólo los que GP2 le tiene asignados
  (`gv_insumo_fleje_proveedor`, por el código de Virgilio o por el componente de GP2 que la lista ya muestra).
  Y **mientras quede alguno sin vincular**, el botón **«Otros (N)»** cambia a la lista de **los que todavía
  no están asignados a ningún proveedor** (Luis, v29.87: *"que aparezca un botón que diga «otros» y que
  permita seleccionar de los que todavía no están vinculados"*). Son **dos listas, no una**: nunca se
  mezclan, y se vuelve con «‹ Volver a los de \<proveedor\>».
- **Las bolsas sólo se ENVÍAN a los inyectores habilitados** (ámbito `inyector`): el mismo filtro se le aplica a
  `material_virgilio_bundle` en «📤 Envío a inyectores».

### ⚠ Lo que GP2 tiene y acá NO va: queda ANOTADO, no se adivina

`GV_Insumo_Origen_Excluido` (ámbito, nombre, motivo). Al 13/10, **dos filas, las dos con la diferencia contra
GP2 escrita** — y las dos **para revisar allá**, porque o GP2 está mal o la lista de Luis está incompleta:

| ámbito | nombre | por qué |
|---|---|---|
| `plastico` | **Simco** | GP2 lo tiene activo en *Sector Bolsas Plásticas* (sin cód. de proveedor) y Luis nombró 3 |
| `partes_plasticas` · `inyector` | **JL Matriceria** | GP2 lo tiene como inyector y Luis nombró 3 |

⚠ **Arcolor y Julio Garcia e Hijos NO hacen falta excluirlos**: GP2 dice que entregan en **Cervantes 2868**, así
que el filtro `entrega_en is null` ya los deja afuera de una recepción **de Virgilio**. Si algún día entregan acá,
se les borra ese campo en GP2 y aparecen solos.

**Los tres los confirmó Luis el 13/10** y no se vuelven a preguntar: *"pone una excepcion en los inyectores para
que solo aparezcan los 3 que te dije, bolsas plasticas son los que ya estan configurados en GV, lo de arcolor y
julio tal cual, solo cervantes no virgilio"*.

### ⚠ Y lo que quedaba SÓLO EN EL FRONT pasó a una tabla (Luis, v29.87)

**Luis:** *"crea tabla si sólo está en el front el dato"*. Tres datos del negocio que vivían escritos en
`index.html`:

| dato | ahora vive en | lo lee |
|---|---|---|
| el apodo del origen («Manolo» = Pat Bet Plast) | **`GV_Insumo_Origen_Apodo`** | `gv_insumo_apodos()` |
| cuántas cajas trae un paquete (25) | **`GV_Insumo_Config`** `caja_x_paquete` | `gv_insumo_config()` |
| las marcas que se eligen al recibir (Loeke · Chef · Mixto; en cajas sin Mixto) | **`GV_Insumo_Config`** `marcas` / `marcas_cajas` | `gv_insumo_config()` |

Los hidrata **`insFetchConfig`** desde `insLoadMeta`; `INS_CAJA_X_PAQ`, `INS_MARCAS`, `INS_CAJA_MARCAS` e
`INS_INY_APODO` pasaron de `const` a `let` y **quedan de FALLBACK**: si la base no contesta, el operario carga
igual que antes. **Al agregar un dato del módulo de insumos, va a la tabla y se hidrata acá: no se escribe un
número más en `index.html`.**

⚠ `gv_insumo_origenes` **no** devuelve el apodo: agregarle una columna pide `DROP` + `CREATE` y el connector se
cuelga con la palabra de borrado (regla del 07/10). Por eso va en su propia RPC, no en la que ya existía.

### ⚠⚠ La lista cerrada NO puede dejar al operario sin poder cargar

- **«✏ Otro origen»** siempre está: el camión que nadie previó se escribe a mano, como antes.
- **Si la base no contesta, queda el texto libre de siempre** — *"no pude leer"* no es *"no hay de dónde recibir"*.
- En flejes, los que **GP2 no le asignó a nadie** (al 13/10: **29 de los 48** de Virgilio) **no se esconden**:
  van contados atrás de **«➕ Ver los N flejes sin proveedor asignado en GP2»**. Y **buscando se ve TODO**: si el
  operario escribe el código, lo tiene que encontrar (regla v20.95).
  ⚠ Los 19 vinculados cubren **4** de los 8 proveedores (Basconia 12, Aperam 6, Altrak 1, Hermac 1); los otros 4
  (Brawin, JL Metales, Szapiro, Resortes Charcas) se ven igual, porque la lista de recepción ya trae **sus
  componentes de GP2** (v29.35) y el alta en Virgilio la hace `gv_insumo_desde_gp2` al elegirlos.

### UN SOLO «Enviar» (y no, no hacía falta el segundo)

El primer «Enviar» de la botonera ya arranca el tiempo (la tarea **Insumos**, `MDI` de `MOD_TAREA`, v28.93). El
segundo sólo servía para que `send()` abriera el toggle RI/EI. Hoy, terminada la documentación, lo abre
**`_insArrancarToggle(mode)`**: el mismo `send()` de siempre (evento, historial, cola offline) con
`{sinAviso:true}` — se saca el cartel *"Reporte enviado correctamente"*, que ahí no aporta nada: lo que confirma
que arrancó es la lista en pantalla. **El aviso de FALLA se mantiene.** Vale para Recibir **y** Entregar.

⚠ **Si el toggle RI/EI quedó ABIERTO** (la app se reinició con la recepción a medias), `_insArrancarToggle`
**RETOMA** —con el borrador si hay— en vez de llamar a `send()`, que lo **cerraría**. Perder la sesión del
operario por volver a entrar sería peor que el segundo Enviar que esto saca.

**Chequeo:** `select * from public.gv_reglas_perdidas;` (vacía) · `select nombre, fuente from
public.gv_insumo_origenes('plastico');` · `select * from public.gv_insumo_config();` ·
`node tests/ins-ri-origen-menu.cjs` (verificado que falla contra la v29.85) · `node tests/ins-envio-tipo.cjs`
(el que quedó viejo: exigía JL Matriceria entre los inyectores, y de paso le pegaba a la base de verdad).
`sql/gv_insumo_origenes_v2982.sql`, centinelas 416-418.

## ⚠ REGLA (Luis, 2026-10-13, v30.00): el SEPARADOR DECIMAL no decide una búsqueda — y un TMP no se da de alta sobre un código que ya existe

**Luis, con los 144 Kg del `TMP-0037`:** *"¿cómo es que se aceptó sin lugar? ¿se permite eso? ¿cómo es que se
guardó sin código?"*.

> ## **`stkMatchBusq` normaliza el decimal de los DOS lados: buscar `13.6` encuentra `13,6`.**
> En los flejes la MEDIDA es el nombre, y **39 de 48 tienen decimal** (27 con coma, 12 con punto).

Lo que costó no normalizarlo: el 13/10 09:09 el legajo 104 recibió 144 Kg de un fleje `13.6 x 0.8`, no lo encontró
en la lista — se llama **`N°19`**, *«13,6 x 0,8 · Fleje N° 19»*, con **coma** — y lo dio de alta como insumo nuevo.
El servidor lo numeró `TMP-0037` y los 144 Kg quedaron en un código que no existe para nadie. El arreglo sólo
**agrega** matches (`(\d),(\d)` → `$1.$2`), no saca ninguno, y vale para TODO buscador que use esa función.

**Tres cosas del circuito que la pregunta destapó, y conviene tener a mano:**

1. **La recepción de un insumo NUNCA pregunta el lugar.** Pide categoría → origen → documentación (remito /
   factura) → el insumo de la lista → cantidad + unidad + **marca** (v29.57). El lugar de un insumo vive en el
   **Mapa** y lo pone un supervisor; la red es la alarma **`gv_mapa_stock_sin_lugar`** (*"hay N en stock y el insumo
   no está en ninguna posición del Mapa"*). ⚠ **Al 13/10 esa alarma tiene 19 insumos**, 7 de ellos cajas: existe,
   pero nadie la mira.
2. **«Aceptar» es del ADMIN, no de la recepción** (Stock y Compras → Insumos): es el paso que le pone el código real,
   el nombre y la ubicación inicial. `TMP-0037` **nunca se aceptó**: quedó pendiente desde las 09:09. Y no se podía
   — `insumo_identificar` **frena** un TMP contra un código en uso (*"una sugerencia del operario no se puede
   fusionar contra un insumo en uso"*), que es correcto: fusionar dos stocks lo decide una persona, no un botón.
3. **El alta se cerró a las 09:35 y Luis la REABRIÓ el mismo día** (v30.05, abajo): la v29.56 había tapado
   `insNuevoOpen` con un `alert`, y `TMP-0037` fue el último que entró por ahí. Hoy el botón está de vuelta **con
   el aviso de parecidos** adelante. **Y lo que sigue abierto no es el código: es el LUGAR** — un código del
   catálogo de GP2 (`gv_insumo_desde_gp2`) también se recibe sin posición, y queda en esa alarma.

Los 144 Kg se fusionaron en `N°19` con el mecanismo de la casa (se renombra el `cod_art` del movimiento, el TMP
sale del catálogo y queda en `Insumos_Historial`), **sin tocar la ubicación** (Luis: *"hay que ver dónde está"*).
⚠ Ojo con el efecto: `N°19` ya tenía R06AT, así que **el Mapa ahora dice R06AT y la alarma se apagó** — si no
están ahí, lo corrige el conteo, no un aviso. Detalle, verificación y rollback: `docs/SUPABASE-GESTION-VIRGILIO.md`
§3.v3000. Lo sostiene `tests/stk-busca-decimal.cjs`.

## ⚠⚠ REGLA (Luis, 2026-10-13, v30.06): el REMITO de una recepción NO SE PIERDE — columna `gv_doc`

(el comentario de la columna, el `.sql` y los textos del código dicen **v30.06**: es la versión con la que se
aplicó. Salió publicada con la v30.09 porque otras sesiones se llevaron los números en el medio.)

**Luis, textual:** *"que no se pierda dios mio, como que se pierde? como columna es lo más elegante, no?"*.

> **El papel va en el MOVIMIENTO: `Movimientos_Stock.gv_doc`** (jsonb)
> `{tipo, remito, fecha_remito, factura, fecha_factura, proveedor}` — **las mismas claves en TODAS las filas de
> esa recepción**, porque es UN papel. Se lee por `gv_insumo_recepcion_marca` (`remito`, `factura`, `doc_tipo`).

**Lo que estaba roto, medido:** la recepción pedía el remito en el paso de documentación y `_insDocState` —el
estado de ese formulario— lo borraba `insDocCancel` al cerrar el modal, dos líneas antes de abrir la lista. El
movimiento nunca lo llevó. **Y había un segundo agujero peor**: `insEnviar` leía el remito de ese mismo objeto
para pasárselo a GP2 (`_insGp2Enviar`), así que **las OC de bolsas se recibían con el remito vacío**. Los dos se
arreglan con lo mismo: `insDocOk` copia el papel a **`window._insDoc`**, que vive hasta que la recepción se
manda o se anula.

| pieza | qué hace |
|---|---|
| `insDocOk` | guarda el papel en `window._insDoc` (sólo lo que tiene algo) |
| `insConfirmar` | arma `doc` y lo pone en **cada** row (`row.gv_doc`); se lo pasa a GP2; al terminar limpia `_insDoc` |
| `insAnular` | limpia `_insDoc`: el papel de una recepción anulada no se arrastra a la siguiente |
| columna | `alter table … add column gv_doc jsonb` — **nullable, prefijo `gv_`, sin default y sin backfill**, como manda la regla de las tablas compartidas con Producción Virgilio. Índice de expresión sobre `gv_doc->>'remito'` |

⚠ **Es jsonb y no cuatro columnas** a propósito: son 5 datos del mismo papel sobre una tabla de 80 mil filas, y
el que se busca (el número de remito) tiene su índice. Al agregar un dato del papel se agrega una clave, no una
columna.

⚠ **Forward-facing**: lo recibido antes de hoy queda con `gv_doc` nulo — no se inventa el remito de una
recepción vieja. La lectura devuelve `remito` nulo ahí.

⚠ `create or replace view` **borra las `reloptions`**: el `security_invoker = true` de
`gv_insumo_recepcion_marca` se repone en el mismo bloque (verificado como `anon`).

### ⚠ v30.10 (Luis, 13/10, D1 «sí»): el papel va TAMBIÉN en la ENTREGA de insumos y en la RECEPCIÓN de mercadería

| dónde | qué lleva `gv_doc` | obligatorio |
|---|---|---|
| **RI** recepción de insumos | remito / factura y sus fechas (el papel del proveedor) | **sí** (como siempre) |
| **EI** entrega de insumos | el **remito NUESTRO**, el que sale con la mercadería | **sí** (v30.12, Luis: *"obligatorio para mandar insumos que salgan con remito"*) — se retira el «Sin remito — seguir» de la v30.10 |
| **RT** recepción de mercadería (`recepcion.js`) | remito, factura y **las dos fechas**, más el proveedor | ya se pedían; antes sólo el número llegaba al `ref` |

- En **EI** el modal del papel aparece después del destino (un paso más, pedido por Luis) y su «‹ Atrás»
  vuelve a la lista de destinos correcta (`window._insEiSub`: inyectores u otros). **Sin número no sale**: el
  campo se pinta en rojo y no hay ninguna puerta que lo saltee (el 2.º argumento de `insDocOk` ya no existe).
- En **RT** el movimiento ya llevaba `ref: opState.remito` —el número, sin decir si era remito o factura— y
  las **fechas y el otro número se perdían**: vivían en `Entregas Prov AT` / el recibo, no en el libro de
  stock. `ref` se conserva igual (lo leen el dedup y la imputación de OC) y el detalle va en `gv_doc`.
- **D5 (Luis): «sí, para adelante»** — ningún backfill. Lo recibido o entregado antes de hoy queda con
  `gv_doc` nulo, y no se inventa el papel de un movimiento viejo.
- Candados: `node tests/ins-remito-guardado.cjs` (bloque (c): EI pide el papel, **sin número frena y marca el
  campo**, no queda puerta de escape, y con número lo guarda) · `node tests/rcp-remito-en-movimiento.cjs` (candado estático sobre
  `recepcion.js`: la fila lleva `gv_doc` armado desde `opState`, sin número escrito a mano, y no se perdió el
  `ref`).

**Chequeo:** `node tests/ins-remito-guardado.cjs` (corre la recepción de verdad y mide el POST: el papel en las
dos filas, con su fecha y su tipo; sin papel no escribe `gv_doc`; anular no lo deja colgado) ·
`select cod_art, origen, marca, remito from public.gv_insumo_recepcion_marca order by id desc limit 5;`
`sql/gv_mov_stock_gv_doc_v3006.sql`, §3.v3006.

## ⚠⚠ REGLA (Luis, 2026-10-13, v30.05): el operario SÍ PUEDE crear un código nuevo al RECIBIR — con el aviso de parecidos

**Luis, textual:** *"hay que darles la opción de poder crear códigos nuevos cuando reciben si no están en la lista
(antes tenían un botón abajo que les permitía hacer eso no, ponéselos)"*.

> **Se RETIRA la v29.56** (*"en Recepción de insumos el operario ya NO da de alta un código nuevo"*, de esta
> misma mañana). El **«+ Agregar insumo»** vuelve a estar en la grilla de categorías y dentro de cada categoría.

| dónde | alta |
|---|---|
| **RI (recibir)**, categoría común | **SÍ** — el botón en los dos lugares |
| **RI**, categoría **CERRADA** (bolsas, cajas) | **NO**: su catálogo es conocido y completo (Thomas, v29.25/30). El botón no se dibuja y `insNuevoOpen` se planta si lo llaman a mano |
| **EI (entregar)** | **NO**, como siempre: dar de alta algo al sacarlo sería sacar stock de algo que nunca entró |

**Y el alta AVISA antes de crear.** Es la lección del `TMP-0037` (arriba): el operario escribió `13.6 x 0.8`
teniendo el fleje en la lista como `N°19` (*13,6 x 0,8*) y se creó un código que no existía para nadie. Ahora
`insNuevoOk` busca los parecidos **por los NÚMEROS del detalle** — sin importar coma ni punto ni el orden — y los
muestra: *«⚠ Puede que ya exista: · N°19 — 13,6 x 0,8 · Fleje N° 19»*. Cancelando **no crea nada y deja la lista
filtrada por ese número**; «crear igual» crea. **No bloquea**: lo que no puede es crearse en silencio teniendo el
gemelo a la vista.

⚠ **La identidad la sigue poniendo el servidor** (`nuevo_insumo_tmp` → `TMP-00NN`) y el código de verdad se lo
pone un admin en Stock y Compras → Insumos. **Un TMP no se fusiona desde el front contra un código en uso**
(`insumo_identificar` lo frena, y está bien): si de verdad son el mismo, lo resuelve una persona.

⚠⚠ **El REMITO que la recepción pide NO se guarda en Virgilio.** `_insDocState` (n° de remito / factura y sus
fechas) se usa para GP2 — bolsas contra su OC — y después se tira (`insDocCancel` lo pone en `null`): el
movimiento no lo lleva en ninguna columna. Lo cargado a mano desde una sesión lo pone en `ref` (`Remito 38880`)
y en la descripción, pero **lo que carga el operario desde el celular queda sin el remito**. Cerrarlo es un
cambio aparte (una columna, o el `ref`), y **no está hecho**.

**Chequeo:** `node tests/ins-alta-duplicado.cjs` (corre el alta de verdad: avisa con el candidato, cancelar no
crea y deja el filtro, «crear igual» crea, y una medida que de verdad no está entra derecho) ·
`node tests/ins-categorias.cjs` · `node tests/ins-ri-cat-bolsas.cjs` · `node tests/ins-admin.cjs`.

## ⚠ REGLA (Luis, 2026-10-13, v29.57): al RECIBIR un insumo se marca DE QUÉ EMPRESA viene — y no parte el stock

(los comentarios del código, el `.sql` y la vista dicen **v29.56**: otra sesión se llevó ese número mientras se escribía esto.)

**Luis:** *"se pide que se marque la empresa (LK o CH) cuando un operario recibe insumos. esto no debería afectar
nada (mismo insumo físicamente, mismo lugar físico) pero debería quedar registro"*. Antes se pedía **sólo en cajas**
(v29.31, Thomas D26).

- El pop-up de cantidad de **Recibir insumos** pide la **Marca** en TODA categoría, obligatoria (el botón «Listo»
  queda deshabilitado y `insEnviar` frena). **Cajas**: Loeke / Chef. **El resto**: Loeke / Chef / **Mixto** (las dos).
  Al **entregar** (EI) no se pide. `INS_MARCAS`, `_insMarcasDe`, `_insMarcaHtml`.
- **La marca NO parte el stock**: el movimiento sigue siendo el mismo insumo en el mismo lugar y con
  **`empresa = 'Mixto'`** (lo fuerza `gv_insumo_unidad_base`, regla v24.89 — medido: 446 de 446 movimientos). Queda
  escrita en la **descripción** (`· marca Loeke`), como ya hacía cajas.
- Consultable en **`gv_insumo_recepcion_marca`** (una fila por recepción, con `marca`, categoría, unidad y origen):
  si el dato sólo vive en un string de la descripción no se puede agrupar.
- ⚠ **Al agregar un dato que acompaña un movimiento de insumos sin cambiar el saldo, va en la descripción, nunca en
  `empresa`**: esa columna la pisa el trigger y la leen el espejo a GP2 y los lectores de stock.
- `sql/gv_insumo_marca_empresa_v2956.sql`, `tests/ins-marca-empresa.cjs` (verificado que falla contra la v29.55).

### ⚠ Y los saldos de insumos en unidad VIEJA (MC) son de antes de la v24.69

`gv_insumo_unidad_base` convierte a la unidad base, pero es **BEFORE INSERT solamente**: las líneas cargadas en MC
antes de esa versión quedaron así, y
`vista_saldos_insumos_x_unidad` **agrupa por unidad** → esos códigos muestran dos saldos (Uni positivo + MC negativo).
**No es un bug vivo**: `gv_importados_stock_insumos` los convierte con el factor y da el número correcto (505C
**98.000** · 439E **312** · 590E **0**, `sin_factor` en 0). Los saldos negativos de insumos son exactamente esas
unidades viejas, todos de categoría `importados`: **cero negativos en las categorías del operario**. Al 13/10, tras
el conteo del 546P, son **3**: 439E −5 · 590E −4 · 505C −3, los tres en MC (eran 5 con los dos grupos del 546P).

⚠⚠ **NO se normalizan: quedan así** (Luis, 13/10, D9: *"dejalo"*). **Hoy son 10 filas en 5 códigos**, medido el
13/10 después del conteo del 546P: `H201Part` 5 (saldo 0) · **`N°7` 2 (saldo 0, que la lista vieja de «18» se
olvidaba)** · `439E` 1 (−5) · `505C` 1 (−3) · `590E` 1 (−4), la última del **25/08**. Las 10 de `546P` salieron de
acá con su conteo (arriba). Las que molestan —el código que muestra dos saldos— son **3**, las de saldo ≠ 0. El UPDATE que las reexpresaría está escrito en
`sql/gv_insumo_marca_empresa_v2956.sql` y **no se aplicó**: es cosmético (que cada código muestre un solo número) y
no cambia ninguna cuenta, así que no vale pisar esas filas de `Movimientos_Stock`. **No volver a proponerlo.** Y si
alguien lo intenta: un INSERT compensatorio NO sirve — la línea nueva con unidad `MC` la convierte el trigger y el
saldo MC sigue ahí; el único camino es el UPDATE de las filas viejas, que no dispara ese trigger.

⚠⚠ **La SALIDA de insumos NO lleva empresa, y no se le agrega** (Luis, 13/10, D10: *"no, solo el registro de la
entrada es importante"*). Medido sobre las 92 entregas (30/06 al 08/10): **92 de 92 con `empresa = 'Mixto'` y 0 con
marca**; lo único que queda es **a quién se le dio** (`ref`: Cervantes 42 · Rafael 8 · Manolo 3 · Bryan 1, más 33 sin
destino del 30/06 al 07/08, de antes de que el campo fuera obligatorio). O sea el circuito es **asimétrico a
propósito**: la entrada dice de qué empresa vino y la salida no dice para cuál se usó. **No proponer pedir la marca
al entregar ni «cerrar el círculo» por empresa.**
⚠ **El 546P se contó en el depósito el 13/10 y quedó en UNA sola unidad, `Uni`** (6.768 Uni; 0 filas en «Cajas» y «MC»). Lo que vale es eso.

## ⚠ REGLA (Thomas, 2026-10-09, v29.32, D32): el stock de insumos de VIRGILIO se COPIA EN VIVO a GP2

*"Cuando hago un relevamiento tengo que ver online en GP2 el stock de Cervantes y el de Virgilio: el máximo necesita las dos plantas."*

- El stock sigue viviendo en `Movimientos_Stock` (deposito `insumos`, D28 a). **`gv_gp2_espejo_insumos(cod, simular)`** deja en
  GP2, en el depósito «<sector> en Virgilio» (virgilio_sector con `ref_id` = sector; bolsas → 57), EXACTAMENTE el saldo de
  Virgilio pasado a la unidad de GP2 (Cajones × uni_x_cajon · Bolsas × 25 kg · Kg · Uni · Paquetes × 25). Reconcilia
  (objetivo − lo que hay) con un movimiento `ajuste` de GP2 con nota «Espejo Virgilio (…)»; si cuadra no escribe.
- Corre por el disparador `zz_gv_gp2_espejo_insumos` (cada movimiento de insumos; nunca frena la carga: el error va al log)
  y por el cron `gv-gp2-espejo-insumos` (:19 y :49). Alcance: cajas, fleje, parte_procesado, partes_crudo, plastico — los
  importados NO.
- **Qué código va con qué componente lo dice `GP2.insumo_equivalencia`** (54 cargadas el 09/10; el resto lo asigna
  Thomas en GP2 → Stock General → Virgilio, D30). Un código sin equivalencia no se copia.
- **D16 (Thomas): el celular del operario de Virgilio NO escribe en GP2.** Lo que pasa en GP2 (envío de bolsas a un inyector,
  consumo) lo carga el admin dentro de GP2. `gv_insumo_envio_inyector` queda sin grant y sin llamador.
- Lectura: `select * from public.gv_gp2_espejo_insumos(null, true);` (qué haría) · `select * from public."GV_GP2_Espejo_Log" order by id desc;`
- Rollback: `select cron.unschedule('gv-gp2-espejo-insumos');` + `alter table public."Movimientos_Stock" disable trigger zz_gv_gp2_espejo_insumos;`
- ⚠⚠ **v29.66 (Luis, 13/10): el depósito «<sector> en Virgilio» SE CREA SOLO si falta.** Sin eso la fila salía «sin depósito
  en Virgilio» y ese stock **no se reflejaba nunca, sin que nadie se enterara**: pasó el 13/10 al vincular C9 y D14
  (Resortes, Sector Bombilla, 24.552 u mudas). Hoy la función lo crea (sólo ejecutando, no al simular) y sigue con el ajuste.
  El insert va con `not exists`, **no** con `on conflict (tipo, ref_id)`: el índice es PARCIAL (`where ref_id is not null`) y
  da 42P10; y el guard hace falta porque dos componentes del mismo sector entran en el mismo loop (el 2.º chocaba con la
  ubicación que creó el 1.º). Marcadores `v29.61-ubic` / `v29.61-ubic3` (llave, no cambiarlos), centinela 398 con patrón de
  CÓDIGO (el `-- v29.61-ubic3` es comentario y `gv_reglas_perdidas` limpia los comentarios antes de buscar: con ese patrón
  el centinela daba «perdida» con la regla puesta). `sql/gv_gp2_espejo_insumos_ubic_v2966.sql`.
- ⚠ **NO se duplica nada, medido el 13/10.** La verdad es Virgilio; GP2 tiene la copia en depósitos SEPARADOS: los 5 (hoy 6)
  `virgilio_sector` **no entran en `v_nivel_stock`**, así que no inflan máximos ni OC de Cervantes, y el **único** escritor de
  esos depósitos es el espejo (0 movimientos de otra fuente). Las bolsas viven sólo en la ubicación 57 (`tipo='sector'`, la
  única que SÍ entra en `v_nivel_stock`, y está bien: el sector se mudó a Virgilio y no hay otro depósito de bolsas). Probado
  en transacción abortada: +1 cajón de G11 en Virgilio → GP2 15.380 → 16.149 **en el acto**. Y 59 de 59 filas en `ok`.
- ⚠ **590E (Pincel Silicona) NO se espeja**: es categoría `importados` en Virgilio y los importados están fuera del alcance a
  propósito (tienen su propio circuito, `Importados_Stock_Parte` / `gv_importados_stock_insumos`).
- `sql/gv_gp2_espejo_insumos_v2932.sql`.

## ⚠ REGLA (Thomas, 2026-10-09, v29.35, D43 · D44): LO VÁLIDO ES GP2 — Recibir insumos muestra el catálogo de GP2

- **Nombres**: un insumo de Virgilio vinculado a GP2 lleva el nombre de GP2 (v29.34: cajas, bolsas, C15, C6, A15, G11, G13).
  Un **fleje** se llama «<medida de GP2> · <nombre de GP2>» (`84 x 1,75 · Fleje N° 13`): la medida adelante sigue
  ordenando la lista del operario (`_insMedida`). Lo arma `gv_gp2_nombre_insumo(comp)`.
- **Recibir insumos** (`showInsumoModal` RI): además de los insumos de Virgilio aparecen TODOS los componentes de GP2 del
  rubro (`gv_gp2_componentes_ri`, anon; rubro → sector: crudo 1 · procesado 2 · fleje 5 · partes plásticas 6 · cajas 11 ·
  bolsas 14). Elegir uno que falta lo da de alta en Virgilio con el código y el nombre de GP2 y lo vincula
  (`gv_insumo_desde_gp2`, idempotente); mismo código y mismo rubro sin vincular → sólo se vincula (no se duplica); código de
  GP2 ya usado por otra cosa en Virgilio → código + sufijo de sector (`A9 CJ`). Así nadie carga como «insumo nuevo» algo
  que ya tiene nombre. La bolsa ya vinculada se ve al recibir aunque no tenga lugar en el Mapa. Sin respuesta de GP2, la
  pantalla queda como antes. Lo recibido se copia a GP2 por el espejo de la v29.32.
- El conteo de insumos del martes 13/10 corrige el stock. `sql/gv_insumos_nombre_gp2_v2934.sql`,
  `sql/gv_ri_catalogo_gp2_v2935.sql` (respaldo de nombres adentro), centinela 388, `tests/ins-ri-gp2-catalogo.cjs`.

## 🗄 RETIRADO — sólo revisar si se pregunta por algo ANTIGUO que no está arriba

> Reglas, versiones y hallazgos que **ya no valen**. Se guardan como historia, no como instrucción.
> **No leer esta sección en el trabajo normal**: sólo cuando alguien pregunta por un comportamiento viejo
> y no aparece en las reglas vigentes de arriba. Nada de acá se vuelve a aplicar sin un pedido explícito.

⚠⚠ **RETIRADA la D8 («las 45 Cajas de 546P no se tocan»): el 546P SE CONTÓ EN EL DEPÓSITO y se unificó**
(Luis, 13/10, mismo día y después de la D8: *"fui yo. está ok, se hizo el conteo en el depo"*). A las 13:59 pasó a
**una sola unidad, `Uni`** —sus grupos «Cajas» (−45) y «MC» (−60) se reexpresaron, refs `unificación: pasa 222 MC a
Uni (bruto 1:1)` y `fix_recatalog_bastidor`— más el ajuste del conteo (`CONTEO 546P X13`, −8.640): **30.528 → 6.768
Uni**. **No se perdió ningún movimiento**: las líneas se reexpresaron, no se borraron. Hoy el 546P tiene **0 filas en
«Cajas» y 0 en «MC»**. Lo que vale es esto, no la D8.
