-- v23.52 (Luis, 28/09): «Historial de cancelados» en A Programar (reemplaza el chip «✕ N anulados»).
-- Junta: anulados desde A Programar (GV_Pedidos_Anulados) + cancelados desde Programación
-- (GV_Desarmes sin vuelta, justificativo «Cancelado desde la PPP…» / «Pedido cancelado…») + NP de
-- ISIS canceladas que no pasaron por el desarme (NP_Canceladas). Lo cancelado desde Facturación NO entra.
-- Al 28/09: 2 desde A Programar, 27 desde Programación. gv_pedidos_anulados queda como estaba.
create or replace function public.gv_pedidos_cancelados_historial(p_dias integer default 3650)
 returns table(empresa text, clave text, es_isis boolean, np_label text, np text, cod text, razon_social text,
               m3 numeric, motivo text, persona text, por text, anulado_at timestamptz, origen text)
 language sql stable security definer set search_path to 'public'
as $function$
  with prog as (
    select d.empresa, coalesce(d.order_id::text, d.np) as clave, bool_or(d.es_isis) as es_isis,
           string_agg(distinct d.np, ', ' order by d.np) as np,
           max(d.cod_cliente) as cod, max(d.razon_social) as razon_social, sum(d.m3) as m3,
           max(regexp_replace(d.justificativo, '^Cancelado desde la PPP:\s*', '')) as motivo,
           max(d.por) as por, max(d.creado_at) as anulado_at
      from public."GV_Desarmes" d
     where not d.vuelve
       and (d.justificativo ilike 'Cancelado desde la PPP%' or d.justificativo ilike 'Pedido cancelado%')
     group by d.empresa, coalesce(d.order_id::text, d.np), date_trunc('minute', d.creado_at)
  )
  select * from (
    select a.empresa, a.clave, a.es_isis, a.np_label, a.np, a.cod, a.razon_social, a.m3,
           a.motivo, a.persona, a.por, a.anulado_at, 'a_programar'::text
      from public."GV_Pedidos_Anulados" a
    union all
    select p.empresa, p.clave, p.es_isis,
           case when p.es_isis then p.np else 'web ' || upper(p.empresa) || ' ' || p.clave end,
           p.np, p.cod, p.razon_social, p.m3, p.motivo, null::text, p.por, p.anulado_at, 'programacion'
      from prog p
    union all
    select 'lk', n.np, true, n.np, n.np, null, null, null, n.motivo, null, n.legajo, n.creado, 'programacion'
      from public."NP_Canceladas" n
     where not exists (select 1 from public."GV_Desarmes" d where d.np = n.np and not d.vuelve)
  ) x
  where x.anulado_at >= now() - make_interval(days => greatest(coalesce(p_dias, 3650), 1))
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
  order by x.anulado_at desc;
$function$;
revoke all on function public.gv_pedidos_cancelados_historial(integer) from public, anon;
grant execute on function public.gv_pedidos_cancelados_historial(integer) to authenticated, service_role;
