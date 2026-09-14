-- ============================================================================
-- v17.23 → salió con la app en v17.34 (2026-09-14, pedido de Luis) — LOG de Cuarentena, "¿quién aprueba?", y el
-- pedido aprobado sale de la lista de ya programados
-- ============================================================================
-- Tres cosas del mismo pedido:
--   (1) "si un cliente está aprobado, que salga de esa lista" → `gv_cuarentena_ya_programado`
--       vuelve a excluir los liberados. Es lo contrario de la v17.15, y ahora sí se puede:
--       la historia de la aprobación dejó de vivir en esa lista y vive en el LOG.
--   (2) Antes de confirmar una aprobación hay que decir QUIÉN la autoriza (Vivi / Marian /
--       Otro con texto), además del comentario. Va como `persona`, separada del usuario de la
--       sesión (`por`): una cosa es quién apretó el botón y otra quién autorizó.
--       Es OBLIGATORIA: `gv_cuarentena_liberar` levanta excepción sin ella.
--   (3) Submódulo "Log de Cuarentena" en Config. Cuarentena: cuándo entró cada pedido, con qué
--       motivos, en qué estado quedó y quién lo cerró.
--
-- LA PIEZA NUEVA ES `GV_Cuarentena_Log`, append-only. Eventos: `entro` (primera vez que se lo
-- ve retenido, o re-entrada después de un aprobado/devuelto), `motivos` (le cambiaron), y
-- `aprobado` / `devuelto`. `gv_cuarentena_log()` los colapsa a una fila por pedido.
--
-- QUIÉN ESCRIBE CADA EVENTO, y por qué hacen falta dos caminos:
--   · `gv_cuarentena_marcar` (lo que TODAVÍA no tiene tanda) — se partió en dos: el cálculo de
--     siempre quedó intacto en `gv_cuarentena_marcar_calc` (sql, stable) y el envoltorio en
--     plpgsql sólo le suma el registro. Así el cálculo se puede seguir leyendo sin efectos.
--   · `gv_cuarentena_log_registrar` (lo que YA tiene tanda) — esos pedidos no pasan por marcar,
--     así que sin esto el log vería la aprobación sin saber cuándo había entrado. Lo llama el
--     front al cargar la lista de "ya programados".
--   Los dos escriben SÓLO si hay novedad (primera vez, re-entrada, o cambio de motivos): marcar
--   se llama en cada carga de A Programar y el log no puede crecer una fila por refresco.
--
-- BACKFILL hecho el mismo día: por cada fila de `GV_Cuarentena_Liberados` que no tenía evento,
-- se insertó un `aprobado` con su `liberado_at` / `liberado_por` (sin `persona`: cuando se
-- aprobaron todavía no se preguntaba quién autorizaba).
--
-- ROLLBACK
--   · Volver a `sql/gv_cuarentena_comentarios_v1715.sql` (trae marcar y ya_programado de antes)
--     y a `sql/gv_cuarentena_devolver_v1720.sql`.
--   · `drop function public.gv_cuarentena_log(integer), public.gv_cuarentena_log_registrar(jsonb),
--      public.gv_cuarentena_marcar_calc(jsonb);`
--   · La tabla `GV_Cuarentena_Log` y las columnas `persona` se conservan: son historia.
-- ============================================================================

alter table public."GV_Cuarentena_Liberados"  add column if not exists persona text;
alter table public."GV_Cuarentena_Comentarios" add column if not exists persona text;

create table if not exists public."GV_Cuarentena_Log" (
  id           bigint generated always as identity primary key,
  empresa      text not null,
  clave        text not null,   -- order_id del pedido web, o la NP si es de ISIS
  np           text,
  cod          text,
  razon_social text,
  evento       text not null,   -- entro | motivos | aprobado | devuelto
  motivos      text[],
  deuda        numeric,
  persona      text,            -- quién autorizó (Vivi / Marian / lo que escribieron)
  por          text,            -- mail de la sesión que apretó el botón
  comentario   text,
  at           timestamptz not null default now()
);
comment on table public."GV_Cuarentena_Log" is
  'v17.23 (pedido de Luis, 2026-09-14) — LOG append-only de la Cuarentena: cuando un pedido ENTRA (primera vez que se lo ve retenido y con que motivos), cuando le CAMBIAN los motivos, cuando lo APRUEBAN (con la persona que lo aprobo y el comentario) y cuando lo DEVUELVEN. La clave es (empresa, clave) = order_id del pedido web o la NP si es de ISIS, igual que GV_Cuarentena_Liberados y _Comentarios. Lo escribe gv_cuarentena_marcar (entro/motivos), gv_cuarentena_log_registrar (los que ya tienen tanda), gv_cuarentena_liberar (aprobado) y gv_cuarentena_devolver (devuelto); se lee con gv_cuarentena_log(). No se borra.';
