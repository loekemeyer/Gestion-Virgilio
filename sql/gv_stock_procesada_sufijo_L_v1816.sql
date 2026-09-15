-- =====================================================================================
-- gv_stock_procesada_sufijo_L_v1816.sql
-- Los codigos NNNL (variante Chef de un articulo de Loeke) dejan de ser articulos
-- aparte en la pantalla Stocks.   ✅ APLICADO el 2026-09-15 (antes v1811, sin aplicar).
-- Problema 218 de github_repo_problemas · tarea Planify 3405.
--
-- EL PROBLEMA
-- ---------------------------------------------------------------------------------
-- 513L es el codigo con el que Chef le vende a sus clientes mercaderia de Loeke: es el
-- MISMO articulo que 513, se pickea de la gondola LK y no tiene stock propio (regla del
-- dueño, v13.71). Pero en la pantalla Stocks figuraba como una fila propia, con stock 0,
-- linea null, descripcion = el codigo y familia_principal apuntando a si misma.
--
-- POR DONDE ENTRABA. No por el stock: `vista_saldos_stock` no tiene ninguna fila NNNL.
-- El universo de la matview es `stock_e UNION dem_raw`, asi que entraba por la DEMANDA:
-- un pedido de Chef con articulo 513L. `dem_raw` / `dem_oc_raw` normalizaban con
--     regexp_replace(upper(resolver_equiv(...)), '^0+(?=.)', '')
-- que saca los ceros a la izquierda y nada mas. La L sobrevivia y nacia un codigo nuevo.
--
-- LA SOLUCION es la funcion canonica que YA EXISTE y que ya usa `vista_generador_oc`:
--   gv_cod_stock('513L') = '513'   (saca '·...', ' LK|CH|LOKE', ceros a la izquierda y la L)
-- Por eso el generador de OC no tenia el codigo partido y la pantalla si.
--
-- SE TOCAN LOS DOS CTE: LA DEMANDA **Y** LA PROYECCION
-- ---------------------------------------------------------------------------------
-- ⚠ La version v1811 de este archivo fundia SOLO la demanda, a proposito, porque creia
--   que `proyeccion_madre.proy_cajas_mes` de los NNNL venia inflado. Estaba al reves:
--   lo inflado nunca fue `proy_cajas_mes` (sale de sales_lines.boxes, o sea ya en cajas),
--   sino `proy_uni_mes`, por el uni-x-caja que caia en 1. Eso se arreglo en LK el mismo
--   dia — `sql/fn_proyeccion_oc_virgilio_uxb_base_L_v1816.sql` — y recien DESPUES se
--   aplico esto. Con el motor arreglado, fundir tambien `proy` es lo correcto:
--     · 513L declara 72 cj/mes de demanda REAL de Chef; son del articulo 513
--     · si no se funde, esa proyeccion queda huerfana (la fila NNNL sale del universo
--       porque no tiene stock ni demanda propia) y se pierde de la pantalla
--     · el desglose por empresa ("513 CH") ya venia fundiendo la L, porque el otro brazo
--       del UNION ALL usa gv_cod_stock sobre GV_Proyeccion_Emp: fundir el total lo acerca
--       a que total y desglose digan lo mismo (lo que falta para eso es el problema 222)
--
-- MEDIDO el 2026-09-15, antes -> despues sobre `stocks_carga_rapida`:
--   · filas            425 -> 369   (-56, las 56 NNNL visibles)
--   · filas NNNL        56 -> 0
--   · demanda total  5.501,66 -> 5.501,66   (re-atribucion, no alta ni baja)
--   · proyeccion    21.693,16 -> 22.496,21  (+803,05: la que colgaba de las filas NNNL)
--   · 513: cajas_pedidas 184 -> 190 (+6, las del 513L) · proy 1.132,17 -> 1.204,17 (+72)
--   · 798E: cajas_pedidas 2 -> 30
--   · gv_endpoints_rotos: 0 · las 3 vistas dependientes con security_invoker: OK
--
-- ⚠ NO USAR `Equivalencias_Familia` para mapear 513L->513: la leen
--   notificar_pedido_secundario_telegram() y corregir_pedido_secundario_auto(), que le
--   sacarian la L a los pedidos de Chef — justo lo contrario de la regla del dueño.
--
-- RESPALDO. Las definiciones previas de la matview y de sus 3 vistas dependientes estan
-- en zz_backups."GV_Backup_Defs_StockProcesada_20260915". El rollback del final las lee
-- de ahi, asi que es exacto. (Ojo: ese respaldo se guardo con pg_get_viewdef sin pretty;
-- comparado contra la version linda difiere solo en parentesis y espacios.)
--
-- ⚠ Es matview: no hay CREATE OR REPLACE, hay que DROP + CREATE. El CASCADE se lleva
--   Stock_Saldos, gv_importados_stock_dep y, en segundo nivel, gv_importados_ordenes
--   — la que ya se cayo dos veces por esto (v16.20 y v16.33). Las tres se recrean en la
--   MISMA transaccion, con security_invoker=true y sus grants.
-- =====================================================================================


