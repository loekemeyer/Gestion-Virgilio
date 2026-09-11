-- ============================================================================
-- BACKUP 2026-09-11 — definiciones de gv_cuarentena_marcar y gv_cuarentena_limite
-- ANTES de la v15.04 (que les agregó los montos: deuda / estado / exceso / límite).
--
-- Para volver atrás: correr este archivo entero. Ojo: después de recrearlas hay que
-- revocarle EXECUTE a `anon` otra vez (Supabase se lo da solo a toda función nueva y
-- estas dos son SECURITY DEFINER):
--   revoke all on function public.gv_cuarentena_marcar(jsonb) from anon, public;
--   revoke all on function public.gv_cuarentena_limite(jsonb) from anon, public;
--   grant execute on function public.gv_cuarentena_marcar(jsonb) to authenticated, service_role;
--   grant execute on function public.gv_cuarentena_limite(jsonb) to authenticated, service_role;
-- ============================================================================

drop function if exists public.gv_cuarentena_marcar(jsonb);
CREATE OR REPLACE FUNCTION public.gv_cuarentena_marcar(p_pedidos jsonb)
 RETURNS TABLE(order_id text, empresa text, motivos text[])
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ped as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'), '') as cod
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  marca as (
    select p.order_id, p.empresa,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'busqueda'
            and f.cod = p.cod and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'deuda'
            and f.cod = p.cod and coalesce(f.deuda,0) > 1000
            and not exists (
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod
                 and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
          limit 1)
      ], null) as motivos
    from ped p
    where p.cod is not null and p.order_id is not null
  )
  select m.order_id, m.empresa, m.motivos
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and lb.order_id = m.order_id);
$function$;

drop function if exists public.gv_cuarentena_limite(jsonb);
CREATE OR REPLACE FUNCTION public.gv_cuarentena_limite(p_pendientes jsonb)
 RETURNS TABLE(order_id text, empresa text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with recursive
  ped as (
    select nullif(trim(e->>'order_id'),'') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'),'') as cod,
           coalesce(e->>'fecha_recep','') as fecha_recep,
           public.gv_ppp_web_valor_items(lower(coalesce(e->>'empresa','lk')),
                nullif(trim(e->>'cod'),''), e->'items', nullif(e->>'cond','')) as monto
    from jsonb_array_elements(coalesce(p_pendientes,'[]'::jsonb)) e
    where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
      and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                       where lb.empresa = lower(coalesce(e->>'empresa','lk'))
                         and lb.order_id = nullif(trim(e->>'order_id'),''))
  ),
  lim as (
    select f.empresa, f.cod, max(f.limite_credito) as limite
    from public."GV_Cuarentena_Fuente" f
    where f.tipo='busqueda' and coalesce(f.limite_credito,0) > 0
    group by f.empresa, f.cod
  ),
  cl as (
    select distinct p.empresa, p.cod
    from ped p join lim l on l.empresa=p.empresa and l.cod=p.cod
    where p.cod is not null
  ),
  npcod as (
    select regexp_replace(np::text,'\D','','g') as np, empresa, btrim(cod_cliente) as cod
      from public."PPP_Web_Programacion" where np is not null
    union
    select regexp_replace(np::text,'\D','','g') as np, gv_empresa_de_np_texto(np::text) as empresa, btrim(cod) as cod
      from public."PPP_Programacion_Diaria" where np is not null and cod is not null
  ),
  base_np as (
    select regexp_replace(bp.pedido::text,'\D','','g') as np,
           jsonb_agg(jsonb_build_object('art', bp.articulo, 'cajas', bp.cajas)) as items
    from public."PPP_Base_Pedidos" bp
    where regexp_replace(bp.pedido::text,'\D','','g') not in
          (select regexp_replace(np::text,'\D','','g') from public."Facturacion_NP" where np is not null)
    group by 1
  ),
  base as (
    select m.empresa, m.cod,
           sum(public.gv_ppp_web_valor_items(m.empresa, m.cod, b.items, '8')) as usado
    from base_np b
    join npcod m on m.np = b.np
    join cl on cl.empresa = m.empresa and cl.cod = m.cod
    group by m.empresa, m.cod
  ),
  pend as (
    select p.empresa, p.cod, p.order_id, p.monto, l.limite,
           row_number() over (partition by p.empresa, p.cod order by p.fecha_recep, p.order_id) as rn
    from ped p join lim l on l.empresa = p.empresa and l.cod = p.cod
    where p.order_id is not null and p.cod is not null
  ),
  walk as (
    select p.empresa, p.cod, p.order_id, p.rn, p.monto, p.limite,
           (coalesce(b.usado,0) + p.monto > p.limite) as cuar,
           case when coalesce(b.usado,0) + p.monto > p.limite then coalesce(b.usado,0)
                else coalesce(b.usado,0) + p.monto end as usado
    from pend p
    left join base b on b.empresa = p.empresa and b.cod = p.cod
    where p.rn = 1
    union all
    select p.empresa, p.cod, p.order_id, p.rn, p.monto, p.limite,
           (w.usado + p.monto > p.limite),
           case when w.usado + p.monto > p.limite then w.usado else w.usado + p.monto end
    from walk w join pend p on p.empresa = w.empresa and p.cod = w.cod and p.rn = w.rn + 1
  )
  select order_id, empresa from walk where cuar;
$function$;