create index if not exists gv_cuar_log_idx  on public."GV_Cuarentena_Log" (empresa, clave, at);
create index if not exists gv_cuar_log_at   on public."GV_Cuarentena_Log" (at desc);
alter table public."GV_Cuarentena_Log" enable row level security;
revoke insert, update, delete, truncate on public."GV_Cuarentena_Log" from anon, authenticated;

-- backfill de las aprobaciones que ya existían
insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, por, at)
select lb.empresa, lb.order_id, null, null, null, 'aprobado', lb.motivos, nullif(lb.liberado_por,''), lb.liberado_at
  from public."GV_Cuarentena_Liberados" lb
 where not exists (select 1 from public."GV_Cuarentena_Log" l
                    where l.empresa = lb.empresa and l.clave = lb.order_id and l.evento = 'aprobado');


-- ── la lista de ya programados vuelve a esconder los aprobados ─────────────
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
  -- v17.23 (pedido de Luis, 2026-09-14): el pedido APROBADO vuelve a salir de la lista — su historia
  -- ahora vive en el LOG de Config. Cuarentena (GV_Cuarentena_Log), que es donde se mira quién lo
  -- aprobó y cuándo. Las columnas aprobado_at / aprobado_por quedan por compatibilidad, en null.
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
    and lb.order_id is null   -- v17.23 (Luis): "si un cliente está aprobado, que salga de esa lista"
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;
revoke all on function public.gv_cuarentena_ya_programado() from public, anon;
grant execute on function public.gv_cuarentena_ya_programado() to authenticated, service_role;

-- ── el cálculo de siempre, ahora aparte (sin efectos) ───────────────────────
create or replace function public.gv_cuarentena_marcar_calc(p_pedidos jsonb)
 returns table(order_id text, empresa text, cod text, np text, razon_social text,
               motivos text[], deuda numeric, estado text, nuevo_pedidos integer)
 language sql stable security definer set search_path to 'public'
as $function$
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
                     where lb.empresa = m.empresa and lb.order_id = m.order_id);
$function$;
revoke all on function public.gv_cuarentena_marcar_calc(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_marcar_calc(jsonb) to authenticated, service_role;


-- ── marcar = calcular + registrar la entrada ───────────────────────────────
drop function if exists public.gv_cuarentena_marcar(jsonb);
create function public.gv_cuarentena_marcar(p_pedidos jsonb)
 returns table(order_id text, empresa text, motivos text[], deuda numeric, estado text, nuevo_pedidos integer)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  -- v17.23 (pedido de Luis, 2026-09-14): el cálculo se mudó tal cual a gv_cuarentena_marcar_calc
  -- y acá sólo se le suma el REGISTRO en GV_Cuarentena_Log, para que el submódulo de Config.
  -- Cuarentena pueda contar cuándo entró cada pedido y con qué motivos. Se escribe sólo cuando
  -- hay novedad (primera vez, re-entrada después de aprobado/devuelto, o cambio de motivos):
  -- esta función la llama el front en CADA carga de A Programar.
  create temp table _calc on commit drop as
    select * from public.gv_cuarentena_marcar_calc(p_pedidos);

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, deuda)
  select c.empresa, c.order_id, c.np, c.cod, c.razon_social,
         case when u.evento is null or u.evento in ('aprobado','devuelto') then 'entro' else 'motivos' end,
         c.motivos, c.deuda
    from _calc c
    left join lateral (
      select l.evento, l.motivos from public."GV_Cuarentena_Log" l
       where l.empresa = c.empresa and l.clave = c.order_id
       order by l.at desc, l.id desc limit 1) u on true
   where u.evento is null
      or u.evento in ('aprobado','devuelto')
      or u.motivos is distinct from c.motivos;

  return query select c.order_id, c.empresa, c.motivos, c.deuda, c.estado, c.nuevo_pedidos from _calc c;