-- 1) APLICAR ==========================================================================
do $mig$
declare
  v_def text; v_new text; v_ss text; v_dep text; v_ord text; v_obj text; c1 int; c2 int;
  a1 text := 'regexp_replace(upper(resolver_equiv(TRIM(BOTH FROM b.articulo))), ''^0+(?=.)''::text, ''''::text)';
  n1 text := 'gv_cod_stock(resolver_equiv(TRIM(BOTH FROM b.articulo)))';
  a2 text := 'regexp_replace(upper(TRIM(BOTH FROM proyeccion_madre.cod)), ''^0+(?=.)''::text, ''''::text)';
  n2 text := 'gv_cod_stock(proyeccion_madre.cod)';
begin
  set local statement_timeout = '300s';

  select def into v_def from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'vista_stock_procesada';
  select def into v_ss  from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'Stock_Saldos';
  select def into v_dep from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'gv_importados_stock_dep';
  select def into v_ord from zz_backups."GV_Backup_Defs_StockProcesada_20260915" where obj = 'gv_importados_ordenes';
  if v_def is null or v_ss is null or v_dep is null or v_ord is null then
    raise exception 'falta alguna definicion en el backup';
  end if;

  -- 4 = dem_raw (SELECT + GROUP BY) + dem_oc_raw (SELECT + GROUP BY)
  -- 2 = el CTE proy, brazo de proyeccion_madre (SELECT + GROUP BY)
  -- Si no son esos numeros, la definicion cambio desde el 15/09: parar y volver a mirarla,
  -- no reemplazar a ciegas.
  c1 := (length(v_def) - length(replace(v_def, a1, ''))) / length(a1);
  if c1 <> 4 then raise exception 'demanda: esperaba 4 ocurrencias, hay %', c1; end if;
  c2 := (length(v_def) - length(replace(v_def, a2, ''))) / length(a2);
  if c2 <> 2 then raise exception 'proyeccion: esperaba 2 ocurrencias, hay %', c2; end if;

  v_new := replace(replace(v_def, a1, n1), a2, n2);
  if position('gv_cod_stock(resolver_equiv' in v_new) = 0
     or position('gv_cod_stock(proyeccion_madre.cod)' in v_new) = 0 then
    raise exception 'el reemplazo no quedo';
  end if;

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

-- (d) 513 se quedo con lo que tenia el 513L (esperado: 190 cajas y proy 1204.17)
select cod, cajas_pedidas, proy_cajas_mes, stock_total
  from public.stocks_carga_rapida where cod in ('513','505','798E');

-- (e) la demanda total no se movio: es re-atribucion, no alta ni baja (esperado 5501.66)
select round(sum(cajas_pedidas), 2) from public.stocks_carga_rapida;


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
