-- =====================================================================================
-- gv_proyeccion_una_sola_tabla_v1817.sql — LA PROYECCION EN UNA SOLA TABLA
-- ✅ APLICADO el 2026-09-15. Problema 222 · tarea Planify 3412.
-- Toca los DOS proyectos: LK (kwkclwhmoygunqmlegrg) y Virgilio (hrxfctzncixxqmpfhskv).
--
-- EL PEDIDO. Thomas: *"no quiero que la proyeccion este en dos tablas distintas, solo una"*.
--
-- COMO ESTABA
-- ---------------------------------------------------------------------------------
--   | tabla               | filas | cron en LK   | motor                          |
--   | proyeccion_madre    |  461  | 25 · mie 09:20 | fn_proyeccion_oc_virgilio()  |
--   | GV_Proyeccion_Emp   |  533  | 40 · mie 09:25 | fn_proyeccion_importados_emp()|
--
-- Los mismos 461 codigos, y **70 no coincidian**: 22.305,87 contra 23.341,78 cj/mes (+4,6%).
-- Peores: 816E 107,50 vs 230,17 · 574 86,67 vs 162,67 · 812E 20,00 vs 81,42 · 106E 5,67 vs 50,92.
--
-- LA CAUSA. Los dos motores usan el mismo metodo (ventana de 6 meses, con fallback a 12 si
-- la de 6 da 0), pero `_fn_proy_window_emp()` lo corre POR EMPRESA y decide el fallback por
-- empresa: un codigo sin ventas en Chef los ultimos 6 meses tomaba el promedio de 12 de Chef
-- y se lo sumaba a la ventana de 6 de LK. Mezclaba ventanas. Y hay un segundo sesgo, mas
-- sutil, que sobrevive aunque no haya fallback: el valor de la ventana de 6 es
-- `greatest(promedio, 4to mes mas alto)`, y la suma de ese maximo calculado por empresa es
-- siempre >= el maximo calculado sobre la serie junta. Por eso el partido SIEMPRE daba mas.
--
-- COMO QUEDA
-- ---------------------------------------------------------------------------------
-- Una sola tabla, `proyeccion_madre`, con dos columnas nuevas: `proy_cajas_lk` y
-- `proy_cajas_chef`. **El desglose es un REPARTO del total**, no un segundo calculo: se
-- calcula el total exactamente como antes y se parte segun cuanto facturo cada empresa en
-- esa misma ventana. Por construccion `lk + chef = proy_cajas_mes`, fila por fila.
--
-- ⚠ Decision, y por que: el total **no se movio ni un centesimo** (22.305,87 antes y
--   despues). El total es el numero que manda las OC; unificar una tabla no puede cambiar
--   de paso cuanto se le compra a un tallerista. Lo que cambia es el desglose, que ahora
--   cierra. La alternativa —quedarse con la suma de las partes— habria subido el total 4,6%
--   arrastrando el sesgo de arriba, que es un artefacto del `greatest`, no demanda real.
--
-- Efecto concreto: 513 tenia "LK 1.132,17 + CH 29,83" contra un total de 1.132,17. Ahora el
-- Chef del 513 en la ventana de 6 meses es 0 —no le compro nada en 6 meses; los 29,83 salian
-- del fallback de 12— y el 513L, que es la variante Chef, sigue con sus 72 cj/mes en Chef.
--
-- Medido el 2026-09-15 sobre las 461 filas: 0 filas donde lk + chef <> total ·
-- total 22.305,87 (identico) · LK 18.358,55 · Chef 3.947,32.
--
-- QUE SE FUE
-- ---------------------------------------------------------------------------------
--   Virgilio: la tabla `GV_Proyeccion_Emp` (respaldada en
--             zz_backups."GV_Backup_ProyeccionEmp_20260915").
--   LK:       el cron 40 `sync-proyeccion-emp-virgilio`, `sync_proyeccion_emp_virgilio()`,
--             `fn_proyeccion_importados_emp()`, `_fn_proy_window_emp()` y la foreign table
--             `virgilio."GV_Proyeccion_Emp"`.
-- Queda UN cron (25, miercoles 09:20), UN motor y UNA tabla.
--
-- Las vistas muertas `E. Madre LK` / `E. Madre CH` NO se tocaron: son vistas, no tablas, no
-- guardan nada y nadie las refresca. Si molestan, se dropean aparte.
-- =====================================================================================


