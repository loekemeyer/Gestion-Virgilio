# Rollback — todo lo que Gestión hizo que afecta a Producción Virgilio

> ⚠ **2026-09-12 — las tablas de backup se mudaron al esquema `zz_backups`.**
> Todos los `public."GV_Backup_…"` / `public."…_bkp_…"` que este archivo cita ahora viven en
> `zz_backups`. Los comandos de rollback de más abajo funcionan igual cambiando el prefijo:
> `public."X"` → `zz_backups."X"`. El índice de lo que se movió está en
> `public."GV_Backups_Indice"`; para volver una a public,
> `alter table zz_backups."X" set schema public;`.


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

### v19.42 (2026-09-17) — `trg_normalizar_empresa_stock`: descarta el NPD "de menos" sin picking (problema 378)

**Qué se tocó:** `public.trg_normalizar_empresa_stock()` (BEFORE INSERT en la tabla compartida
`Movimientos_Stock`). Se agregó un guard: una fila `ajuste` sobre `separar_pedidos`, con
`delta < 0`, `client_id` de NPD (`'npd_…'`) y `ref` = tanda **sin picking** de ese código en
`separar_pedidos`, se **descarta** (`RETURN NULL`). Antes esa fila dejaba Pickeados en negativo
(caso 323E/E03C = −1, único negativo de la base al 17/09).

**Impacto en Producción:** el guard sólo dispara con el `client_id` determinístico del wizard de
armado (`npd_…`) y sólo cuando **no hay picking** de esa (tanda, código) → en ese caso la fila es
un fantasma también para Producción. Cualquier NPD con picking real pasa igual que antes.
Medido: barrido de negativos en `separar_pedidos` = sólo 323E; test en transacción abortada
(ZZPHANTOM sin picking → descartada; 315 con picking → insertada).

**Dato ya escrito:** el −1 de 323E se neutralizó con un `+1` (`client_id`
`fix378_323E_E03C_neutraliza_npd`); el registro NPD de Franco no se tocó. Saldo verificado = 0.

**Rollback:**
```sql
-- 1) trigger: volver a la versión v18.30 (inmediatamente anterior)
\i sql/gv_ajuste_hereda_empresa_v1830.sql   -- o reaplicar esa función a mano
-- 2) dato: sacar el +1 de compensación (deja 323E en -1 de nuevo)
delete from public."Movimientos_Stock" where client_id = 'fix378_323E_E03C_neutraliza_npd';
-- backup del entorno del -1: zz_backups."GV_Backup_323E_sepped_20260917"
```

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

## `gondola_return_check` y `aceptar_conteo`: leían `vista_saldos_stock` sin agrupar — v15.91 (2026-09-11)

**Objetos COMPARTIDOS tocados** (los dos con `CREATE OR REPLACE`, **misma firma**):
`public.gondola_return_check(jsonb)` y `public.aceptar_conteo(bigint, text)`. Único cambio: el
saldo se lee con `sum(...)` / `group by` porque `vista_saldos_stock` devuelve una fila por
(cod_art, empresa) desde la v15.71 (292 códigos con dos filas). Mismo tipo de retorno, mismas
columnas: para Producción sólo cambia que el número que ve es el **total** del código y que
`gondola_return_check` devuelve una fila por código en vez de dos.

**Rollback exacto:** correr `sql/backups/funciones_vista_saldos_stock_20260911_pre_v1589.sql`
(trae las dos definiciones tal cual estaban). **Definición nueva:** `sql/gv_saldos_group_by_funciones_v1589.sql`. §3.cj.3.

## v15.92 (2026-09-11) — `entregas_virgilio_dedup()`: la clave de dedup deja de mirar la TANDA

**Objeto compartido tocado:** `public.entregas_virgilio_dedup()` (trigger BEFORE INSERT de
`public."Entregas_Virgilio"`, tabla que también escribía Producción).

**Por qué:** un pedido reprogramado a otra tanda y vuelto a armar se grababa entero de nuevo y
movía el stock dos veces. La clave `np|tanda|cod_art` no lo veía porque la tanda era otra.
4 NP afectadas (98532, 98533, 98490, 98583), 43 filas, 57 cajas contadas por dos.

**Qué cambia:** clave `np|cod_art` (las tres cantidades siguen en el `EXISTS`). Un rearmado
idéntico en otra tanda se descarta; un agregado con otra cantidad sigue entrando.

**Impacto medido:** `select count(*) from public."Entregas_Virgilio"` no cambia por el trigger
(sólo filtra inserts futuros). Antes/después del fix, ninguna NP queda con Entregas en dos
tandas nombradas distintas.

**Rollback exacto:** `sql/entregas_virgilio_dedup_v1592.sql` (sección ROLLBACK al principio del
archivo): volver a `np|tanda|cod_art` + `and coalesce(e.tanda,'') = coalesce(new.tanda,'')`.
Datos: `insert into public."Entregas_Virgilio" select * from public."GV_Backup_Entregas_Dup_20260911";`
y `delete from public."Movimientos_Stock" where tipo='ajuste' and ref like 'reversa armado duplicado%';`

## v16.04 (2026-09-12) — el módulo de importados pasa a leer el STOCK REAL (sin tocar `v_importados_ordenes`)

**Objeto compartido tocado:** NINGUNO. Se anota igual porque el cambio nace de un objeto que
**sí** usa Producción y por eso NO se tocó.

**Qué usa Producción:** `v_importados_ordenes` se lee por REST con la anon key desde
`index.html:12022` del repo `loekemeyer/Produccion-Virgilio`, e `Importados_Mov_Stock` recibe
inserts vía la RPC `importados_marcar_llegada` (`sql/importados_pedidos_rpc.sql:56`). Las dos
**quedan exactamente como estaban**.

**Qué se agregó (objetos nuevos, prefijo `gv_`, `security_invoker = true`):**

- `public.gv_importados_stock_dep` — stock real del depósito por código normalizado
  (`gv_cod_stock`) y empresa, en cajas. Misma suma de depósitos que
  `vista_stock_procesada.stock_total` (terminado + excedente + separar_pedidos + a_facturar +
  a_guardar + racks + racks_ch + para_envasar).
- `public.gv_importados_ordenes` — copia de `v_importados_ordenes` con `stock_actual` sacado de
  esa vista en lugar del libro propio `Importados_Mov_Stock`. Agrega `stock_cajas`.

Gestión (`index.html`, `SUPABASE_IMPORTADOS_OC_ENDPOINT`) apunta a la vista nueva; Producción
sigue leyendo la vieja.

**Impacto medido (12/09/2026, 154 filas `principal and activo`):** 122 sin cambio, 32 cambiaron.
Las dos grandes son PARTES y **no cambian el resultado**: 505C `stock_actual` 262.400 → 0 y
1000900 68.000 → 0, pero su `stock_total` sigue siendo el del depósito de insumos (130.000 y
107.500) porque para una parte manda el insumo. 026 +2.520 u y 027 +1.272 u (antes no cruzaban
contra el depósito). Las otras 28 son de 8 a 192 unidades.

**Rollback exacto:** en `index.html`, volver
`SUPABASE_IMPORTADOS_OC_ENDPOINT` a `/rest/v1/v_importados_ordenes`. Opcional:
`drop view if exists public.gv_importados_ordenes;` y
`drop view if exists public.gv_importados_stock_dep;`. SQL completo en
`sql/gv_importados_stock_real_v1604.sql`.

## v16.08 (2026-09-12) — `vista_saldos_stock` deja de emitir el mismo `cod_art` dos veces

**Objeto compartido tocado:** `public.vista_saldos_stock` (`create or replace`, mismas columnas,
mismo orden, mismos tipos). La lee Producción Virgilio (`sql/generar_reporte_agentes_v2.sql`,
`notificar_conteo_gondola`) y media docena de pantallas de Gestión.

**Por qué se tocó (era un incendio):** el cron 55
(`REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada`, cada 2 min) venía **fallando
desde el 11/09 14:44 ART** con `duplicate key value violates unique constraint
"idx_vista_stock_procesada_cod" — Key (cod)=(547) already exists`. La materializada quedó con el
snapshot de las 14:44 y **la pantalla de Stock mostró datos de 10 horas atrás mientras los
operarios pickeaban**.

