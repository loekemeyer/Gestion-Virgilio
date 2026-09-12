# Plan — sacar los códigos `"438E LK"` de una vez

> **Pedido de Luis (2026-09-11):** *"hay que cambiar esa vista. ya tiene toda la data como
> para no tener que hacer esa conversión y limpiar esas llamadas muertas. planealo para
> cuando pusheemos esto a main"*.
>
> **Esto NO se hace junto con el merge.** Va DESPUÉS, con la empresa ya viajando y unos
> días de rodaje. Sacar el andamio antes de que fragüe es cómo se rompen las cosas.

## Por qué el sufijo existía

No había dónde guardar la empresa. El único lugar era el **nombre de la celda** de
`Planimetria` (`"438E LK"`). Con `GV_Lugar` la empresa es una **columna**, así que el sufijo
no tiene más razón de ser. La meta es `cod: "438E"` + `emp: "LK"`, siempre.

## Dónde vive hoy el sufijo

| dónde | filas | qué pasa |
|:--|--:|:--|
| `Movimientos_Stock.cod_art` | **0** | el trigger lo pela desde siempre — nada que hacer |
| `Capacidad_Sector.cod` | **0** | — |
| `GV_Lugar_Item.cod` (tabla nueva) | **0** | nació limpia |
| `Planimetria.cod` | 8 | 4 duales × 2 |
| `Equivalencias_Codigos.cod_real` | 6 | ver abajo |
| `vista_saldos_stock.cod_art` | 8 | lo **emite** la vista |
| `index.html` | — | `codBase` ×67, `PICK_UBIC_DUAL` ×15, `pkCodEmpresa` ×11, `pkResolveArt` ×3 |

## ⚠ CORRECCIÓN (2026-09-12, Luis): el paso 1 tal como estaba escrito FUNDE dos productos

> *"1 sí, pero no mezcles con el otro de CH, lo mismo para 437"*.

**El paso 1 de abajo está mal y no se ejecuta como está.** Decía "es un `CASE` de menos".
Medido: **no lo es**, y el que lo corre funde 809E LK con 809E CH.

El motivo es una línea de `stockFetchSaldos`:

```js
const k = String(x.cod_art);   // ⬅ la CLAVE del mapa de saldos es el código CON sufijo
```

Hay **14 call sites** de `stockFetchSaldos` (MG, Bajar de racks, Insumos, OCG, CP, faltantes,
capacidad de góndola…) y todos leen `m[cod]` como el **total** de ese artículo. Hoy el sufijo
es lo único que mantiene separados los cuatro duales; si la vista deja de emitirlo:

| código | LK | CH | sumarlos es… |
|:--|:--|:--|:--|
| `809E` | Corta **Pizza** (J13-J14) | Corta **Queso** (M13-M15) | **incorrecto: dos productos** |
| `437E` | colador LK (F09-F12) | colador CH (L07-L08) | **incorrecto** |
| `438E` | (F13-F16) | (L05-L06) | **incorrecto** |
| los otros 292 códigos con dos filas | mismo artículo | mismo artículo | correcto |

O sea: para **4** códigos sumar está mal y para **292** está bien. Un cambio en la vista no
puede distinguirlos — el que distingue es el lector.

### Lo que SÍ se hizo (v16.14)

`codCanonSuf` —la función única de mostrar un código, 50 call sites— ahora separa la empresa
del código: **`809E · CH`** en vez de `809E CH`. Es el 100% de la parte VISIBLE (que era el
pedido original: *"eliminar toda instancia de esos códigos feos"*) con cero riesgo: una
función, ningún lector cambia de clave, ninguna suma se mueve.

### Tramos 1 y 2: HECHOS (v16.16, 2026-09-12)

- **Tramo 1** — `vista_saldos_stock` tiene `clave` (al final del select; `create or replace
  view` no deja insertar una columna en el medio). Medido antes y después: **488 filas, misma
  firma md5 `84f2d585c9f6c01310ed5b53e41a2092`, `clave` distinta de `cod_art` en 0 filas**.
  `sql/gv_vista_saldos_clave_v1616.sql`, backup en `GV_Backup_vista_saldos_def_20260912`.
