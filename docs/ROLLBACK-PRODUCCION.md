# Rollback — todo lo que Gestión hizo que afecta a Producción Virgilio

> **Decisión del dueño (2026-09-08):** Producción Virgilio **ya no se usa** (todo migró a
> Gestión). De acá en adelante **no** se condiciona ningún cambio de Gestión por "no romper
> Producción". A cambio, **todo cambio que toque un objeto compartido / de Producción se anota
> ACÁ**, con el impacto y el **rollback exacto**, para poder volver atrás en bloque si hiciera
> falta. Este archivo es la fuente única de "cómo desarmar lo que rompe Producción".
>
> Regla operativa nueva: cuando toques `public.*` compartido, **primero** dejás la entrada acá.

---

## 0. Kill-switch maestro — apagar la toma de control de Gestión (vuelve todo a Producción)

Esto NO es de esta sesión; es el interruptor de fondo. Si hay que devolverle el pipeline a
Producción, se corre esto en **Virgilio** (`hrxfctzncixxqmpfhskv`):

```sql
-- 1) apagar la numeración propia y el armado automático de Gestión
update public."PPP_Web_Config" set valor = 0      where clave = 'numeracion_activa';
select cron.alter_job(71, active := false);   -- tandas diarias 00:01
select cron.alter_job(73, active := false);   -- armado intradía

-- 2) reabrir la canilla del espejo de ISIS (que Gestión vuelva a leer lo de ISIS)
--    (o al revés: ponerle un corte). Ver §3.m/§3.ap de SUPABASE-GESTION-VIRGILIO.md
update public."PPP_Web_Config" set valor = null where clave in ('espejo_np_corte_lk','espejo_np_corte_chef');
```

Y del lado del dueño, en los otros proyectos: reactivar los crons de LK (7/10) y Chef (1/2)
que hoy están apagados (`active := true`). Detalle completo en `CLAUDE.md` (sección de la
numeración) y en `docs/SUPABASE-GESTION-VIRGILIO.md`.

---

## 1. Registro de cambios que tocan objetos compartidos / de Producción

### v14.75 (2026-09-10) — 6 writers de Movimientos_Stock pasan `empresa` explícita

**Regla del dueño:** la columna `empresa` se agregó al pipeline para ser la fuente explícita; que
el trigger la adivine es el parche. Para duales sin sufijo ni NP en el ref, el trigger caía en
**'Mixto'** → stock al código base (oculto), ni LK ni CH (la góndola CH de un dual no se reponía).
Se corrigieron los **6 writers** que insertaban en `Movimientos_Stock` sin `empresa`:

- `registrar_baja_racks` → `item.emp` o `Racks_Planimetria.emp` del sector (cierra el gap de
  reposición: bajar un rack CH ahora cae en la góndola CH).
- `racks_plani_ingreso` / `racks_plani_ingreso_nacional` → `p_emp` (ya lo recibían).
- `aceptar_conteo` → `Capacidad_Sector.empresa` del sector contado.
- `anular_modo_op` → `Control_Modo_OP.linea`.
- `faltante_resolver` → empresa del separado/picking de esa tanda+cod (si es inequívoco).

En todas: si no se puede determinar, queda `NULL` → el trigger decide (comportamiento previo).
El trigger `trg_normalizar_empresa_stock` RESPETA la empresa cuando llega != NULL/Mixto (verificado).

- **Objetos compartidos:** las 6 funciones SECURITY DEFINER (las llama el front por nombre).
- **SQL aplicado:** `sql/gv_empresa_en_writers_20260910.sql`.
- **Rollback:** `sql/backups/writers_movimientos_stock_pre_v1462_20260910.sql` (las 3 de racks
  completas; conteo/anular/faltante = quitar `, empresa` del INSERT y el cálculo de `v_emp`).
- **Nota:** no reasigna stock histórico. Al 10/09 no hay stock de duales en 'Mixto' (todo LK/CH),
  pero 438E/439E tienen el 100% atribuido LK (default de migración D1) con la góndola CH en negativo
  → se resuelve con un ajuste manual LK→CH según packaging (decisión del dueño, pendiente).

### v14.69 (2026-09-10) — Guarda anti-doble-generación de OCs + limpieza de duplicados

**Qué se cambió (tabla compartida `Ordenes_Compra`).**
1. **Datos:** se borraron **109 filas duplicadas** del `2026-09-09`. El generador se corrió DOS
   veces ese día (14:25 y 15:40) → cada línea quedó insertada dos veces (todas las OCs mostraban
   cada artículo repetido, con el pedido al doble). Se dejó la 1ra corrida (id más chico por
   `fecha+proveedor+codigo`); ninguna duplicada tenía recepción (`cantidad_recibida=0`).
   **Backup:** `public."GV_Backup_OC_dup_20260909"` (224 filas, las del día completo antes de borrar).
2. **Backend:** nueva RPC `public.gv_oc_generar_pendientes(jsonb)` (SECURITY DEFINER, grant sólo
   `authenticated`). El front (`index.html` `ocgGenerar`) ya no hace POST crudo a `Ordenes_Compra`;
   llama a la RPC, que es **idempotente por día**: por `(fecha,proveedor,codigo)` borra la línea
   pendiente SIN recepción y recién ahí inserta → re-generar refresca, no duplica. Las líneas
   recibidas/cerradas no se tocan ni se re-insertan.

**Impacto medido.** Antes del fix: `select count(*) from "Ordenes_Compra" where fecha='2026-09-09'`
= 224 (109 grupos duplicados). Después: 115 filas, `grupos_dup_totales = 0` en toda la tabla.