-- 1) EN LK (kwkclwhmoygunqmlegrg) =====================================================

-- 1a) la ventana, ahora con el reparto por empresa adentro del mismo calculo
create or replace function public._fn_proy_window_split(p_meses integer)
 returns table(item text, proy_cajas numeric, proy_lk numeric, proy_chef numeric)
 language sql stable security definer
 set search_path to 'public' set statement_timeout to '60s'
as $function$
  with vent as (select greatest(coalesce(p_meses,6),1)::int as meses),
  mm as (
    select least(max(extract(year from (invoice_date)::date)::int*12 + extract(month from (invoice_date)::date)::int), (extract(year from current_date)::int*12 + extract(month from current_date)::int) - 1) as endm
    from public.sales_lines where invoice_date ~ '^\d{4}-\d{2}-\d{2}'
  ),
  norm as (
    select regexp_replace(upper(sl.item_code),'^0+(?=.)','') as nitem,
           (extract(year from (sl.invoice_date)::date)::int*12 + extract(month from (sl.invoice_date)::date)::int) as midx,
           sl.empresa as emp,
           sl.boxes::numeric as v
    from public.sales_lines sl, mm, vent
    where sl.invoice_date ~ '^\d{4}-\d{2}-\d{2}'
      and sl.customer_code is not null and sl.customer_code not in ('1','3878')
      and sl.empresa in ('lk','chef')
      and (extract(year from (sl.invoice_date)::date)::int*12 + extract(month from (sl.invoice_date)::date)::int)
          between mm.endm - (vent.meses - 1) and mm.endm
  ),
  base as (
    select coalesce(r.to_code, nz.nitem) as item, nz.midx,
           sum(nz.v) as v,
           sum(nz.v) filter (where nz.emp = 'lk') as v_lk
    from norm nz
    left join public.sales_item_remap r on r.from_code = nz.nitem
    where not exists (select 1 from public.sales_excluded_items e where e.item_code = nz.nitem)
    group by 1,2
  ),
  grid as (
    select i.item, g as midx
    from (select distinct item from base) i, mm, vent, generate_series(mm.endm - (vent.meses - 1), mm.endm) g
  ),
  serie as (
    select g.item, g.midx, coalesce(b.v, 0) as v, coalesce(b.v_lk, 0) as v_lk
    from grid g left join base b on b.item = g.item and b.midx = g.midx
  ),
  st as (
    select item,
           sum(v) / (select meses from vent) as media,
           (array_agg(v order by v desc))[least(4, (select meses from vent))] as m4,
           sum(v) as tot, sum(v_lk) as tot_lk
    from serie group by item
  ),
  p as (
    select item,
           round(case when (select meses from vent) <= 6 then greatest(media, coalesce(m4, 0)) else media end, 2) as proy,
           case when tot > 0 then tot_lk / tot else 1 end as share_lk
    from st
  )
  select item, proy,
         round(proy * share_lk, 2) as proy_lk,
         proy - round(proy * share_lk, 2) as proy_chef
  from p;
$function$;

-- 1b) el motor unico. Cambia el tipo de retorno, asi que va DROP + CREATE.
drop function if exists public.fn_proyeccion_oc_virgilio();
create function public.fn_proyeccion_oc_virgilio()
 returns table(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric,
               proy_cajas_lk numeric, proy_cajas_chef numeric)
 language sql stable security definer
 set search_path to 'public' set statement_timeout to '60s'
