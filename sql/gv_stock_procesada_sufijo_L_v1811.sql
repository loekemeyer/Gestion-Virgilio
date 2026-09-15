-- =====================================================================================
-- gv_stock_procesada_sufijo_L_v1811.sql
-- Los codigos NNNL (variante Chef de un articulo de Loeke) dejan de ser articulos
-- aparte en la pantalla Stocks.
--
-- ⚠ NO APLICADO TODAVIA: la DDL quedo frenada por permisos en la sesion del 15/09.
--    Para aplicarlo, correr el bloque "1) APLICAR" con el MCP de Supabase.
--
-- EL PROBLEMA (problema 218 de github_repo_problemas)
-- ---------------------------------------------------------------------------------
-- 513L es el codigo con el que Chef le vende a sus clientes mercaderia de Loeke: es el
-- MISMO articulo que 513, se pickea de la gondola LK y no tiene stock propio (regla del
-- dueño, v13.71). Pero en la pantalla Stocks figura como una fila propia, con stock 0,
-- linea null, descripcion = el codigo y familia_principal apuntando a si misma.
--
-- POR DONDE ENTRA. No por el stock: `vista_saldos_stock` no tiene ninguna fila NNNL.
-- El universo de la matview es `stock_e UNION dem_raw`, asi que entra por la DEMANDA:
-- un pedido de Chef con articulo 513L. `dem_raw` / `dem_oc_raw` normalizan con
--     regexp_replace(upper(resolver_equiv(...)), '^0+(?=.)', '')
-- que saca los ceros a la izquierda y nada mas. La L sobrevive y nace un codigo nuevo.
--
-- Medido el 2026-09-15 sobre `stocks_carga_rapida`:
--   · 56 filas NNNL visibles, todas con stock 0
--   · 192 cajas pedidas que NO se le suman a su codigo base -> la pantalla muestra menos
--     demanda de la real en los 56 codigos madre
--   · 807,51 cj/mes de proyeccion colgando de esas filas
-- Simulacion de la demanda con la normalizacion nueva (SELECT, sin escribir):
--   290 codigos -> 237; se funden 56; se mueven 192 cajas; total 5.426,66 cajas intacto.
--
-- LA SOLUCION es la funcion canonica que YA EXISTE y que ya usa `vista_generador_oc`:
--   gv_cod_stock('513L') = '513'   (saca '·...', ' LK|CH|LOKE', ceros a la izquierda y la L)
-- Por eso el generador de OC nunca estuvo afectado y la pantalla si.
--
-- ⚠⚠ SOLO SE TOCA LA DEMANDA, NO LA PROYECCION — y es a proposito.
-- El CTE `proy` tambien normaliza con el regex viejo, pero fundirlo HOY contaminaria al
-- codigo base: los 124 NNNL de `proyeccion_madre` vienen calculados a uni x caja = 1
-- (declaran 1.610,56 cj/mes cuando al uxb real son 145,34). Medido lo que pasaria:
--   106E: proy real 5,67 -> quedaria 105,67   (18x)
--   123 : proy real 49,17 -> quedaria 191,17  (4x)
--   31  : proy real 489,33 -> quedaria 680,33
-- Fundiendo SOLO la demanda, las filas NNNL desaparecen del universo (no tienen stock) y
-- su proyeccion inflada queda huerfana, o sea deja de mostrarse: es estrictamente mejor.
-- La segunda etapa (fundir tambien `proy`) recien cuando se arregle el motor en LK:
-- `fn_proyeccion_oc_virgilio()` del proyecto kwkclwhmoygunqmlegrg, que es donde nace el
-- uni x caja = 1. Ver la tarea "Th Sacar los codigos NNNL de la pantalla Stocks".
--
-- RESPALDO. Las definiciones previas de la matview y de sus 3 vistas dependientes, con
-- reloptions e indices, estan en zz_backups."GV_Backup_Defs_StockProcesada_20260915".
-- El rollback del final las lee de ahi, asi que es exacto.
--
-- ⚠ Es matview: no hay CREATE OR REPLACE, hay que DROP + CREATE. El CASCADE se lleva
--   Stock_Saldos, gv_importados_stock_dep y, en segundo nivel, gv_importados_ordenes
--   — la que ya se cayo dos veces por esto (v16.20 y v16.33). Las tres se recrean en la
--   MISMA transaccion, con security_invoker=true y sus grants.
-- =====================================================================================


