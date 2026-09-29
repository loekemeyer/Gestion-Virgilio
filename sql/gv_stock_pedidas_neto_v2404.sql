-- ============================================================================
-- v24.04 (Luis, 2026-09-29) — LAS CAJAS PEDIDAS SE CONTEMPLAN IGUAL EN STOCKS Y EN OCs
--
-- Luis: *"si lo comprometido no es stock disponible, esta bien. pero se tiene que contemplar
-- igual en OCs que en Stocks"* · *"el neto adelante y el pickeado en el tooltip (que pickeado
-- seria «pickeados», osea los que TP, y los que estan pickeados ahora sin TP. que lo aclare
-- el tooltip)"* · *"que el tooltip avise en casos de familia y escondelo cuando da 0 (si a uno
-- con familia tiene valor, mostralo en toda la familia)"*.
--
-- EL PROBLEMA, medido el 29/09 sobre el 501: Stocks dice 251 cajas pedidas y OCs dice 225. No
-- es redondeo: son DOS COLUMNAS DE LA MISMA FILA de vista_stock_procesada con dos criterios
-- —`cajas_pedidas` (toda la demanda viva) y `cajas_pedidas_familia` (sin las NP cuya tanda ya
-- tiene TP, regla v19.85 de Thomas)— y cada pantalla lee una. El criterio de OCs es el bueno y
-- NO se toca: una caja ya pickeada esta separada para su pedido, no es demanda a comprar, igual
-- que no es stock disponible. La que contaba de mas era Stocks.
--
-- Impacto: 109 codigos, 13.132,33 -> 11.279,33 cajas pedidas. CERO en la compra: el generador
-- de OC ya usaba el neto.
--
-- ⚠⚠ ESTA VERSION REEMPLAZA A gv_stock_pedidas_neto_v2402.sql, QUE TENIA UN BUG GRAVE y por eso
-- no se ejecuto: parchaba refresh_stocks_carga_rapida() con un LEFT JOIN LATERAL contra una
-- funcion set-returning, que NO se inlinea (SET search_path) y se habria ejecutado UNA VEZ POR
-- FILA: 367 x 682 ms = ~4 minutos por refresco, cada 2. Es el pozo de gv_destino_score (v20.62)
-- y gv_espejo_np_pasa (v20.78) otra vez. Medido antes de aplicarlo.
--
-- LO QUE HACE ESTA: UN SOLO OBJETO NUEVO. Nada existente se toca.
--   · NO toca vista_stock_procesada (matview: su DROP CASCADE arrastra Stock_Saldos,
--     gv_importados_stock_dep y, en 2.o nivel, gv_importados_ordenes — lo que dejo Importados
--     en 404 en la v16.20 y la v16.33).
--   · NO toca refresh_stocks_carga_rapida() (la editan varias sesiones, esta protegida por el
--     hook) ni stocks_carga_rapida ni vista_generador_oc.
--   · NO toca `cajas_pedidas`, que sostiene `visible_en_stock`: sin eso 9 codigos quedarian en
--     0 pedidos y 5 —198E, 951E, 952E, 953E, 970E— se irian del listado por tener stock 0,
--     que es el pozo de la v20.95.
--   · Si la vista falla o no esta, el front cae al total y la pantalla sigue andando.
--
-- ROLLBACK, una linea:   drop view if exists public.gv_stock_pedidas_neto;
--
-- ✅ APLICADA el 29/09 con el si de Luis. Backup previo de la derivada que lee la pantalla:
--    zz_backups."GV_Backup_StocksCargaRapida_20260929" (367 filas, RLS prendida y escritura
--    revocada en el mismo paso). No hacia falta —la vista no toca nada existente— pero Luis lo
--    pidio: *"hace un backup por si acaso, despues se limpia si todo ok"*.
--
-- MEDIDO al aplicarla (29/09), no en transaccion abortada:
--   · 237 filas · 550 / 548 / 555 ms como `authenticated` (timeout del rol: 8.000 ms, o sea 14x
--     de margen) · anon ve las 237 (NO cae en la trampa de la v20.45: una vista
--     security_invoker sobre tablas con RLS no da error, da MENOS filas — se probo con
--     `set local role anon`, no desde el MCP, que entra como postgres).
--   ⚠ La pantalla la lee EN PARALELO y sin await (Luis: *"hace la carga en paralelo, evalua para
--     evitar timeouts"*): la tabla se dibuja con el total y se redibuja cuando llega el neto. Si
--     la lectura falla o tarda, Stocks queda igual que la v24.03. Techo de 20 s en el fetch, que
--     es para la RED colgada: la base corta sola a los 8 s.
--   · suma de `total` = 13.132,3334 = `sum(cajas_pedidas)` de la matview, EXACTO: la vista
--     replica el total y por eso la resta (total = neto + con_tp) cierra.
--   · 501: tot 251 / neto 225 / tp 26 · 505: 551 / 481 / 70 · 839: fam 838E, es_secundario.
--   · 437E LK y 437E CH quedan SEPARADOS (son dos productos distintos, regla de los duales):
--     la familia agrupa por (principal, sufijo de empresa), no por el codigo pelado. Sin ese
--     `suf` en el partition, los dos duales caian en la misma bolsa.
-- ============================================================================

create or replace view public.gv_stock_pedidas_neto
with (security_invoker = true) as
with pick as (
  -- tandas con el picking TERMINADO: su demanda ya esta separada, no se compra
  select distinct upper(btrim(texto)) t
    from public."Registros_Produccion_Virgilio"
   where opcion = 'TP' and nullif(btrim(coalesce(texto,'')),'') is not null),
encurso as (
  -- picking EMPEZADO y sin cerrar: hay cajas levantadas de gondola pero la tanda no cerro, asi
  -- que esa demanda SIGUE contando. El texto de un PKC viene como 'TANDA|NP': la tanda es el
  -- primer campo (mismo criterio que gv_evento_tanda).
  select distinct upper(btrim(split_part(texto,'|',1))) t
    from public."Registros_Produccion_Virgilio"
   where opcion in ('EP','PKC') and nullif(btrim(coalesce(texto,'')),'') is not null
     and upper(btrim(split_part(texto,'|',1))) not in (select t from pick)),
cerradas as (
  -- las MISMAS cuatro fuentes que `dem_raw` de vista_stock_procesada, o el total no coincide
  select np from public."Facturacion_NP"             where np is not null
  union select np from public."GV_PPP_Entregados_Historico" where np is not null
  union select np from public."NP_Canceladas"        where np is not null
  union select np_label from public."GV_Web_Cancelados" where np_label is not null),
np_raw as (
  select btrim(p.np) np, upper(btrim(coalesce(p.tanda,''))) tanda
    from public."GV_PPP_Programacion_Diaria" p
  union all
  select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx), upper(btrim(coalesce(w.tanda,'')))
    from public."PPP_Web_Programacion" w),
