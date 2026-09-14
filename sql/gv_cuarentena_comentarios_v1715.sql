-- ============================================================================
-- v17.15 (2026-09-14, pedido de Luis) — CUARENTENA: aprobación con COMENTARIO + log
-- ============================================================================
-- Pedido:
--   (1) "Ya programados y el cliente está en cuarentena" pasa a ser una TABLA: NP, tanda,
--       código de cliente, motivos como badges, APROBACIÓN (si fue aprobado y cuándo) y un
--       COMENTARIO (icono de librito que abre un pop-up con el log y deja agregar líneas).
--   (2) Al aprobar un pedido de Cuarentena y mandarlo a programación, salta un cuadro de
--       comentario para que quien aprueba deje asentado por qué.
--
-- DECISIÓN QUE HAY QUE TENER PRESENTE: `gv_cuarentena_ya_programado()` **dejó de esconder los
-- pedidos ya liberados**. Antes los sacaba con un `not exists` contra GV_Cuarentena_Liberados;
-- con esa exclusión la columna "Aprobación" habría estado SIEMPRE vacía, que es justo lo que
-- Luis pidió ver. Ahora se muestran, en verde y con quién los aprobó. El filtro que sigue
-- acotando la lista es el de siempre: entrega de hoy en adelante y NP sin facturar.
--
-- LA CLAVE ES UNA SOLA para las tres tablas (Liberados, Comentarios y la lista): el `order_id`
-- del pedido web o, cuando es una NP de ISIS que no tiene order_id, la **NP**. La función la
-- devuelve ya resuelta en la columna `clave`, así el front no la arma por su cuenta.
--
-- Medición del día: la lista pasó de 17 a 20 filas (las 3 que estaban escondidas por aprobadas).
--
-- ROLLBACK
--   · Volver a aplicar `sql/gv_clientes_nuevos_v1712.sql` (trae la versión anterior de
--     gv_cuarentena_ya_programado y de gv_cuarentena_marcar) y la de liberar de
--     `sql/gv_cuarentena_pago_planify_v1546.sql`.
--   · `drop function public.gv_cuarentena_comentar(text,text,text,text,text);`
--     `drop function public.gv_cuarentena_comentarios(text,text);`
--   · La tabla de comentarios se conserva: es historia, no se borra.
-- ============================================================================

create table if not exists public."GV_Cuarentena_Comentarios" (
  id         bigint generated always as identity primary key,
  empresa    text not null,
  order_id   text not null,
  np         text,
  texto      text not null,
  por        text,
  creado_at  timestamptz not null default now()
);
comment on table public."GV_Cuarentena_Comentarios" is
  'v17.15 (pedido de Luis, 2026-09-14) — LOG de comentarios de Cuarentena, uno por linea con fecha/hora y autor. La clave es (empresa, order_id) donde order_id es el del pedido web o, si es una NP de ISIS que no tiene, la NP: la MISMA clave que usa GV_Cuarentena_Liberados. Se escribe al aprobar (gv_cuarentena_liberar con p_comentario) y desde el librito de la tabla "Ya programados" (gv_cuarentena_comentar). No se borra: es historia.';
create index if not exists gv_cuar_coment_idx on public."GV_Cuarentena_Comentarios" (empresa, order_id, creado_at);
alter table public."GV_Cuarentena_Comentarios" enable row level security;
revoke insert, update, delete, truncate on public."GV_Cuarentena_Comentarios" from anon, authenticated;
-- Sin policies: `anon` ve 0 filas. Lo leen y escriben las RPC de abajo, que son SECURITY DEFINER
-- con el chequeo de supervisor adentro.


-- ── agregar una línea al log ────────────────────────────────────────────────
create or replace function public.gv_cuarentena_comentar(
  p_empresa text, p_order_id text, p_texto text, p_np text default null, p_por text default null)
returns table(id bigint, creado_at timestamptz, por text, texto text)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede comentar en cuarentena.' using errcode='42501';
  end if;
  if coalesce(btrim(p_texto),'') = '' then
    raise exception 'El comentario no puede estar vacío.' using errcode='22023';
  end if;
  return query
  insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por)
  values (lower(p_empresa), nullif(btrim(p_order_id),''), nullif(btrim(p_np),''), btrim(p_texto),
          nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),''))
  returning "GV_Cuarentena_Comentarios".id, "GV_Cuarentena_Comentarios".creado_at,
            "GV_Cuarentena_Comentarios".por, "GV_Cuarentena_Comentarios".texto;
end;
$function$;
revoke all on function public.gv_cuarentena_comentar(text,text,text,text,text) from public, anon;
grant execute on function public.gv_cuarentena_comentar(text,text,text,text,text) to authenticated, service_role;


