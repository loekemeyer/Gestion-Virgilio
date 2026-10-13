# Góndolas · Racks · Sector Crudo/Procesado (SC y SP)

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠⚠ REGLA (Luis, 2026-10-13, v29.97): EN EL DEPÓSITO HAY **TRES** CLASES DE LUGAR — Góndolas · Racks · **Sector SC y SP**

**Luis, textual:** *"Vamos a entender algo. en el deposito tenes diferentes cosas: Gondolas / Racks / Sector SC
y SP. Sector SC y SP usa un nomenclador similar al de gondolas y racks y puede que la confusion surja de ahi."*

> ## **SC = Sector Crudo · SP = Sector Procesado.** Son la mesa de trabajo de **Cervantes (GP2)** dentro del
> ## depósito, NO racks de Virgilio. Su nomenclador es la **grilla de UN DÍGITO** (`A1`…`L6`), y por eso se
> ## confunde con la góndola `A01` y con el rack `AD05`.

| clase | nomenclador | qué guarda | dónde vive el saldo |
|---|---|---|---|
| **Góndola** | letra + **2 dígitos**: `A01`…`Ñ60`, `P`, `Y`, `Z` | cajas de artículo para pickear | `Movimientos_Stock` dep. `terminado` |
| **Rack** | letra(s) + **2 dígitos**, con `AD`/`AT` en los de insumo: `AD05`, `X22`, `R01AD`, `V09AT`, `AF13` | master cajas de artículo · fleje · plástico · importados | `Movimientos_Stock` dep. `racks` / `racks_ch` / `insumos` |
| **SC y SP** | letra(s) + **UN dígito**: `A1`…`L6` (52 celdas) + `MEDIO` | **piezas de Cervantes**: `partes_crudo` (SC) y `parte_procesado` (SP) | **`GP2.inventario`** (ubicación «Sector Crudo» / «Sector Procesado»), NO Virgilio |

### ⚠⚠ v30.03 (Luis, 13/10): SC y SP es SU PROPIO LUGAR — la celda se llama **`IN-A1`** y su tipo es **`scp`**

**Luis:** *"hagamos que sea su propio sector, lugar. IN-A1 por ejemplo? queda bien asi?"* · *"claro,
agrega al mapa este sector"* · *"una vez hecho fijate que vincule bien con insumos y con todo lo que
tenga que vincular bien … y una vez tengamos la base bien armada, limpiamos todo"*.

> ## **ES UN SOLO SECTOR Y NO SE PARTE: `IN-<letra><número>`, y nada más que eso.**
> **Luis, 13/10:** *"no importa SP o SC, ese sector tiene de los dos. todo ese sector es
> IN-\*Letra\*\*Numero\*, no te compliques mas que eso"*. La grilla está **INTERCALADA** —`G1`-`G4`
> tiene piezas de SC y `G5`-`G6` de SP; `L1`-`L4` SP y `L5`-`L6` SC; `H1` SP y `H2`-`H7` SC—, así
> que **un prefijo `SC-` / `SP-` habría que renombrarlo cada vez que una pieza cambia de celda**.
> SC y SP son **de qué es la PIEZA** (su categoría de Insumos), no de qué es la CELDA: el Mapa
> **no rotula la celda por sector** y el encabezado no los cuenta aparte.

### ⚠⚠ EL PADRÓN DE LA GRILLA ES EXACTO: **77 celdas, `IN-A1` … `IN-L7`** (Luis, 13/10, v30.10)

**Luis, textual:** *"esos sectores deberían ser «IN-» letras de la A a la L con la siguiente logica /
De la A a la E van del 1 al 6 (ej. IN-A1, IN-E6) / F es del 1 al 5 / G del 1 al 6 / De H a L son del 1 al 7"*
y, por el `IN-F6` que ya tenía una pieza: *"creale la IN-F6 y listo"*.

| columnas | números | celdas |
|---|---|---:|
| **A · B · C · D · E · F · G** | 1 a 6 | 42 |
| **H · I · J · K · L** | 1 a **7** | 35 |
| | | **77** |