**La causa:** la vista agrupaba por `(ckey, empresa)` pero sólo metía el sufijo de empresa dentro
del `cod_art` cuando el código está en `codigos_duales`. Un código **no dual** con movimientos
estampados `'LK'`/`'CH'` **y** otros `'Mixto'` salía **dos veces con el mismo `cod_art`**. Al
12/09 eran **~280 códigos**.

**Qué cambia:** la clave de salida se calcula por fila (`outkey`) y se agrupa por ella. Para un
código dual no cambia nada. Para uno no dual las dos filas se funden en una y `empresa` pasa a
`'Mixto'` cuando los movimientos traían empresas distintas. El front de Gestión ya acumulaba las
filas repetidas desde la v15.71, así que no lo afecta.

**Impacto medido:** 781 filas → **488**, duplicados **0**, total de cajas **idéntico**
(48.197,00). Después del cambio, `refresh materialized view concurrently vista_stock_procesada`
volvió a correr (363 filas, 0 duplicados) y **el cron 55 se recuperó solo** (los runs de 21:58 y
22:00 en `succeeded`).

**Rollback exacto:**
```sql
select definicion from public."GV_Backup_Viewdefs_20260912"
 where objeto = 'public.vista_saldos_stock';
-- ejecutar ese texto como create or replace view public.vista_saldos_stock as <definicion>
```
⚠ Volver atrás **reinstala la falla del refresh**: el duplicado vuelve y la pantalla de Stock se
vuelve a congelar. Notas: `sql/gv_stock_vivo_menos_pedidos_v1608.sql`.

## v16.09 (2026-09-12) — `actualizar_saldo_trigger()`: el stock_total se comía el depósito insumos

**Objeto compartido tocado:** `public.actualizar_saldo_trigger()`, la función del trigger
`trigger_actualizar_saldo_stock` sobre `Movimientos_Stock`. **Corre también para Producción.**
Backup de la definición anterior en `public."GV_Backup_Viewdefs_20260912"`
(`objeto = 'public.actualizar_saldo_trigger()'`).

**Los dos errores:**

1. `total_saldo := SUM(delta)` sobre **todos** los depósitos → sumaba `insumos` dentro del
   `stock_total`. La definición buena es la de `vista_stock_procesada` (de donde copia el cron 57):
   terminado + excedente + separar_pedidos + a_facturar + a_guardar + racks + racks_ch +
   para_envasar, **sin** insumos.
2. `ins_saldo` filtraba `deposito = 'insumos_dep'`, un valor que **no existe** en
   `Movimientos_Stock` (el depósito se llama `insumos`), así que la columna `insumos_dep` de
   `stocks_carga_rapida` quedaba **siempre en 0**.

**Por qué no se veía:** el cron 57 pisa la tabla cada 5 minutos con los valores de la matview, así
que el error del trigger duraba minutos — hasta que el cron se cayó 7 h el 11/09 y quedó a la vista.

**Impacto medido** (11/09 con el cron caído, y recalculado después del fix):

| cod | antes | ahora | matview | insumos que se comía |
|---|---|---|---|---|
| 590E | 2.447 | **51** | 51 | 2.396 (**48×** de más) |
| 584E | 1.215 | **15** | 15 | 1.200 |
| 35E | 577 | **49** | 49 | 528 |
| 440E | 231 | **39** | 39 | 192 |

Los 4 cuadran exacto con la matview después del cambio.

**Rollback exacto:**
```sql
select definicion from public."GV_Backup_Viewdefs_20260912"
 where objeto = 'public.actualizar_saldo_trigger()';
-- ejecutar ese texto
```
Notas: `sql/gv_trigger_stock_total_v1609.sql`.

## v16.16 (2026-09-12) — `vista_uni_x_caja` y `vista_uxb_articulo` pasan a leer `GV_UxB`

**Objetos compartidos tocados:** `public.vista_uni_x_caja` y `public.vista_uxb_articulo`
(`create or replace`, mismas columnas y tipos). Las usan `vista_stock_procesada` (pantalla Stock),
`vista_generador_oc` (Generar OCs), `vista_importados_partes` y el Excel de ISIS de Facturación —
todo eso lo lee también Producción.

**Qué cambia:** se les antepone `GV_UxB` (la tabla única de unidades por caja, cargada del listado
mayorista que pasó Thomas el 12/09) como primera prioridad. El resto de la cascada queda igual, así
que un código que no esté en el listado resuelve exactamente como antes. Además los `DISTINCT ON`
de `vista_uxb_articulo` pasan a llevar desempate explícito: antes eran **no deterministas** y
devolvían un valor distinto según la corrida.

**Impacto medido:** 296 de los códigos pasan a resolver por `GV_UxB`; los conflictos entre la vista
de compra y la de factura bajaron de **33 a 1** (el 724, discontinuo). Cambian de valor 10 códigos,
todos por el listado del dueño: 231/232/233 (12→24), 712E (12→24), 730/731 (24→12), 824 (12→36) y
los DISPLAY 801/901/910/911 (factura 36→12).

**Rollback exacto:**
```sql
select definicion from public."GV_Backup_Viewdefs_20260912"
 where objeto in ('public.vista_uni_x_caja','public.vista_uxb_articulo');
-- ejecutar cada texto como create or replace view <objeto> as <definicion>
```

**Aparte, tabla borrada:** `public."Uni_x_Articulo_x_Caja"` (447 filas), que no la usaba nadie —
ni Gestión ni Producción. Backup en `public."GV_Backup_Uni_x_Articulo_x_Caja_20260912"`; para
volverla: `create table public."Uni_x_Articulo_x_Caja" as select * from public."GV_Backup_Uni_x_Articulo_x_Caja_20260912";`

## 2026-09-12 · v16.16 — `vista_saldos_stock` gana la columna `clave` (objeto COMPARTIDO)

**Qué se cambió.** `create or replace view public.vista_saldos_stock` agregando **una columna
al final**, `clave`, con el mismo valor que `cod_art` tiene hoy. Ninguna otra columna se tocó.
Sin cambio de `reloptions` (la vista sigue sin `security_invoker`, como estaba) ni de grants.

**Impacto medido** (misma consulta antes y después):

| | antes | después |
|:--|--:|--:|
| filas | 488 | 488 |
| firma md5 de todas las columnas viejas | `84f2d585c9f6c01310ed5b53e41a2092` | igual |
| filas con `clave` distinta de `cod_art` | — | 0 de 488 |

**Por qué.** El front usaba `cod_art` como clave del mapa de saldos y el sufijo de empresa era
lo único que separaba 809E LK (Corta Pizza) de 809E CH (Corta Queso). `clave` permite migrar
los lectores antes de pelar `cod_art`.

**Backup de la definición previa:** tabla `public."GV_Backup_vista_saldos_def_20260912"`
(columna `definicion`, RLS prendida).
## v16.21 (2026-09-12) — se borró la tabla `cob_uxb_lk`; `GV_UxB` es la única de UxB

**Objetos compartidos tocados:** las vistas `vista_plata_perdida`, `vista_facturacion_neto_items`,
`vista_facturable_anticipado`, `cobranzas_precios_super`, `gv_articulo_empresa` (sólo se les cambió
la fuente `cob_uxb_lk` → `gv_uxb_lk`, nada más de la definición), las tablas `proyeccion_madre`,
`OC_Maximos`, `precios_venta` (se les corrigió el UxB placeholder), y la Edge Function
`sync-precios-venta` (v10). Se borró `public.cob_uxb_lk`.

**Impacto medido:** `vista_facturacion_neto_items` pasa de $1.382.133.599,36 a $1.384.819.066,43
(+$2.685.467, +0,19 %) con las **mismas 10.604 filas**. Es el arreglo de un bug real: el catálogo de
LK manda `uxb = 1` como "no sé" y Facturación cobraba unidades en vez de cajas (029 Colador Ø16:
5 cajas × 24 u se facturaban como 5 × 1). Las otras tres vistas de negocio no se movieron ni una fila
ni un peso.