- **Tramo 2** — los **7** lectores de la vista pasaron a `clave`: `pkFetchExcedente`,
  `_pkConteoSistema`, `_stkGondolaSaldoVivo`, `stockFetchSaldos` (la clave del mapa),
  `_pppChkFetchSaldos`/`_pppChkBuildMaps`, y los dos de `recepcion.js`. Todos con fallback
  `x.clave || x.cod_art` en JS. Suite 138 bloques EXIT=0.
- **El invariante quedó medido: 8 filas de duales** (809E, 437E, 438E y 439E × LK/CH). El
  439E **sí** vuelve en dos filas acá (tiene movimientos en las dos empresas); lo que le
  falta es el LUGAR de CH en `GV_Lugar_Item` — problema aparte, ya registrado.

⚠ **El rollback de la vista obliga a rollear la app a ≤ v16.15**: siete lecturas piden
`clave` y PostgREST devuelve 400 si no existe.

### Tramo 3: HECHO (v16.20, 2026-09-12)

`vista_saldos_stock.cod_art` **quedó pelado**: 488 filas, **0 con sufijo** (eran 8), y `clave`
distinta de `cod_art` en exactamente esas 8 (los duales). Detalle y rollback en
`sql/gv_vista_saldos_pelar_cod_art_v1620.sql`.

**No alcanzaba con tocar la vista.** Se midió md5 + count de los **10 objetos que dependen de
ella** antes y después. Cinco no se movieron; cinco sí:

| objeto | antes | sin fix | final | qué pasaba |
|:--|--:|--:|--:|:--|
| `gv_stock_cod_duplicado` | 0 | 4 | 0 | el chequeo agrupaba por `cod_art` y dejaba de servir |
| `vista_facturable_anticipado` | 724 | 749 | 724 | join por `canon_cod(cod_art)` → duplicaba |
| `vista_stock_procesada` (matview) | 363 | 367 | 363 | CTE `stock` por `cod_art` |
| `stock_v2.vsp_fix` (matview) | 363 | 367 | 363 | ídem |
| `vista_faltante_catalogo` | 505 | 497 | **497** | corrección, ver abajo |

⚠ **`vista_stock_procesada` tiene un UNIQUE INDEX en `cod`**: sin el fix, el próximo `REFRESH`
habría fallado por clave duplicada. Falla ruidosa, pero falla — y la pantalla de Stock la lee
por `Stock_Saldos`.

`vista_faltante_catalogo` baja 8 filas **a propósito**: los pseudo-códigos con sufijo
(`809E CH` no es un código) figuraban como "en stock y sin alta en el catálogo" siendo falsos
positivos.

Las dos matviews no admiten `create or replace`, así que fueron **DROP + CREATE WITH DATA en
UNA transacción**, recreando el unique index y las dos vistas que colgaban de la matview
(`Stock_Saldos` y `gv_importados_stock_dep`, ésta con `security_invoker=true`) con sus grants.
Las matviews **no tenían grants a `anon`**: la app las lee por `Stock_Saldos`.

**Funciones migradas a `clave` (5):** `aceptar_conteo`, `gondola_return_check`,
`oc_backfill_valores`, `check_stock_anomalias` y `generar_reporte_agentes` (las dos últimas
para que el Telegram siga diciendo de qué empresa es el negativo). **No se tocaron**
`actualizar_saldo_trigger` (arma su propia clave, sólo menciona la vista en un comentario) ni
`notificar_conteo_gondola_telegram` (ya pelaba el sufijo con un regexp que ahora es un no-op).

### Tramo 4: HECHO (v16.30, 2026-09-12) — y era el que más plata costaba

Los 4 duales dejan de ser invisibles para los chequeos de stock. Detalle y rollback en
`sql/gv_stock_clave_tramo4_v1630.sql`.

