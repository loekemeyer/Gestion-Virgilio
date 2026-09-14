-- BACKUP 2026-09-14 — definición VIVA de las tres funciones de Cuarentena ANTES de la
-- v17.74 (evaluar con el cliente de Chef los pedidos de LK que se facturan por Chef).
-- Volcado con pg_get_functiondef. Para deshacer la v17.74: correr este archivo entero y
-- borrar las filas de GV_Cliente_Isis.

CREATE OR REPLACE FUNCTION public.gv_cuarentena_limite(p_pendientes jsonb)
 RETURNS TABLE(order_id text, empresa text, exceso numeric, limite numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v15.04 (dueño 2026-09-11): además de marcar, devuelve POR CUÁNTO se pasa del límite
  -- ("Excede crédito por $100.000") y cuál es el límite. La lógica de greedy no cambió.
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
      from public."GV_PPP_Programacion_Diaria" where np is not null and cod is not null
  ),
  base_np as (
    select regexp_replace(bp.pedido::text,'\D','','g') as np,
           jsonb_agg(jsonb_build_object('art', bp.articulo, 'cajas', bp.cajas)) as items
    from public."GV_PPP_Base_Pedidos" bp
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
                else coalesce(b.usado,0) + p.monto end as usado,
           (coalesce(b.usado,0) + p.monto - p.limite) as exceso
    from pend p
    left join base b on b.empresa = p.empresa and b.cod = p.cod
    where p.rn = 1
    union all
    select p.empresa, p.cod, p.order_id, p.rn, p.monto, p.limite,
           (w.usado + p.monto > p.limite),
           case when w.usado + p.monto > p.limite then w.usado else w.usado + p.monto end,
           (w.usado + p.monto - p.limite)
    from walk w join pend p on p.empresa = w.empresa and p.cod = w.cod and p.rn = w.rn + 1
  )
  select order_id, empresa, round(exceso::numeric, 2) as exceso, round(limite::numeric, 2) as limite
  from walk where cuar;
$function$;

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
           nullif(trim(e->>'razon_social'), '') as razon_social
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  marca as (
    select p.order_id, p.empresa, p.cod, p.np, p.razon_social,
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
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.empresa and pg.cod = p.cod
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.empresa and cn.cod = p.cod limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'deuda'
          and f.cod = p.cod and coalesce(f.deuda,0) > 1000
          and not exists (
            select 1 from public.cobranzas_cliente_cadena cc
             where cc.cod_cliente = p.cod
               and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
          and not exists (
            select 1 from public."GV_Cuarentena_Pagados" pg
             where pg.empresa = p.empresa and pg.cod = p.cod
               and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'busqueda'
          and f.cod = p.cod and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.empresa and cn.cod = p.cod limit 1) as nuevo_pedidos
    from ped p
    where p.cod is not null and p.order_id is not null
  )
  select m.order_id, m.empresa, m.cod, m.np, m.razon_social, m.motivos, m.deuda, m.estado, m.nuevo_pedidos
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(m.order_id));
$function$;

CREATE OR REPLACE FUNCTION public.gv_cuarentena_ya_programado()
 RETURNS TABLE(origen text, empresa text, np text, order_id bigint, clave text, tanda text, fecha_entrega date, cod text, razon_social text, motivos text[], deuda numeric, estado text, picking_empezado boolean, nuevo_pedidos integer, aprobado_at timestamp with time zone, aprobado_por text, comentarios integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with prog as (
    select 'web'::text as origen, w.empresa,
           public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
           w.order_id, w.tanda, w.fecha_entrega, btrim(w.cod_cliente) as cod, w.razon_social
      from public."PPP_Web_Programacion" w
     where w.np is not null and w.fecha_entrega >= current_date
    union all
    select 'isis', case when (regexp_replace(coalesce(d.np,''),'\D','','g'))::bigint > 90000
                        then 'lk' else 'chef' end,
           btrim(d.np), null::bigint, d.tanda,
           nullif(btrim(d.fecha_entrega),'')::date, btrim(d.cod), d.razon_social
      from public.gv_ppp_programacion_diaria d
     where nullif(regexp_replace(coalesce(d.np,''),'\D','','g'),'') is not null
       and nullif(btrim(d.fecha_entrega),'')::date >= current_date
  ),
  marca as (
    select p.*,
      coalesce(p.order_id::text, p.np) as clave,
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
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.empresa and pg.cod = p.cod
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.empresa and cn.cod = p.cod limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'deuda' and f.cod = p.cod
          and coalesce(f.deuda,0) > 1000
          and not exists (select 1 from public.cobranzas_cliente_cadena cc
                           where cc.cod_cliente = p.cod
                             and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
          and not exists (select 1 from public."GV_Cuarentena_Pagados" pg
                           where pg.empresa = p.empresa and pg.cod = p.cod
                             and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'busqueda'
          and f.cod = p.cod and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.empresa and cn.cod = p.cod limit 1) as nuevo_pedidos
    from prog p
   where p.cod is not null
  )
  select m.origen, m.empresa, m.np, m.order_id, m.clave, m.tanda, m.fecha_entrega, m.cod, m.razon_social,
         m.motivos, m.deuda, m.estado,
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where btrim(r.texto) = btrim(m.tanda) and nullif(btrim(m.tanda),'') is not null),
         m.nuevo_pedidos,
         lb.liberado_at, nullif(lb.liberado_por,''),
         (select count(*)::int from public."GV_Cuarentena_Comentarios" c
           where c.empresa = m.empresa and public.gv_cuarentena_clave(c.order_id) = public.gv_cuarentena_clave(m.clave))
  from marca m
  left join public."GV_Cuarentena_Liberados" lb
         on lb.empresa = m.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(m.clave)
  where array_length(m.motivos, 1) >= 1
    and lb.order_id is null
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;
