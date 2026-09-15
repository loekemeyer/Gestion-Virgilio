# Handoff — OC, códigos NNNL y proyección · 2026-09-15

Sesión: https://claude.ai/code/session_01FR4v2gqbcT4ASALUUmCdRd · Pedido de **Thomas**.
Todo lo medido acá es del **2026-09-15**; si pasó un miércoles, volver a medir (los crons de
proyección corren miércoles 09:20 y 09:25, y las OC se generan a mano los miércoles).

---

## ⛔ Lo que bloquea TODO lo de abajo: el permiso de DDL

`mcp__Supabase__apply_migration` y `execute_sql` con DDL quedaron **rechazados por el
clasificador del modo auto**. En `.claude/settings.json` de este repo `apply_migration`
figura en `"ask"`, pero el modo auto decide solo y dice que no.

Tres salidas, de menor a mayor fricción:
1. Thomas pega el SQL en el **SQL Editor de Supabase** (los archivos están listos y probados).
2. Mover `mcp__Supabase__apply_migration` de `"ask"` a `"allow"` en `.claude/settings.json`.
3. Salir del modo auto con `/config` para que la aprobación la dé él a mano.

**No intentar aplicar la DDL por otra vía.** Lo que sí funciona sin permiso: `execute_sql` de
sólo lectura, INSERT/UPDATE en `planify.tasks` y en `github_repo_problemas`.

---

## 1. Códigos NNNL — problema 218 · SQL listo, sin aplicar

**Qué es.** `513L` es la variante con la que Chef le vende a sus clientes mercadería de Loeke.
Mismo artículo que `513`, se pickea de la góndola LK, **sin stock propio** (regla del dueño,
v13.71). Thomas: *"con la L al final ya hablé mil veces que no va"*.

### 1a. La fila fantasma en Stocks

No entra por el stock — `vista_saldos_stock` no tiene **ninguna** fila NNNL. El universo de
`vista_stock_procesada` es `stock_e UNION dem_raw`, así que entra por la **demanda**: un pedido
de Chef con artículo 513L. `dem_raw` / `dem_oc_raw` normalizan con un regex que sólo saca los
ceros a la izquierda.

| Medición sobre `stocks_carga_rapida` | |
|---|---|
| Filas NNNL visibles (todas con stock 0) | 56 |
| Cajas pedidas que NO se le suman al código base | 192 |
| Proyección colgando de esas filas | 807,51 cj/mes |

**Arreglo:** que `dem_raw` / `dem_oc_raw` usen `gv_cod_stock()`, la función canónica que ya usa
`vista_generador_oc` (`gv_cod_stock('513L') = '513'`). Simulado en un SELECT: la demanda pasa de
290 a 237 códigos, se mueven 192 cajas, el total (5.426,66) queda intacto.

👉 **`sql/gv_stock_procesada_sufijo_L_v1811.sql`** — aplicación, verificaciones y rollback exacto.
Respaldo de las 4 definiciones previas en `zz_backups."GV_Backup_Defs_StockProcesada_20260915"`.

⚠ Es matview: `DROP … CASCADE` se lleva `Stock_Saldos`, `gv_importados_stock_dep` y, en segundo
nivel, `gv_importados_ordenes` — la que ya se cayó dos veces por esto (v16.20 y v16.33). Las tres
se recrean en la misma transacción con `security_invoker=true` y sus grants.

⚠ **NO usar `Equivalencias_Familia`** para mapear 513L→513: la leen
`notificar_pedido_secundario_telegram()` y `corregir_pedido_secundario_auto()`, que le sacarían
la L a los pedidos de Chef — justo lo contrario de la regla del dueño.

### 1b. El generador de OC SUBCUENTA a los NNNL ← lo más caro

**Ojo: en esta misma sesión primero se dijo al revés.** Lo correcto, medido:

- `proyeccion_madre.proy_cajas_mes` de los NNNL está **BIEN**: sale de `sales_lines.boxes`, o sea
  ya viene en cajas (513L = 72 cj/mes).
- `proy_uni_mes` está **MAL**: `fn_proyeccion_oc_virgilio()` la calcula como
  `proy_cajas * coalesce(products.uxb, loke_products.uxb, 1)` y ningún NNNL está en esos
  maestros → el uxb cae en **1** y queda 12 o 24 veces por debajo.
- `vista_generador_oc` suma `proy_uni_mes` y divide por `GV_UxB`, así que **no está inmune**.

| | cajas/mes |
|---|---|
| Demanda real de los 124 NNNL | 1.610,56 |
| Lo que cuenta el generador hoy | 145,34 |