⚠ **Se RETIRA el «F es del 1 al 5»** de la primera versión del padrón (v30.09): **F va de 1 a 6**, como
A-G. Lo decidió Luis el mismo día al ver que `IN-F6` existía con el `D14` (Resorte 520 Niq.) anotado.

Las **22 que faltaban** se dieron de alta el 13/10 (A4, C3, C4, D2, E3, E4, F3, F4, F5, I1, I2, I3, I5,
I6, I7, J5, J7, K1, K2, K3, K7, **L7**), todas vacías. Al 13/10 el padrón está **completo**: 77 celdas,
**55 con pieza y 22 libres**; el Mapa dibuja la libre como «libre», no la esconde.

⚠ **El front NO tiene el padrón escrito**: `pscpCols` saca las columnas de los datos, así que una celda
nueva aparece sola con su alta. **Agregar una celda es un `insert`, no un deploy** — y el CHECK del nombre
ya acepta hasta dos dígitos, así que `IN-L7` entra sin DDL.

`sql/gv_scp_padron_v3009.sql` (el alta, la verificación y el rollback; con F hasta 6 desde la v30.10).

| pieza | qué es |
|---|---|
| `GV_Lugar` | las **77** celdas del padrón con **`tipo = 'scp'`**, empresa `IN`, nombre `IN-A1`…`IN-L7`. Se dieron de alta **IN-K4, IN-K5 e IN-K6**, que tenían piezas cargadas y no existían, y las 22 del padrón que faltaban |
| **`gv_scp_sector(txt)`** | el resolvedor de la grilla: `IN-A1`, `IN A1`, `in-a1` y el **`A1` pelado** (es lo que se tipea hoy) |
| **`gv_insumo_sector(txt)`** | el **cuello ÚNICO de una posición de INSUMO** = `coalesce(gv_rack_sector, gv_scp_sector)`: rack de insumo (`R01AD`, `AF13`, `X20`) **o** celda de SC/SP. Lo usan `gv_insumo_ubicacion` y las **dos** RPC que escriben una posición (`gv_insumo_ubicaciones_guardar`, `gv_insumo_posicion_guardar`) |
| **`gv_scp_celda`** | la vista de la solapa nueva: una fila por celda, con la pieza, su sector (SC/SP) y su saldo |
| Mapa | tercer modo **📐 SC y SP** (`pmapModo('scp')`), una solapa por columna; tocar una celda abre su editor y escribe por **la misma RPC** que las posiciones de racks |
| `Insumos_Ubicaciones.sector` | las 63 filas de la grilla pasaron a `IN-xx` |

> ## ⚠⚠ **Lo que esto CIERRA: `gv_rack_sector('A1')` ahora devuelve NULL.**
> `gv_rack_sector` filtra `tipo = 'rack'`, así que **Ingreso a racks no puede ofrecer una celda de
> SC/SP ni guardar una caja ahí**. Antes devolvía `A1`. Es el mismo pozo de la v29.67 (el operario
> escribió `AB3` en el campo del código) visto del otro lado.

- **Al agregar una celda a SC/SP va con el prefijo**: `insert into "GV_Lugar"(sector,tipo,empresa) values ('IN-C3','scp','IN');`
  Los dos CHECK se ampliaron (`tipo` acepta `scp`; el nombre acepta `IN-xx`).
- **El saldo de una pieza de SC/SP lo lleva GP2**, no Virgilio: acá se dice **DÓNDE** está. En
  `GP2.ubicacion` no hay celdas (SC y SP son **una** ubicación cada uno), así que la celda física
  existe sólo en `Insumos_Ubicaciones.sector`. El espejo `gv_gp2_espejo_sync` copia todo `GV_Lugar`
  sin filtrar tipo, así que GP2 ve las celdas solo (medido 13/10: `GP2.virgilio_lugar` tipo `scp` = **77**).
- **Y de paso se arreglaron 3 insumos** que estaban en rojo: `gv_insumo_ubicacion` pasó de **145 a
  148** posiciones resueltas. Quedan **2** sin lugar, y son las dos de **`medio`**.