as $function$
  with p6 as (select item, proy_cajas, proy_lk, proy_chef from public._fn_proy_window_split(6)),
       p12 as (select item, proy_cajas, proy_lk, proy_chef from public._fn_proy_window_split(12)),
       merged as (
         select coalesce(p6.item, p12.item) as item,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_cajas
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_cajas else 0 end as proy_cajas,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_lk
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_lk else 0 end as proy_lk,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_chef
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_chef else 0 end as proy_chef
         from p6 full join p12 on p12.item = p6.item
       ),
       -- NNNL (513L): variante Chef de un articulo de Loeke, sin ficha propia. El uni x caja
       -- se resuelve del codigo base pelando la L (misma regla que gv_cod_stock de Virgilio).
       conbase as (
         select item, proy_cajas, proy_lk, proy_chef,
                regexp_replace(item, '([0-9E])L$', '\1') as base
         from merged
       )
  select m.item as cod, m.proy_cajas as proy_cajas_mes,
         coalesce(p.uxb, lk.uxb, pb.uxb, lkb.uxb)::integer as uxb,
         round(m.proy_cajas * coalesce(p.uxb, lk.uxb, pb.uxb, lkb.uxb, 1))::numeric as proy_uni_mes,
         m.proy_lk as proy_cajas_lk, m.proy_chef as proy_cajas_chef
  from conbase m
  left join public.products p on regexp_replace(upper(p.cod),'^0+(?=.)','') = m.item
  left join public.loke_products lk on regexp_replace(upper(lk.cod),'^0+(?=.)','') = m.item
  left join public.products pb on m.base <> m.item and regexp_replace(upper(pb.cod),'^0+(?=.)','') = m.base
  left join public.loke_products lkb on m.base <> m.item and regexp_replace(upper(lkb.cod),'^0+(?=.)','') = m.base
  where m.proy_cajas > 0
  order by m.proy_cajas desc;
$function$;
revoke all on function public.fn_proyeccion_oc_virgilio() from public;
grant execute on function public.fn_proyeccion_oc_virgilio() to service_role;

-- 1c) la foreign table y el sync, que ahora bajan tambien el desglose
alter foreign table virgilio.proyeccion_madre add column proy_cajas_lk numeric;
alter foreign table virgilio.proyeccion_madre add column proy_cajas_chef numeric;
-- (cuerpo completo de sync_proyeccion_madre_virgilio(): ver el objeto vivo; lo unico que
--  cambio es que la temporal y el insert llevan proy_cajas_lk y proy_cajas_chef)

-- 1d) se retira el motor por empresa
select cron.unschedule('sync-proyeccion-emp-virgilio');
drop function if exists public.sync_proyeccion_emp_virgilio();
drop function if exists public.fn_proyeccion_importados_emp();
drop function if exists public._fn_proy_window_emp(integer, text);
drop foreign table if exists virgilio."GV_Proyeccion_Emp";


-- 2) EN VIRGILIO (hrxfctzncixxqmpfhskv) ===============================================
alter table public.proyeccion_madre add column if not exists proy_cajas_lk numeric;
alter table public.proyeccion_madre add column if not exists proy_cajas_chef numeric;