**Rollback.**
```sql
-- 1) restaurar los duplicados borrados (si hiciera falta)
insert into public."Ordenes_Compra"
  select * from public."GV_Backup_OC_dup_20260909" b
  where not exists (select 1 from public."Ordenes_Compra" o where o.id = b.id);
-- 2) sacar la guarda backend
drop function if exists public.gv_oc_generar_pendientes(jsonb);
-- 3) revertir el front: ocgGenerar vuelve al POST a SUPABASE_OC_ENDPOINT (commit v14.69).
-- backup table: drop table public."GV_Backup_OC_dup_20260909";  -- recién cuando esté OK
```
SQL fuente: `sql/gv_oc_generar_pendientes_v1469.sql`.

### v14.44 (2026-09-08) — `precios_venta` pasó a ser SÓLO LK

**Qué se cambió.** La Edge Function `sync-precios-venta` **dejó de mergear** LK+Chef en
`precios_venta` (antes: "si el código coincide, Chef gana"). Ahora `precios_venta` = **sólo LK**
y `precios_venta_chef` = **sólo Chef**.

**Qué de Producción se ve afectado.** Producción tiene vistas **sin** `gv_` que leen
`precios_venta` **sin enrutar por empresa**:
- `vista_facturacion_neto_items` / `vista_facturacion_neto`
- `vista_cruce_facturacion`
- `vista_facturable_anticipado`
- `vista_plata_perdida`

Estas ahora **valúan las NP de Chef contra la lista de LK** (y pierden los códigos
Chef-exclusivos que quedaron viejos en `precios_venta`). Para **Gestión** no hay problema: su
cadena `gv_` sí enruta por empresa (v14.44). El impacto es **sólo** en esas vistas de Producción.

**Rollback exacto** (volver a la lista mezclada con "Chef gana"):
1. En `supabase/functions/sync-precios-venta/index.ts`, volver el bloque 3 a un solo `Map`
   que cargue LK y después Chef (Chef pisa), y hacer `upsert('precios_venta', …)` con eso;
   quitar el `upsert('precios_venta_chef', …)`. (El commit v14.44 tiene el diff exacto.)
2. Redeploy: `mcp Supabase deploy_edge_function` (o Dashboard), `verify_jwt = false`.
3. Re-correr: `select net.http_post(url:='https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/sync-precios-venta', headers:='{"Content-Type":"application/json"}'::jsonb, body:='{}'::jsonb);`
4. (Opcional) restaurar el snapshot previo: `public.gv_bkp_precios_venta_20260908` (337 filas) /
   `gv_bkp_precios_venta_chef_20260908` (101).

**Nota:** el enrutado por empresa que sí conviene (para que Producción tampoco se rompa) sería
agregarles a esas 4 vistas de Producción la misma rama que `gv_vista_facturacion_neto_items`
(LK→`precios_venta`, Chef→`precios_venta_chef`). No se hizo porque Producción no se usa; queda
como opción si algún día se la quiere dejar consistente en vez de revertir.

### v14.51 (2026-09-08) — columna `gv_app` en `Registros_Produccion_Virgilio`

**Qué se cambió.** `alter table public."Registros_Produccion_Virgilio" add column gv_app text;` —
nullable, sin default, sin backfill. Gestión manda `gv_app = 'gestion@' + APP_VERSION` en sus dos
caminos de escritura (`trySendOneReport` y `bulkSendDayReplay`); Producción **no la manda**, así que
**NULL = Producción**. Sirve para saber desde qué app trabajó cada operario, que hasta ahora no se
podía: la tabla es la misma para las dos y no guardaba ni URL, ni user_agent, ni versión.

**Qué de Producción se ve afectado.** Nada. Verificado antes de correrlo, no después:
- Producción **no hace `select *`** sobre la tabla — sus referencias en `index.html`,
  `productividad.html`, `recepcion.js` y `sw.js` nombran columnas. El único `SELECT *` del repo está
  **comentado**, en un SQL de rollback del 2026-08-13.
- Los **grants son a nivel tabla** (`anon`/`authenticated` con INSERT, sin ACL por columna) → la
  columna nueva queda cubierta sola, no hizo falta ningún grant.
- La policy de INSERT es `insert_all` con **`with_check = true`** — no enumera columnas, así que no
  rechaza el payload nuevo.
- Sin trigger (habría corrido también para Producción) y sin tocar ninguna fila existente.

Si Producción volviera a usarse, sigue insertando igual: sus filas quedan con `gv_app` NULL, que es
justamente lo que las identifica.

**Rollback:** `alter table public."Registros_Produccion_Virgilio" drop column gv_app;` + sacar
`gv_app` de los dos payloads de `index.html`. Sin pérdida de datos operativos (la columna es sólo
procedencia). `sql/gv_app_sello_eventos_v1451.sql`, §3.bl de `SUPABASE-GESTION-VIRGILIO.md`,
regresión `tests/gv-app-tag.cjs`.

### v14.62 (2026-09-10) — columna `gv_nombre_prueba` en `Registros_Produccion_Virgilio` (legajo 600 = entrevistas)

**Qué se cambió.** `alter table public."Registros_Produccion_Virgilio" add column gv_nombre_prueba text;` —
nullable, sin default, sin backfill (mismo patrón exacto que `gv_app`). El legajo **600** es el legajo
COMPARTIDO de entrevistas/prueba: cada candidato entra con 600, registra su nombre y hace la prueba
**real** (persiste eventos y descuenta stock, igual que un operario — **no** es como el 0/1, que no
persisten). Para saber quién hizo cada prueba, Gestión manda `gv_nombre_prueba = <nombre del candidato>`
en sus dos caminos de escritura (`trySendOneReport` y `bulkSendDayReplay`) **sólo** cuando el legajo es
600; en cualquier otro evento va NULL. Se agregó también la función `es_legajo_entrevista(text)` (fuente
de verdad de "cuál es el legajo de entrevista", hoy 600) y la vista supervisor `gv_pruebas_entrevistas`.

**Qué de Producción se ve afectado.** Nada, por lo mismo que `gv_app` (verificado antes, no después):
grants a nivel tabla → la columna queda cubierta sola; policy `insert_all` con `with_check = true` → no
enumera columnas; sin trigger; sin tocar filas existentes; Producción no hace `select *`. `es_legajo_entrevista`
y `gv_pruebas_entrevistas` son objetos **nuevos** con prefijo `gv_`/`es_legajo_` que Producción no referencia.