- ⚠⚠ **`medio` NO ES UN LUGAR y no se le inventa uno** (Luis, 13/10: *"medio no se que es ni que
  debería ser, no va para mi, es como que algo no tenga lugar"*). Sus dos filas salieron, y las piezas
  **`A1`** (Mgo Plano 501 Pint., 7 cajones) y **`H1`** (Manija Redonda p/cromar, 10 cajones) pasaron
  a la alerta **«insumo con stock y sin posición»** del Mapa, que es donde se ven y donde se las
  ubica con un click. **Si vuelve a aparecer un `medio`, es eso: algo sin lugar.**
- ⚠ **`gv_rack_celda` ya no ve la grilla** (Luis, 13/10: *"d1 dale"*). Su rama de insumos traía
  `gv_insumo_ubicacion` **sin mirar el tipo del lugar**, así que las 63 filas de SC/SP salían como
  `sin_lugar` en la solapa Racks — la vista no sabía que esas celdas habían dejado de ser racks. El
  parche le agrega `exists (… GV_Lugar lr where lr.sector = u.sector and lr.tipo = 'rack')`. La
  **regla protegida** que toca (*"una celda por DIRECCIÓN: un rack partido se ve como sus N partes"*)
  **sigue en pie**: no cambia nada de las partes. Medido: de 306 filas a 243 y el **md5 de esas 243
  es el mismo antes y después**; `prkRacks` del front saltea `^IN[-\s]` como segunda red.
- ⚠⚠ **Y se LIMPIÓ `Insumos_Ubicaciones`** (Luis: *"d3 limpia"*): **150 → 110 filas**, las 110
  resuelven, **0 con código fantasma** y **0 fuera del nombre canónico**. Salieron las **38** que no
  matcheaban ningún código de `Insumos` y tenían su gemelo válido en la misma celda (29 el fleje sin
  el `N°`, 4 con su código ISIS, 8 la pieza con un punto de más, 5 basura `-` `--` `---` `----`
  `N|24`; las 38 en cantidad 0) y las **2 de `medio`**; **30** pasaron al nombre canónico
  (`N7` → `N07`, `R1AD` → `R01AD`, `V9 AT` → `V09AT`, `AF1` → `AF01`, `Z2` → `Z02`).
  Backup: `zz_backups."GV_Backup_InsUbic_20261013"` · `select jsonb_pretty(public.gv_scp_limpiar(true));`
  dice qué haría, fila por fila.

**Chequeo:** `select public.gv_scp_sector('A1'), public.gv_rack_sector('A1'), public.gv_insumo_sector('R1Ad');`
→ `IN-A1`, **NULL**, `R01AD` · `select count(*) from public.gv_scp_celda;` (77: 55 con pieza + 22 libres) ·
`select * from public.gv_reglas_perdidas;` · `select count(*) from public."Insumos_Ubicaciones";` (110,
todas resueltas y con el nombre canónico) · `node tests/pmap-scp.cjs`.
`sql/gv_sector_scp_v2998.sql` (rollback: `select public.gv_scp_revertir();`), 5 centinelas.
⚠ Los objetos de la base, los 5 centinelas, el `.sql` y los comentarios del código dicen **v29.98**
(la versión con que se aplicaron): es la llave de idempotencia, **no cambiarla**; la app salió en la
v30.03 porque otras sesiones se adelantaron.

### El mislabel que esto RETIRA

⚠⚠ **El bullet de la v22.80 dice que la grilla `A1…L6` son «racks de insumos». ES FALSO y queda RETIRADO.**
Se dieron de alta así el 25/09 —tipo `rack`, empresa `IN`— y de ahí salió la confusión; **la v30.03 las
pasó a `tipo = 'scp'` y a nombre `IN-A1`** (bloque de arriba). Medido el 13/10, antes de tocar nada:

- las **52 celdas de un dígito** de `GV_Lugar` son **exactamente** donde viven `parte_procesado` (SP: `A1`-`A6`,
  `B1`-`B6`, `C1`, `C2`, `C5`, `C6`, `D1`, `D3`-`D6`, `E1`, `E2`, `E5`, `E6`, `F1`, `F2`, `F6`, `G5`, `G6`, `H1`,
  `L1`-`L4`) y `partes_crudo` (SC: `G1`-`G4`, `H2`-`H7`, `I4`, `J1`-`J4`, `J6`, `L5`, `L6`);
- **0 cajas de artículo** pasaron por ellas en toda la historia (`deposito in (racks, racks_ch)` con ubicación de
  un dígito → vacío). No son racks: no guardan cajas.
- `K4`, `K5` y `K6` tienen piezas de SC cargadas y **no existen en `GV_Lugar`**: el alta del 25/09 los salteó.

⚠ **`gv_rack_sector('A1')` devolvía `A1`** (y `('A01')` NULL, porque A01 es góndola): el resolvedor de racks
**aceptaba una celda de SC/SP** y **Ingreso a racks la ofrecía**. No hizo daño porque nadie guardó una caja ahí.
**Cerrado en la v30.03**: con `tipo = 'scp'` ese `coalesce` no la encuentra más y devuelve NULL.

### Y en GP2 no hay celdas: SC y SP son UNA ubicación cada uno

`GP2.ubicacion` tiene **12 `sector`** (`Sector Crudo`, `Sector Procesado`, `Sector Fleje`, `Sector Caja`…) y
**ninguna celda adentro**: el saldo de una pieza es por (componente, sector), sin posición. **La celda física
`A1`…`L6` existe SÓLO en `Insumos_Ubicaciones.sector` de Virgilio**, para que el operario sepa dónde mirar. Son
dos niveles de detalle distintos y no se reconcilian.

⚠⚠ **Y el CÓDIGO de una pieza de SC/SP también se pisa con el de una caja.** `CONOCIMIENTO_GP2.md` lo tiene
medido del 03/09: **`A1`, `A4`, `A8` y `A9` existen DOS veces en `GP2.componente`** —una pieza de Sector
Procesado y una Caja— y la regla de allá es *"unir por `componente.id`, y si hay que resolver desde un código,
desambiguar por sector"*. O sea: la colisión de nomencladores **no es sólo de lugares, es también de códigos**.

> **Antes de decir que una posición «no existe» o que un código «está mal cargado»: mirar si no es SC/SP.**
> El criterio es el dígito: **un dígito = SC/SP · dos dígitos = góndola o rack.**

**Chequeo:**

```sql
-- las 52 celdas de SC/SP, con qué categoría de insumo vive en cada una
select u.sector, i.categoria, count(*)
  from public."Insumos_Ubicaciones" u
  join public."Insumos" i on upper(btrim(i.cod)) = upper(btrim(u.cod))
 where upper(btrim(u.sector)) ~ '^[A-Z]{1,2}[0-9]$'
 group by 1,2 order by 1;
-- y que ninguna tenga cajas de artículo (tiene que dar vacío)
select m.ubicacion, m.cod_art, sum(m.delta) from public."Movimientos_Stock" m
 where m.deposito in ('racks','racks_ch') and upper(btrim(coalesce(m.ubicacion,''))) ~ '^[A-Z]{1,2}[0-9]$'
 group by 1,2 having sum(m.delta) <> 0;
```

### ⚠ Lo que esto explica: las posiciones «con dos códigos» NO son racks compartidos

Barrido del 13/10 sobre `Insumos_Ubicaciones`: **38 filas** no matchean ningún código de `Insumos`, **las 38 en
cantidad 0** y **las 38 con su gemelo válido en LA MISMA celda**. No es un lugar con dos cosas: es **la misma
cosa escrita dos veces**.

| cuántas | qué son | ejemplo |
|---:|---|---|
| 29 | el fleje **sin el `N°`** | `63` junto a `N°63` en R11AD |
| 4 | el fleje **con su código ISIS** | `1645` = `N°35` · `2565` = `N°36` · `2615` = `N°18` · `2745` = `N°37` |
| 8 | la pieza de SP **con un punto de más** | `DISC.1` junto a `DISC1` · `DISC. 4` junto a `DISC4` |
| 5 | basura de verdad | `-`, `--`, `---`, `----`, `N|24` |

⚠⚠ **Queda RETIRADO lo que reporté antes** (*"basura de carga, no racks compartidos — eso se limpia en
`Insumos_Ubicaciones`"*): de las 38, **sólo 5 son basura**; las otras 33 son el mismo insumo con una segunda
grafía, y 4 de ellas son **su código ISIS**, que es un dato bueno escrito en el campo equivocado — el ISIS vive
en `Insumos.isis` y en `GP2.insumo_equivalencia.isis` (regla v29.79), no en el código de una ubicación.

### ⚠ INSUMOS: dónde está cada uno sale del Mapa (Luis, 25/09, v22.80)

**Luis:** *"es un mismo depósito físico … son racks de insumos. Dejalos con el nomenclador que ya existe, no inventes
uno nuevo · AD adelante AT atrás · sí, ponelo en el mapa"*.

- Los racks de insumos son `GV_Lugar` tipo `rack`, **empresa `IN`** (R01AD, K04, X20…). Se sumaron 69 que faltaban:
  ⚠⚠ **la grilla A1…L6 NO son racks de insumos: es SC/SP — ver la regla de arriba, v29.97** (A1 ≠ A01: A01 es
  góndola; por eso `gv_lugar_sector_fmt` acepta un dígito) y
  R07AD, R10AD/AT, R12AT, R16AD, V01AD, V02AT, V05AT, V11AT, V12AT, V13AD, AF02/04/07/16/18, AE04.
- **`gv_rack_sector(texto)`** resuelve cualquier grafía: primero el nombre exacto (A1), después con cero y AD/AT
  (`R1Ad` → R01AD, `V9 At` → V09AT, `W1` → W01). Es la misma para racks de artículos y de insumos.
- `Insumos_Ubicaciones` sigue siendo la tabla del módulo; se lee resuelta en **`gv_insumo_ubicacion`** y se escribe
  por **`gv_insumo_ubicaciones_guardar`**, que rechaza una posición que no esté en el Mapa. `vista_insumos.ubicacion`
  (lo que ve el operario en Recibir/Entregar insumos) sale de ahí. Al 25/09: 145 de 149 resuelven; `medio`, Y29 y Z07
  (celdas de góndola) quedan en rojo ⚠ en la pestaña Insumos.
- El Mapa de racks muestra los insumos (🧰, con la cantidad declarada en el módulo, en su unidad).
- `Insumos_Ubicaciones_Unificadas` está muerta desde el 11/08: nadie la lee ni la escribe.
- ⚠⚠ **`Insumos_Ubicaciones.cantidad` es DECORATIVA: no se carga a mano y no se corrige** (medido el 13/10, con
  el conteo de 505C). **142 de 149 filas están en 0 o null** (112 códigos de 116), **ninguna función la lee** para
  calcular algo —sólo las dos RPC que la escriben, `gv_insumo_ubicaciones_guardar` y `gv_insumo_posicion_guardar`—
  y el front **omite el número cuando es 0** (`_stkInsUbicStr` en Stocks y el `🧰 insumo` del Mapa): nadie ve un
  «0» en pantalla. El saldo real de un insumo sale SIEMPRE de `Movimientos_Stock` (deposito `insumos`, convertido
  con `Insumos_Factores`), que es lo que leen el módulo, las compras y el espejo a GP2.
  ⚠ **Cargarle el número a un código suelto es peor que dejarlo vacío**: lo vuelve el 5.º con dato entre 112 sin
  dato, sin que nada lo reconcilie después — es el pozo de la copia que nadie poda (regla v23.00). Si algún día
  esa columna tiene que valer, se llena sola desde el saldo, no a mano.
- `sql/gv_insumos_ubicacion_v2279.sql` (rollback en la cabecera), `tests/ins-aceptar-ubic.cjs`.

### ⚠⚠ EL MAPA ES EL PUNTO PRINCIPAL — y avisa el stock sin lugar (Luis, 25/09, v22.82)

**Luis:** *"que todas las definiciones de qué cosa hay en cada rack/góndola se puedan editar desde mapas; pasa a ser
el punto principal y cambiarlo ahí informa a todos los demás"* · *"evitá choques con el stock: sería raro que
Movimientos_Stock diga que hay stock de un código pero ninguna góndola/rack lo tenga"*.

| qué | tabla canónica | se edita en el Mapa por |
|---|---|---|
| código y capacidad de cada celda de góndola | `GV_Lugar_Item` (`Capacidad_Sector` es vista) | `gv_lugar_item_guardar` / `_sacar` |
| qué hay en cada posición de rack de artículos | `Movimientos_Stock` (racks, `ubicacion`) (`Racks_Planimetria` es vista) | `gv_rack_posicion_guardar` · `gv_rack_ubicar` |
| qué insumo hay en cada posición | `Insumos_Ubicaciones` (lectura resuelta `gv_insumo_ubicacion`) | **`gv_insumo_posicion_guardar`** |

- **La pestaña Insumos ya no tipea la ubicación**: la muestra y tiene **📍 Editar en el Mapa**. La única escritura
  que queda fuera del Mapa es «Aceptar» un TMP (la ubicación inicial, por `gv_insumo_ubicaciones_guardar`).
- Una posición de rack con varios insumos es **una** celda; un rack `IN` abre sólo el editor de insumos.
- **Alerta**: `gv_mapa_stock_sin_lugar` (góndola con cajas y sin celda · racks sin posición · insumo con stock y
  sin posición · insumo anotado en un lugar que no existe). Se ve arriba del Mapa en las dos pestañas y cada
  renglón se arregla ahí mismo. Al 25/09: 3 góndola (55219 LK 835 caj) · 7 racks · 38 insumos · 4 sin lugar.
- ⚠ **38 filas de `Insumos_Ubicaciones` con códigos que no existen en Insumos** (`63`, `N|24`, `---`, `DISC.1`…),
  todas en 0: se ven como «(no está en Insumos)» y se sacan con 🗑 (la RPC deja quitar aunque el código no exista).
- `sql/gv_mapa_punto_unico_v2281.sql` (rollback en la cabecera), `tests/pmap-punto-unico.cjs`.

### ⚠ `Capacidad_Sector` es una VISTA (Luis, 25/09, v22.75)

Había dos lugares para lo mismo y se desincronizaban: el mapa (`GV_Lugar_Item`) tenía **654 celdas
sin capacidad** y la capacidad vivía sólo en `Capacidad_Sector`, que escribían tres pantallas por su
cuenta (Stock → Capacidad «Importar» y «Borrar todo», y Despiece «Guardar sector») más el espejo de
`gv_lugar_item_guardar`. Hoy **`GV_Lugar_Item` es la única fuente** y `Capacidad_Sector` la lee
(`security_invoker`, sólo celdas con capacidad, empresa del `GV_Lugar`).

- Escribir: **`gv_lugar_item_guardar`** / **`gv_lugar_item_sacar`**. Un `INSERT`/`UPDATE` sobre la vista
  (front viejo, Producción) pasa por el trigger `gv_capacidad_sector_escribir` → la misma RPC, que
  rechaza un lugar que no existe en `GV_Lugar` (`A-62`). **Sin DELETE**: «Borrar todo» ya no existe.
- ⚠ Producción Virgilio tiene el «Importar» con `on_conflict` (upsert): **sobre una vista falla**. A
  propósito: era la puerta de los sectores mal escritos.
- Al pasar se midió la suma de capacidad por código: cambian **sólo 828** (−45: la fila `C-08/828` era
  falsa, el relevamiento del 11/09 dice C08 = 539E) y **865E** (−60: su celda L57 está inactiva).

**Rollback** y el bloque que se corrió: `sql/gv_capacidad_sector_vista_v2275.sql`. Las definiciones de
los 12 dependientes quedaron en `zz_backups."GV_Backup_CapSector_defs_20260925"`. Lo sostiene
`tests/cap-sector-vista.cjs`.

