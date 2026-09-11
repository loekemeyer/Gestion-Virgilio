-- BACKUP 2026-09-11 — definición de lk_reingresos_feed ANTES del cambio "En stock / Reingreso".
-- Rollback: ejecutar este archivo tal cual en el SQL editor de Gestión Virgilio (hrxfctzncixxqmpfhskv).
-- Qué hacía de más: filtraba `and reingreso_est is not null`, así que un importado sin fecha
-- cargada no llegaba al feed y en el catálogo de LK quedaba sin ninguna señal de stock.
CREATE OR REPLACE FUNCTION public.lk_reingresos_feed()
 RETURNS TABLE(cod text, reingreso_est date, sin_stock boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with imp as (
    select gv_cod_stock(cod_art) as cod,
           max(reingreso_est)         as reingreso_est,
           max(nullif(uni_x_caja, 0)) as uxc
    from public."Importados"
    where coalesce(activo, true) and reingreso_est is not null
      and upper(coalesce(marca, '')) <> 'CH'
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
$function$;