end;
$function$;
revoke all on function public.gv_cuarentena_marcar(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_marcar(jsonb) to authenticated, service_role;


-- ── los que YA tienen tanda: se registran aparte ───────────────────────────
create or replace function public.gv_cuarentena_log_registrar(p_filas jsonb)
returns integer
language plpgsql security definer set search_path to 'public'
as $function$
declare v_n integer := 0;
begin
  -- v17.23 (pedido de Luis) — registra en el log los pedidos que están retenidos pero NO pasan
  -- por gv_cuarentena_marcar: los que YA tienen tanda (la lista "Ya programados y el cliente está
  -- en cuarentena"). Sin esto, el log sólo vería la aprobación, sin saber cuándo había entrado.
  -- Mismo criterio de novedad que marcar: primera vez, re-entrada, o cambio de motivos.
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor.' using errcode='42501';
  end if;
  with f as (
    select lower(coalesce(e->>'empresa','lk')) empresa,
           nullif(btrim(e->>'clave'),'') clave,
           nullif(btrim(e->>'np'),'') np,
           nullif(btrim(e->>'cod'),'') cod,
           nullif(btrim(e->>'razon_social'),'') razon_social,
           case when jsonb_typeof(e->'motivos') = 'array'
                then array(select jsonb_array_elements_text(e->'motivos')) end motivos,
           (e->>'deuda')::numeric deuda
      from jsonb_array_elements(coalesce(p_filas,'[]'::jsonb)) e
  ),
  ins as (
    insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, deuda)
    select f.empresa, f.clave, f.np, f.cod, f.razon_social,
           case when u.evento is null or u.evento in ('aprobado','devuelto') then 'entro' else 'motivos' end,
           f.motivos, f.deuda
      from f
      left join lateral (
        select l.evento, l.motivos from public."GV_Cuarentena_Log" l
         where l.empresa = f.empresa and l.clave = f.clave
         order by l.at desc, l.id desc limit 1) u on true
     where f.clave is not null
       and (u.evento is null or u.evento in ('aprobado','devuelto') or u.motivos is distinct from f.motivos)
    returning 1)
  select count(*)::int into v_n from ins;
  return v_n;
end;
$function$;
revoke all on function public.gv_cuarentena_log_registrar(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_log_registrar(jsonb) to authenticated, service_role;


-- ── aprobar: ahora con la persona que autoriza (obligatoria) ───────────────
drop function if exists public.gv_cuarentena_liberar(text,text,text[],text,text);
create function public.gv_cuarentena_liberar(
  p_empresa text, p_order_id text, p_motivos text[] default null,
  p_comentario text default null, p_por text default null,
  p_persona text default null, p_np text default null)
returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_quien text; v_persona text; v_clave text := nullif(trim(p_order_id),'');
  v_np text; v_cod text; v_rs text;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede liberar pedidos de cuarentena.' using errcode='42501';
  end if;
  -- v17.23 (pedido de Luis): además del usuario logueado se guarda QUIÉN aprobó (Vivi, Marian, o
  -- lo que hayan escrito en "Otro"). Las dos cosas: `por` es trazabilidad técnica (el mail de la
  -- sesión) y `persona` es la respuesta a "¿quién lo autorizó?", que es lo que se mira después.
  v_quien   := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  v_persona := nullif(btrim(p_persona),'');
  if v_persona is null then
    raise exception 'Falta indicar quién aprueba el pedido.' using errcode='22023';
  end if;

  insert into public."GV_Cuarentena_Liberados" (empresa, order_id, motivos, liberado_por, persona)
  values (lower(p_empresa), v_clave, p_motivos, coalesce(v_quien,''), v_persona)
  on conflict (empresa, order_id) do update
     set motivos = excluded.motivos, liberado_at = now(),
         liberado_por = excluded.liberado_por, persona = excluded.persona;

  -- el comentario de la aprobación es una línea más del mismo log del pedido
  if coalesce(btrim(p_comentario),'') <> '' then
    insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
    values (lower(p_empresa), v_clave, nullif(btrim(p_np),''), btrim(p_comentario), v_quien, v_persona);
  end if;

  select l.np, l.cod, l.razon_social into v_np, v_cod, v_rs
    from public."GV_Cuarentena_Log" l
   where l.empresa = lower(p_empresa) and l.clave = v_clave
   order by l.at desc, l.id desc limit 1;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, motivos, persona, por, comentario)
  values (lower(p_empresa), v_clave, coalesce(nullif(btrim(p_np),''), v_np), v_cod, v_rs,
          'aprobado', p_motivos, v_persona, v_quien, nullif(btrim(p_comentario),''));
end;
$function$;
revoke all on function public.gv_cuarentena_liberar(text,text,text[],text,text,text,text) from public, anon;
grant execute on function public.gv_cuarentena_liberar(text,text,text[],text,text,text,text) to authenticated, service_role;


-- ── devolver a Cuarentena, también registrado ──────────────────────────────
drop function if exists public.gv_cuarentena_devolver(text,text,text,text,text);
create or replace function public.gv_cuarentena_devolver(
  p_empresa text, p_np text, p_clave text default null,
  p_comentario text default null, p_por text default null, p_persona text default null)
returns table(np_sacadas integer, detalle text)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_np text := btrim(coalesce(p_np,''));
  v_clave text := nullif(btrim(coalesce(p_clave, p_np, '')), '');
  v_quien text; v_persona text; v_n integer := 0; v_det text; v_cod text; v_rs text;
begin
  -- v17.20 — "Enviar a → Cuarentena": devolver el pedido a Cuarentena de verdad, no sólo despintar
  -- la marca de aprobado. Si sólo se borrara la fila de GV_Cuarentena_Liberados, el pedido seguiría
  -- en su tanda y saliendo igual: el botón sería mentiroso. Así que además se lo SACA DE LA
  -- PROGRAMACIÓN, que es lo que lo devuelve a "A Programar" — y ahí gv_cuarentena_marcar lo vuelve
  -- a retener solo. Las guardas fuertes las ponen las funciones que ya existían y acá se reusan:
  -- web → gv_ppp_web_desprogramar (falla si alguna tanda ya se empezó a trabajar);
  -- ISIS → gv_ppp_isis_desprogramar (falla si la NP ya tuvo Carga Camión o Recepción Remitos).
  -- v17.23: queda registrado en GV_Cuarentena_Log con la persona que lo devolvió.
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede devolver un pedido a cuarentena.' using errcode='42501';
  end if;
  if v_np = '' then raise exception 'No me pasaste la NP.'; end if;
  v_quien   := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  v_persona := nullif(btrim(p_persona),'');

  if v_np ~* '^(LK|CH)\s*\d+' then
    select w.np_sacadas into v_n from public.gv_ppp_web_desprogramar(v_np, v_quien) w;
    v_det := v_np;
  else
    select i.np_sacadas, i.detalle into v_n, v_det
      from public.gv_ppp_isis_desprogramar(array[v_np],
             'vuelta a Cuarentena' || coalesce(': ' || nullif(btrim(p_comentario),''), ''), v_quien) i;
  end if;

  delete from public."GV_Cuarentena_Liberados" lb
   where lb.empresa = lower(p_empresa) and lb.order_id = v_clave;

  insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
  values (lower(p_empresa), v_clave, v_np,
          '↩ Vuelto a Cuarentena (sacado de la programación)' ||
          coalesce(': ' || nullif(btrim(p_comentario),''), '.'), v_quien, v_persona);

  select l.cod, l.razon_social into v_cod, v_rs
    from public."GV_Cuarentena_Log" l
   where l.empresa = lower(p_empresa) and l.clave = v_clave
   order by l.at desc, l.id desc limit 1;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, persona, por, comentario)
  values (lower(p_empresa), v_clave, v_np, v_cod, v_rs, 'devuelto', v_persona, v_quien,
          nullif(btrim(p_comentario),''));

  return query select coalesce(v_n,0), coalesce(v_det, v_np);
