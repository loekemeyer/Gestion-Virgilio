# Sesión de Luis · 11 al 13/09/2026 — la empresa viaja con el código, y los racks

> **Para qué es este archivo.** Cerrar esta sesión y poder seguirla en otra sin releer el chat.
> Lo que está **hecho** está acá para que **nadie lo rehaga** (ya pasó dos veces en esta misma
> tanda), y lo que queda **pendiente** está con el lugar exacto donde continuarlo.
>
> Estado al cerrar: `main` en **v16.92** · suite **140 bloques, EXIT=0**.

---

## 1. El problema de fondo, en una frase

No había dónde guardar de qué empresa era cada caja, así que la empresa se fue metiendo
**adentro del nombre del código**: `"438E LK"` en las tablas, `809E-QUESO` escrito a mano en los
racks. Cuatro códigos son **duales** — el mismo código es **dos productos distintos**:

| código | Loekemeyer | Chef |
|:--|:--|:--|
| `809E` | Corta **Pizza** · góndolas J13-J14 | Corta **Queso** · M13-M15 |
| `437E` | F09-F12 | L07-L08 |
| `438E` | F13-F16 | L05-L06 |
| `439E` | H33, H34, Ñ53, Ñ54 | **sin lugar cargado** ← pendiente |

Para esos cuatro, **sumar las dos empresas no significa nada**. Para los otros ~480 códigos que
la vista devuelve en varias filas, sumar es lo correcto. Ningún cambio en una vista puede
distinguir los dos casos: **el que distingue es el lector**. Ésa es la idea que ordena todo lo
que sigue.

---

## 2. HECHO — no rehacer

### 2.1 El pipeline de la empresa (v15.71 → v16.30)

- **`Movimientos_Stock.empresa`** viaja desde la recepción hasta la facturación. El corte
  `Stock_Config.pkc_empresa_desde` se prendió el **11/09 17:55** (kill-switch:
  `delete from "Stock_Config" where clave='pkc_empresa_desde';`).
- **`vista_saldos_stock`** agrupa por `(código, empresa)`. Los 4 sitios del front que **pisaban**
  en vez de **acumular** se arreglaron en la v15.71.
- **Picking**: el código se muestra **pelado** con un chip de empresa al lado; la ubicación se
  limpia y se agrupa (`M13 · M14 · M15` → `M13 a M15`). Luis lo verificó en pantalla: E01F (Chef)
  → `M13 a M15`, E01C (Loeke) → `J13 y J14`.
- **`codCanonSuf`** —la función única de mostrar un código, 50 call sites— separa la empresa:
  **`809E · CH`**, no `809E CH`.

### 2.2 Sacar el sufijo de raíz — los 4 tramos

| tramo | qué | versión |
|:--|:--|:--|
| 1 | `vista_saldos_stock` gana la columna **`clave`** (= el `cod_art` de antes) | v16.16 |
| 2 | los **7 lectores** del front pasan a `clave` (fallback `x.clave \|\| x.cod_art`) | v16.16 |
| 3 | **`cod_art` queda PELADO** + los dependientes que lo usaban como clave | v16.20 |
| 4 | los 4 chequeos que no veían a los duales | v16.30 |

**Medición del tramo 3** (md5 + count de los 10 objetos que dependen de la vista):

| objeto | antes | sin el fix | final |
|:--|--:|--:|--:|
| `gv_stock_cod_duplicado` | 0 | 4 | 0 |
| `vista_facturable_anticipado` | 724 | 749 | 724 |
| `vista_stock_procesada` (matview) | 363 | 367 | 363 |
| `stock_v2.vsp_fix` (matview) | 363 | 367 | 363 |
| `vista_faltante_catalogo` | 505 | 497 | **497** (corrección: los 8 pseudo-códigos con sufijo eran falsos positivos) |

⚠ `vista_stock_procesada` tiene un **UNIQUE INDEX en `cod`**: sin el fix, el próximo `REFRESH`
habría fallado. Las matviews no admiten `create or replace`, así que fueron DROP + CREATE WITH
DATA **en una transacción**, recreando el índice y las dos vistas que colgaban.

**Medición del tramo 4** — lo más caro:

| dónde | antes | con el fix |
|:--|--:|--:|
| `oc_backfill_valores`, stock del `809E` para la OC | 0 | **456** |
| ídem `437E` / `439E` | 0 / 0 | 16 / 16 |
| aviso de góndola, 400 cajas de `809E` por CH | no avisaba | **avisa** (120+400 > 465,6) |
| control: `505` (no dual) | 2.719 | 2.719 |

**El 809E se compraba como si no hubiera una sola caja, habiendo 456.** Ninguna de las 574 OC
abiertas era de un dual, así que no hubo datos que reparar.

### 2.3 Las piezas que quedaron, y que hay que REUSAR

- **`public.gv_stock_clave(cod, empresa)`** — la clave de saldos. Hace UNA cosa: agrega la
  empresa **sólo si el código es dual**; para el resto devuelve el código tal cual. **488 de 488**
  filas coinciden con la columna `clave` de la vista. ⚠ **No re-canoniza el código**: el `clave`
  de un no dual es la grafía **cruda** (`66`, `NY Virgen`), no la canónica.
- **`gondAcumPorCod(rows, linea, norm)`** en `recepcion.js` — pura y testeada de verdad
  (`tests/gond-exceso-dual.cjs`). Un código es dual si la vista devuelve `clave` distinta de
  `cod_art`: no hace falta pedir `codigos_duales` y un 5.º dual se cubre solo.
- **`gondola_return_check(jsonb, text)`** — firma con empresa; la de 1 argumento es envoltorio
  **sin DEFAULT** (con default las dos firmas serían ambiguas).

### 2.4 Otras cosas cerradas

- **Editor viejo de Planimetría**: escribía a una tabla que ya nadie lee (desde la v15.77
  `window.GONDOLA` sale de `gv_lugar_articulo`). Lleva un banner que lo dice y un botón al editor
  nuevo. No se borró.
- **`?v=` de `recepcion.js`**: estaba clavado en 15.39 desde la v15.44, o sea que los cambios a
  ese archivo llegaban recién al vencer el cache. Ahora acompaña a `APP_VERSION` y **hay un test
  que lo ata**.
- **Capacidad de góndola por empresa** (v16.51): la hizo otro chat citando el problema 92.

---

## 3. PENDIENTE

### 3.1 Los códigos inventados en los racks — `sql/PENDIENTE-racks-codigos-inventados-20260913.sql`

Ese archivo tiene el backup, las filas exactas y qué pantalla se mueve con cada write. ⚠ Los
códigos malos están en **DOS** tablas: `Racks_Planimetria` (ocupación) y `GV_Lugar_Item`
(planimetría).

> **Actualizado 14/09 (verificado contra la base, no contra este archivo):** el **bloque (1) YA SE
> EJECUTÓ** — `546V` está en `Racks_Planimetria` (X13 117 · AE09 117 · AD12 63 master) y en las 2
> filas de `GV_Lugar_Item`, y `1546903` / `VASTIDOR` ya no existen. Donde abajo dice "no se ejecutó
> nada", léase sólo para los bloques (2) y (3), que **siguen pendientes**: `1000900` sigue en Y4
> (40 master) y `522S` en W04 (20 master). El problema **110** sigue abierto.

| bloque | qué | estado |
|:--|:--|:--|
| **(1)** | `1546903` + `VASTIDOR` → **`546V`** "Bastidor 546". 891 cajas, 3 posiciones (AD12 189, AE09 351, X13 351) + 2 filas de `GV_Lugar_Item`. `546V` libre en las 4 tablas, 0 movimientos de stock en los viejos. | **Luis lo decidió: se puede ejecutar** |
| **(2)** | espiral `1000900` (Y4, 160 cajas). Luis: *"es todo lo mismo, pero de diferentes importaciones"*. Candidatos: `007` "Espiral (Chef)" y `H201PART` "Espiral TN". | **falta que Luis elija el código** |
| **(3)** | `522S` → `522E` (W04, 80 cajas). Luis: *"es el artículo suelto sin cartón del importado 522E. Vamos a mandarlo a envasar y pasa a ser 522E"*. | **falta definir si las 80 entran YA al stock como `para_envasar`** (hoy ese depósito está en 0 para el 522E) |