-- Los 4 consumidores de GV_Proyeccion_Emp se repuntaron metiendo, EN EL FROM y conservando
-- el alias, un subselect con exactamente las mismas columnas (cod, empresa, proy_cajas_mes),
-- asi no hubo que reescribir ni una referencia de arriba:
--
--   FROM "GV_Proyeccion_Emp"        ->  FROM ( <el subselect> ) "GV_Proyeccion_Emp"
--   FROM "GV_Proyeccion_Emp" g      ->  FROM ( <el subselect> ) g
--
--   (SELECT pm.cod, e.empresa, e.proy_cajas_mes
--      FROM proyeccion_madre pm
--      CROSS JOIN LATERAL (VALUES ('lk'::text,   COALESCE(pm.proy_cajas_lk,   (0)::numeric)),
--                                 ('chef'::text, COALESCE(pm.proy_cajas_chef, (0)::numeric))) e(empresa, proy_cajas_mes)
--     WHERE e.proy_cajas_mes > (0)::numeric)
--
-- Son: vista_stock_procesada (matview -> DROP CASCADE, que se lleva Stock_Saldos,
-- gv_importados_stock_dep y gv_importados_ordenes; las 3 se recrean en la misma transaccion
-- con security_invoker=true y sus grants), v_importados_ordenes y gv_stock_procesada_dup
-- (estas dos con create or replace + `alter view ... set (security_invoker = true)`, que
-- CREATE OR REPLACE VIEW borra las reloptions sin avisar).
-- El bloque exacto que se corrio esta en la migracion `proyeccion_una_sola_tabla_v1817`.
-- Respaldos: zz_backups."GV_Backup_Defs_Proyeccion_20260915" (las 6 definiciones vivas) y
-- zz_backups."GV_Backup_ProyeccionEmp_20260915" (los datos de la tabla).

drop table public."GV_Proyeccion_Emp";
select public.refresh_stocks_carga_rapida();


-- 3) VERIFICAR ========================================================================
-- (a) el desglose cierra contra el total, fila por fila -> 0
select count(*) from public.proyeccion_madre
 where round(coalesce(proy_cajas_lk,0) + coalesce(proy_cajas_chef,0), 2) <> proy_cajas_mes;

-- (b) el total no se movio -> 22305.87
select round(sum(proy_cajas_mes),2) total, round(sum(proy_cajas_lk),2) lk,
       round(sum(proy_cajas_chef),2) chef from public.proyeccion_madre;

-- (c) no quedo nada roto por el CASCADE -> vacio
select * from public.gv_endpoints_rotos;

-- (d) las 5 vistas conservan security_invoker -> vacio
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname='public' and c.relkind='v'
   and c.relname in ('Stock_Saldos','gv_importados_stock_dep','gv_importados_ordenes',
                     'v_importados_ordenes','gv_stock_procesada_dup')
   and coalesce(array_to_string(c.reloptions,','),'') not like '%security_invoker%';

-- (e) la tabla vieja no existe mas, y las pantallas siguen trayendo lo mismo
--     (esperado: 0 · 369 · 156 · 156 · 0)
select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='GV_Proyeccion_Emp') tabla_vieja,
       (select count(*) from public.stocks_carga_rapida) stocks,
       (select count(*) from public.gv_importados_ordenes) imp,
       (select count(*) from public.v_importados_ordenes) v_imp,
       (select count(*) from public.gv_stock_procesada_dup) dups;


-- 4) ROLLBACK =========================================================================
-- En Virgilio: recrear GV_Proyeccion_Emp desde zz_backups."GV_Backup_ProyeccionEmp_20260915"
--   (con RLS y las 2 policies: gv_proy_emp_read para anon/authenticated y gv_proy_emp_writer
--   para lk_ppp_reader), y volver las 6 definiciones desde
--   zz_backups."GV_Backup_Defs_Proyeccion_20260915" (la matview con DROP + CREATE + el indice
--   unico por cod, las vistas con security_invoker=true y sus grants).
-- En LK: volver fn_proyeccion_oc_virgilio() a 4 columnas (ver
--   sql/fn_proyeccion_oc_virgilio_uxb_base_L_v1816.sql), recrear _fn_proy_window_emp,
--   fn_proyeccion_importados_emp y sync_proyeccion_emp_virgilio, la foreign table
--   virgilio."GV_Proyeccion_Emp" y el cron:
--   select cron.schedule('sync-proyeccion-emp-virgilio','25 9 * * 3',
--                        'select public.sync_proyeccion_emp_virgilio();');
