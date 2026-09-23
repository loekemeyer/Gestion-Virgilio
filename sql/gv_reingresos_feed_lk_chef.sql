-- Cartel "Sin stock / hasta dd/mm" de importados en las páginas LK y CHEF
-- (Luis, 2026-09-23). APLICADO en hrxfctzncixxqmpfhskv el 23/09. Problema 522.
--
-- Síntoma: la página LK casi no mostraba el cartel (1 de 74 con fecha) y Chef no lo tenía.
-- Causas: (1) la demanda salía de vista_stock_vs_pedidos, que sólo cuenta NP de ISIS:
-- las NP web no sumaban. (2) en los 4 duales sumaba stock y pedidos de LK y CH.
-- Regla (Luis): SIN STOCK = disponible <= 0 O pedidos >= disponible.
-- Fecha = Importados.reingreso_est, exacta. LK: marca <> 'CH'; Chef: marca = 'CH'.
-- vista_stock_vs_pedidos NO se tocó (la usan otros).
-- Consumo: LK lee v_lk_reingresos / v_ch_reingresos por FDW (lk_ppp_reader); el cron 39
-- de LK las espeja a reingreso_cache / reingreso_cache_chef (pagina-LK-copia, sql/reingreso_chef.sql).
-- Centinelas: GV_Reglas_Centinela 135, 136, 137.

create or replace function public.gv_reingresos_feed(p_emp text)
 returns table(cod text, reingreso_est date, sin_stock boolean)
 language sql stable security definer set search_path to 'public'
as $function$
  with _rf_emp as (select upper(btrim(p_emp)) as e),
  imp as (
    select gv_cod_stock(cod_art) as cod,
           max(reingreso_est)         as reingreso_est,
           max(nullif(uni_x_caja, 0)) as uxc
    from public."Importados", _rf_emp x
    where coalesce(activo, true)
      and case when x.e = 'CH' then upper(coalesce(marca, '')) = 'CH'
               else upper(coalesce(marca, '')) <> 'CH' end
    group by gv_cod_stock(cod_art)
  ),
  _rf_dual as (select gv_cod_stock(d.cod) as cod from public.codigos_duales d),
  _rf_stk as (
    select gv_cod_stock(s.cod_art) as cod,
           sum(coalesce(s.terminado,0) + coalesce(s.excedente,0) + coalesce(s.separar_pedidos,0)
             + coalesce(s.a_facturar,0) + coalesce(s.a_guardar,0) + coalesce(s.racks,0)
             + coalesce(s.racks_ch,0) + coalesce(s.para_envasar,0)) as stock
    from public.vista_saldos_stock s, _rf_emp x
    where gv_cod_stock(s.cod_art) not in (select cod from _rf_dual)
       or upper(coalesce(s.empresa,'')) = x.e
    group by gv_cod_stock(s.cod_art)
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
    cross join _rf_emp x
    where nullif(btrim(b.articulo), '') is not null
      and not exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = p.np)
      and ( gv_cod_stock(b.articulo) not in (select cod from _rf_dual)
            or (case when upper(btrim(b.articulo)) ~ '[0-9E]L$' then 'LK'
                     when gv_empresa_de_np_texto(p.np) = 'chef' then 'CH'
                     else 'LK' end) = x.e )
    group by gv_cod_stock(b.articulo)
  ),
  _rf_disp as (
    select i.cod, i.reingreso_est,
           coalesce(st.stock, 0)
             + coalesce(floor(coalesce(pt.stock_parte, 0) / nullif(i.uxc, 0)), 0) as disponible,
           coalesce(d.pedidos, 0) as pedidos
    from imp i
    left join _rf_stk st on st.cod = i.cod
    left join parte pt on pt.cod = i.cod
    left join _rf_dem d on d.cod = i.cod
  )
  select cod, reingreso_est, (disponible <= 0 or pedidos >= disponible) as sin_stock
  from _rf_disp
  -- Luis 23/09: codigos sin cartel ni pedido partido (tabla editable, sql/gv_reingreso_excluido.sql)
  where not exists (select 1 from public."GV_Reingreso_Excluido" x where x.cod = _rf_disp.cod);
$function$;
revoke all on function public.gv_reingresos_feed(text) from public, anon, authenticated;

create or replace function public.lk_reingresos_feed()
 returns table(cod text, reingreso_est date, sin_stock boolean)
 language sql stable security definer set search_path to 'public'
as $function$ select * from public.gv_reingresos_feed('LK'); $function$;

create or replace function public.ch_reingresos_feed()
 returns table(cod text, reingreso_est date, sin_stock boolean)
 language sql stable security definer set search_path to 'public'
as $function$ select * from public.gv_reingresos_feed('CH'); $function$;
revoke all on function public.ch_reingresos_feed() from public, anon, authenticated;
grant execute on function public.ch_reingresos_feed() to lk_ppp_reader;

create or replace view public.v_ch_reingresos with (security_invoker = true)
  as select * from public.ch_reingresos_feed();
revoke all on public.v_ch_reingresos from anon, authenticated;
grant select on public.v_ch_reingresos to lk_ppp_reader;

-- Chequeo (23/09: LK 33 con fecha / 63 sin stock; CH 5 con fecha / 9 sin stock):
-- select 'LK', count(*) filter (where sin_stock and reingreso_est is not null) from public.gv_reingresos_feed('LK')
-- union all select 'CH', count(*) filter (where sin_stock and reingreso_est is not null) from public.gv_reingresos_feed('CH');
-- Rollback de la lógica: volver lk_reingresos_feed a la versión de sql/reingreso_virgilio.sql de pagina-LK-copia.