Aparte: **2 posiciones contradicen su planimetría** (AD06 tiene `809E-QUESO` y `GV_Lugar_Item`
dice `368E`; W02 tiene `PEDIDOS` y dice `102E`) y **37 de las 105 ocupadas no tienen planimetría
cargada**. `CAJAS` y `PEDIDOS` (10 posiciones, 0 cajas) son etiquetas de uso, no artículos.

### 3.2 El 439E de Chef no tiene lugar — problema **88**

8 cajas en góndola y 8 en a facturar, pero `gv_lugar_articulo` sólo devuelve lugar LK. Si entra
un pedido de Chef con 439E, **el picking manda al operario a la góndola de Loeke**. Y su
capacidad en `Capacidad_Sector` para CH es **0**. **Hay que preguntarle el sector a la chica del
depósito — no está en la base y no se adivina.**

### 3.3 El 809E pasa a `820E` — idea **1421**

Decisión de Luis: en la próxima importación el de Loeke entra como `820E` y deja de ser dual.
Los 5 pasos están en `agente_propuestas` y en `docs/IDEAS-USUARIO.md`. Al 13/09 el 809E de Loeke
tiene **28 cajas** en góndola contadas + **64 en el rack AE11** que el stock no cuenta.

### 3.4 Lo que queda del plan del sufijo — `docs/PLAN-SACAR-SUFIJO-EMPRESA.md`

- La **capacidad** de un dual ya se arregló, pero la Parte 1 todavía tiene: borrar las 6 filas de
  sufijo de `Equivalencias_Codigos` (conservando `727` y `727EN`, que son equivalencias de
  verdad), retirar `Planimetria`, y limpiar los ~67 `codBase` que quedaron no-op.

> **CERRADO el 14/09 — y dos de las tres cosas estaban mal caracterizadas.** Verificado contra la
> base, no contra este archivo:
>
> 1. **`Equivalencias_Codigos`: HECHO** (v17.06). Pero no eran "6 filas de sufijo" iguales: cuatro
>    (`437E`, `438E`, `439E`, `809E`) eran mapeo **identidad + sufijo** y se borraron; las otras dos
>    (`438EL`, `439EL`) mapean la **variante L** al artículo base — eso sí sirve, así que se les
>    corrigió el destino en vez de borrarlas. Era el único de los tres con riesgo activo: el cron
>    canoniza el picking contra esa tabla, así que era una vía viva para reintroducir el sufijo.
> 2. **`Planimetria`: NO se puede retirar.** El plan lo pide como si ya no la leyera nadie y la leen
>    **`vista_nc_loeke_chef`** (viva, 36 filas), **`planimetria_autoorden()`** y **7 puntos de
>    `index.html`**. Lo retirado es el *editor* viejo (§2.4), no la tabla.
> 3. **Los 67 `codBase` NO son no-op — NO HAY QUE BORRARLOS.** La función es
>    `trim().toUpperCase().replace(/\s+(LK|CH|LOKE)$/,"")`, y las dos mitades siguen trabajando:
>    el `trim/upper` siempre, y el `replace` sobre las **8 claves con sufijo que hoy devuelve
>    `vista_saldos_stock.clave`** — los 4 duales × 2 empresas (`437E LK/CH`, `438E LK/CH`,
>    `439E LK/CH`, `809E LK/CH`), que es justo lo que produce `gv_stock_clave` al agregar la empresa
>    sólo cuando el código es dual. **Borrarlos rompía la pantalla de stock para los 4 duales.**
>    Chequeo antes de volver a intentarlo:
>    `select clave from public.vista_saldos_stock where clave ~* '\s+(LK|CH|LOKE)$';` — mientras
>    devuelva filas, `codBase` es código vivo.

### 3.5 Otros problemas abiertos que salieron en paralelo

`124` reportes que cruzan LK y Chef por `cod_cliente` · `125` el espejo PPP de LK congelado por el
rename a `GV_` · `127` dos saldos negativos sin diagnóstico · `117` el log del sync de feriados.

> **Actualizado 14/09:** `124` y `125` **cerrados**. `127` **cerrado**, y con una corrección: no
> había tales negativos — la medición agrupaba por `cod_art` crudo y la app netea por código
> canónico (§3.eb.1 de la doc de Supabase). `117` sigue abierto.
Lista viva: `select * from github_repo_problemas.v_problemas where estado='abierto'`.

---

## 4. Dos cosas que NO hay que volver a intentar