np_t as (
  -- ⚠ UNA tanda por NP. Sin el distinct on, el left join MULTIPLICA la demanda de toda NP que
  --   este en las dos tablas: medido, el 501 daba 251 contra 235.
  select distinct on (np) np, tanda from np_raw order by np, (tanda <> '') desc, tanda),
d as (
  select public.gv_cod_stock_dem(b.articulo, b.pedido) c, btrim(b.pedido) np,
         sum(coalesce(b.cajas,0)) cajas
    from public.gv_demanda_pedidos b
   where nullif(btrim(b.articulo),'') is not null
     and not exists (select 1 from cerradas x where x.np = b.pedido)
   group by 1,2),
porcod as (
  select d.c cod,
         sum(d.cajas) total,
         coalesce(sum(d.cajas) filter (where coalesce(t.tanda,'') not in (select t from pick)),0) neto,
         coalesce(sum(d.cajas) filter (where coalesce(t.tanda,'')     in (select t from pick)),0) con_tp,
         coalesce(sum(d.cajas) filter (where coalesce(t.tanda,'')     in (select t from encurso)),0) en_curso
    from d left join np_t t on t.np = d.np
   group by d.c having sum(d.cajas) > 0),
fam as (
  select regexp_replace(upper(btrim(cod_secundario)),'^0+(?=.)','') sec,
         regexp_replace(upper(btrim(cod_principal)),'^0+(?=.)','')  ppal
    from public."Equivalencias_Familia"),
conbase as (
  -- el sufijo de empresa se pela SOLO para buscar la familia; la fila sigue siendo la del dual
  select p.*, regexp_replace(p.cod,'\s+(LK|CH|LOKE)$','') base,
         coalesce(substring(p.cod from '(\s+(?:LK|CH|LOKE))$'),'') suf
    from porcod p),
confam as (
  select c.*, coalesce(f.ppal, c.base) ppal_base
    from conbase c left join fam f on f.sec = c.base)
select cod,
       ppal_base || suf        as familia,
       ppal_base <> base       as es_secundario,
       total, neto, con_tp, en_curso,
       -- ⚠ la familia agrupa por (principal, EMPRESA): 437E LK y 437E CH son dos productos
       --   distintos y no se suman (regla de los duales).
       sum(neto)     over (partition by ppal_base, suf) as fam_neto,
       sum(con_tp)   over (partition by ppal_base, suf) as fam_con_tp,
       sum(en_curso) over (partition by ppal_base, suf) as fam_en_curso,
       count(*)      over (partition by ppal_base, suf) as fam_miembros
  from confam;

comment on view public.gv_stock_pedidas_neto is
  'v24.04 — Cajas pedidas de cada codigo partidas en NETO (lo que falta cubrir, el mismo '
  'criterio que usa el generador de OC), CON_TP (tanda con el picking terminado: ya separada, '
  'no se compra) y EN_CURSO (tanda con el picking empezado sin TP: sigue contando). La pantalla '
  'de Stocks muestra el neto y el resto en el tooltip. total = neto + con_tp, y la suma de '
  'total coincide con sum(cajas_pedidas) de vista_stock_procesada.';

grant select on public.gv_stock_pedidas_neto to anon, authenticated, service_role;

-- CHEQUEO
-- a) el total replica el de la matview (si esto no da igual, la vista se desfaso):
--    select (select sum(total) from public.gv_stock_pedidas_neto) vista,
--           (select sum(cajas_pedidas) from public.vista_stock_procesada) matview;
-- b) que anon la vea (NO alcanza probarla desde el MCP, que entra como postgres):
--    do $$ declare n int; begin set local role anon;
--      select count(*) into n from public.gv_stock_pedidas_neto; reset role;
--      raise notice 'anon ve %', n; end $$;
-- c) la fila del 501 y el caso de familia:
--    select * from public.gv_stock_pedidas_neto where cod in ('501','839') ;