end;
$function$;
revoke all on function public.gv_cuarentena_devolver(text,text,text,text,text,text) from public, anon;
grant execute on function public.gv_cuarentena_devolver(text,text,text,text,text,text) to authenticated, service_role;


-- ── el log, colapsado a una fila por pedido ────────────────────────────────
create or replace function public.gv_cuarentena_log(p_dias integer default 60)
returns table(empresa text, clave text, np text, cod text, razon_social text,
              motivos text[], deuda numeric, entro_at timestamptz, estado text,
              cerrado_at timestamptz, persona text, por text, comentario text,
              comentarios integer, eventos integer)
language sql stable security definer set search_path to 'public'
as $function$
  -- v17.23 (pedido de Luis, 2026-09-14) — el LOG de Cuarentena, una fila por pedido: cuándo entró,
  -- con qué motivos, en qué estado quedó y quién lo cerró (aprobó o devolvió) con su comentario.
  -- Sale de GV_Cuarentena_Log, que es append-only: acá se lo colapsa a lo último de cada cosa.
  with base as (
    select l.* from public."GV_Cuarentena_Log" l
     where l.at >= now() - make_interval(days => greatest(coalesce(p_dias, 60), 1))
  ),
  claves as (select distinct b.empresa, b.clave from base b),
  det as (
    select k.empresa, k.clave,
      (select l.np from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.np is not null
        order by l.at desc, l.id desc limit 1) as np,
      (select l.cod from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.cod is not null
        order by l.at desc, l.id desc limit 1) as cod,
      (select l.razon_social from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.razon_social is not null
        order by l.at desc, l.id desc limit 1) as razon_social,
      (select l.motivos from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.motivos is not null
        order by l.at desc, l.id desc limit 1) as motivos,
      (select l.deuda from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.deuda is not null
        order by l.at desc, l.id desc limit 1) as deuda,
      (select l.at from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.evento = 'entro'
        order by l.at desc, l.id desc limit 1) as entro_at,
      (select l.evento from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave
        order by l.at desc, l.id desc limit 1) as ult_evento,
      (select l.at from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.evento in ('aprobado','devuelto')
        order by l.at desc, l.id desc limit 1) as cerrado_at,
      (select l.persona from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.evento in ('aprobado','devuelto')
        order by l.at desc, l.id desc limit 1) as persona,
      (select l.por from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.evento in ('aprobado','devuelto')
        order by l.at desc, l.id desc limit 1) as por,
      (select l.comentario from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave and l.evento in ('aprobado','devuelto')
        order by l.at desc, l.id desc limit 1) as comentario,
      (select count(*)::int from public."GV_Cuarentena_Comentarios" c
        where c.empresa = k.empresa and c.order_id = k.clave) as comentarios,
      (select count(*)::int from public."GV_Cuarentena_Log" l
        where l.empresa = k.empresa and l.clave = k.clave) as eventos
    from claves k
  )
  select d.empresa, d.clave, d.np, d.cod, d.razon_social, d.motivos, d.deuda, d.entro_at,
         case when d.ult_evento = 'aprobado' then 'aprobado'
              when d.ult_evento = 'devuelto' then 'devuelto'
              else 'retenido' end,
         case when d.ult_evento in ('aprobado','devuelto') then d.cerrado_at end,
         case when d.ult_evento in ('aprobado','devuelto') then d.persona end,
         case when d.ult_evento in ('aprobado','devuelto') then d.por end,
         case when d.ult_evento in ('aprobado','devuelto') then d.comentario end,
         d.comentarios, d.eventos
    from det d
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by coalesce(d.cerrado_at, d.entro_at) desc nulls last;
$function$;
revoke all on function public.gv_cuarentena_log(integer) from public, anon;
grant execute on function public.gv_cuarentena_log(integer) to authenticated, service_role;

-- Chequeos
--   select * from public.gv_cuarentena_log(60);
--   select * from public."GV_Cuarentena_Log" order by at desc limit 20;
--   select count(*) from public.gv_cuarentena_ya_programado();   -- sin los aprobados