### 4.1 `Racks_Planimetria` **no** se migra a `GV_Lugar` (problema 111)

El plan decía que la reemplazan `GV_Lugar` + `GV_Lugar_Item`. **Es un error de categoría:**

| tabla | qué responde | columnas |
|:--|:--|:--|
| `GV_Lugar` + `GV_Lugar_Item` | qué código **pertenece** acá | `cod`, `clase`, `cajas_max` |
| `Racks_Planimetria` | qué hay **ahora** en esta posición | `master_cajas`, `innercajas`, `estado` |

Verificadas las **6 lecturas + la RPC `racks_plani_mover`**: todas preguntan por la ocupación,
**ninguna** pregunta "dónde pertenece". Las tablas nuevas no tienen dónde guardar cantidades, así
que repuntarlas rompía **Bajar de racks**, el movedor de palets y el alta de insumos. **Conviven.**

### 4.2 No duplicar reglas que otro chat ya resolvió

En esta sesión se empezó a rehacer la capacidad por empresa con una vista y una función propias;
al ver que la v16.51 ya la tenía inline, **se borraron las dos** en vez de dejar una segunda
definición. Antes de escribir una regla, buscar si ya existe.

---

## 5. Errores de esta sesión, para no repetirlos

1. **Pushée `index.html` con los marcadores de conflicto adentro.** Hice `git add -A` después de
   un merge fallido. La app estuvo rota ~2 minutos (hotfix `6a466be`). **Después de cada
   `git merge origin/main`, mirar si el merge falló ANTES de commitear.** `main` se mueve
   rapidísimo: hubo ~8 colisiones de número de versión en dos días.
2. **Dije "760 cajas invisibles" y eran 424.** El rack AD5 (336 de Chef) sí estaba contado.
3. **Listé `523C` como código sin alta y ya estaba** en `Insumos` ("Cremallera Doble Aleta", 6.000
   de saldo). Lo comparé contra `OC_Maximos`, que es el maestro de **artículos** y no lleva
   insumos. **Para un insumo hay que mirar `Insumos`.**
4. **Dije que el plan del tramo 3 "era un `CASE` de menos".** Se movieron 5 de 10 dependientes.
   Medir antes y después, siempre.

---

## 6. Backups de esta sesión (esquema `zz_backups`)

| tabla | qué guarda |
|:--|:--|
| `GV_Backup_vista_saldos_def_20260912` | DDL previo de `vista_saldos_stock`, las 2 matviews, las 2 vistas dependientes y las funciones (filas `DDL v16.29%` = previas al tramo 4) |
| `GV_Backup_snapshot_dependientes_20260912` | count + md5 de cada dependiente por momento (antes / después / control / final) |
| `GV_Backup_picking_pre_v1580`, `GV_Backup_mixto_saldos_20260911`, `GV_Backup_total_pre_backfill`, `GV_Backup_lugar_*_20260911`, `GV_Backup_aguardar_empresa_20260911` | del pipeline de la empresa |

Rollback detallado de cada cambio compartido: `docs/ROLLBACK-PRODUCCION.md` (entradas del 12 y
13/09). ⚠ Rollear `vista_saldos_stock` **obliga** a rollear la app a **v16.15 o anterior**: desde
la v16.16 siete lecturas piden `clave` y PostgREST devuelve 400 si no existe.

---

## 7. Archivos de esta sesión

| archivo | qué es |
|:--|:--|
| `sql/PENDIENTE-racks-codigos-inventados-20260913.sql` | **lo único sin ejecutar**, listo para correr |
| `sql/gv_vista_saldos_clave_v1616.sql` | tramo 1 y 2 |
| `sql/gv_vista_saldos_pelar_cod_art_v1620.sql` | tramo 3, con la tabla de impacto medido |
| `sql/gv_stock_clave_tramo4_v1630.sql` | tramo 4 |
| `docs/PLAN-SACAR-SUFIJO-EMPRESA.md` | el plan vivo, con las correcciones de los tramos 3 y 4 y el aviso de los racks |
| `tests/gond-exceso-dual.cjs` | el aviso de góndola mira la góndola de SU empresa |
| `tests/lugar-editor.cjs`, `tests/gondola-gv-lugar.cjs`, `tests/pk-ubic-empresa.cjs` | del pipeline de lugares |