Simulado sobre los 119 códigos base afectados: corregirlo **sube el máximo en 64** y hace que
**17 códigos pidan 391 cajas más**. Parte de lo que entra sin OC es mercadería que el generador
tendría que haber pedido.

**Arreglo:** en LK (`kwkclwhmoygunqmlegrg`), que `fn_proyeccion_oc_virgilio()` resuelva el uxb del
código base (pelando la L) antes del `coalesce(..., 1)`. **Hacer esto ANTES** de fundir el CTE
`proy` de `vista_stock_procesada` (el archivo 1811 funde sólo la demanda, a propósito).

---

## 2. La proyección en dos tablas — problema 222 · sin arreglar

Pedido de Thomas: *"no quiero que la proyección esté en dos tablas distintas, solo una"*.

| Tabla | Filas | Cron en LK | Motor |
|---|---|---|---|
| `proyeccion_madre` | 461 | 25 · mié 09:20 | `fn_proyeccion_oc_virgilio()` |
| `GV_Proyeccion_Emp` | 533 | 40 · mié 09:25 | `fn_proyeccion_importados_emp()` |

Mismos 461 códigos, **70 no coinciden**: 22.305,87 contra 23.341,78 cj/mes (+4,6 %). Peores:
816E 107,50 vs 230,17 · 574 86,67 vs 162,67 · 812E 20,00 vs 81,42 · 106E 5,67 vs 50,92.

**Causa.** Los dos motores usan el mismo método (ventana de 6 meses, fallback a 12 si la de 6 da
0), pero `_fn_proy_window_emp()` lo corre **por empresa** y el fallback se dispara por empresa: un
código sin ventas en Chef los últimos 6 meses toma el promedio de 12 de Chef y se lo suma a la
ventana de 6 de LK. Mezcla ventanas, y por eso el partido siempre da ≥ que el junto.

**Consumidores** (hay que moverlos a la que quede):
- `proyeccion_madre` → 4 funciones (`gondola_return_check`, `notificar_oc_pendientes_telegram`,
  `oc_backfill_valores`, `watchdog_frescura_datos`) y 6 vistas (`vista_generador_oc`,
  `vista_stock_procesada`, `vista_uni_x_caja`, `vista_nombres_articulos`,
  `vista_proyeccion_super`, `E. Madre LK`).
- `GV_Proyeccion_Emp` → `gv_importados_ordenes`, `v_importados_ordenes`, `gv_stock_procesada_dup`,
  `vista_stock_procesada`.
- `vista_stock_procesada` lee **las dos** y las une con `UNION ALL`.

**Propuesta:** una sola tabla `proyeccion_madre` con columna `empresa` (`lk` / `chef`), un solo
motor en LK que decida el fallback **una vez sobre la serie conjunta**, el total se saca sumando y
el desglose filtrando. Se van `GV_Proyeccion_Emp` y las vistas muertas `E. Madre LK` / `E. Madre CH`
(nadie las refresca desde agosto y marzo).

---

## 3. Desglose de ventas por cliente — SQL listo, sin aplicar

Pedido: *"las ventas de los 5 más importantes + una fila de otros"*. **El front ya está pusheado**
(v18.13) y llama a `gv_ventas_clientes_mes_cod`; mientras no exista contesta 404 y el desglose lo
dice en una línea. En cuanto se creen las funciones se enciende **sin tocar el front**.

👉 **`sql/gv_ventas_clientes_mes_v1812.sql`** — son **dos** funciones, una por proyecto:
`fn_ventas_clientes_mes_virgilio` en LK y `gv_ventas_clientes_mes_cod` en Virgilio (envoltorio
HTTP, calcado de `ventas_mensuales_cod`).

Probado a mano contra LK (513 / mayo 26): Osa 400 · Inc 183 · Patagonia 92 · Enrique Reyes 40 ·
Horcada 40 · **Otros 846** = **1.601**, igual que la columna. Ese mes el 513 le fue a **137
clientes**: por eso el corte de 5 + Otros lo hace el backend.

⚠ La primera versión filtraba por mes y después por artículo y **se pasó de los 60 s**
(`sales_lines` tiene 236.272 filas): normalizar `item_code` con `regexp_replace` en el `WHERE`
inutiliza `idx_sales_lines_item_invoice`. La que quedó arma un juego de códigos candidatos y filtra
con `in` de literales.

⚠ La clave publishable y el `x-feed-secret` **no están en el repo** (se publica por GitHub Pages):
el bloque que crea la función los lee del cuerpo de `ventas_mensuales_cod`.

---

## 4. Órdenes de compra — el estado, para la decisión de Thomas

Disparador original: le llegan WhatsApps de *"SIN OC generada (OC = 0)"*. **No es un bug del
aviso** — es el gate obligatorio de la v17.99/v17.27, y tiene razón.