**Pieza nueva: `public.gv_stock_clave(p_cod, p_empresa)`** — una sola definición de "la clave
de saldos de (código, empresa)". Hace UNA cosa: le agrega la empresa al código **cuando el
código es dual**; para todo lo demás devuelve el código tal cual, o sea que es un no-op
demostrable. **488 de 488 filas** coinciden con la columna `clave` de la vista.

⚠ **No re-canoniza el código.** Una primera versión sí lo hacía y fallaba el match en **17 de
488** filas: el `clave` de la vista para un no dual es la grafía **cruda** más corta (`66`,
`NY Virgen`), no la canónica (`066`, `NY VIRGEN`).

**Impacto medido, lo más caro primero:**

`oc_backfill_valores` — el stock que se descuenta al armar una OC:

| código | línea | stock antes | stock con el fix |
|:--|:--|--:|--:|
| `809E` | CH | 0 | **456** |
| `437E` | CH | 0 | 16 |
| `439E` | LK | 0 | 16 |
| `438E` | CH | 0 | 0 |

O sea: **el 809E se compraba como si no hubiera una sola caja, habiendo 456.** Ninguna de las
574 OC abiertas es de un dual, así que el fix no reescribe nada — cambia la próxima.

El aviso de "no devolver a góndola" — 400 cajas de 809E, capacidad 388 (umbral 1,20× = 465,6):

| por | góndola | total | ¿avisa? |
|:--|--:|--:|:--|
| CH | 120 | 520 | **sí**, exceso |
| LK | 28 | 428 | no, y está bien: hay lugar |
| v16.29 (sin empresa) | 0 | 400 | **NO avisaba** ← el bug |

Control de no-regresión: el 505 (no dual) da 2.719 de góndola con empresa y sin.

`aceptar_conteo` — la empresa **ya estaba resuelta por el sector**, pero sólo se usaba para
ESCRIBIR el movimiento; la lectura iba por el código pelado, así que para un dual leía 0 y
ajustaba por la diferencia entera. Ahora se resuelve antes (de `GV_Lugar`, con fallback a
`Capacidad_Sector`) y **un dual sin empresa resuelta no se procesa**: devuelve error pidiendo
que se le cargue la empresa al sector. 0 conteos históricos de duales y 0 pendientes.

En el front la lógica quedó en **`gondAcumPorCod`**, pura y testeada de verdad
(`tests/gond-exceso-dual.cjs`, 12 chequeos). Un código es dual si la vista devuelve `clave`
distinta de `cod_art` — no hace falta pedir `codigos_duales` y un 5.º dual se cubre solo.
De paso: el **`?v=` de `recepcion.js` estaba clavado en 15.39**; ahora acompaña a `APP_VERSION`
y el test lo ata para que no se vuelva a desfasar.

### Lo que FALTA

- **La capacidad de góndola de un dual sigue siendo la suma de las dos góndolas.**
  `Capacidad_Sector` tiene columna `empresa` pero no se filtra: filtrarla cambiaría también la
  conducta de los no duales, así que va aparte.
- Los pasos 3 a 6 de la Parte 1 (borrar las 6 filas de sufijo de `Equivalencias_Codigos`,
  retirar `Planimetria`, limpiar los `codBase` no-op) y el enrutamiento de racks de la Parte 2.

La clave del mapa tiene que dejar de ser un string que parece un código y pasar a ser el par
`(cod, empresa)` **explícito**, en los 14 lectores, ANTES de tocar la vista. Concretamente:

3. ~~**Tramo 3:**~~ HECHO — ver arriba. `cod_art` deja de llevar el sufijo — se borra la rama del `CASE` y queda
   `(array_agg(cod_art order by length(cod_art), cod_art))[1]`, o sea la grafía cruda más
   corta, igual que hoy para los no duales. Para un dual las dos filas devuelven `809E`
   (el trigger pela el sufijo al escribir en `Movimientos_Stock`), y `clave` las sigue
   separando. **Chequeo obligatorio: el mapa tiene que seguir con 8 entradas de duales.**