**Backups:** `GV_Redir_bkp_20260912` (cob_uxb_lk + las otras 3 tablas, antes), 
`GV_UxB_bkp_prenorm_20260912`, `GV_UxB_pre_sync_20260912`, `GV_Viewdefs_bkp_20260912b`
(definición + grants de las 7 vistas), `GV_Baseline_20260912` (filas e importes de antes).

**Rollback exacto:**

```sql
-- 1) recuperar la definición previa
select definicion from public."GV_Backup_vista_saldos_def_20260912"
 where objeto = 'public.vista_saldos_stock' order by guardado_at limit 1;
-- 2) ejecutarla como: create or replace view public.vista_saldos_stock as <definicion>;
```

⚠ **El rollback de la vista OBLIGA a rollear la app a v16.15 o anterior.** Desde la v16.16
siete lecturas piden `clave` (`pkFetchExcedente`, `_pkConteoSistema`, `_stkGondolaSaldoVivo`,
`stockFetchSaldos`, `_pppChkFetchSaldos`, y las dos de `recepcion.js`) y PostgREST devuelve
**400** si la columna no existe. Los `try/catch` degradan a "sin datos" en vez de romper la
pantalla, pero el stock se vería en 0.

## 2026-09-12 · v16.20 — `vista_saldos_stock.cod_art` queda PELADO (tramo 3) · objetos COMPARTIDOS

**Qué se cambió.** Se borró del `CASE` de `cod_art` la rama que le pegaba `" LK"` / `" CH"` a los
4 códigos duales. `cod_art` es ahora siempre la grafía cruda más corta; la empresa vive en su
columna y la identidad de los duales la sostiene `clave` (v16.16).

Y con eso hubo que tocar los dependientes que usaban `cod_art` como CLAVE:

| objeto | tipo | qué se le hizo |
|:--|:--|:--|
| `vista_saldos_stock` | vista | el pelado |
| `gv_stock_cod_duplicado` | vista | agrupa por `clave` |
| `vista_facturable_anticipado` | vista | join por `canon_cod(s.clave)` |
| `public.vista_stock_procesada` | **matview** | DROP + CREATE WITH DATA (CTE `stock` por `clave`) |
| `stock_v2.vsp_fix` | **matview** | ídem |
| `public."Stock_Saldos"` | vista | recreada igual (colgaba de la matview) |
| `public.gv_importados_stock_dep` | vista | recreada igual, con `security_invoker=true` |
| `aceptar_conteo`, `gondola_return_check`, `oc_backfill_valores`, `check_stock_anomalias`, `generar_reporte_agentes` | funciones | pasan a `clave` |

**Impacto medido** (count + md5 de los 10 dependientes, antes / sin el fix / final):

| objeto | antes | sin fix | final |
|:--|--:|--:|--:|
| `gv_stock_cod_duplicado` | 0 | 4 | 0 |
| `vista_facturable_anticipado` | 724 | 749 | 724 |
| `vista_stock_procesada` | 363 | 367 | 363 |
| `stock_v2.vsp_fix` | 363 | 367 | 363 |
| `vista_faltante_catalogo` | 505 | 497 | **497** (corrección: los 8 pseudo-códigos con sufijo dejan de figurar como sin alta) |
| los otros 5 | — | — | misma firma md5 |

Tres quedaron con misma cantidad de filas y firma distinta al final (`vista_stock_procesada`,
`vsp_fix`, `vista_generador_oc`): es **deriva de datos** de otro chat que cambiaba `GV_UxB` en
paralelo. Comprobado: `vista_generador_oc` tenía firma idéntica justo después del pelado y
cambió después, sin que se la tocara.

⚠ **`vista_stock_procesada` tiene un UNIQUE INDEX en `cod`**: sin el fix el próximo `REFRESH`
habría fallado por clave duplicada.

**Backups:** `GV_Backup_vista_saldos_def_20260912` (DDL previo de la vista, las 2 matviews, las 2
vistas dependientes y las 5 funciones) y `GV_Backup_snapshot_dependientes_20260912` (count + md5
por momento). Las dos con RLS y sin `insert/update/delete` para `anon`.

**Rollback exacto:**

```sql
select id, objeto, definicion from public."GV_Backup_vista_saldos_def_20260912" order by id;
-- funciones: la definicion ya viene como CREATE OR REPLACE FUNCTION, se ejecuta tal cual
-- vistas:    create or replace view <objeto> as <definicion>
-- matviews:  drop materialized view … cascade; create materialized view … as <definicion> with data;
--            create unique index idx_vista_stock_procesada_cod on public.vista_stock_procesada (cod);
--            + recrear "Stock_Saldos" y gv_importados_stock_dep con sus grants
```

⚠ Rollear la vista obliga a rollear la app a **v16.15 o anterior** (desde la v16.16 el front
pide `clave`). Notas: `sql/gv_vista_saldos_pelar_cod_art_v1620.sql`.
-- 1) volver la tabla con su contenido original
create table public.cob_uxb_lk as
  select cod, uxb::int uxb from public."GV_Redir_bkp_20260912" where tabla = 'cob_uxb_lk';
alter table public.cob_uxb_lk add primary key (cod);
grant select, insert, update, delete on public.cob_uxb_lk to anon, authenticated, service_role;

-- 2) volver las 7 vistas a su definición previa
do $$
declare r record;
begin
  for r in select nombre, def, grants from public."GV_Viewdefs_bkp_20260912b" loop
    execute format('create or replace view public.%I as %s', r.nombre, r.def);
    if r.grants is not null then execute r.grants; end if;
  end loop;
end $$;
drop view if exists public.gv_uxb_lk;

-- 3) volver el UxB de las 3 tablas
update public.proyeccion_madre m set uxb = b.uxb::int
  from public."GV_Redir_bkp_20260912" b where b.tabla='proyeccion_madre' and b.cod = m.cod;
update public."OC_Maximos" o set uni_x_caja = b.uxb
  from public."GV_Redir_bkp_20260912" b where b.tabla='OC_Maximos' and b.cod = o.cod;
update public.precios_venta p set uxb = b.uxb::int
  from public."GV_Redir_bkp_20260912" b where b.tabla='precios_venta' and b.cod = p.cod;

-- 4) sacar los triggers y volver GV_UxB a como estaba
drop trigger if exists gv_uxb_protege_curado_trg on public."GV_UxB";
drop trigger if exists gv_uxb_normaliza_cod_trg on public."GV_UxB";
truncate public."GV_UxB";
insert into public."GV_UxB" select * from public."GV_UxB_bkp_prenorm_20260912";

-- 5) la Edge Function: redeployar la v9 (el diff está en el commit de la v16.21,
--    supabase/functions/sync-precios-venta/index.ts)
```

## v16.22 (2026-09-12) — el UxB se resuelve por empresa; 067 = 60

**Objetos compartidos tocados:** `vista_facturacion_neto_items`, `vista_facturable_anticipado` y
`vista_plata_perdida` (se les agregó el join a `gv_uxb_emp` y el escalón `uxe.uxb` en el COALESCE
del uxb; nada más de la definición), la tabla `precios_venta` (realineada desde `GV_UxB`), y la
Edge Function `sync-precios-venta` (v12: el payload de `precios_venta` ya no lleva `uxb`).
Objetos nuevos: la vista `gv_uxb_emp`.

**Impacto medido:** `vista_facturacion_neto_items` pasa de $1.384.819.066,43 a $1.395.224.315,83
(+$10.405.249) con las **mismas 10.604 filas**, todo en 5 códigos de Chef (824, 830, 877E, 828 y
26 — ver §3.da de `docs/SUPABASE-GESTION-VIRGILIO.md` para el detalle línea por línea).
`vista_plata_perdida` y `vista_facturable_anticipado`: **0 de diferencia**.

**Backup:** `GV_Viewdefs_bkp_20260912c` (definición previa de las 3 vistas; con RLS y sin
escritura para `anon`).

**Rollback exacto:**

```sql
do $$
declare r record;
begin
  for r in select nombre, def from public."GV_Viewdefs_bkp_20260912c" loop
    execute format('create or replace view public.%I as %s', r.nombre, r.def);
  end loop;