### Cómo se genera una OC

`A pedir = ceil(max(0, Máximo + Pedidos − Stock))`, con
`Máximo = min(proyección × índice(1,5), capacidad de góndola)`. Sin proyección, el Máximo es la
capacidad de góndola, y sólo si el código tiene proveedor real. Stock = los 8 depósitos. Pedidos =
NP no facturadas cuya tanda no tiene TP. Vive en `vista_generador_oc`; la usan igual el cron y el
botón ⚙ Generar OCs.

### Lo medido (14 días al 15/09)

56 pares (tallerista, código) entregados / 6.761 cajas. **41 pares y 5.921 cajas (87,6 %) no
tenían OC vigente** para ese tallerista, según `oc_vigentes_por_proveedor`, que es la que usa la app.

| Caso | Pares | Cajas |
|---|---|---|
| Tiene OC pero ya se recibió entera (`pend = 0` la saca de vigentes) | 26 | 2.724 |
| Tiene OC con saldo pero **a nombre de otro proveedor** | 7 | 1.608 |
| Con OC vigente | 15 | 840 |
| El código no tiene **ninguna** OC en 120 días | 8 | 1.589 |

Casos concretos: **544** lo entregó *Pedernera* y la OC está a nombre de *Log/ Fabr* con 435
pendientes · **760** y **550** los entregó *Garcia* y la OC es de *Poly* · **513** tiene 2.706 cj de
stock contra 2.520 de capacidad, así que el generador no pide nada y entraron 806 igual.

### Tres cosas abiertas, no registradas como problema

1. **El excedente no queda en ningún lado.** `gv_oc_aplicar_recepcion` topea el descuento en
   `least(recibido, cantidad − recibida)`: hay **0 líneas** con `cantidad_recibida > cantidad` en
   120 días. Las 5.921 cajas entraron al stock y el único rastro es el WhatsApp.
2. **104 de 354 filas de `OC_Maximos` no tienen proveedor** → nunca van a tener OC, y cada caja que
   entre manda un mensaje. 43 más están inactivas.
3. **Cron 50 `ocs-auto-miercoles` apagado desde el 04/08**, esperando un go-live que nunca se
   confirmó. Lo único que corre es `ocs-auto-sim` (jobid 51), que avisa "generaría N líneas" y no
   escribe. Las OC las genera alguien a mano cada miércoles (las 604 líneas tienen `notas` nulo).
   **Recomendación: prenderlo DESPUÉS de arreglar el uxb (§1b)**, no antes, o genera sobre datos
   que subcuentan. `select cron.alter_job(50, active := true);` + apagar el 51.

---

## 5. Tareas de Planify abiertas

| id | Tarea | Estado |
|---|---|---|
| 3405 | Th Sacar los codigos NNNL de la pantalla Stocks | abierta |
| 3409 | Th Desglose por mes en el pop-up de Proyeccion | abierta |
| 3406 | Th Pop-up Proyeccion: orden cod-vta-entrega-grafico | cerrada ✅ |

Todas en el Planify de **Tomás Beviglia (20)** con prefijo `Th `, que es como van los pedidos del
dueño.

---

## 6. Lo que YA quedó hecho y pusheado (para no rehacerlo)

- **v18.11** — pop-up de Proyección en el orden pedido: código · factur. · entrega · gráfico al
  final. Y las dos columnas laterales a 52 px fijos, porque la de la derecha era `flex:0 0 auto`,
  el track absorbía la diferencia y la marca punteada de la proyección caía en una x distinta en
  cada fila.
- **v18.13** — desglose por mes. **Entrega anda**: tocar el número abre día, quién y remito, desde
  `vista_historial_entregas`; se trae una vez al abrir el pop-up y filtra en memoria. Cotejado con
  513 / mayo 26: 420 + 226 + 224 + 138 = 1.008, igual que la columna. **Venta espera la RPC** (§3).
- Respaldo de definiciones en `zz_backups."GV_Backup_Defs_StockProcesada_20260915"`.
- Problemas **218** (reescrito, tenía el error al revés) y **222** registrados, los dos `abierto`.

⚠ **Al tocar `index.html`: tiene un byte NUL adentro** (separador de claves de `_pppGeoCod`).
Cualquier script que lo edite tiene que leer y escribir en **latin1 o bytes**, y verificar el largo
del resultado antes de guardar. Y el bump va con `node scripts/bump-version.cjs <ver>`, nunca a mano.

⚠ En esta sesión **tres chats distintos pushearon a `main` al mismo tiempo** (v18.09, v18.10 y
v18.12 salieron de otros). Antes de bumpear, `git fetch origin main` y mirar en qué versión está.
