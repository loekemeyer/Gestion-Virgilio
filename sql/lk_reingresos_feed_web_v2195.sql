-- lk_reingresos_feed — cartel "Sin stock / hasta dd/mm" de importados en la página LK
-- (Luis, 2026-09-23). APLICADO en hrxfctzncixxqmpfhskv el 23/09.
--
-- Síntoma: la página LK casi no mostraba el cartel (1 código de 74 con fecha).
-- Causa: la demanda salía de vista_stock_vs_pedidos, que sólo cuenta NP de ISIS
-- (GV_PPP_Programacion_Diaria). Las NP web (LK 0xxx / CH 0xxx) no sumaban.
-- Regla (Luis): SIN STOCK = disponible <= 0 O pedidos >= disponible.
-- La fecha es exacta la de Importados.reingreso_est (lo que muestra Gestión).
-- Después: 33 códigos con cartel. LK lo copia con el cron 39 (sync_reingresos_virgilio).
-- vista_stock_vs_pedidos NO se tocó (la usan otros).
create or replace function public.lk_reingresos_feed()
 returns table(cod text, reingreso_est date, sin_stock boolean)
 language sql stable security definer set search_path to 'public'
as $function$
  with imp as (
    select gv_cod_stock(cod_art) as cod,
           max(reingreso_est)         as reingreso_est,
           max(nullif(uni_x_caja, 0)) as uxc
    from public."Importados"
    where coalesce(activo, true)
      and upper(coalesce(marca, '')) <> 'CH'
    group by gv_cod_stock(cod_art)
  ),
  parte as (
    select gv_cod_stock(cod) as cod, sum(coalesce(stock_parte, 0)) as stock_parte
    from public.vista_importados_stock_parte
    group by gv_cod_stock(cod)
  ),
  _rf_pend as (
    select btrim(np) as np from public."GV_PPP_Programacion_Diaria" where np is not null
    union
    select (case when lower(empresa) = 'lk' then 'LK ' else 'CH ' end) || lpad(np::text, 4, '0')
      from public."PPP_Web_Programacion" where np is not null
  ),
  _rf_dem as (
    select gv_cod_stock(b.articulo) as cod, sum(coalesce(b.cajas, 0)) as pedidos
    from public.gv_demanda_pedidos b
    join _rf_pend p on p.np = btrim(b.pedido)
    where nullif(btrim(b.articulo), '') is not null
      and not exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = p.np)
    group by gv_cod_stock(b.articulo)
  ),
  _rf_disp as (
    select i.cod, i.reingreso_est,
           coalesce(svp.stock_total, 0)
             + coalesce(floor(coalesce(pt.stock_parte, 0) / nullif(i.uxc, 0)), 0) as disponible,
           coalesce(d.pedidos, 0) as pedidos
    from imp i
    left join public.vista_stock_vs_pedidos svp on svp.cod = i.cod
    left join parte pt on pt.cod = i.cod
    left join _rf_dem d on d.cod = i.cod
  )
  select cod, reingreso_est, (disponible <= 0 or pedidos >= disponible) as sin_stock
  from _rf_disp;
$function$;
-- chequeo: select count(*) filter (where sin_stock and reingreso_est is not null) from public.lk_reingresos_feed();