end $$;
drop view if exists public.gv_uxb_emp;

-- volver el 067 a 50 y sacarle el curado (sólo si se decide que era 50)
update public."GV_UxB" set uxb = 50, curado = false where empresa = 'LK' and cod = '67';

-- sacar el lado CH de los duales que se cargó en esta versión
delete from public."GV_UxB"
 where empresa = 'CH' and origen like 'dual 12/09/2026: lado CH desde Articulos_Cajas%';

-- la Edge Function: redeployar la v11 (el diff está en el commit de la v16.22,
-- supabase/functions/sync-precios-venta/index.ts) — vuelve a mandar uxb a precios_venta
```

## 2026-09-12 · v16.30 — tramo 4: los 4 duales dejan de ser invisibles para los chequeos de stock

**Objetos tocados.** Función NUEVA `public.gv_stock_clave(text,text)` (STABLE, `execute`
revocado a `PUBLIC` y otorgado a `anon`/`authenticated`/`service_role`), y `create or replace`
de tres funciones compartidas: `aceptar_conteo(bigint,text)`,
`gondola_return_check(jsonb,text)` (firma nueva; la de 1 argumento queda como envoltorio que
pasa `NULL`, **sin DEFAULT** porque con default las dos firmas serían ambiguas) y
`oc_backfill_valores(boolean)`.

**Impacto medido.** Cuatro lugares preguntaban "¿cuánto hay de este código en góndola?"
filtrando por el código PELADO; para los 4 duales no matcheaba nada y el saldo daba 0:

| dónde | antes | con el fix |
|:--|--:|--:|
| `oc_backfill_valores`, stock del `809E` | 0 | **456** |
| ídem `437E` / `439E` | 0 / 0 | 16 / 16 |
| aviso de góndola, 400 cajas de `809E` por CH | no avisaba | **avisa** (120+400 > 465,6) |
| ídem por LK | no avisaba | no avisa (28+400 < 465,6), correcto |
| control: `505` (no dual) | 2.719 | 2.719 |

Ninguna de las **574 OC abiertas** es de un dual, así que nada se reescribió: cambia la
próxima. `aceptar_conteo` tenía **0 conteos de duales** en la historia y 0 pendientes.

**Backup:** `zz_backups."GV_Backup_vista_saldos_def_20260912"`, filas con
`objeto like 'DDL v16.29%'`.

**Rollback exacto:**

```sql
select objeto, definicion from zz_backups."GV_Backup_vista_saldos_def_20260912"
 where objeto like 'DDL v16.29%';
-- cada `definicion` ya viene como CREATE OR REPLACE FUNCTION: se ejecuta tal cual
drop function public.gondola_return_check(jsonb, text);
drop function public.gv_stock_clave(text, text);
```

Notas: `sql/gv_stock_clave_tramo4_v1630.sql`.

---

## v16.33 (2026-09-12) — `vista_stock_procesada` recreada + `vista_ppp_pedidos_entregados` + crons 57/68

Tres objetos compartidos. Los tres arreglan fallas que ya estaban en producción, medidas sobre
24 h de logs y de `cron.job_run_details` — no son cambios de comportamiento pedidos.

### 1. `vista_stock_procesada` (matview) — DROP CASCADE + CREATE

**Impacto medido: ninguno sobre los datos de hoy.** Antes y después dan idéntico:
363 filas · `stock_total` 48197.00 · `cajas_pedidas` 4720.66 · `a_pedir` 7561.00 ·
`uni_x_caja` 5163.00 · 361 visibles. Las dependientes también: `Stock_Saldos` 363,
`gv_importados_stock_dep` 482. Y `refresh_stocks_carga_rapida()` deja `stocks_carga_rapida`
en 363 / 48197.00, igual que el matview.

Lo que cambia es que **ya no puede fallar el refresh**: el CTE `stock` ahora agrupa por código
normalizado y suma, en vez de dejar pasar dos filas cuando `053` y `53` conviven. Sin eso, el
`REFRESH CONCURRENTLY` fallaba 1 de cada 3 veces contra el índice único y el stock quedaba viejo.

⚠ El DROP fue **CASCADE**, así que se llevó `Stock_Saldos` y `gv_importados_stock_dep`; las dos
se vuelven a crear en la misma transacción, con sus opciones (`gv_importados_stock_dep` mantiene
`security_invoker=true`; `Stock_Saldos` sigue **sin** él, como estaba) y sus grants.

**Backup:** `zz_backups."GV_Backup_stock_procesada_20260912"` — def del matview, sus índices, y
def + opciones + grants de las dos dependientes.

**Rollback:** correr `sql/gv_stock_procesada_dup_v1633.sql` cambiando
`replace(d, viejo, nuevo)` por `d` a secas. Y `drop view public.gv_stock_procesada_dup;`.

### 2. `vista_ppp_pedidos_entregados`

`max(p.fecha_entrega::date)` → `max(nullif(btrim(p.fecha_entrega), '')::date)`, y se le prendió
`security_invoker = true` (no lo tenía, o sea salteaba la RLS). Antes tiraba 500; después 1227
filas, las mismas corridas como `anon`. Se comprobó primero que `anon` lee las 5 tablas base
completas, así que prender el invoker no le saca nada a nadie.

**Backup:** `zz_backups."GV_Backup_viewdef_ppp_entregados_20260912"`.

**Rollback:**

```sql
do $$ begin execute 'create or replace view public.vista_ppp_pedidos_entregados as '
  || (select def from zz_backups."GV_Backup_viewdef_ppp_entregados_20260912"); end $$;
```

### 3. Crons 57 y 68 — `pg_advisory_xact_lock(5768)` en el `command`

No se tocó ninguna función: sólo el `command` del cron, que pg_cron manda como una sola
simple-query, así que los dos statements comparten transacción y el candado se suelta al commit.
Serializa las dos corridas y mata los 11 deadlocks diarios.

**Backup:** `zz_backups."GV_Backup_cron_job_20260912"`.

**Rollback:**

```sql
select cron.alter_job(57, command := (select command from
  zz_backups."GV_Backup_cron_job_20260912" where jobid = 57));
select cron.alter_job(68, command := (select command from
  zz_backups."GV_Backup_cron_job_20260912" where jobid = 68));
```

Notas: `sql/gv_stock_procesada_dup_v1633.sql`, `sql/gv_fix_entregados_y_deadlock_v1633.sql`,
`docs/HALLAZGOS-LOGS-20260912.md`.

## 2026-09-14 (v17.47) — la tanda D67B se renombró a E01E en `Registros_Produccion_Virgilio`

**Qué se tocó (tabla COMPARTIDA):** `update public."Registros_Produccion_Virgilio" set texto = 'E01E'
where upper(btrim(texto)) = 'D67B'` — **5 filas** (AP, EP, PUB, TAP y TP de esa tanda). Misma operación
en `Entregas_Virgilio` (17 filas), que no es compartida.

**Por qué:** Marianela pidió pasar D67B, D67N y E01A al camión 1 del 15/09. El camión agrupa por el
número de la tanda, así que había que meter D67B en la serie E01; y como el estado de armado se
resuelve por código de tanda, dejar los registros en D67B habría mostrado como "Sin empezar" una
tanda que estaba armada desde el 11/09.

**Impacto en Producción Virgilio:** ninguno medible — la app de Producción ya no se usa (dueño,
2026-09-08). Si se la volviera a abrir, la tanda D67B ya no existe con ese nombre: sus eventos
aparecen bajo E01E, con las mismas fechas y legajos.

**Rollback exacto** (backup completo en `zz_backups."GV_Backup_D67B_Registros_20260914"`, 5 filas, y
`zz_backups."GV_Backup_D67B_Entregas_20260914"`, 17 filas):

```sql
update public."Registros_Produccion_Virgilio" set texto = 'D67B' where upper(btrim(texto)) = 'E01E';
update public."Entregas_Virgilio"             set tanda = 'D67B' where upper(btrim(tanda)) = 'E01E';
update public."GV_PPP_Prog_Override" o set tanda = b.tanda, tanda_previa = b.tanda_previa, nota = b.nota
  from zz_backups."GV_Backup_ProgOverride_20260914b" b
 where o.np = b.np and o.np in ('44607','44608','98694');
