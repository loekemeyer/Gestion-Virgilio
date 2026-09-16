-- =====================================================================================
-- BACKUP previo a la v19.16 (`sql/gv_excepcion_cuarentena_v1916.sql`).
-- Tomado el 2026-09-16 con `pg_get_functiondef` de la base viva (hrxfctzncixxqmpfhskv).
--
-- QUÉ DESARMA: la v19.16 cambia, en las dos funciones de abajo, el `not exists` contra
-- `public.cobranzas_cliente_cadena` (que era lo que eximía a los SÚPER del motivo `deuda`)
-- por `not public.gv_cuarentena_exento(empresa, cod, 'deuda')`, que lee la tabla nueva
-- `public.gv_excepcion_cuarentena`. También le agrega a `gv_supers_sync()` el mantenimiento
-- de las filas `origen='super'` de esa tabla.
--
-- ROLLBACK COMPLETO:
--   1) correr este archivo entero (deja las 3 funciones como estaban);
--   2) `drop function if exists public.gv_cuarentena_exento(text,text,text);`
--   3) `drop table if exists public.gv_excepcion_cuarentena;`
-- `cobranzas_cliente_cadena` NO se toca en la v19.16 (siguen colgando de ella las 10 vistas
-- de Facturación), así que el rollback no necesita reconstruir nada de datos.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.gv_cuarentena_marcar_calc(p_pedidos jsonb)
 RETURNS TABLE(order_id text, empresa text, cod text, np text, razon_social text, motivos text[], deuda numeric, estado text, nuevo_pedidos integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.74 (Thomas, 2026-09-14): el pedido de la página LK que se FACTURA por Chef (Tierra
  -- del Fuego, artículos con L) se evalúa contra el padrón de CHEF, con el código de Chef del
  -- mismo CUIT. El mapeo vive en GV_Cliente_Isis (lo empuja LK) y lo resuelve gv_cuarentena_ident;
  -- sin mapeo devuelve el mismo (empresa, cod) y nada cambia. Sólo se remapea un pedido de la
  -- PÁGINA: "A Programar" disfraza una NP de ISIS sin tanda como pedido con order_id = 'np'+NP
  -- (index.html), y esa NP lleva el código de SU ISIS, así que su padrón es el suyo.
  -- La IDENTIDAD del pedido (order_id + empresa) NO se toca: aprobaciones, log y comentarios
  -- siguen guardados como 'lk', que es lo que ve el front.
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
    select p.order_id, p.empresa, p.cod, p.np, p.razon_social,
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
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod_ev
                 and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
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
            select 1 from public.cobranzas_cliente_cadena cc
             where cc.cod_cliente = p.cod_ev
               and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
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
  -- v16.57 (problema 14) — La Cuarentena sólo mira lo que TODAVÍA NO tiene tanda:
  -- gv_cuarentena_marcar / _limite corren adentro del armado, sobre los pendientes. Si el
  -- reporte de deuda llega DESPUÉS de que el pedido ya recibió tanda, el pedido sigue viaje.
  -- Esto lo saca a la luz: los mismos motivos, aplicados a lo YA programado y todavía frenable.
  -- No retira nada: retirar un pedido de una tanda ya armada es una decisión operativa.
  -- v17.12 (Luis, 2026-09-14): mismos motivos = también `cliente_nuevo` (GV_Clientes_Nuevos).
  -- v17.23 (Luis, 2026-09-14): el pedido APROBADO sale de la lista — su historia vive en el LOG.
  -- v17.74 (Thomas, 2026-09-14): "mismos motivos" incluye mirar el padrón que corresponde. Un
  -- pedido WEB de LK que se factura por Chef (Tierra del Fuego) se evalúa con el cliente de Chef
  -- (gv_cuarentena_ident / GV_Cliente_Isis). Las NP de ISIS NO se remapean: llevan el código de
  -- su propio ISIS. La columna `empresa` sigue siendo la del pedido: es la clave de Liberados
  -- y Comentarios.
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
  prog2 as (
    select p.*, id.empresa as emp_ev, id.cod as cod_ev
      from prog p
      cross join lateral public.gv_cuarentena_ident(p.empresa, p.cod, p.origen = 'web') id
  ),
  marca as (
    select p.*,
      coalesce(p.order_id::text, p.np) as clave,
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
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod_ev
                 and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'deuda' and f.cod = p.cod_ev
          and coalesce(f.deuda,0) > 1000
          and not exists (select 1 from public.cobranzas_cliente_cadena cc
                           where cc.cod_cliente = p.cod_ev
                             and lower(cc.empresa) in (p.emp_ev, case p.emp_ev when 'chef' then 'ch' when 'ch' then 'chef' else p.emp_ev end))
          and not exists (select 1 from public."GV_Cuarentena_Pagados" pg
                           where pg.empresa = p.emp_ev and pg.cod = p.cod_ev
                             and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.emp_ev and f.tipo = 'busqueda'
          and f.cod = p.cod_ev and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.emp_ev and cn.cod = p.cod_ev limit 1) as nuevo_pedidos
    from prog2 p
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

CREATE OR REPLACE FUNCTION public.gv_supers_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  delete from public.cobranzas_cliente_cadena;
  insert into public.cobranzas_cliente_cadena (empresa, cod_cliente, super_key)
  select case when s.empresa = 'chef' then 'ch' else 'lk' end, s.cod, s.super_key
    from public."GV_Supers" s where s.activo;
  return null;
end $function$;
