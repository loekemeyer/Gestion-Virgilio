-- =====================================================================================
-- v19.16 (Luis, 2026-09-16) — LA LISTA DE EXCEPCIONES DE CUARENTENA, EN UNA TABLA PROPIA
--
-- Pedido: *"Fijate que me parece que hay lógica en el front que exceptúa a los súper de
-- cuarentena (saca el detalle de una tabla gv_supers o algo así). Quiero que crees una tabla
-- en Supa que sea gv_excepcion_cuarentena que incluya a los supers que están exentos
-- actualmente y además a Torres y Liva, Osa y Muller y Muller."*
--
-- ── DÓNDE ESTABA LA EXCEPCIÓN (no era el front) ──────────────────────────────────────
-- El front NO exime a nadie: `cuarMarcarPedidos()` le manda TODOS los pedidos de A Programar
-- al backend y pinta lo que vuelve. `pppEsSuper()` / `GV_Supers` sólo deciden camión, tanda y
-- nombre corto — no tocan la Cuarentena.
--
-- La excepción vivía en el BACKEND y era una sola línea, repetida 4 veces (2 en
-- `gv_cuarentena_marcar_calc`, 2 en `gv_cuarentena_ya_programado`):
--
--     and not exists (select 1 from public.cobranzas_cliente_cadena cc
--                      where cc.cod_cliente = p.cod_ev and lower(cc.empresa) in (…))
--
-- `cobranzas_cliente_cadena` es la tabla DERIVADA de `GV_Supers` (la rellena el trigger
-- `gv_supers_sync`, v17.72), así que Luis tenía razón en el origen del dato: la lista de
-- súper. Lo que no se veía es que la excepción **sólo tapa el motivo `deuda`**: un súper
-- suspendido, sin cta. cte., excedido de crédito o marcado como cliente nuevo cae igual.
--
-- ── LO QUE HACE ESTA VERSIÓN ─────────────────────────────────────────────────────────
-- 1. Crea `public.gv_excepcion_cuarentena` — la lista explícita de quién está exento y **de
--    qué motivo** (`motivos text[]`, hoy `{deuda}` para todos). Deja de ser un efecto lateral
--    de una tabla de Facturación que se llama "cobranzas".
-- 2. `gv_cuarentena_exento(empresa, cod, motivo)` — la única pregunta, como `gv_es_super`.
-- 3. Las 4 líneas de arriba pasan a preguntarle a esa función. `cobranzas_cliente_cadena`
--    **NO se toca**: le cuelgan 10 vistas de Facturación y un DROP ahí es el pozo de la
--    v16.20/v16.33. Queda como lo que es, una tabla de Facturación.
-- 4. `gv_supers_sync()` (el trigger de `GV_Supers`) mantiene además las filas `origen='super'`
--    de la tabla nueva. Así un súper que se dé de alta mañana queda exento solo, como hoy, y
--    las filas `origen='manual'` no las toca nadie. Sin esto, sacar la excepción de
--    `cobranzas_cliente_cadena` sería una regresión silenciosa.
-- 5. Carga los 19 súper activos + los 3 clientes que pidió Luis, en sus DOS empresas (el
--    código es por empresa — regla del CLAUDE.md, el mismo número es otro cliente en LK y CH):
--
--      | Cliente                    | LK   | Chef |
--      |----------------------------|------|------|
--      | Torres Y Liva S.A Cif      |  288 |  271 |
--      | Osa Distribuidora S.R.L.   | 2533 | 2340 |
--      | Muller Y Muller S.R.L.     |  862 | 1179 |
--
--    Los códigos salen de `GV_Cuarentena_Fuente` (las planillas del ERP de las dos empresas).
--
-- ── POR QUÉ ESOS 3 (medido antes de tocar nada) ──────────────────────────────────────
-- Los tres están **Activo** y sin suspensión en las dos empresas, pero con deuda corriente
-- en LK, o sea que caían en Cuarentena por `deuda` y sólo por eso:
--   Torres Y Liva 288  → $30.231.142,32   (límite $90.000.000)
--   Osa 2533           → $14.581.913,64   (límite $72.000.000)
--   Muller 862         → $12.031.476,19   (límite $79.000.000)
-- En Chef los tres vienen sin deuda cargada. Como la excepción es sólo del motivo `deuda`,
-- **siguen cayendo** si alguna vez los suspenden, se pasan del límite o quedan como cliente
-- nuevo: eso es a propósito.
--
-- ROLLBACK: `sql/backups/gv_cuarentena_exento_pre_v1916.sql` (las 3 funciones como estaban)
-- + `drop function public.gv_cuarentena_exento(text,text,text);`
-- + `drop table public.gv_excepcion_cuarentena;`
-- =====================================================================================