**Rollback:**
```sql
alter table public."Registros_Produccion_Virgilio" drop column gv_nombre_prueba;
drop view if exists public.gv_pruebas_entrevistas;
drop function if exists public.es_legajo_entrevista(text);
```
\+ sacar `gv_nombre_prueba`/`esLegajoEntrevista`/`promptNombreEntrevista` de `index.html`. Sin pérdida de
datos operativos. `sql/gv_nombre_prueba_entrevistas_v1462.sql`, `sql/gv_pruebas_entrevistas_v1462.sql`,
regresión `tests/entrevista-legajo600.cjs`.

### v14.48 (2026-09-08) — columna `gv_empresa` generada en `Entregas_Virgilio`

**Qué se cambió.** `alter table public."Entregas_Virgilio" add column gv_empresa text generated
always as (public.gv_empresa_de_np_texto(np)) stored;` — columna GENERADA STORED, read-only.

**Qué de Producción se ve afectado.** Nada: es una columna nueva que ningún writer escribe y que
Producción no selecciona. Se computa sola para las filas existentes y futuras. (El `alter` de una
columna generada reescribe la tabla una vez — 9.8k filas, instantáneo.)

**Rollback:** `alter table public."Entregas_Virgilio" drop column gv_empresa;` (sin pérdida de datos:
la columna es derivada). `sql/entregas_virgilio_gv_empresa.sql`.

### v14.54 (2026-09-09) — `gv_cod_stock` normaliza el código en las vistas de proyección

**Qué se cambió.** `create or replace` de 3 vistas COMPARTIDAS (`vista_venta_mensual`,
`vista_recepcion_mensual`, `vista_stock_vs_pedidos`) para que normalicen el código con la nueva
función `public.gv_cod_stock` (pela `·celda`, sufijo empresa, ceros y la **L**). Antes venta y
demanda no pelaban la L → `439EL` era un SKU fantasma en abastecimiento/OCs. `security_invoker=true`
preservado; sólo cambia la normalización del código, columnas/estructura idénticas.

**Qué de Producción se ve afectado.** Mejora para las dos: la proyección deja de partir un artículo
en `439E`/`439EL`. No toca datos (son vistas). Medido: 0 códigos L en las 5 vistas de proyección;
`439E` consolidó la demanda que iba a `439EL`.

**Rollback:** correr `sql/backups/proyeccion_views_20260909_pre_v1454.sql` (restaura los 3 defs
viejos) y `drop function public.gv_cod_stock(text);`. `sql/gv_cod_stock.sql`.

### v14.47 (2026-09-08) — `sync-precios-venta` RECONCILIA (borra lo que no está en el catálogo)

**Qué se cambió.** La Edge Function ahora, después del upsert, borra de `precios_venta` y
`precios_venta_chef` las filas cuyo `actualizado < nowIso` (las que no están en el catálogo de
origen). Sacó las 115 filas viejas de Chef que quedaban en `precios_venta` (337 → 222).

**Qué de Producción se ve afectado.** Las vistas de Producción que leen `precios_venta` sin
enrutar (ver v14.44) ahora, para un código que **no** es de LK (p.ej. 613, propio de Chef), lo
ven como **sin precio** en vez de con el valor viejo de Chef. Es lo correcto (ese código no es de
LK), pero cambia el número para esas vistas. Gestión no se ve afectada (usa `precios_venta_chef`
para Chef).

**Rollback:** restaurar las filas viejas desde el backup
`public.gv_bkp_precios_venta_20260908_pre_reconcile` (337 filas):
`insert into precios_venta select * from public.gv_bkp_precios_venta_20260908_pre_reconcile on conflict (cod) do update set precio_unit=excluded.precio_unit, actualizado=excluded.actualizado;`
y volver la función a la versión sin `reconcileStale` (commit anterior). Pero ojo: la próxima
corrida del cron volvería a reconciliar salvo que también se revierta la función.

### v14.45 (2026-09-08) — `sync-precios-venta` cada 15 min (cron 66)

**Qué se cambió.** Cron 66 pasó de diario (06:00 ART, guarda de 24 h) a `*/15 * * * *`, sin guarda.
**Impacto en Producción:** ninguno funcional (sólo refresca más seguido las mismas tablas).
**Rollback:** `select cron.alter_job(66, schedule := '0 9 * * *', command := <bloque do/begin con la guarda de 24 h>);` (el bloque está en `sql/sync_precios_venta.sql`).

---

## 1.z — OC_Maximos: sacar los E importados ('Racks') del flujo de OC (v14.60, 2026-09-09)

**Regla del dueño (09/09):** *"Todos los de E son importados. No se piden por OC salvo por los de
Danica."* En `OC_Maximos`, **`Racks` NO es un proveedor** — es donde se estiba lo importado. Los
**78 códigos E** con `proveedor='Racks'` entraban al flujo de OC (`tiene_prov_real` ⇒ `maximo`/
`a_pedir` ⇒ generador `ocs-auto-*` + `vista_generador_oc`). Se les sacó el proveedor. **Garcia (11)
y Log/ Fabr (9) son proveedores REALES y quedan** (Danica ≈ Garcia, según el dueño).

- **Objeto compartido tocado:** `public."OC_Maximos"` (config, la lee Producción también).
- **Cambio:** `update public."OC_Maximos" set proveedor = null where btrim(coalesce(proveedor,''))='Racks';` (78 filas, todas `cod ~* 'E'`, 0 no-E, sin `proveedor2='Racks'`). No se tocó `activo` (no los marca discontinuos) ni Garcia/Log-Fabr.
- **Impacto medido:** después, esas 78 → `tiene_prov_real=false` ⇒ fuera del generador (`where activo and total>0 and tiene_prov_real`) y del INSERT (exige `proveedor`). El generador real (`vista_generador_oc.total`) ya daba 0 para ellas. Nota: `vista_stock_procesada.a_pedir` sigue mostrando un número por proyección en la fila BASE huérfana (ej. 809E=283), pero el abast tab ya saltea `es_importado` y no genera OC.
- **Rollback exacto:** `sql/backups/oc_maximos_racks_a_null_20260909.sql` (re-set `proveedor='Racks'` en los 78 códigos) + `refresh materialized view public.vista_stock_procesada;`.

