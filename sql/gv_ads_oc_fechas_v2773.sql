-- v27.73 (Luis, 07/10): fechas de generación de las últimas OC (Art Term), para el selector de rango de ADS
-- ("1 - 07.10.26"). Sólo lectura. Rollback: drop function public.gv_ads_oc_fechas(int);
create or replace function public.gv_ads_oc_fechas(p_n int default 12)
returns table(n int, fecha date) language sql stable security definer set search_path = public as $$
  select (row_number() over (order by z.fecha desc))::int, z.fecha
    from (select distinct o.fecha from "Ordenes_Compra" o where o.rubro = 'Art Term' and o.fecha is not null
           order by o.fecha desc limit greatest(1, least(coalesce(p_n,12), 52))) z
   order by 1;
$$;
grant execute on function public.gv_ads_oc_fechas(int) to anon, authenticated;