-- ── 1) LA TABLA ──────────────────────────────────────────────────────────────────────
create table if not exists public.gv_excepcion_cuarentena (
  empresa         text not null check (empresa in ('lk','chef')),
  cod             text not null,
  nombre          text not null,
  motivos         text[] not null default array['deuda'],
  origen          text not null default 'manual' check (origen in ('super','manual')),
  activo          boolean not null default true,
  nota            text,
  creado_at       timestamptz not null default now(),
  actualizado_at  timestamptz not null default now(),
  actualizado_por text,
  primary key (empresa, cod),
  constraint gv_excepcion_cuarentena_motivos_ck check (
    motivos <@ array['deuda','suspendido','sin_cta_cte','limite_credito','cliente_nuevo']
    and array_length(motivos, 1) >= 1)
);
create index if not exists gv_excepcion_cuarentena_origen_idx
  on public.gv_excepcion_cuarentena (origen);

alter table public.gv_excepcion_cuarentena enable row level security;
drop policy if exists gv_excepcion_cuarentena_lectura on public.gv_excepcion_cuarentena;
create policy gv_excepcion_cuarentena_lectura on public.gv_excepcion_cuarentena
  for select to anon, authenticated using (true);
grant select on public.gv_excepcion_cuarentena to anon, authenticated;
revoke insert, update, delete, truncate on public.gv_excepcion_cuarentena from anon, authenticated;

comment on table public.gv_excepcion_cuarentena is
  'v19.16 — quién NO cae en Cuarentena y por qué motivo. origen=super lo mantiene solo el '
  'trigger gv_supers_sync desde GV_Supers; origen=manual se carga a mano y el sync no lo toca.';

-- ── 2) LA PREGUNTA, EN UN SOLO LUGAR ─────────────────────────────────────────────────
create or replace function public.gv_cuarentena_exento(
  p_empresa text, p_cod text, p_motivo text default 'deuda')
returns boolean
language sql stable parallel safe
set search_path to 'public', 'pg_temp'
as $$
  select exists (
    select 1 from public.gv_excepcion_cuarentena e
     where e.activo
       and e.empresa = public.gv_emp_norm(p_empresa)
       and e.cod     = regexp_replace(btrim(coalesce(p_cod, '')), '\.0+$', '')
       and coalesce(nullif(btrim(p_motivo), ''), 'deuda') = any (e.motivos)
  );
$$;
revoke all on function public.gv_cuarentena_exento(text, text, text) from public;
grant execute on function public.gv_cuarentena_exento(text, text, text)
  to anon, authenticated, service_role;

-- ── 3) EL SYNC DESDE GV_Supers (mismo trigger que ya rellena cobranzas_cliente_cadena) ──
create or replace function public.gv_supers_sync()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- (a) la tabla derivada de Facturación, como siempre (v17.72)
  delete from public.cobranzas_cliente_cadena;
  insert into public.cobranzas_cliente_cadena (empresa, cod_cliente, super_key)
  select case when s.empresa = 'chef' then 'ch' else 'lk' end, s.cod, s.super_key
    from public."GV_Supers" s where s.activo;

  -- (b) v19.16: y la excepción de Cuarentena de los SÚPER. Sólo las filas `origen='super'`:
  --     si alguien cargó a mano una excepción para ese mismo (empresa, cod), manda la manual
  --     y el sync no la pisa ni la borra.
  delete from public.gv_excepcion_cuarentena e
   where e.origen = 'super'
     and not exists (select 1 from public."GV_Supers" s
                      where s.activo and s.empresa = e.empresa and s.cod = e.cod);

  insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, nota, actualizado_por)
  select s.empresa, s.cod, s.nombre, array['deuda'], 'super',
         'Súper (GV_Supers). La deuda del súper la lleva Cobranzas por cadena.', 'gv_supers_sync'
    from public."GV_Supers" s
   where s.activo
  on conflict (empresa, cod) do update
     set nombre = excluded.nombre, actualizado_at = now()
   where public.gv_excepcion_cuarentena.origen = 'super';

  return null;
end $function$;

-- ── 4) LA CARGA INICIAL ──────────────────────────────────────────────────────────────
-- (a) los 19 súper activos — se los deja poner al propio trigger, para no escribir dos veces
--     la misma regla. Un update sin cambios alcanza para dispararlo (es AFTER … FOR EACH
--     STATEMENT), y no modifica ningún dato de GV_Supers.
update public."GV_Supers" set actualizado_at = actualizado_at where true;

