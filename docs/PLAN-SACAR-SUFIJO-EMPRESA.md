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