---

### v14.59 (2026-09-09) — descontar la OC al recibir (`Ordenes_Compra`)

**Qué se cambió.** Nueva función `public.gv_oc_aplicar_recepcion(text, jsonb)` (SECURITY DEFINER,
grant a anon/authenticated) que el front llama tras cada recepción exitosa y hace `UPDATE` de
`public."Ordenes_Compra"` (`cantidad_recibida` +=, `estado`='recibida' al completar, `fecha_entrega_real`).
Antes esa columna no se tocaba nunca (0 de 729 OCs con `cantidad_recibida > 0`).
**Impacto en Producción:** `Ordenes_Compra` la puebla `generar_ocs_automaticas` (objeto de Gestión);
Producción ya no se usa. El cambio sólo hace que las OCs reflejen lo recibido (que es lo correcto).
No hay trigger: la escritura sale del front vía la RPC, no corre sola para nadie más.
**Backup previo:** `public."GV_Backup_Ordenes_Compra_20260909"` (729 filas, snapshot completo).
**Rollback:**
```sql
-- 1) dejar de descontar
drop function if exists public.gv_oc_aplicar_recepcion(text, jsonb);
-- 2) restaurar cantidad_recibida/estado/fecha_entrega_real desde el snapshot
update public."Ordenes_Compra" o
   set cantidad_recibida   = b.cantidad_recibida,
       estado              = b.estado,
       fecha_entrega_real  = b.fecha_entrega_real
  from public."GV_Backup_Ordenes_Compra_20260909" b
 where b.id = o.id;
```
(Y sacar la llamada `supabase.rpc("gv_oc_aplicar_recepcion", …)` de `recepcion.js`.)

---

### v14.60 (2026-09-09) — "la nueva pisa la vieja" (OC vigente = la de fecha más nueva)

**Qué se cambió.** Dos funciones, para que una OC nueva del mismo proveedor+código deje muerta a
la vieja (que no reaparezca al completar la nueva):
- `public.oc_vigentes_por_proveedor(text)` — `create or replace`. En `oc_filtrada` el `WHERE` pasó de
  `estado <> 'recibida' AND (cantidad - cantidad_recibida) > 0` a `lower(estado) NOT IN ('cerrada','anulada')`
  (ahora las 'recibida' cuentan para `max_fecha`; el `HAVING pend>0` saca las completas).
- `public.gv_oc_aplicar_recepcion(text, jsonb)` — mismo criterio: fija `max_fecha` incluyendo 'recibida'
  y sólo descuenta esa fecha.
**Impacto en Producción:** `oc_vigentes_por_proveedor` la usa sólo el módulo de recepción de Gestión
(`recepcion.js`), no Producción. Sin cambio de display hoy (0 OCs 'recibida'); sólo cambia el
comportamiento post-recepción. Efecto lateral: una OC 'cerrada' ya no figura como vigente (antes sí).
**Rollback:** volver a poner en `oc_filtrada` de `oc_vigentes_por_proveedor` el `WHERE`
`... AND lower(coalesce(estado,'')) <> 'recibida' AND (cantidad - coalesce(cantidad_recibida,0)) > 0 ...`
(definición previa completa en el git, commit anterior a v14.60), y en `gv_oc_aplicar_recepcion` el
`WHERE ... <> 'recibida' AND (cantidad - coalesce(cantidad_recibida,0)) > 0`. Datos: restore desde
`GV_Backup_Ordenes_Compra_20260909` (bloque de v14.59 arriba). SQL vigente: `sql/oc_nueva_pisa_vieja_v1460.sql`.

---

### 2026-09-10 — `ventas_mensuales_cod` manda un header secreto a LK (cierre de leak en LK)