```

Nota: `sql/gv_camion1_1509_v1747.sql`.

---

## v17.73 (2026-09-14) — trigger `zzz_guardado_no_negativo` en `Movimientos_Stock`

**Objeto compartido tocado:** `public."Movimientos_Stock"` — se le agregó un **quinto trigger**
`BEFORE INSERT`, `zzz_guardado_no_negativo` (función `public.trg_guardado_no_negativo()`).
No se modificó ninguna fila ni columna existente, y no se tocó ninguno de los otros triggers.

**Qué hace:** rechaza un `insert` que deje `a_guardar` en negativo. Filtra durísimo antes de
mirar nada: sólo actúa si `tipo = 'guardado'` **y** `deposito = 'a_guardar'` **y** `delta < 0`.
Todo lo demás (recepción, picking, separado, facturado, ajuste, insumos, `guardado_fuera_lista`,
y las patas de destino `terminado`/`excedente`) sale por el `return NEW` de la primera línea sin
consultar nada.

**Impacto en Producción Virgilio:** la app ya no se usa (dueño, 2026-09-08). Si se la volviera a
abrir, su módulo de guardado escribe contra la misma tabla, así que le aplicaría el mismo
candado — y ahí sí importa que **Producción NO tiene la mitad del front de la v17.73**: su
`stockMove` seguiría tragándose el 400 en `console.error` y el operario vería un "✅ Guardado"
que no ocurrió. **Si se reactiva Producción Virgilio, o se apaga este trigger, o se le porta el
cambio de `stockMove`/`mgConfirmar`.**

**Costo:** un `sum()` sobre `Movimientos_Stock` filtrado por `deposito` y por la expresión del
índice `idx_ms_norm_cod`, que ya existe sobre exactamente esa expresión. Sólo en el guardado.

**Rollback exacto:**

```sql
drop trigger if exists zzz_guardado_no_negativo on public."Movimientos_Stock";
drop function if exists public.trg_guardado_no_negativo();
```

Nota: `sql/gv_guardado_no_negativo_v1773.sql`, `docs/SUPABASE-GESTION-VIRGILIO.md` §3.fn.

---

## Los códigos NNNL dejan de ser artículos aparte — `vista_stock_procesada` (v18.16, 2026-09-15)

**Objeto compartido tocado:** la matview `public.vista_stock_procesada` (DROP + CREATE, porque
no hay `create or replace` de matview) y, por el CASCADE, sus 3 dependientes:
`public."Stock_Saldos"`, `public.gv_importados_stock_dep` y `public.gv_importados_ordenes`
(ésta cuelga en segundo nivel y ya se cayó dos veces por esto — v16.20 y v16.33). Las tres se
recrearon en la misma transacción, con `security_invoker = true` y sus grants.

**Qué cambió:** dos CTE dejaron de normalizar con `regexp_replace(..., '^0+(?=.)', '')` y pasaron
a usar `gv_cod_stock()`, que además le saca la **L** final (sólo detrás de dígito o E):
`dem_raw` / `dem_oc_raw` (la demanda) y el brazo de `proyeccion_madre` del CTE `proy`. Con eso
`513L` —la variante con la que Chef vende mercadería de Loeke— deja de ser una fila propia y
sus cajas y su proyección se le suman al `513`. **Ninguna columna cambió**, así que nada que lea
estas vistas se rompe: cambian los valores, no la forma.

**Impacto en Producción Virgilio:** su `index.html` lee `vista_stock_procesada`, `Stock_Saldos`
y `stocks_carga_rapida` (grepeado el 15/09 sobre el repo clonado). Va a ver los mismos números
fundidos, que es justamente lo que pidió el dueño ("con la L al final ya hablé mil veces que no
va"). No hay cambio de esquema, así que no hay nada que portar.

**Medido, antes → después** (`stocks_carga_rapida`): 425 → 369 filas · 56 → 0 filas NNNL ·
demanda 5.501,66 → 5.501,66 (re-atribución) · proyección 21.693,16 → 22.496,21 (+803,05, la que
colgaba de las filas NNNL) · `513` 184 → 190 cajas y 1.132,17 → 1.204,17 de proyección ·
`gv_endpoints_rotos` en 0 · las 3 vistas conservan `security_invoker`.

**Rollback exacto:** el bloque `3) ROLLBACK` de `sql/gv_stock_procesada_sufijo_L_v1816.sql`, que
recrea las 4 definiciones leyéndolas de `zz_backups."GV_Backup_Defs_StockProcesada_20260915"` y
después corre `select public.refresh_stocks_carga_rapida();`.

**Nota:** el motor de la proyección se arregló **antes**, en LK
(`sql/fn_proyeccion_oc_virgilio_uxb_base_L_v1816.sql`). Eso no toca ningún objeto de Producción:
`fn_proyeccion_oc_virgilio()` vive en `kwkclwhmoygunqmlegrg`. Lo que sí baja a esta base es su
resultado, en `public.proyeccion_madre`, respaldado en
`zz_backups."GV_Backup_ProyeccionMadre_20260915"`.

---

## La proyección pasa a una sola tabla — `proyeccion_madre` + columnas (v18.17, 2026-09-15)

**Objetos compartidos tocados:** `public.proyeccion_madre` (dos columnas **nuevas**, nullable y
sin default: `proy_cajas_lk` y `proy_cajas_chef` — agregar está permitido, no se tocó ninguna
columna existente) y otra vez la matview `public.vista_stock_procesada` con sus 3 dependientes
por el CASCADE. Además se **borró** la tabla `public."GV_Proyeccion_Emp"`.

**Impacto en Producción Virgilio:** su `index.html`, `recepcion.js` y `admin/admin.js` nombran
`proyeccion_madre`, que **sigue existiendo con las mismas columnas de antes** — sólo tiene dos
más. `GV_Proyeccion_Emp` **no aparece en ningún archivo** de ese repo (grepeado el 15/09 sobre
`--include=*.js --include=*.html --include=*.sql`), así que borrarla no le saca nada.

**Medido:** `proyeccion_madre` sigue en 461 filas y el total en 22.305,87 cj/mes, idéntico al de
antes; lo que cambia es que ahora el desglose por empresa sale de esa misma fila y cierra
(0 filas donde `lk + chef <> total`).

**Rollback exacto:** bloque `4) ROLLBACK` de `sql/gv_proyeccion_una_sola_tabla_v1817.sql`. Los
datos de la tabla borrada están en `zz_backups."GV_Backup_ProyeccionEmp_20260915"` y las 6
definiciones vivas previas en `zz_backups."GV_Backup_Defs_Proyeccion_20260915"`.

---

## v18.30 (2026-09-15) — `trg_normalizar_empresa_stock` + `reconciliar_pipeline_stock_etapa2` (objetos COMPARTIDOS)

**Qué se tocó:** dos funciones de `public.*` que usa el pipeline de stock, o sea también Producción
si escribe movimientos.

| Objeto | Cambio |
|---|---|
| `public.trg_normalizar_empresa_stock()` (trigger `zz_normalizar_empresa`, BEFORE INSERT de `Movimientos_Stock`) | una fila **sin empresa** cuyo `ref` es una tanda (`LETRA+NN+LETRA`) y cuyo depósito es `separar_pedidos` / `a_facturar` / `terminado` hereda la empresa del `picking` de esa (tanda, código), si es **una sola**. Antes caía en `Mixto` |
| `public.reconciliar_pipeline_stock_etapa2()` | las filas `Mixto` de `separar_pedidos` se netean contra la empresa del picking de esa (tanda, código) al calcular el neto |

**Por qué:** el ajuste del aviso "de menos / no hay en góndola" nacía `Mixto`, el picking sale
`LK`/`CH` desde el 11/09, y como el saldo es por empresa **no se restaban**: Pickeados quedaba
negativo y el `separado` devolvía a góndola una caja que no existe. Caso testigo E11A/116.
Detalle completo y mediciones en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.ha.

**Impacto medido (no "no debería afectar"):**

* `reconciliar_pipeline_stock_etapa2()` corrida sobre los datos reales en transacción abortada →
  **0 filas emitidas**: no reprocesa ni toca nada de lo existente.
* Ninguna fila de `Movimientos_Stock` fue modificada ni borrada. El cambio sólo afecta **inserts
  nuevos** y el **cálculo** de tandas todavía sin `separado`.
* Firmas sin cambios, así que los dos consumidores (`reconciliar_pipeline_stock()` y
  `trg_entregas_reconciliar()`) siguen compilando igual.

**Riesgo para Producción:** si Producción inserta un movimiento sobre una tanda ya pickeada **sin**
empresa, ahora queda con la empresa del picking en vez de `Mixto`. Es la partición correcta; lo que
cambia es que deja de sumar en `Mixto`.

**Rollback exacto (vuelve todo al comportamiento previo, sin tocar datos):**

```bash
psql "$VIRGILIO_URL" -f sql/backups/empresa_mixto_ajuste_pre_v1830_20260915.sql
```

o pegar ese archivo en el SQL editor: trae los `CREATE OR REPLACE` de las dos funciones tal como
estaban antes del cambio.

---

## v18.40 — 2026-09-15 · UPDATE de 7 filas en `Entregas Tallerista Virgilio` (tabla compartida)

**Qué se tocó.** 7 filas de `public."Entregas Tallerista Virgilio"` cuyo `Cod` estaba tipeado sin
la `E` final (582, 583, 584, 599, 727, 943, 948 → sus variantes `NNNE`). Autorizado por el dueño
el mismo día. Ids: 1961, 1962, 1960, 2293, 1902, 2294, 2295. 212 cajas.

**Impacto medido en Producción Virgilio.** Ninguno en el front (`grep -rn "Entregas Tallerista"`
sobre `produccion-virgilio` sólo pega en dos `.sql` de ahí: un script de prueba y la receta del
trigger de Planify — no hay JS ni HTML que lea la tabla). **Y ningún trigger se disparó**: los dos
que tiene la tabla, `trg_recep_pagos_tall` y `trg_virgilio_espejo_gp2`, son `AFTER INSERT`, no
`AFTER UPDATE`. En Gestión, el efecto es el buscado: las entregas ahora imputan al artículo real y dejan de dispararse los avisos de
"SIN OC generada" sobre códigos inexistentes. **El stock no se movió**: sólo 582 y 583 habían
llegado a `Movimientos_Stock` y los dos ya estaban en 0 (queda la huella
`ref = "fix typo 583->583E (racks->gondola)"`).

**Rollback exacto.**

```sql
update public."Entregas Tallerista Virgilio" t
   set "Cod" = b."Cod"
  from zz_backups."GV_Backup_EntregasTall_SinE_20260915" b
 where t.id = b.id;