-- (b) los 3 que pidió Luis, en sus dos empresas
insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, nota, actualizado_por)
values
  ('lk',   '288',  'Torres Y Liva S.A Cif',    array['deuda'], 'manual', 'Pedido de Luis, 2026-09-16: no cae en Cuarentena por deuda corriente.', 'luis'),
  ('chef', '271',  'Torres Y Liva',            array['deuda'], 'manual', 'Pedido de Luis, 2026-09-16: no cae en Cuarentena por deuda corriente.', 'luis'),
  ('lk',   '2533', 'Osa Distribuidora S.R.L.', array['deuda'], 'manual', 'Pedido de Luis, 2026-09-16: no cae en Cuarentena por deuda corriente.', 'luis'),
  ('chef', '2340', 'Osa Distribuidora S.R.L.', array['deuda'], 'manual', 'Pedido de Luis, 2026-09-16: no cae en Cuarentena por deuda corriente.', 'luis'),
  ('lk',   '862',  'Muller Y Muller S.R.L.',   array['deuda'], 'manual', 'Pedido de Luis, 2026-09-16: no cae en Cuarentena por deuda corriente.', 'luis'),
  ('chef', '1179', 'Muller Y Muller S.R.L.',   array['deuda'], 'manual', 'Pedido de Luis, 2026-09-16: no cae en Cuarentena por deuda corriente.', 'luis')
on conflict (empresa, cod) do update
   set nombre = excluded.nombre, motivos = excluded.motivos, origen = 'manual',
       activo = true, nota = excluded.nota, actualizado_at = now(),
       actualizado_por = excluded.actualizado_por;

-- ── 5) LOS DOS CONSUMIDORES ──────────────────────────────────────────────────────────
-- Cambia UNA condición (repetida dos veces en cada una): el `not exists` contra
-- cobranzas_cliente_cadena pasa a `not public.gv_cuarentena_exento(…, 'deuda')`. Lo demás
-- queda igual; abajo va el CREATE completo, que es lo que manda (regla del CLAUDE.md: la
-- definición viva va en el repo, no "aplicada en la base").

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
  -- v19.16 (Luis, 2026-09-16): la excepción del motivo `deuda` ya no sale de la tabla de
  -- Facturación cobranzas_cliente_cadena sino de gv_excepcion_cuarentena, vía
  -- gv_cuarentena_exento(). Los súper siguen adentro (los pone el trigger gv_supers_sync) y se
  -- le suman los que se carguen a mano. Se evalúa con el par REMAPEADO (emp_ev/cod_ev), igual
  -- que el resto de los motivos.
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
            and not public.gv_cuarentena_exento(p.emp_ev, p.cod_ev, 'deuda')
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
          and not public.gv_cuarentena_exento(p.emp_ev, p.cod_ev, 'deuda')
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
  -- v19.16 (Luis, 2026-09-16): la excepción del motivo `deuda` sale de gv_excepcion_cuarentena
  -- (gv_cuarentena_exento), no de cobranzas_cliente_cadena. Misma lista de súper + los manuales.
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
            and not public.gv_cuarentena_exento(p.emp_ev, p.cod_ev, 'deuda')
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
          and not public.gv_cuarentena_exento(p.emp_ev, p.cod_ev, 'deuda')
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

-- ── 6) CENTINELA: la excepción de los súper no se puede desincronizar ────────────────
-- Vacía = todo bien. Un súper activo sin su fila en la tabla de excepciones (o al revés) es
-- exactamente la regresión que introduciría sacar la excepción de cobranzas_cliente_cadena.
create or replace view public.gv_excepcion_cuarentena_desincronizada
with (security_invoker = true) as
  select 'super_sin_excepcion'::text as que, s.empresa, s.cod, s.nombre
    from public."GV_Supers" s
   where s.activo
     and not exists (select 1 from public.gv_excepcion_cuarentena e
                      where e.empresa = s.empresa and e.cod = s.cod and e.activo
                        and 'deuda' = any (e.motivos))
  union all
  select 'excepcion_de_super_que_ya_no_es_super', e.empresa, e.cod, e.nombre
    from public.gv_excepcion_cuarentena e
   where e.origen = 'super'
     and not exists (select 1 from public."GV_Supers" s
                      where s.activo and s.empresa = e.empresa and s.cod = e.cod);
grant select on public.gv_excepcion_cuarentena_desincronizada to anon, authenticated;

-- ── VERIFICACIÓN ─────────────────────────────────────────────────────────────────────
-- (a) 25 filas: 19 súper + 6 manuales
-- select origen, count(*) from public.gv_excepcion_cuarentena group by 1;
-- (b) el centinela, vacío
-- select * from public.gv_excepcion_cuarentena_desincronizada;
-- (c) los 3 ya no caen por deuda, y un cliente cualquiera con deuda sigue cayendo
-- select * from public.gv_cuarentena_marcar_calc(jsonb_build_array(
--   jsonb_build_object('order_id','999001','empresa','lk','cod','288'),
--   jsonb_build_object('order_id','999002','empresa','lk','cod','2533'),
--   jsonb_build_object('order_id','999003','empresa','lk','cod','862')));   -- vacío = bien
