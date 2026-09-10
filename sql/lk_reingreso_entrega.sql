-- =============================================================================
-- lk_reingreso_entrega.sql — Lo que Virgilio expone a LK para: (1) fecha
-- estimada de entrega global en el carrito del portal, y (2) reingreso estimado
-- de importados (E) sin stock en el catálogo. (2026-09-09)
-- =============================================================================
-- El dueño carga ambos datos en el módulo Importación (index.html,
-- openPedidosImportacion / _pedImpRender):
--   · Fecha de entrega global  → Stock_Config['entrega_estimada_global']
--   · Reingreso por artículo    → Importados.reingreso_est (date)
--
-- LK los lee por el FDW virgilio_db (rol lk_ppp_reader) a través de dos vistas
-- envueltas en funciones SECURITY DEFINER (las vistas de stock son
-- security_invoker y lk_ppp_reader no tiene SELECT sobre las bases), y las
-- espeja a tablas locales con un cron (nada de FDW en el camino caliente).
-- Detalle del lado LK en el repo pagina-LK: sql/reingreso_virgilio.sql.
-- =============================================================================

alter table public."Importados" add column if not exists reingreso_est date;

-- "Sin stock" = falta>0 (pedidos_ped > stock_total, todo en CAJAS), contando el
-- stock de PARTE (en UNIDADES → cajas dividiendo por uni_x_caja). Así los que se
-- arman con partes importadas (94xE, 584E, 522S…) no aparecen sin stock mientras
-- haya partes. Solo devuelve filas con reingreso_est cargado (la fecha es el gate).
create or replace function public.lk_reingresos_feed()
returns table(cod text, reingreso_est date, sin_stock boolean)
language sql
stable
security definer
set search_path = public
as $$
  with imp as (
    select gv_cod_stock(cod_art) as cod,
           max(reingreso_est)         as reingreso_est,
           max(nullif(uni_x_caja, 0)) as uxc
    from public."Importados"
    where coalesce(activo, true) and reingreso_est is not null
    group by gv_cod_stock(cod_art)
  ),
  parte as (
    select gv_cod_stock(cod) as cod, sum(coalesce(stock_parte, 0)) as stock_parte
    from public.vista_importados_stock_parte
    group by gv_cod_stock(cod)
  )
  select i.cod,
         i.reingreso_est,
         ( coalesce(svp.pedidos_ped, 0)
           > coalesce(svp.stock_total, 0)
             + coalesce(floor(coalesce(pt.stock_parte, 0) / nullif(i.uxc, 0)), 0)
         ) as sin_stock
  from imp i
  left join public.vista_stock_vs_pedidos svp on svp.cod = i.cod
  left join parte pt on pt.cod = i.cod;
$$;
revoke all on function public.lk_reingresos_feed() from public;
grant execute on function public.lk_reingresos_feed() to lk_ppp_reader;

create or replace view public.v_lk_reingresos as select * from public.lk_reingresos_feed();
grant select on public.v_lk_reingresos to lk_ppp_reader;

-- Config global (solo la clave que LK necesita).
create or replace function public.lk_config_feed()
returns table(clave text, valor text)
language sql
stable
security definer
set search_path = public
as $$
  select clave, valor from public."Stock_Config" where clave in ('entrega_estimada_global');
$$;
revoke all on function public.lk_config_feed() from public;
grant execute on function public.lk_config_feed() to lk_ppp_reader;

create or replace view public.v_lk_config as select * from public.lk_config_feed();
grant select on public.v_lk_config to lk_ppp_reader;
