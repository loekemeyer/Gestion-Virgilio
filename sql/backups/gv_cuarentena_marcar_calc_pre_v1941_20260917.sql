-- Respaldo de public.gv_cuarentena_marcar_calc(jsonb) ANTES de la v19.41
-- (excepción "reposición chica": factura ≤ 10 días + pedido de 1 código → se le saca el motivo
-- `deuda`). Para deshacer: correr este archivo tal cual.
CREATE OR REPLACE FUNCTION public.gv_cuarentena_marcar_calc(p_pedidos jsonb)
 RETURNS TABLE(order_id text, empresa text, cod text, np text, razon_social text, motivos text[], deuda numeric, estado text, nuevo_pedidos integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ped as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'), '') as cod,
           nullif(trim(e->>'np'), '') as np,
           nullif(trim(e->>'razon_social'), '') as razon_social,
           id.empresa as emp_ev,
           id.cod     as cod_ev
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
    cross join lateral public.gv_cuarentena_ident(
      lower(coalesce(e->>'empresa','lk')),
      nullif(trim(e->>'cod'), ''),
      coalesce(nullif(trim(e->>'order_id'), ''), '') !~* '^np') id
  ),
  marca as (
    select p.order_id, p.empresa, p.cod, p.np, p.razon_social, p.emp_ev, p.cod_ev,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.emp_ev and f.tipo = 'busqueda'
            and f.cod = p.cod_ev and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.emp_ev and f.tipo = 'deuda'
            and f.cod = p.cod_ev and coalesce(f.deuda,0) > 1000
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'deuda'
          and f.cod = p.cod_ev and coalesce(f.deuda,0) > 1000
          and not exists (
            select 1 from public."GV_Cuarentena_Pagados" pg
             where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
               and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'busqueda'
          and f.cod = p.cod_ev and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1) as nuevo_pedidos
    from ped p
    where p.cod is not null and p.order_id is not null
  ),
  exc as (
    select m.*,
           (select coalesce(array_agg(x order by ord), array[]::text[])
              from unnest(m.motivos) with ordinality u(x, ord)
             where not public.gv_cuarentena_exento(m.emp_ev, m.cod_ev, x)) as motivos_ok
      from marca m
  )
  select e.order_id, e.empresa, e.cod, e.np, e.razon_social, e.motivos_ok,
         case when 'deuda' = any (e.motivos_ok) then e.deuda end,
         case when e.motivos_ok && array['suspendido','sin_cta_cte'] then e.estado end,
         case when 'cliente_nuevo' = any (e.motivos_ok) then e.nuevo_pedidos end
  from exc e
  where array_length(e.motivos_ok, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = e.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(e.order_id));
$function$;