-- 1) APLICAR ==========================================================================
do $mig$
declare
  v_def text; v_new text; v_ss text; v_dep text; v_ord text;
  a1 text := 'regexp_replace(upper(resolver_equiv(TRIM(BOTH FROM b.articulo))), ''^0+(?=.)''::text, ''''::text)';
  n1 text := 'gv_cod_stock(resolver_equiv(TRIM(BOTH FROM b.articulo)))';
  c1 int; v_obj text;
begin
  set local statement_timeout = '300s';

  select def into v_def from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'vista_stock_procesada';
  select def into v_ss  from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'Stock_Saldos';
  select def into v_dep from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'gv_importados_stock_dep';
  select def into v_ord from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'gv_importados_ordenes';
  if v_def is null or v_ss is null or v_dep is null or v_ord is null then
    raise exception 'falta alguna definicion en el backup';
  end if;

  -- 4 = dem_raw (SELECT + GROUP BY) + dem_oc_raw (SELECT + GROUP BY). Si no son 4, la
  -- definicion cambio desde el 15/09: parar y volver a mirarla, no reemplazar a ciegas.
  c1 := (length(v_def) - length(replace(v_def, a1, ''))) / length(a1);
  if c1 <> 4 then raise exception 'demanda: esperaba 4 ocurrencias, hay %', c1; end if;

  v_new := replace(v_def, a1, n1);
  if position('gv_cod_stock(resolver_equiv' in v_new) = 0 then raise exception 'el reemplazo no quedo'; end if;

  execute 'drop materialized view public.vista_stock_procesada cascade';
  execute 'create materialized view public.vista_stock_procesada as ' || v_new;
  execute 'create unique index idx_vista_stock_procesada_cod on public.vista_stock_procesada using btree (cod)';

  execute 'create view public."Stock_Saldos" with (security_invoker=true) as ' || v_ss;
  execute 'create view public.gv_importados_stock_dep with (security_invoker=true) as ' || v_dep;
  execute 'create view public.gv_importados_ordenes with (security_invoker=true) as ' || v_ord;

  foreach v_obj in array array['"Stock_Saldos"','gv_importados_stock_dep','gv_importados_ordenes'] loop
    execute 'grant select, insert, update, delete, references, trigger on public.' || v_obj || ' to anon';
    execute 'grant select, insert, update, delete, references, trigger, truncate on public.' || v_obj || ' to authenticated, service_role';
  end loop;
end $mig$;

-- la tabla que lee la pantalla es un espejo de la matview; el refresh borra las
-- filas huerfanas solo, asi que los 56 NNNL se van sin tocar nada a mano.
select public.refresh_stocks_carga_rapida();


-- 2) VERIFICAR ========================================================================
-- (a) no quedan endpoints rotos por el CASCADE  -> tiene que dar VACIO
select * from public.gv_endpoints_rotos;

-- (b) las 3 vistas conservan security_invoker   -> tiene que dar VACIO
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'v'
   and c.relname in ('Stock_Saldos','gv_importados_stock_dep','gv_importados_ordenes')
   and coalesce(array_to_string(c.reloptions, ','), '') not like '%security_invoker%';

-- (c) no queda ningun NNNL en la pantalla       -> tiene que dar 0
select count(*) from public.stocks_carga_rapida where upper(btrim(cod)) ~ '^[0-9]+[A-Z]*L$';

-- (d) 513 se quedo con las 6 cajas que tenia el 513L, y su proyeccion NO cambio
--     (esperado: cajas_pedidas +6, proy_cajas_mes sigue en 1132.17)
select cod, cajas_pedidas, proy_cajas_mes, stock_total
  from public.stocks_carga_rapida where cod in ('513','505','838','798E');

-- (e) la demanda total no se movio: es re-atribucion, no alta ni baja
select round(sum(cajas_pedidas), 2) from public.stocks_carga_rapida;   -- antes: ver nota


-- 3) ROLLBACK =========================================================================
-- Vuelve exactamente a lo que habia el 2026-09-15, leyendo del mismo respaldo.
do $rb$
declare v_def text; v_ss text; v_dep text; v_ord text; v_obj text;
begin
  set local statement_timeout = '300s';
  select def into v_def from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'vista_stock_procesada';
  select def into v_ss  from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'Stock_Saldos';
  select def into v_dep from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'gv_importados_stock_dep';
  select def into v_ord from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'gv_importados_ordenes';

  execute 'drop materialized view public.vista_stock_procesada cascade';
  execute 'create materialized view public.vista_stock_procesada as ' || v_def;
  execute 'create unique index idx_vista_stock_procesada_cod on public.vista_stock_procesada using btree (cod)';
  execute 'create view public."Stock_Saldos" with (security_invoker=true) as ' || v_ss;
  execute 'create view public.gv_importados_stock_dep with (security_invoker=true) as ' || v_dep;
  execute 'create view public.gv_importados_ordenes with (security_invoker=true) as ' || v_ord;
  foreach v_obj in array array['"Stock_Saldos"','gv_importados_stock_dep','gv_importados_ordenes'] loop
    execute 'grant select, insert, update, delete, references, trigger on public.' || v_obj || ' to anon';
    execute 'grant select, insert, update, delete, references, trigger, truncate on public.' || v_obj || ' to authenticated, service_role';
  end loop;
end $rb$;
select public.refresh_stocks_carga_rapida();