**Qué se cambió.** `public.ventas_mensuales_cod(text,int)` (la usa el popup "de dónde sale la
proyección" en `index.html`) ahora manda un header `x-feed-secret` en su llamada `http()` a LK
(`fn_ventas_mensuales_virgilio`). Motivo: esa función de LK estaba abierta a cualquiera con la anon
key pública (leak de volúmenes mensuales por artículo). LK ahora exige ese header; sin él devuelve
`[]`. El secreto vive en `app_settings.virgilio_feed_secret` de **LK** y está embebido como
constante `s` en esta función (mismo nivel que la anon key `k` que ya estaba hardcodeada acá).

**Impacto en Producción:** ninguno — Producción no usa ese popup (es del panel comercial/LK). La
función devuelve lo mismo para el llamador legítimo (verificado: `ventas_mensuales_cod('505',6)` →
6 meses OK). Es un `create or replace` de una función compartida, permitido bajo la regla del
2026-09-08 (Producción ya no se usa), anotado acá como corresponde.

**Rollback:** `create or replace` de `ventas_mensuales_cod` sacando el tercer header
`public.http_header('x-feed-secret', s)` y la constante `s` (definición previa en git / en el runbook
`sql/pendiente_8436_http_ssrf_runbook.sql`). Del lado LK, sacar el CTE `gate` de
`fn_ventas_mensuales_virgilio`. Detalle completo en el repo GestOpClientes,
`docs/PENDIENTES-SEGURIDAD-2026-09-09.md`.

---

### 1.x — idea 4259 (2026-09-11): completar desde "a guardar" en el picking (evento PKA)

**Qué toca de compartido:** la tabla `public."Movimientos_Stock"` (agrega filas nuevas con
`tipo='aguardar'` y un índice parcial nuevo) y agrega objetos nuevos con prefijo `gv_`. **No**
modifica filas/objetos existentes de Producción. Producción Virgilio no emite eventos `PKA`, así
que nada de esto se dispara para su app.

**Objetos nuevos:**
- índice `mov_stock_aguardar_dedup` (parcial, `WHERE tipo='aguardar'`) en `Movimientos_Stock`.
- función `public.gv_reconciliar_aguardar()` (SECURITY DEFINER, revocada a anon/authenticated).
- cron `gv-reconciliar-aguardar` (jobid 81, `*/2 * * * *`).
- evento nuevo `opcion='PKA'` en `Registros_Produccion_Virgilio` (texto `TANDA|ART|N`).
- filas nuevas en `Movimientos_Stock` con `tipo='aguardar'` (deps `a_guardar` −N / `separar_pedidos` +N).

**Rollback exacto:**
```sql
select cron.unschedule('gv-reconciliar-aguardar');
drop function if exists public.gv_reconciliar_aguardar();
-- deshacer los movimientos que ya escribió (vuelve a_guardar/separar_pedidos a como estaban):
delete from public."Movimientos_Stock" where tipo='aguardar';
drop index if exists public.mov_stock_aguardar_dedup;
-- (opcional) borrar los eventos PKA:
-- delete from public."Registros_Produccion_Virgilio" where opcion='PKA';
```
Del lado del front (repo Gestión, `index.html` v15.38): se reactiva el pop-up viejo cambiando
`if (false && enDeposito.length)` por `if (enDeposito.length)` y se quita el paso nuevo
(`pkAGuardarCardHtml()` del cierre del picking). Detalle en SUPABASE-GESTION §3.

---

## 2. Backups vigentes (para restore puntual)

| backup | qué guarda | fecha |
|---|---|---|
| `public.GV_Backup_Ordenes_Compra_20260909` | `Ordenes_Compra` completa antes de descontar al recibir (729 filas) | 2026-09-09 |
| `public.gv_bkp_precios_venta_20260908` | `precios_venta` antes del split (337 filas, lista mezclada) | 2026-09-08 |
| `public.gv_bkp_precios_venta_chef_20260908` | `precios_venta_chef` antes del re-sync (101 filas) | 2026-09-08 |
| `public.gv_bkp_precios_venta_20260908_pre_reconcile` | `precios_venta` antes de reconciliar (337, con las 115 viejas) | 2026-09-08 |
| `public.gv_bkp_precios_venta_chef_20260908_pre_reconcile` | `precios_venta_chef` antes de reconciliar (101) | 2026-09-08 |

> Estos backups son tablas en `public`. Borrarlos cuando el cambio esté consolidado y ya no se
> quiera el rollback (`drop table public.gv_bkp_precios_venta_20260908;` …).

## Baches de importación — v14.94 (2026-09-11)

**Objeto compartido tocado:** `public."Importados"` (columnas `pedido_curso`, `reingreso_est`) — ahora
las escribe `gv_importados_resync()` como mirror de la tabla nueva `GV_Importados_Baches`. Objetos
nuevos (no de Producción): tabla `GV_Importados_Baches` + RPCs `gv_importado_bache_*` /
`gv_importados_resync` / `gv_importado_baches`.

**Impacto medido:** backfill = 69 filas / 360.952 u; el mirror da los MISMOS valores que había (no cambia
`enCurso` ni el feed a LK). Prueba 934E: 2 baches → reingreso = fecha más cercana; anular restaura.

**Backup:** `public."GV_Importados_curso_bkp_20260911"` (id, cod_art, marca, pedido_curso, reingreso_est).

**Rollback exacto:**
```sql
update public."Importados" im
set pedido_curso = b.pedido_curso, reingreso_est = b.reingreso_est
from public."GV_Importados_curso_bkp_20260911" b where b.id = im.id;
drop function if exists public.gv_importado_baches(bigint);
drop function if exists public.gv_importado_bache_borrar(bigint);
drop function if exists public.gv_importado_bache_editar(bigint,numeric,date,boolean);
drop function if exists public.gv_importado_bache_llego(bigint,numeric,text);
drop function if exists public.gv_importado_bache_add(bigint,numeric,date,text);
drop function if exists public.gv_importados_resync(bigint);
drop table if exists public."GV_Importados_Baches";
```
Y revertir `index.html` (el "Cargar pedido ya hecho" volvía a `importados_set_curso` + PATCH `reingreso_est`).

## 437EL / 438EL separados — v15.01 (2026-09-11)

**Objetos compartidos tocados:** `Importados` (2 filas: `cod_art` 437E→437EL id 69, 438E→438EL id 65),
`Importados_Volumen` (+2 filas), vista `v_importados_ordenes` (replace: normalización `gv_cod_stock`,
proy sólo códigos base), función `lk_reingresos_feed` (replace: sólo marca ≠ CH).

**Impacto medido:** ver `docs/SUPABASE-GESTION-VIRGILIO.md` §3.bm (proy: sólo 437EL/438EL; stock:
438EL −384 u, 439E −186 u por entregas `…EL`).

**Rollback exacto:** bloque ROLLBACK al final de `sql/gv_importados_lk_ch_separados_v1501.sql`
(restaurar `cod_art` desde `GV_Importados_bkp_437_438_20260911`, borrar volumen `…EL`, y volver la
vista/feed a `ltrim(upper(btrim(x)),'0')` sin filtros).

## Limpieza Importados — v15.05 (2026-09-11)

`Importados`: id 129 (809E) `marca LK→CH`, `principal false→true`, descripción "Corta queso x12";
**delete** de 11 filas `principal=false` (copias exactas) y 2 filas de `GV_Importados_Baches`.
Backups: `GV_Importados_bkp_809E_20260911`, `GV_Importados_bkp_copias_20260911`,
`GV_Importados_Baches_bkp_copias_20260911`. Rollback = reinsertar desde los backups (mismas columnas,
sin `_bkp_at`) y `update "Importados" set marca='LK', principal=false where id=129`. Detalle §3.bm.1.

## PI Fujian cargado + 439EL/439E — v15.06 (2026-09-11)

`GV_Importados_Baches`: 6 baches nuevos (`creado_por = 'PI HT26-06-600-R1'`, fecha 2026-11-01). `Importados`:
id 68 `cod_art 439E→439EL`; alta id 164 (439E·CH). `Importados_Volumen`: alta 439EL (copia de 439E).
Backups `GV_Importados_bkp_439_20260911`, `GV_Importados_Volumen_bkp_439_20260911`. Rollback: borrar los 6
baches + `gv_importados_resync` de 63/65/66/67/68/164, `delete "Importados" id=164`, `update id=68 cod_art='439E'`,
`delete "Importados_Volumen" cod='439EL'`. Detalle §3.bm.2.

## FOB 825·CH según PI Fujian — v15.07 (2026-09-11)

`Importados` id 76 (825·CH): `fob_uni 0.5 → 0.25`. Backup `GV_Importados_bkp_fob825_20260911`.
Rollback: `update "Importados" set fob_uni = 0.5 where id = 76`. Detalle §3.bm.2.

## uni × master según PI Fujian — v15.09 (2026-09-11)

`Importados_Volumen`: 13 filas Fujian (026, 027, 035E, 110, 437E, 437EL, 438E, 438EL, 439E, 439EL, 440E, 824,
825) con inner/master/medidas/m³/fuente del PI. Backup `GV_Importados_Volumen_bkp_pi_fujian_20260911`.
Rollback: `update "Importados_Volumen" v set (uni_inner,uni_master,largo_cm,ancho_cm,alto_cm,m3_master,fuente) =
(b.uni_inner,b.uni_master,b.largo_cm,b.ancho_cm,b.alto_cm,b.m3_master,b.fuente) from
"GV_Importados_Volumen_bkp_pi_fujian_20260911" b where b.cod = v.cod`. Detalle §3.bm.2.

## Stock de Importados sincronizado + ventas por empresa — v15.11 (2026-09-11)

`v_importados_ordenes` recreada (ventas por `gv_empresa`; sin Cervantes). `Importados_Mov_Stock`: +98 filas
`ref like 'sync stock depósito 2026-09-11%'`. `Importados` ids 78/144/154: `uni_x_caja` al maestro. Backups
`GV_Importados_Mov_Stock_bkp_20260911`, `GV_Importados_bkp_uxc_20260911`. Rollback: borrar las 98 filas por `ref`,
vista de `sql/gv_importados_lk_ch_separados_v1501.sql`, uni×caja desde el backup. Detalle §3.bm.3.

## Fechas de baches Becky / Kangli llegado — v15.12 (2026-09-11)

`GV_Importados_Baches`: 26 de Becky `fecha_reingreso → 2026-11-15`; 8 de Kangli `estado → llegado`,
`unidades_llegadas = unidades` (sin movimiento de stock). Backup `GV_Importados_Baches_bkp_fechas_20260911`.
Rollback: restaurar fecha/estado/unidades_llegadas desde el backup por `id` + `gv_importados_resync`. Detalle §3.bm.4.

## PI Ownland OL-10139 + embarque de julio cerrado — v15.13 (2026-09-11)

`GV_Importados_Baches`: +13 (`creado_por='PI OL-10139'`), 7 del backfill → `llegado` sin stock. `Importados`: alta id 165
(119E), id 129 `fob_uni 0.7→0.47`. `Importados_Volumen`: alta 119E; 729E y 877E al PI. `Importados_Mov_Stock`: +1 `inicial` 0
(119E). Backups `GV_Importados_Baches_bkp_ownland_20260911`, `GV_Importados_bkp_ownland_20260911`,
`GV_Importados_Volumen_bkp_ownland_20260911`. Detalle y rollback §3.bm.5.

## PI Hugo Wong NY26-031438 + embarque de julio cerrado — v15.15 (2026-09-11)

`GV_Importados_Baches`: +11 (`creado_por='PI NY26-031438'`), 7 del backfill → `llegado` sin stock. `Importados` ids 81/123
FOB al PI. `Importados_Volumen` 727E master 144 + inner; 539E/540E inner. Backups `GV_Importados_Baches_bkp_hugowong_20260911`,
`GV_Importados_bkp_hugowong_20260911`, `GV_Importados_Volumen_bkp_hugowong_20260911`. Detalle y rollback §3.bm.7.

## PI Zhixin BX260722D — v15.17 (2026-09-11)

`GV_Importados_Baches`: +5 (`creado_por='PI BX260722D'`, fecha 2026-11-29). `Importados` ids 156–160 FOB al PI.
`Importados_Volumen` 566E/582E/583E/584E/590E al PI. Backups `GV_Importados_bkp_zhixin_20260911`,
`GV_Importados_Volumen_bkp_zhixin_20260911`. Detalle y rollback §3.bm.9.

## Becky 2.º pedido CI B260601 — v15.20 (2026-09-11)

`GV_Importados_Baches`: 19 del backfill editados (unidades − CI, fecha 29/09) + 19 nuevos (`creado_por='CI B260601'`, 15/11).
`Importados`: FOB de 12 filas al CI. Backups `GV_Importados_Baches_bkp_becky_20260911`, `GV_Importados_bkp_becky_fob_20260911`.
Detalle y rollback §3.bm.12.

## Becky: baches = PI B260601 y PI B260601-2 — v15.21 (2026-09-11)

`GV_Importados_Baches` (Becky): 19 del 1.º ajustados al PI + 19 duplicados anulados; 26 del 2.º ajustados al PI, 3 anulados
(945E/994E/999E), 3 nuevos (404E, 601E, 989E). `Importados`: alta 989E; FOB de 9 filas y `uni_x_caja` de 7 al PI.
`Importados_Mov_Stock`: +1 `inicial` 0 (989E). Backups `GV_Importados_Baches_bkp_becky2_20260911`,
`GV_Importados_bkp_becky2_20260911`. Detalle y rollback §3.bm.13.

## Proyección por empresa para Importados — v15.23 (2026-09-11)

Virgilio: tabla nueva `GV_Proyeccion_Emp`; `v_importados_ordenes` recreada (ya no lee `proyeccion_madre`);
`ventas_mensuales_cod` pasa a 3 args. LK: 3 funciones nuevas + `fn_ventas_mensuales_virgilio` a 3 args + foreign table +
cron `sync-proyeccion-emp-virgilio`. `proyeccion_madre` intacta. Rollback en §3.bm.15.

## Proyección: variantes L + familias; vista_stock_procesada por empresa — v15.24 (2026-09-11)

`v_importados_ordenes` recreada (CTE `pe`: sum + `Equivalencias_Familia`). `vista_stock_procesada` (materializada) y
`Stock_Saldos` dropeadas y recreadas con el CTE `proy` ampliado; grants idénticos. Backup de definiciones y relacl en
`GV_bkp_relacl_vista_stock_procesada_20260911`. Detalle y rollback §3.bm.16.

## Partes: stock de terminados en vista_importados_partes — v15.26 (2026-09-11)

`vista_importados_partes` recreada (`create or replace`, + columna `stock_term_uni`, security_invoker repuesto) y una
fila nueva en `Importados_Partes_Map` (505C → 114; backup `GV_Importados_Partes_Map_bkp_20260911`). Sólo la lee
Gestión (`ocgFetchImportados`). Rollback en `sql/gv_importados_partes_stock_terminados_v1526.sql` / §3.bm.18.

## Insumos como stock del módulo de importados — v15.27 (2026-09-11)

Tabla nueva `GV_Importados_Insumo_Map`, vista nueva `gv_importados_stock_insumos` y `v_importados_ordenes` recreada
(+ `stock_insumos`, `es_parte`, `stock_total`; el resto idéntico). Def anterior en `GV_bkp_def_v_importados_ordenes_20260911`.
Sólo lo lee Gestión. Rollback en `sql/gv_importados_stock_insumos_v1527.sql` / §3.bm.19.

## 323ES pool + GV_Importados_Alias — v15.29 (2026-09-11)

Tabla nueva `GV_Importados_Alias` (RLS, lectura anon/authenticated); alta 323ES en `Importados` (id 167) y
`Importados_Volumen`; un bache movido de 323E a 323ES (backup `GV_Importados_Baches_bkp_323ES_20260911`). §3.bm.21.

## Corregir códigos: reparto del stock del secundario — v15.66 (2026-09-11)

`create or replace view vista_correcciones_pedido_rich` (objeto de Producción, v10.10): agrega 6 columnas al
final (`sec_pedido_total`, `sec_np_total`, `sec_orden`, `sec_acum_antes`, `sec_disp`, `sec_cubre`); las 14
existentes no cambian de nombre, tipo ni orden. Producción la lee con las 14 viejas → sin impacto. Rollback:
bloque comentado al final de `sql/vista_correcciones_pedido_rich_v1566_reparto_sec.sql`. §3.cj.

## Corregir códigos: la cola pone primero las NP sin pickear — v15.67 (2026-09-11)

`create or replace view vista_correcciones_pedido_rich`: sólo cambia el orden de la ventana (estado → fecha → NP);
mismas 20 columnas. Rollback: re-correr el `create or replace view` de
`sql/vista_correcciones_pedido_rich_v1566_reparto_sec.sql`. §3.cj.1.
## PKC con depósito declarado — v15.41 (2026-09-11)

**Objetos COMPARTIDOS tocados** (los dos con `CREATE OR REPLACE`, misma firma):
`public.reconciliar_pipeline_stock_etapa1()` (la corre el cron **jobid 68**, cada 10 min)
y `public.reconciliar_stock_articulo_rt(text,text)` (la dispara el trigger
`trg_pkc_reconciliar_rt` en cada INSERT de PKC). Las dos, porque si sólo se cambia una el
trigger escribe la adivinanza en cada evento y el cron la corrige 10 min después: flip-flop.

**Qué cambió.** El evento PKC del picking ahora puede traer un 5.º campo
(`TANDA|ART|esp|real|excedente` = cuántas de las `real` cajas salieron del **excedente**).
Cuando viene, las dos funciones **usan ese número**; antes re-derivaban el reparto
góndola/excedente por saldos vivos al reconciliar. Sólo cambió la rama **B (forward)**;
la rama A (histórico, gated por `Stock_Config.etapa1_pkc_desde`) quedó intacta.

**Impacto medido (2026-09-11).** Con los PKC de 4 campos que hay hoy, `tiene_dep = false`
→ `want_exc = picked` → el cálculo es **idéntico al anterior**: se corrió la función con el
código nuevo y las 23.311 filas `tipo='picking'` no se movieron (los 30 renglones nuevos
eran la tanda D67E que se estaba pickeando en vivo). Prueba del camino nuevo con tanda
falsa `ZZDEP1|207|10|10|3` (art 207: excedente 27): dio **excedente −3 / góndola −7 /
separar_pedidos +10**; la lógica vieja daba **excedente −10 / góndola 0**. Con el
interruptor apagado volvió a −10/0. Todo el rastro de prueba borrado y el art 207 volvió a
su saldo original (excedente 27, góndola 133).

**Interruptor (no hace falta rollback para volver atrás):**
```sql
insert into public."Stock_Config"(clave, valor) values ('pkc_deposito_activo','0')
  on conflict (clave) do update set valor='0';   -- vuelve a repartir por saldos
delete from public."Stock_Config" where clave='pkc_deposito_activo';   -- default = prendido
```

**Rollback real** (volver a las definiciones previas): correr entero
`sql/backups/reconciliar_pkc_pre_v1541_20260911.sql`.
Definición nueva: `sql/gv_pkc_deposito_v1541.sql`. Front: `pkTotalesArt` / `pkSendDetail` /
`_pk.excOk` en `index.html`, test `tests/pk-deposito-pkc.cjs`.

---

## La empresa del remito sobrevive hasta la góndola — v15.71 (2026-09-11)

**Objeto COMPARTIDO tocado:** el trigger de recepción sobre `public."Movimientos_Stock"`
(`CREATE OR REPLACE`, misma firma). **Un solo cambio**: si el INSERT ya trae
`empresa IN ('LK','CH')`, se **respeta**; antes se pisaba con `'Mixto'` de forma
incondicional para todo lo que no fuera dual. Los duales siguen resolviéndose igual.

**Objetos NUEVOS (no tocan nada de Producción):** `GV_Lugar`, `GV_Lugar_Item`,
`GV_Lugar_Pendiente`, `gv_ocupacion_lugar`, `gv_saldos_stock_emp`, `gv_norm_sector(text)`.
Todos con prefijo `GV_`/`gv_`, RLS prendida y las vistas con `security_invoker = true`.

**Datos tocados:** backfill de `empresa` sobre las filas de `deposito='a_guardar'`
(1.389 filas, delta 2.572). Quedó **0 en `'Mixto'`**: 1.118 `LK` + 283 `CH`.

**Rollback de los datos:**
```sql
-- el backup tiene la empresa original de cada fila
update public."Movimientos_Stock" m
   set empresa = b.empresa_anterior
  from public."GV_Backup_aguardar_empresa_20260911" b
 where b.id = m.id and m.deposito = 'a_guardar';
```

**Rollback del trigger:** volver a la definición previa (la de la v14.75, que fuerza
`'Mixto'` salvo dual). El archivo nuevo es `sql/gv_empresa_recepcion_mg.sql` y lleva la
definición anterior comentada arriba.

**Rollback de las tablas nuevas:** `drop` en este orden —
`gv_ocupacion_lugar`, `gv_saldos_stock_emp`, `GV_Lugar_Item`, `GV_Lugar_Pendiente`,
`GV_Lugar`, `gv_norm_sector(text)`. Nada más las lee: el front las consulta
best-effort y si no están se comporta como antes (`gvFetchLugares` devuelve vacío y el
input de ubicación deja de validar, no traba el guardado).

**Front:** `stockFetchSaldos`, `pkFetchExcedente`, `_stkGondolaSaldoVivo`, `gvFetchLugares`,
`gvNormSector`, `showMGModal`, `mgConfirmar` en `index.html`.

---

## La empresa sobrevive al picking — v15.73 (2026-09-11)

**Objetos COMPARTIDOS tocados** (los dos con `CREATE OR REPLACE`, misma firma, partiendo
de las definiciones vivas de la v15.41): `public.reconciliar_pipeline_stock_etapa1()`
(cron **jobid 68**, cada 10 min) y `public.reconciliar_stock_articulo_rt(text,text)`
(trigger `trg_pkc_reconciliar_rt` en cada INSERT de PKC).

**Objeto NUEVO:** la vista `public.gv_lugar_articulo` (sector de cada artículo por
empresa, `security_invoker = true`). No la lee nada viejo.

**Qué cambió.** El PKC puede traer un 6.º campo con la **empresa**
(`TANDA|ART|esp|real|excedente|EMPRESA`). Cuando viene, las dos funciones la escriben en
la columna `empresa` en vez de dejar que caiga al `DEFAULT 'Mixto'`. Sólo cambia la rama
**B (forward)**; la rama A (histórico) queda intacta, igual que en la v15.41.

**⚠ El interruptor es un CORTE POR FECHA, no un booleano.** Las filas ya escritas tienen
`empresa = 'Mixto'` y el índice único lleva `coalesce(empresa,'')`: una fila nueva con
`'LK'` **no choca con la vieja** y quedarían las dos → **stock descontado dos veces**. Con
`Stock_Config.pkc_empresa_desde` cada tanda vive entera de un solo lado.

```sql
-- prender (DESPUÉS de publicar el front v15.73)
insert into public."Stock_Config"(clave, valor) values ('pkc_empresa_desde', now()::text)
  on conflict (clave) do update set valor = now()::text;
-- apagar: vuelve todo a 'Mixto' sin tocar código
delete from public."Stock_Config" where clave = 'pkc_empresa_desde';
```

Mientras la fila no exista, el valor es `infinity` y **el comportamiento es idéntico al de
hoy**: se puede desplegar el SQL sin cambiar nada, y prenderlo cuando se quiera.

**Rollback real** (volver a las definiciones previas): correr entero
`sql/backups/reconciliar_pkc_pre_v1541_20260911.sql` — son las mismas dos funciones que ya
respalda la entrada de la v15.41. Y `drop view public.gv_lugar_articulo;`.

**Definición nueva:** `sql/gv_empresa_picking.sql`.
**Front:** `aggEmp` / `empDeClave` / `items[].emp` / el bloque de sector por `gv_lugar_articulo`
/ `pkTotalesArt` / `pkSendDetail` en `index.html`.

## Corregir códigos: `stk` con `group by` (cada NP salía dos veces) — v15.88 (2026-09-11)

`create or replace view vista_correcciones_pedido_rich` (objeto de Producción, v10.10): el CTE `stk`
pasa a `sum(...) … group by 1` sobre `vista_saldos_stock`, que desde la v15.71 devuelve una fila por
(cod_art, empresa) y sin agrupar duplicaba toda la vista. **Mismas 20 columnas**, mismo orden, mismos
tipos → Producción, que la lee con las 14 viejas, sólo ve el saldo correcto (total del código) y una
fila por NP en vez de dos. Rollback: re-correr el `create or replace view` de
`sql/vista_correcciones_pedido_rich_v1567_orden_sin_pickear.sql`. §3.cj.2.