```

El backup tiene las 7 filas completas (todas las columnas), con RLS prendida y sin grants para
`anon`/`authenticated`. Detalle en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.hf. Problema 264.

---

## 2026-09-16 (v18.86) — `trg_normalizar_empresa_stock()`: el guardado hereda la empresa del montón

**Objeto compartido tocado:** la función `public.trg_normalizar_empresa_stock()`, que usa el
trigger `zz_normalizar_empresa` (BEFORE INSERT) de `public."Movimientos_Stock"`. Corre también
para Producción Virgilio, que escribe en esa misma tabla.

**Qué cambió.** Se agregó UN bloque: un movimiento de tipo `guardado*` que llega **sin empresa
explícita** y va a `a_guardar` / `terminado` / `excedente` ahora hereda la empresa con la que
ese artículo entró a A Guardar, **si entró con una sola**. Si entró con dos, no se adivina.
Nada más se tocó: el resto del cuerpo es idéntico.

**Impacto sobre Producción.** Estrictamente menos `'Mixto'` y más `LK`/`CH` en filas que antes
quedaban sin empresa. No cambia ninguna fila que ya venga con empresa explícita, no cambia
deltas ni depósitos, y no rechaza ningún INSERT. Producción no lee la columna `empresa` para
decidir nada del picking; la usan las vistas de saldos, que mejoran.

**Por qué hacía falta.** Sin eso, una fila sin empresa caía derecho en `'Mixto'` y partía el
saldo del artículo: la mercadería entraba a A Guardar como LK y salía como Mixto, así que el
`−` no cancelaba al `+`. El 16/09 eso puso **475 cajas inexistentes** en "Mover a Góndola".
Detalle en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.hz. Problema 331.

**ROLLBACK exacto:** ejecutar `sql/backups/trg_normalizar_empresa_stock_pre_v1886.sql`, que es
la definición anterior tal cual salió de `pg_get_functiondef`. No hay que tocar el trigger
(sigue apuntando a la misma función).

**También del 16/09, sobre datos de la tabla compartida:** se reasignaron **24 filas** de
`Movimientos_Stock` (`empresa` 'Mixto' → 'LK'/'CH'), las 12 parejas del guardado del 14/09 y
16/09 de los 10 códigos con saldo partido. Sólo cambió `empresa`; ni `delta`, ni `deposito`, ni
`ts`. Backup fila por fila en `zz_backups."GV_Backup_MovStock_Mixto_guardado_20260916"`.
Rollback: `update public."Movimientos_Stock" m set empresa = b.empresa from
zz_backups."GV_Backup_MovStock_Mixto_guardado_20260916" b where b.id = m.id;`

---

## 2026-09-16 (v18.91) — `gv_ppp_np_desarmar()`: el desarme vuelve a «A guardar», no a la góndola

**Objeto compartido tocado:** la función `public.gv_ppp_np_desarmar(text,text,text,boolean,boolean)`,
que ESCRIBE en `public."Movimientos_Stock"` (tabla compartida con Producción Virgilio).

**Qué cambió.** Sólo el DESTINO de la mercadería devuelta. Antes se repartía entre `terminado`
(góndola) y `excedente` según de dónde había salido cada caja, y el resto caía en `a_guardar`;
ahora **va todo a `a_guardar`**, en los tres caminos (`p_vuelve`, `p_a_guardar`, y el desarme a
secas). Son tres expresiones del `select` y el mensaje de un `raise`. No cambia cuántas cajas se
mueven, ni de qué depósito salen (`a_facturar` / `separar_pedidos` siguen igual), ni la empresa.

**Impacto sobre Producción.** Producción no desarma pedidos (la función es de Gestión), así que
lo único que ve es el saldo: la misma cantidad de cajas, en `a_guardar` en vez de en `terminado`
/ `excedente`. Un desarme ya no hace aparecer stock en una góndola donde físicamente no está.

**Por qué.** Regla de Luis (16/09): *"si hay un pedido programado que se pickeo y se manda de
vuelta a programar, hace que los items que se pickearon vayan a A guardar"*. Deshace la v18.80,
del mismo día. Detalle en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.ih.

**ROLLBACK exacto:** sobre la definición viva (`pg_get_functiondef`), volver a poner las tres
expresiones originales — están literales en `sql/gv_ppp_np_desarmar_v1891.sql`:

```
'0::numeric as a_term'   →  'case when v_ag then 0 else least(c.total, c.org_term) end as a_term'
'0::numeric as a_exc'    →  'case when v_ag then 0 else least(c.total - least(c.total, c.org_term), c.org_exc) end as a_exc'
'c.total as a_guardar'   →  'case when v_ag then c.total else c.total - least(c.total, c.org_term) - least(c.total - least(c.total, c.org_term), c.org_exc) end as a_guardar'
```

**No se tocó ningún dato** de `Movimientos_Stock` en este cambio: sólo aplica de acá en adelante.


---

## v19.23 (2026-09-16) — `vista_productividad_diaria` y `vista_productividad_semanal` reemplazadas

**Objetos compartidos tocados:** las dos vistas de `public.*`.

**Quién las consume, medido el 16/09** (no alcanzaba con mirar el tablero de Gestión):

| Consumidor | Cómo se verificó |
|---|---|
| front de `produccion-virgilio` (`.js` / `.html`) | **0 apariciones** (clon fresco `bba6bcb`, grep) |
| `reporte_diario_telegram(date, boolean)` | corrida con `p_enqueue = false` → 681 chars, **sin enviar** |
| `reporte_semanal_telegram(date, boolean)` | corrida con `p_enqueue = false` → 364 chars, **sin enviar** |
| `reporte_agentes_rendimiento_anomalo()` | **NO se llamó**: encola Telegram sin guard. Se corrió su consulta interna a mano → 8 filas |

⚠ Esa última no tiene flag de "no enviar": si hay que probarla, se prueba la consulta, no la
función. Las tres salieron del repo de Producción (`sql/reporte_diario.sql`,
`sql/reporte_semanal.sql`, `sql/rendimiento_anomalo.sql`) y siguen vivas en la base compartida.

**Por qué no se rompen:** no se agregó, quitó ni renombró ninguna columna — cambió sólo cómo se
calculan los minutos.

**Qué cambió:** pasan de medir tiempo de RELOJ a medir **horas activas** (la noche, el fin de
semana y los feriados no cuentan), y dejan de descartar la tanda cerrada al otro día. Detalle y
medición en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.it.

**Impacto medido:** ningún valor bajó; subieron los días que tenían un cierre cruzado (23 de 460
cierres en 40 días). Ninguna columna se agregó ni se quitó, así que cualquier lector sigue
funcionando igual.

**Objetos nuevos (no tocan nada existente):** `gv_jornada_ventanas`, `gv_min_activos`,
`gv_fin_activo`.

**Rollback exacto:**

```bash
# deja las dos vistas como estaban (v19.07) y repone security_invoker
psql < sql/backups/vista_productividad_pre_v1923_20260916.sql
```

Las tres funciones nuevas pueden quedar: sin las vistas nuevas no las llama nadie. Para borrarlas
igual: `drop function public.gv_fin_activo(text,timestamptz,timestamptz,numeric);
drop function public.gv_min_activos(text,timestamptz,timestamptz);
drop function public.gv_jornada_ventanas(text,timestamptz,timestamptz);`



## v19.26 (2026-09-16/17) — `trg_normalizar_empresa_stock`: la empresa la da el artículo

**Objeto compartido tocado:** `public.trg_normalizar_empresa_stock()` (trigger BEFORE INSERT
de `Movimientos_Stock`) y 55.380 filas de la propia tabla (columna `empresa`, nada más).

**Qué cambió.** Para un código NO dual el trigger ya no escribe `Mixto`: toma la empresa del
artículo (góndola → lista de precios → racks) y pisa lo que venga del front. Para los duales
no cambia nada salvo que la NP ahora se busca de los dos lados de la barra del `ref`.

**Impacto medido.** La huella del saldo (`md5` de `sum(delta)` por cod_art+depósito) es
**idéntica** antes y después: `d8028d919ec17a583c4662d52550ae23`. Ningún depósito cambió de
número. Lo que cambia es la columna `empresa`, que sólo parte la pila en `vista_saldos_stock`
para los 4 códigos duales.

**Rollback exacto.**
```sql
-- 1) el trigger
select def from zz_backups."GV_Backup_Fn_NormalizarEmpresa_20260916";  -- y ejecutarlo
-- 2) las filas (apagar antes el trigger de saldo: corre FOR EACH ROW y reescanea todo)
alter table public."Movimientos_Stock" disable trigger trigger_actualizar_saldo_stock;
update public."Movimientos_Stock" m set empresa = b.empresa_antes
  from zz_backups."GV_Backup_MovStock_empresa_backfill_20260916" b where b.id = m.id;
