-- v15.11 — Pedidos Importación: ventas por empresa + stock sincronizado con el depósito (2026-09-11, YA APLICADO)
-- Proyecto Supabase: hrxfctzncixxqmpfhskv. Detalle y medición: docs/SUPABASE-GESTION-VIRGILIO.md §3.bm.3
--
-- 1) Vista: el CTE `arm` toma Entregas_Virgilio con plant por gv_empresa (antes: todo a Loeke + Cervantes a Chef).
--    El resto es idéntico a sql/gv_importados_lk_ch_separados_v1501.sql.
--
--   ), arm as (
--     select gv_cod_stock(e.cod_art) as cod_norm,
--            case when lower(coalesce(e.gv_empresa,'')) = 'chef' then 'Chef' else 'Loeke' end as plant,
--            e.creado as ts, coalesce(e.cajas_entregadas, 0::numeric) as cajas
--     from public."Entregas_Virgilio" e
--   ), ventas as ( ... sin cambios ... )
--
-- 2) Backup + ajuste (98 movimientos, delta neto +122.177 u)
create table public."GV_Importados_Mov_Stock_bkp_20260911" as select * from public."Importados_Mov_Stock";

with dep as (
  select gv_cod_stock(cod_art) as cod, empresa,
         sum(coalesce(terminado,0)+coalesce(excedente,0)+coalesce(separar_pedidos,0)+coalesce(a_facturar,0)
            +coalesce(a_guardar,0)+coalesce(racks,0)+coalesce(racks_ch,0)+coalesce(para_envasar,0)) as cajas
  from public.vista_saldos_stock group by 1,2
), imp as (
  select o.id, o.cod_art, o.marca, gv_cod_stock(o.cod_art) as cod, o.uni_x_caja, o.stock_actual,
         case when upper(coalesce(o.marca,''))='CH' then 'CH' else 'LK' end as emp,
         case when upper(coalesce(o.marca,''))='CH' then 'Chef' else 'Loeke' end as plant,
         count(*) over (partition by gv_cod_stock(o.cod_art)) as filas_cod
  from public.v_importados_ordenes o
  where o.principal and o.activo
    and gv_cod_stock(o.cod_art) not in (select gv_cod_stock(parte) from public."Importados_Partes_Map")
), calc as (
  select i.*,
         round((coalesce(d1.cajas,0) + case when i.filas_cod = 1 or i.emp='LK' then coalesce(dm.cajas,0) else 0 end) * i.uni_x_caja) as objetivo_uni,
         exists (select 1 from public."Importados_Mov_Stock" ms where ms.tipo='inicial' and gv_cod_stock(ms.cod_art) = i.cod
                   and (case when upper(coalesce(ms.marca,''))='CH' then 'Chef' else 'Loeke' end) = i.plant) as tiene_inicial
  from imp i
  left join dep d1 on d1.cod = i.cod and d1.empresa = i.emp
  left join dep dm on dm.cod = i.cod and dm.empresa = 'Mixto'
  where i.uni_x_caja > 0
)
insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
select now(), c.cod_art, c.marca,
       case when c.tiene_inicial then 'ajuste' else 'inicial' end,
       c.objetivo_uni - c.stock_actual,
       'sync stock depósito 2026-09-11 (vista_saldos_stock)', null, now()
from calc c
where c.objetivo_uni <> c.stock_actual;

-- 3) uni x caja al maestro (838E, 877E, 590ES)
-- create table public."GV_Importados_bkp_uxc_20260911" as select * from public."Importados" where id in (78,144,154);
-- update public."Importados" i set uni_x_caja = u.uni_x_caja, actualizado = now()
--   from public.vista_uni_x_caja u
--  where i.id in (78,144,154) and gv_cod_stock(u.codn::text) = gv_cod_stock(i.cod_art) and u.fuente = 'maestro';

-- Chequeo: 0 negativas
select count(*) filter (where stock_actual < 0) as negativas from public.v_importados_ordenes where principal and activo;

-- ROLLBACK
--   delete from public."Importados_Mov_Stock" where ref like 'sync stock depósito 2026-09-11%';
--   vista: sql/gv_importados_lk_ch_separados_v1501.sql (bloque 2)
--   update public."Importados" i set uni_x_caja = b.uni_x_caja from public."GV_Importados_bkp_uxc_20260911" b where b.id = i.id;
