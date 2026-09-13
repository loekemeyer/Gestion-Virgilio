-- v16.57 — Problema 14: la Cuarentena no ve lo que YA tiene tanda
--
-- La Cuarentena sólo evalúa lo que TODAVÍA NO está programado: `gv_cuarentena_marcar` y
-- `gv_cuarentena_limite` corren adentro del armado, sobre los pendientes. Si el reporte de
-- deuda entra DESPUÉS de que el pedido recibió tanda, el pedido sigue viaje y nadie se entera.
--
-- Medido al 2026-09-13, con el reporte de deuda del 11/09 12:43 cargado: **10 pedidos ya
-- programados de clientes en cuarentena**, todos con entrega del 14 al 17/09 y ninguno con
-- picking empezado:
--
--   NP        tanda  entrega     cliente                      deuda
--   LK 0007   E01A   14/09       Torres Y Liva S.A            $32.172.182
--   LK 0008   E01A   14/09       Torres Y Liva S.A            $32.172.182
--   98635     D67I   14/09       Distribuidora Pezzali S.A.    $2.033.330
--   98617     D67H   14/09       Riondini Lucas                $1.008.629
--   CH 0004   E03B   15/09       Ierakuin Srl                  $2.062.528
--   CH 0003   D69E   16/09       Gifel S.R.L.                  $1.955.317
--   LK 0018   D69F   16/09       Bazar Monica                  $1.080.583
--   CH 0014   E12G   17/09       Clapera Alicia Raquel         $4.894.986
--   CH 0015   E12G   17/09       Clapera Alicia Raquel         $4.894.986
--   CH 0018   E12H   17/09       Del Plastic S.R.L.                $4.030
--
-- ⚠ NO retira nada, y es a propósito: sacar un pedido de una tanda ya armada es una decisión
-- operativa (rompe el picking, deja un camión a medias). Lo que hace es que dejen de ser
-- invisibles. La acción la toma una persona con el botón que ya existe.
--
-- Los motivos son EXACTAMENTE los de `gv_cuarentena_marcar` — no se inventó una regla nueva:
--   · suspendido / sin cta. cte. (`GV_Cuarentena_Fuente` tipo 'busqueda', suspendido = true)
--   · deuda > $1.000 (tipo 'deuda'), con la exención de SÚPER de la v14.94
--     (`cobranzas_cliente_cadena`, normalizando 'chef' ↔ 'ch') y con el "Ya pagó" de la v15.46
--     (`GV_Cuarentena_Pagados.pagado_at >= GV_Cuarentena_Fuente.cargado_at`)
--   · se saltean los liberados (`GV_Cuarentena_Liberados`)
--
-- Sólo mira lo TODAVÍA FRENABLE: fecha de entrega de hoy en adelante y sin fila en
-- `Facturacion_NP`. Cubre las dos fuentes: `PPP_Web_Programacion` y `gv_ppp_programacion_diaria`.
--
-- Es SECURITY DEFINER porque `GV_Cuarentena_Fuente` y `GV_Cuarentena_Liberados` tienen RLS
-- prendida SIN policies y sin grants: no se leen desde el cliente, sólo por función. Mantiene
-- el mismo gate que la original (`es_supervisor_virgilio() or gv_es_supervisor_o_servicio()`) y
-- nace cerrada: execute revocado a public y anon.
--
-- Front: `cuarYaProgHtml()` en `index.html` la muestra como un bloque rojo arriba de la columna
-- 🚧 Cuarentena de "A Programar", con NP, tanda, fecha, cliente, motivo y monto, y una etiqueta
-- "pickeando" si ya hay eventos de operarios sobre esa tanda.

create or replace function public.gv_cuarentena_ya_programado()
returns table(
  origen text, empresa text, np text, order_id bigint, tanda text,
  fecha_entrega date, cod text, razon_social text,
  motivos text[], deuda numeric, estado text, picking_empezado boolean)
language sql
stable
security definer
set search_path to 'public'
as $function$
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
          limit 1)
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
          and f.cod = p.cod and f.suspendido is true limit 1) as estado
    from prog p
   where p.cod is not null
  )
  select m.origen, m.empresa, m.np, m.order_id, m.tanda, m.fecha_entrega, m.cod, m.razon_social,
         m.motivos, m.deuda, m.estado,
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where btrim(r.texto) = btrim(m.tanda) and nullif(btrim(m.tanda),'') is not null)
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and lb.order_id = coalesce(m.order_id::text, m.np))
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;

revoke all on function public.gv_cuarentena_ya_programado() from public, anon;
grant execute on function public.gv_cuarentena_ya_programado() to authenticated, service_role;

-- select * from public.gv_cuarentena_ya_programado();   -- vacía = ninguno se escapó