update public."Movimientos_Stock" m set empresa = b.empresa_antes
  from zz_backups."GV_Backup_MovStock_empresa_alineadas_20260916" b where b.id = m.id;
alter table public."Movimientos_Stock" enable trigger trigger_actualizar_saldo_stock;
select public.refresh_stocks_carga_rapida();
-- 3) el resto
select cron.unschedule('gv-refrescar-articulo-empresa');
drop table public."GV_Articulo_Empresa_Cache" cascade;
```

⚠ **Al revertir, revertir las dos cosas juntas.** Si se vuelve el trigger viejo y se dejan
las filas alineadas (o al revés), historia y futuro quedan con criterios distintos y el
`ON CONFLICT` del reconciliador **duplica el picking** — pasó el 16/09 a las 18:20 con las
tandas D72A y E11B, 126 filas.

**Planimetría:** el sector `P39` pasó de empresa `CH` a `LK` (backup
`zz_backups.GV_Backup_Lugar_P39_20260916`); tiene un solo artículo, el 396.

## v19.29 (2026-09-17) — `gv_ppp_programacion_diaria`: una NP «en espera» queda sin fecha de entrega

**Qué se cambió.** El espejo de ISIS —que Producción ve a través de la vista de compatibilidad
`PPP_Programacion_Diaria`— tiene una rama nueva: si la NP está marcada en
`public."GV_PPP_Armados_Espera"`, devuelve `fecha_entrega = ''`. La **tanda queda** (a diferencia
de `desprogramada`, que borra tanda y fecha). Es el módulo «⏸ Armados en espera» que pidió Luis:
un pedido que se arma a propósito sin fecha de entrega definida.

**Impacto en Producción.** Una NP parada le va a imprimir el remito con `Fecha Entrega —`, igual
que hoy pasa con una NP desprogramada. Sólo puede pasar con NP que un supervisor haya parado a
mano desde Gestión; **con la tabla vacía, la vista devuelve exactamente lo mismo que antes** (el
`left join` no agrega ni saca filas: la clave es `np`, única en esa tabla).

**Medición (2026-09-17).** `GV_PPP_Armados_Espera` tiene 0 filas al aplicarse;
`gv_ppp_isis_sin_tanda` da 5 antes y 5 después; `gv_endpoints_rotos` vacío; la vista conserva
`security_invoker=true`.

**Rollback exacto.** `sql/backups/pre_v1929_armados_espera_20260917.sql` recrea la vista sin esa
rama (y vuelve a poner `security_invoker`). Si además hay que "despertar" lo que quedó parado:

```sql
select * from public."GV_PPP_Armados_Espera";                      -- qué está parado y de qué tanda
select * from public.gv_ppp_tanda_mover('<TANDA>', date '<AAAA-MM-DD>', 'rollback', true);
```

⚠ Restaurar la vista **no** le devuelve la fecha a una tanda ya parada: la fecha de una tanda WEB
se puso en `NULL` en `PPP_Web_Programacion`, y eso se deshace reprogramándola (arriba) o desde la
app con «📅 Cambiar de día».

**Permisos que hay que conservar** (si no, se cae el FDW de LK, no Producción):
`grant select on public."GV_PPP_Armados_Espera" to anon, authenticated, lk_ppp_reader, ch_ppp_reader;`

---

## v19.32 (2026-09-17) — mover un PEDIDO de día, y elegir en qué tanda cae

**Qué se tocó de lo compartido.** Cuatro objetos que Producción también mira:

| Objeto | Qué se hace |
|---|---|
| `public.gv_ppp_prog_arbol` | `create or replace`: el CTE `est` ahora aplica un **piso** de estado por NP desde `GV_PPP_NP_Estado` (`greatest()`). Es una función `gv_*`, sólo la lee Gestión. |
| `public."Registros_Produccion_Virgilio".texto` | `update` **sólo al re-codificar una tanda entera** (`gv_ppp_tanda_renombrar`), mismo precedente que la v17.47 |
| `public."Entregas_Virgilio".tanda` | ídem |
| `public."Movimientos_Stock".ref` | ídem: se renombra el código de tanda, **no se mueve un solo movimiento de stock** |
| `public."Facturacion_NP".tanda` | `update` al separar una NP: Carga Camión ofrece las NP desde acá, no por el evento `TAP` |

**Objeto nuevo:** `public."GV_PPP_NP_Estado"` (prefijo `GV_`, RLS prendida). Nace vacía; con la
tabla vacía el árbol devuelve exactamente lo mismo que antes.

**Impacto en Producción.** Nulo mientras nadie mueva nada. Cuando se mueve una tanda entera,
Producción ve el **código nuevo** en los eventos y los remitos — que es justo lo que se quiere, y
lo mismo que ya pasaba desde la v17.47. Renombrar **no borra ni duplica** eventos: los actualiza.

**Medición (2026-09-17).** Prueba real en transacción abortada: D72B → E34A renombró **9 eventos**
y **138 filas** de `Movimientos_Stock.ref`, sin tocar deltas ni saldos. `gv_ppp_np_estado`
coincide **153/153** con el estado que el árbol ya mostraba. Centinelas después:
`gv_ppp_tanda_dos_dias` 0, `gv_ppp_super_mezclado` 0, `gv_ppp_tanda_camion_mezclado` 1 (la D69F de
siempre), `gv_endpoints_rotos` 0.

**Rollback exacto.**

```sql
-- 1) el piso de estado: vaciarlo devuelve el árbol al comportamiento anterior sin recrear nada
delete from public."GV_PPP_NP_Estado" where np is not null;   -- supautils exige el WHERE