4. **Tramo 4:** el aviso de exceso de góndola de la recepción. Sus `cods` son PELADOS, así
   que para los 4 duales el filtro por `clave` no matchea ni antes ni después y el aviso no
   salta. Hay que pasarle la empresa de la recepción (que ya la tiene: es la que usa
   `trg_normalizar_empresa_stock`).
4. **Invariante a chequear en cada paso:** `m` tiene que seguir teniendo **dos entradas** para
   809E, 437E y 438E. Si en algún momento queda una sola, el operario trae el producto
   equivocado — es el mismo bug que costó la v15.77.

Ojo con `439E`: está en `codigos_duales` pero en `gv_lugar_articulo` **sólo tiene lugar LK**
(H33 H34 Ñ54). O es dual y le falta el lugar de CH, o no es dual. Hay que resolverlo antes,
porque el invariante de arriba no se puede escribir sin saber cuántas entradas le tocan.

---

## Paso 1 — la vista (es un `CASE` de menos, no una vista nueva)

`vista_saldos_stock` **ya agrupa por `(ckey, empresa)` y ya devuelve la columna `empresa`**.
Lo único que hace falta es borrar la rama del `CASE` que pega el sufijo:

```sql
-- HOY
case when c.empresa in ('LK','CH') and exists (select 1 from codigos_duales d where …)
     then c.ckey || ' ' || c.empresa        -- ⬅ ESTA rama se va
     else (array_agg(c.cod_art …))[1]
end as cod_art
-- QUEDA
(array_agg(c.cod_art order by length(c.cod_art), c.cod_art))[1] as cod_art
```

Con eso `cod_art` es **siempre pelado** y la empresa va en su columna. Es un objeto
**compartido** → entrada en `docs/ROLLBACK-PRODUCCION.md` y backup de la definición previa.

⚠ **Efecto inmediato:** un código dual pasa a devolver **dos filas con el mismo `cod_art`**.
Todo lector tiene que **sumar o agrupar por `(cod_art, empresa)`**, nunca quedarse con una
fila. Los 4 lugares del front que hacían eso ya se arreglaron en la **v15.71** (`stockFetchSaldos`,
`pkFetchExcedente`, `_stkGondolaSaldoVivo`, y el aviso de góndola de `recepcion.js`), así que
ese trabajo **ya está hecho**.

## Paso 2 — los lectores que usan el sufijo COMO CLAVE

Son los que arman `"438E LK"` para buscar el sector o el saldo. Se migran a `(código, empresa)`:

| función | qué hace hoy | qué queda |
|:--|:--|:--|
| `pkCodEmpresa` | `G[a+" "+emp] ? … : a` | se borra: la empresa ya viaja en `items[].emp` (v15.73) |
| `pkResolveArt` | pela la L + pega el sufijo | sólo pela la L (`pkStripL`) |
| `PICK_UBIC_DUAL` | mapa a mano de las celdas de los 4 duales | lo reemplaza `gv_lugar_articulo` |
| `codBase` (×67) | pela el sufijo | **quedan no-op**: pelar lo que ya está pelado no rompe nada, pero hay que borrarlas o el próximo que lea el código no entiende por qué están |

**Orden seguro:** primero migrar los lectores (paso 2), después cambiar la vista (paso 1).
Al revés queda una ventana en la que el front busca una clave que la vista ya no emite.
El `codBase` de más es inofensivo mientras tanto — por eso se limpia al final.

## Paso 3 — los datos

- **`Planimetria`** (8 filas con sufijo): se borran junto con la tabla, ver abajo.
- **`Equivalencias_Codigos`**: **la tabla NO es al pedo** — tiene dos clases de fila y sólo
  una sobra.

  | cod_pedido | cod_real | clase | ¿se va? |
  |:--|:--|:--|:--|
  | `727` | `727E` | equivalencia real (baja de artículo) | **NO** |
  | `727EN` | `727E` | equivalencia real (unificación) | **NO** |
  | `437E` `438E` `439E` | `… LK` | sufijo de empresa | sí |
  | `809E` | `809E CH` | sufijo de empresa | sí |
  | `438EL` `439EL` | `… LK` | regla L | sí — ya está en `pkStripL` + `pkEmpresaArt` y en el trigger |

  O sea: **se borran 6 de 8 filas, la tabla queda** con las equivalencias de verdad.