-- ── leer el log de un pedido ────────────────────────────────────────────────
create or replace function public.gv_cuarentena_comentarios(p_empresa text, p_order_id text)
returns table(id bigint, creado_at timestamptz, por text, texto text)
language sql stable security definer set search_path to 'public'
as $function$
  select c.id, c.creado_at, c.por, c.texto
    from public."GV_Cuarentena_Comentarios" c
   where c.empresa = lower(p_empresa) and c.order_id = nullif(btrim(p_order_id),'')
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by c.creado_at;
$function$;
revoke all on function public.gv_cuarentena_comentarios(text,text) from public, anon;
grant execute on function public.gv_cuarentena_comentarios(text,text) to authenticated, service_role;


-- ── liberar (aprobar) ahora acepta el comentario de la aprobación ───────────
-- DROP + CREATE porque cambia la firma (dos parámetros nuevos con default). Las llamadas de
-- 3 argumentos que ya existían siguen andando.
drop function if exists public.gv_cuarentena_liberar(text,text,text[]);
create function public.gv_cuarentena_liberar(
  p_empresa text, p_order_id text, p_motivos text[] default null,
  p_comentario text default null, p_por text default null)
returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare v_quien text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede liberar pedidos de cuarentena.' using errcode='42501';
  end if;
  v_quien := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  insert into public."GV_Cuarentena_Liberados" (empresa, order_id, motivos, liberado_por)
  values (lower(p_empresa), nullif(trim(p_order_id),''), p_motivos, coalesce(v_quien,''))
  on conflict (empresa, order_id) do update set motivos = excluded.motivos, liberado_at = now();
  -- v17.15 (pedido de Luis): al aprobar se puede dejar un comentario, y queda como una línea
  -- más del log del pedido (mismo lugar que el librito de "Ya programados").
  if coalesce(btrim(p_comentario),'') <> '' then
    insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, texto, por)
    values (lower(p_empresa), nullif(trim(p_order_id),''), btrim(p_comentario), v_quien);
  end if;
end;
$function$;
revoke all on function public.gv_cuarentena_liberar(text,text,text[],text,text) from public, anon;
grant execute on function public.gv_cuarentena_liberar(text,text,text[],text,text) to authenticated, service_role;


-- ── la lista, ahora con clave / aprobación / cantidad de comentarios ────────
drop function if exists public.gv_cuarentena_ya_programado();
create function public.gv_cuarentena_ya_programado()
 returns table(origen text, empresa text, np text, order_id bigint, clave text, tanda text,
               fecha_entrega date, cod text, razon_social text, motivos text[], deuda numeric,
               estado text, picking_empezado boolean, nuevo_pedidos integer,
               aprobado_at timestamptz, aprobado_por text, comentarios integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- v16.57 (problema 14) — La Cuarentena sólo mira lo que TODAVÍA NO tiene tanda:
  -- gv_cuarentena_marcar / _limite corren adentro del armado, sobre los pendientes. Si el
  -- reporte de deuda llega DESPUÉS de que el pedido ya recibió tanda, el pedido sigue viaje.
  -- Esto lo saca a la luz: los mismos motivos, aplicados a lo YA programado y todavía frenable.
  -- No retira nada: retirar un pedido de una tanda ya armada es una decisión operativa.
  -- v17.12 (pedido de Luis, 2026-09-14): mismos motivos = también `cliente_nuevo` (GV_Clientes_Nuevos).
  -- v17.15 (pedido de Luis, 2026-09-14): la lista pasó a ser una TABLA con APROBACIÓN y COMENTARIOS,
  -- así que los pedidos ya aprobados YA NO SE ESCONDEN: se muestran con quién los aprobó y cuándo
  -- (antes un `not exists` contra GV_Cuarentena_Liberados los sacaba, y entonces la columna de
  -- aprobación habría estado siempre vacía). `clave` es la misma que usan Liberados y Comentarios:
  -- el order_id del pedido web o, si es una NP de ISIS que no tiene, la NP.
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
           where c.empresa = m.empresa and c.order_id = m.clave)
  from marca m
  left join public."GV_Cuarentena_Liberados" lb
         on lb.empresa = m.empresa and lb.order_id = m.clave
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;
revoke all on function public.gv_cuarentena_ya_programado() from public, anon;
grant execute on function public.gv_cuarentena_ya_programado() to authenticated, service_role;

-- Chequeos
--   select count(*) filas, count(*) filter (where aprobado_at is not null) aprobados,
--          count(*) filter (where comentarios > 0) con_coment
--     from public.gv_cuarentena_ya_programado();
--   select * from public."GV_Cuarentena_Comentarios" order by creado_at desc limit 20;