-- 2) volver a la firma vieja de gv_ppp_tanda_mover (la de 4 args se dropeó a propósito)
--    está en sql/gv_ppp_armados_espera_v1929.sql
-- 3) el árbol sin el piso: sql/gv_ppp_armados_espera_v1929.sql trae el CREATE completo de v19.29
```

⚠ **Lo que NO se deshace solo:** un renombre de tanda ya aplicado. Para volver atrás hay que
renombrarla de vuelta, que es una operación simétrica:

```sql
select * from public.gv_ppp_tanda_renombrar('<NUEVA>', '<VIEJA>', 'rollback');
```

Y una fusión (tanda de origen que quedó vacía y dejó de existir) se deshace moviendo esos pedidos
de vuelta con `gv_ppp_pedido_mover(<np>, <fecha vieja>, '<TANDA VIEJA>')`.

---

## v19.34 (2026-09-17) — «✕ Cancelar pedido» desde la fila de la NP

**Qué se tocó de lo compartido.**

| Objeto | Qué se hace |
|---|---|
| `public."Movimientos_Stock"` | **inserta** los movimientos de devolución (`tipo = 'desarme'`): `a_facturar`/`separar_pedidos` en negativo y `a_guardar` en positivo. Nada de esto es nuevo: es lo que ya hacía `gv_ppp_np_desarmar` desde la v18.90. Lo que cambió es **quién lo dispara** (ahora también el botón de la PPP) y **cuándo se deja** (con `p_forzar`, una NP que ya tenía Carga Camión). |
| `public."Registros_Produccion_Virgilio"` | **sólo lectura**: se agregó el evento `FSS` al chequeo de «ya salió». No se escribe nada. |
| `public.gv_ppp_web_armar_pendientes` | `create or replace` con un pase nuevo **(a0c)** al principio, calcado del (a0b). Es una función `gv_*`: la lee el cron de armado de Gestión, no Producción. |
| `public."PPP_Web_Programacion"` | `update tanda = null, fecha_entrega = null` de la NP cancelada — igual que el desarme de la v18.90. |
| `public."NP_Canceladas"` / `public."GV_PPP_Prog_Override"` | la NP de ISIS cancelada se anota y se oculta, igual que antes. |

**Objeto nuevo:** `public."GV_PPP_Web_NP_Cancelada"` (prefijo `GV_`, RLS prendida, `select` para
`anon`/`authenticated`). Nace vacía; con la tabla vacía el armador se comporta exactamente igual.

**Impacto en Producción.** Nulo mientras nadie cancele nada. Cuando se cancela, Producción ve lo
mismo que veía con el desarme desde la v18.90: la NP sale de la programación y el remito no se
imprime. La única diferencia real es que ahora **se puede cancelar una NP que ya tiene `CCN`**, y
en ese caso el stock vuelve a `a_guardar` aunque la mercadería ya haya salido físicamente — por eso
el front lo avisa en rojo y el backend lo escribe en el justificativo.

**Medición (2026-09-17).** Pruebas en transacción abortada: 98668 (D66D) devuelve **60 cajas** a
`a_guardar` y sale de la PPP; un pedido web de 5 NP cancelado «sólo ésta» deja **4** en pie;
98633 (entregada de verdad) **rebota** sin `p_forzar`. `gv_ppp_np_devolucion` coincide **80/80**
con la fórmula que reemplaza. El armador, con un bloque marcado, arma **sólo el otro**.

**Rollback exacto.** `sql/backups/pre_v1934_cancelar_pedido_20260917.sql` — saca el pase (a0c),
vuelve `gv_ppp_np_desarmar` a su firma de 5 argumentos (la de la v18.94) y dropea las tres
funciones nuevas.

⚠ **Lo que NO se deshace solo:** los movimientos de stock que una cancelación ya escribió, y la
NP que ya salió de la PPP. Para revivir una NP cancelada:

```sql
-- web, un bloque
delete from public."GV_PPP_Web_NP_Cancelada" where np_label = '<NP>';
-- web, el pedido entero
delete from public."GV_Web_Cancelados" where np_label = '<NP>';
-- ISIS
delete from public."NP_Canceladas" where np = '<NP>';
update public."GV_PPP_Prog_Override" set oculto = false where np = '<NP>';
```

Y el stock se revierte con el movimiento inverso (nunca borrando la fila: el log es append-only).

⚠ **Antes de borrar `GV_PPP_Web_NP_Cancelada`, mirarla**: cada fila es una NP que un supervisor
canceló a mano, y sin ella el cron la vuelve a programar sola.

---

## v19.46 (2026-09-17) — `detectar_faltantes_llegaron()` reescrita por performance

**Objeto compartido tocado:** `public.detectar_faltantes_llegaron()` — función de `public.*`, o sea
alcanzable desde Producción Virgilio. Se hizo `CREATE OR REPLACE` (no se cambió firma, ni tipo de
retorno, ni grants; `CREATE OR REPLACE` los conserva).

**Qué cambió:** SÓLO el plan de la consulta. El CTE `fmark` hacía un `exists` correlacionado contra
`Movimientos_Stock` por cada fila de `Entregas_Virgilio` (967 × 63.614 = 61,5 millones de
comparaciones); ahora pre-agrega una vez y JOINea. **La salida es idéntica**, verificado fila por
fila sobre las 967 filas (`llego` 0 diferencias, `arrived_after` 0 diferencias en 4 tandas que
suman 967).

**Impacto medido:** de **64.700 ms** a **37–87 ms** por corrida. La dispara el cron **34**
(`*/2 * * * *`), que estaba ocupando el **54 % del tiempo de la base** (233.157 s de ejecución en
120 h de reloj) y por eso la app tiraba `canceling statement due to statement timeout` al azar.

**Quién la usa:** sólo el cron 34. `grep` en el repo: ninguna llamada desde el front de Gestión
(`index.html`, `recepcion.js`, `planimetria.js`). Producción Virgilio no la llama —es una función
de alerta server-side, no hay `rpc/detectar_faltantes_llegaron` en ningún front—, así que no hay
pantalla que pueda cambiar de comportamiento. Lo que sí toca son las tablas de siempre
(`Faltantes_Tareas` + Telegram), y eso no cambió.

**Rollback exacto:**

```sql
-- correr sql/backups/detectar_faltantes_llegaron_pre_v1945.sql
```

⚠ Ese rollback devuelve la versión de 64,7 s por corrida cada 2 minutos. Sólo tiene sentido si el
arreglo resultara incorrecto, y la equivalencia está verificada sobre el 100 % de los datos.

**Lo que NO se tocó** y queda anotado como pendiente (§3.iz): `reconciliar_pipeline_stock()`
(17,9 s de media, cron 68), la cola del `pg_advisory_xact_lock(5768)` entre los crons 57 y 68
(media de 4,6 s de espera pura) y `ppp_web_armar_tandas`, que ya llega a 7,7 s contra el límite
de 8 s.