## Paso 4 — retirar `Planimetria`

**En datos ya está reemplazada.** Comparadas las 369 filas de `Planimetria` contra las 782 de
`GV_Lugar_Item`, quedan **28 diferencias** y ninguna es una pérdida:

- **19 sin stock**: los 4 Acacia dados de baja, los que están en 0 (`231` `232` `233` `537`
  `567` `071` `124` `724` `208` `337` `580E`), las grafías (`702` `702EN` `727EN`) y `592E`
  (que está en `GV_Lugar_Pendiente`).
- **9 con stock que el relevamiento ubicó en OTRO sector**: `513` (2.574 cajas), `439E`,
  `368E`, `355`, `601E`, `658`, `547`, `574`, `659`. Acá `Planimetria` tiene el lugar
  **viejo** y `GV_Lugar_Item` el que relevó el depósito el 11/09 — o sea que la diferencia
  es la corrección, no un faltante. (El `G14:355` es el mismo que Luis ya había marcado
  como mal cargado.)

**En código NO está reemplazada todavía**, y esto es lo que hay que hacer antes de tocarla:
`index.html` la lee en 4 lugares, y uno es el **editor de planimetría** (≈línea 27564) que
**escribe directo** a la tabla. Hay que migrar ese editor a `GV_Lugar` / `GV_Lugar_Item`
antes de retirar nada, o el supervisor edita una tabla que ya no manda.

## Orden final

1. Mergear la rama y prender la empresa (ver `§3.cl` y `§3.cm`). **Dejar correr unos días.**
2. Migrar los lectores del front a `(código, empresa)` — paso 2.
3. Cambiar `vista_saldos_stock` — paso 1.
4. Borrar las 6 filas de sufijo de `Equivalencias_Codigos` — paso 3.
5. Migrar el editor de planimetría a las tablas nuevas y recién ahí retirar `Planimetria` — paso 4.
6. Limpiar los 67 `codBase` que quedaron no-op.

Cada paso es reversible solo y se puede parar en cualquiera de ellos.

---

# Parte 2 — Enrutar TODO lo que toca las tablas viejas a las nuevas

> **Pedido de Luis (2026-09-11):** *"fijate todo lo que toque las tablas que estoy buscando
> reemplazar y planeá el enrutamiento a las nuevas (que el editor pueda editar la nueva por
> ejemplo)"*.

## Las cuatro tablas viejas y quién las toca

| tabla vieja | la reemplaza | lecturas | **escrituras (lo crítico)** |
|:--|:--|--:|:--|
| `Planimetria` | `GV_Lugar_Item` + `GV_Lugar.orden` | 2 | `planimUpsert` (L34510, POST) · `planimDeleteRow` (L34550, DELETE) — **el editor del supervisor** |
| `Capacidad_Sector` | `GV_Lugar_Item.cajas_max` | 8 | `dpSaveCap` (L34400, POST) · `stkCapImport` (L19280, POST + **DELETE masivo**) |
| `Racks_Planimetria` | `GV_Lugar` (`tipo='rack'`) + `GV_Lugar_Item` | 9 | `stkInsAlta` (L20712, POST) |
| `planimetria.js` (estático, 7 kB) | cache offline de `GV_Lugar_Item` | baseline de `window.GONDOLA` | se **regenera**, no se edita |

`Ubicaciones_Articulos` y `Stock_Ubicaciones` **no se leen desde el front**: fueron fuentes de
la carga inicial y nada más. Se retiran sin tocar código.

## La bisagra es `window.GONDOLA`, y por eso esto sale barato

`window.GONDOLA` tiene forma `{ cod: [sector, orden] }` y se usa en **25 lugares**. Hoy lo
llena `planimetria.js` (baseline offline) y encima lo mergea `loadPlanimetriaRemote` (L8500)
con `Planimetria`.

**Si se mantiene la forma y sólo se cambia de dónde se llena, los 25 consumidores no se tocan.**
La consulta equivalente contra las tablas nuevas es directa:

```sql
select cod, sector, orden from public.gv_lugar_articulo where tipo = 'gondola' order by orden;
```

Y para lo que necesita empresa ya está resuelto: el picking usa `gv_lugar_articulo` por
`(código, empresa)` desde la **v15.73**. O sea que `GONDOLA` queda como **fallback offline**
y la vista como fuente viva — que es justo el reparto que ya tiene hoy con `planimetria.js`.

## El editor: que edite la tabla nueva

`planimUpsert(cod, sector, orden)` y `planimDeleteRow(cod)` escriben a `Planimetria`, cuya
clave es **`cod`** — o sea **un código, un lugar**. Las tablas nuevas invierten eso: la clave
es `(sector, cod, clase)`, así que **un código puede estar en varios lugares** (que es la
realidad: el 437E está en F09-F12). El editor hay que rehacerlo, no re-apuntarlo:

| hoy | queda |
|:--|:--|
| una fila por código, con su sector | una fila por **lugar**, con lo que tiene adentro |
| `orden` se edita por código | `orden` es del **lugar** (`GV_Lugar.orden`) |
| borrar = borrar el código | borrar = sacar el código **de ese lugar** |
| no distingue artículo de insumo | `clase` obliga a elegir |
| no tiene empresa | la empresa la da el lugar, no se tipea |
| no tiene capacidad | `cajas_max` entra acá y `Capacidad_Sector` desaparece |

**El editor nuevo es el de `Capacidad_Sector` y el de `Planimetria` fundidos en uno**, porque
las dos tablas se fusionaron en `GV_Lugar_Item`. Pantalla: elegir lugar → ver qué tiene →
agregar/sacar códigos con su `cajas_max`.

⚠ `stkCapImport` (L19280) hace un **`DELETE` masivo** (`?id=gt.0`) y recarga de un Excel. Ese
patrón **no se replica**: sobre `GV_Lugar_Item` sería borrar la planimetría entera. El
importador nuevo tiene que ser `upsert` por `(sector, cod, clase)` y, si hace falta borrar,
que sea explícito y acotado al lugar.

## Orden de enrutamiento (después del merge, ver Parte 1)

1. **Lecturas primero, que son inofensivas.** Repuntar `loadPlanimetriaRemote` (L8500) y las 8
   de `Capacidad_Sector` a `gv_lugar_articulo` / `GV_Lugar_Item`, manteniendo la forma de
   `window.GONDOLA`. Los 25 consumidores no se enteran. Verificable comparando el `GONDOLA`
   viejo contra el nuevo: tienen que dar el mismo mapa salvo los 28 casos ya documentados
   (19 sin stock + 9 que el relevamiento reubicó).
2. **Regenerar `planimetria.js`** desde `GV_Lugar_Item` para que el baseline offline coincida
   con la fuente viva. Hoy se generó de un Excel en 2026-08-28 y ya quedó viejo.
3. **Racks:** repuntar las 9 lecturas y `stkInsAlta` a `GV_Lugar` (`tipo='rack'`).
4. **El editor fundido** (Planimetría + Capacidad en uno) escribiendo a `GV_Lugar_Item`.
   Hasta que exista, **dejar el viejo andando**: un supervisor sin editor es peor que un
   editor que escribe a una tabla que ya nadie lee.
5. **Recién ahí** retirar `Planimetria`, `Capacidad_Sector`, `Racks_Planimetria`,
   `Ubicaciones_Articulos` y `Stock_Ubicaciones`. Con backup y entrada en
   `docs/ROLLBACK-PRODUCCION.md`: son tablas compartidas.

**Regla de todo el tramo:** ninguna tabla vieja se borra hasta que su reemplazo esté
escribiendo Y leyendo en producción. Entre medio conviven — cuesta un poco de ruido y evita
quedarse sin editor un lunes a la mañana.
