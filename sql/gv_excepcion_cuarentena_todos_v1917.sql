-- =====================================================================================
-- v19.17 (Luis, 2026-09-16) — LA EXCEPCIÓN ES DE **TODO**, NO SÓLO DE LA DEUDA
--
-- Pedido, encima de la v19.16: *"excepción de todo, no solo deuda (limite credito y estado
-- también)"*.
--
-- La v19.16 dejó la lista (`public.gv_excepcion_cuarentena`) y la pregunta
-- (`gv_cuarentena_exento`), pero cableada a UN solo motivo: `deuda`. Era el único que la
-- excepción vieja (el `not exists` contra `cobranzas_cliente_cadena`) sabía tapar. Los otros
-- cuatro seguían entrando:
--
--   `suspendido` / `sin_cta_cte` → del reporte **Búsqueda CL** (`GV_Cuarentena_Fuente`)
--   `limite_credito`            → lo calcula `gv_cuarentena_limite` (greedy, ni miraba la lista)
--   `cliente_nuevo`             → de `GV_Clientes_Nuevos`
--
-- ── CÓMO SE CABLEÓ (y por qué así) ───────────────────────────────────────────────────
-- En `gv_cuarentena_marcar_calc` y `gv_cuarentena_ya_programado` la excepción **dejó de ser
-- una condición adentro de cada motivo** y pasó a ser UN filtro sobre el array ya armado:
--
--     (select coalesce(array_agg(x order by ord), array[]::text[])
--        from unnest(m.motivos) with ordinality u(x, ord)
--       where not public.gv_cuarentena_exento(m.emp_ev, m.cod_ev, x))
--
-- Un solo lugar por función en vez de uno por motivo, y **un motivo nuevo queda cubierto
-- solo**. Si el array queda vacío, el `array_length(...) >= 1` de siempre saca el pedido: no
-- hubo que tocar el criterio de "está en cuarentena". Las columnas `deuda`, `estado` y
-- `nuevo_pedidos` se anulan si su motivo se fue, para que la pantalla no muestre un monto de
-- un motivo que ya no aplica.
--
-- `gv_cuarentena_limite` es la excepción a la excepción: no arma un array, hace una caminata
-- greedy. Ahí el cliente exento se saca del CTE `ped`, o sea que **ni se lo mide** contra el
-- límite — más barato y sin riesgo de que el greedy lo cuente como crédito consumido.
--
-- El motivo `deuda` ya no lleva su guarda inline (la de la v19.16): la tapa el mismo filtro.
-- Queda en UN solo lugar por función.
--
-- ── LO QUE CAMBIA DE VERDAD (medido el 16/09, antes de tocar) ────────────────────────
-- Ampliar la excepción a los 5 motivos no toca sólo a los 3 clientes de Luis: los SÚPER
-- también están en la lista, y hay 4 que hoy caen por un motivo que no es deuda —
--
--   | cliente              | motivo que hoy lo frena              |
--   |----------------------|--------------------------------------|
--   | Carrefour  CH 1087   | `suspendido` (Búsqueda CL de Chef)    |
--   | Libertad   CH 1093   | `suspendido`                          |
--   | Coto       CH 2261   | `suspendido`                          |
--   | Gigot      LK 4263   | `cliente_nuevo` (GV_Clientes_Nuevos)  |
--
-- Los tres de Chef figuran *Suspendido* con límite 0 **porque a ese cliente no se le vende por
-- Chef** — es el mismo cuadro que ya había mordido con Tierra del Fuego (v17.75: evaluar por el
-- padrón equivocado retiene pedidos sanos). Con la v19.17 dejan de caer.
--
-- ⚠ CONTRACARA, que es la decisión que se toma acá: si a un súper lo suspenden **de verdad**,
-- la Cuarentena ya no lo va a frenar. La lista de excepciones pasa a ser el único lugar donde
-- eso se decide, y `motivos` es por cliente: para que a uno se le controle el estado alcanza
-- con sacarle `suspendido` de su fila, sin tocar código ni sacarlo de la lista.
--
-- ROLLBACK:
--   `sql/gv_excepcion_cuarentena_v1916.sql` §5 (marcar_calc y ya_programado como v19.16)
-- + `sql/backups/gv_cuarentena_limite_pre_v1917.sql` (limite como v17.74)
-- + `update public.gv_excepcion_cuarentena set motivos = array['deuda'];`
-- + volver el default de la columna y el insert de `gv_supers_sync` a `array['deuda']`.
-- =====================================================================================

-- ── 1) LA LISTA: los 5 motivos en las 25 filas, y en el default ──────────────────────
alter table public.gv_excepcion_cuarentena
  alter column motivos set default array['deuda','suspendido','sin_cta_cte','limite_credito','cliente_nuevo'];

update public.gv_excepcion_cuarentena
   set motivos = array['deuda','suspendido','sin_cta_cte','limite_credito','cliente_nuevo'],
       actualizado_at = now()
 where motivos is distinct from array['deuda','suspendido','sin_cta_cte','limite_credito','cliente_nuevo'];

comment on column public.gv_excepcion_cuarentena.motivos is
  'De qué motivos está exento este cliente. Los 5 = exento de toda la Cuarentena (v19.17). '
  'Sacarle uno alcanza para que ese motivo lo vuelva a frenar, sin tocar código.';

-- ── 2) EL SYNC DE LOS SÚPER, con los 5 ───────────────────────────────────────────────
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
  --     v19.17: nacen exentos de los CINCO motivos, no sólo de la deuda.
  delete from public.gv_excepcion_cuarentena e
   where e.origen = 'super'
     and not exists (select 1 from public."GV_Supers" s
                      where s.activo and s.empresa = e.empresa and s.cod = e.cod);

  insert into public.gv_excepcion_cuarentena (empresa, cod, nombre, motivos, origen, nota, actualizado_por)
  select s.empresa, s.cod, s.nombre,
         array['deuda','suspendido','sin_cta_cte','limite_credito','cliente_nuevo'], 'super',
         'Súper (GV_Supers). La cuenta del súper la lleva Cobranzas por cadena.', 'gv_supers_sync'
    from public."GV_Supers" s
   where s.activo
  on conflict (empresa, cod) do update
     set nombre = excluded.nombre, actualizado_at = now()
   where public.gv_excepcion_cuarentena.origen = 'super';

  return null;
end $function$;

-- ── 3) EL CENTINELA, contra los 5 motivos ────────────────────────────────────────────
create or replace view public.gv_excepcion_cuarentena_desincronizada
with (security_invoker = true) as
  select 'super_sin_excepcion'::text as que, s.empresa, s.cod, s.nombre
    from public."GV_Supers" s
   where s.activo
     and not exists (select 1 from public.gv_excepcion_cuarentena e
                      where e.empresa = s.empresa and e.cod = s.cod and e.activo
                        and e.motivos @> array['deuda','suspendido','sin_cta_cte','limite_credito','cliente_nuevo'])
  union all
  select 'excepcion_de_super_que_ya_no_es_super', e.empresa, e.cod, e.nombre
    from public.gv_excepcion_cuarentena e
   where e.origen = 'super'
     and not exists (select 1 from public."GV_Supers" s
                      where s.activo and s.empresa = e.empresa and s.cod = e.cod);
alter view public.gv_excepcion_cuarentena_desincronizada set (security_invoker = true);
grant select on public.gv_excepcion_cuarentena_desincronizada to anon, authenticated;

-- ── 4) LOS TRES CONSUMIDORES ─────────────────────────────────────────────────────────

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
  -- v19.16 (Luis, 2026-09-16): la excepción sale de gv_excepcion_cuarentena (tabla propia), no
  -- de la tabla de Facturación cobranzas_cliente_cadena.
  -- v19.17 (Luis, 2026-09-16): y es de TODOS los motivos, no sólo de `deuda`. El filtro es UNO
  -- solo, sobre el array ya armado (CTE `exc`), así un motivo nuevo queda cubierto solo. Si el
  -- array queda vacío, el `array_length >= 1` de siempre saca el pedido. `deuda`, `estado` y
  -- `nuevo_pedidos` se anulan si su motivo se fue: no mostrar el monto de algo que ya no aplica.
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
  exc as (   -- v19.17: se le sacan al pedido los motivos de los que el cliente está exento
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
  -- v19.16 / v19.17 (Luis, 2026-09-16): la excepción sale de gv_excepcion_cuarentena y es de
  -- TODOS los motivos. Mismo filtro único que en gv_cuarentena_marcar_calc (CTE `exc`).
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
  ),
  exc as (   -- v19.17: idem marcar_calc — un solo filtro para los 5 motivos
    select m.*,
           (select coalesce(array_agg(x order by ord), array[]::text[])
              from unnest(m.motivos) with ordinality u(x, ord)
             where not public.gv_cuarentena_exento(m.emp_ev, m.cod_ev, x)) as motivos_ok
      from marca m
  )
  select m.origen, m.empresa, m.np, m.order_id, m.clave, m.tanda, m.fecha_entrega, m.cod, m.razon_social,
         m.motivos_ok,
         case when 'deuda' = any (m.motivos_ok) then m.deuda end,
         case when m.motivos_ok && array['suspendido','sin_cta_cte'] then m.estado end,
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where btrim(r.texto) = btrim(m.tanda) and nullif(btrim(m.tanda),'') is not null),
         case when 'cliente_nuevo' = any (m.motivos_ok) then m.nuevo_pedidos end,
         lb.liberado_at, nullif(lb.liberado_por,''),
         (select count(*)::int from public."GV_Cuarentena_Comentarios" c
           where c.empresa = m.empresa and public.gv_cuarentena_clave(c.order_id) = public.gv_cuarentena_clave(m.clave))
  from exc m
  left join public."GV_Cuarentena_Liberados" lb
         on lb.empresa = m.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(m.clave)
  where array_length(m.motivos_ok, 1) >= 1
    and lb.order_id is null
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;

-- El límite de crédito no arma un array: es una caminata greedy. Al cliente exento se lo saca
-- del universo (`ped`), o sea que ni se lo mide — y así tampoco puede aparecer como crédito
-- consumido de sí mismo. Es el único cambio respecto de la v17.74.
CREATE OR REPLACE FUNCTION public.gv_cuarentena_limite(p_pendientes jsonb)
 RETURNS TABLE(order_id text, empresa text, exceso numeric, limite numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v15.04 (dueño 2026-09-11): además de marcar, devuelve POR CUÁNTO se pasa del límite
  -- ("Excede crédito por $100.000") y cuál es el límite. La lógica de greedy no cambió.
  -- v17.74 (Thomas, 2026-09-14): el pedido de la página LK que se factura por Chef mide contra
  -- el LÍMITE DE CRÉDITO DE CHEF y con el código de Chef (gv_cuarentena_ident / GV_Cliente_Isis).
  -- El crédito YA USADO se remapea igual, así que las NP web de LK de ese cliente y las NP de
  -- Chef del mismo cliente suman a la misma cuenta. Las NP de ISIS no se remapean: llevan el
  -- código de su propio ISIS. La valorización va con el par remapeado: gv_ppp_web_valor_items
  -- cotiza los artículos con L contra la lista de LK pelando la L, que es el precio real.
  -- La columna `empresa` que sale sigue siendo la del PEDIDO ('lk'): es la clave que usa el front.
  -- v19.17 (Luis, 2026-09-16): el cliente exento de `limite_credito` en gv_excepcion_cuarentena
  -- se saca acá, en `ped`: no se lo mide contra el límite.
  with recursive
  ped as (
    select nullif(trim(e->>'order_id'),'') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'),'') as cod,
           id.empresa as emp_ev,
           id.cod     as cod_ev,
           coalesce(e->>'fecha_recep','') as fecha_recep,
           public.gv_ppp_web_valor_items(id.empresa, id.cod, e->'items', nullif(e->>'cond','')) as monto
    from jsonb_array_elements(coalesce(p_pendientes,'[]'::jsonb)) e
    cross join lateral public.gv_cuarentena_ident(
      lower(coalesce(e->>'empresa','lk')),
      nullif(trim(e->>'cod'),''),
      coalesce(nullif(trim(e->>'order_id'),''), '') !~* '^np') id
    where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
      and not public.gv_cuarentena_exento(id.empresa, id.cod, 'limite_credito')
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
    select distinct p.emp_ev as empresa, p.cod_ev as cod
    from ped p join lim l on l.empresa=p.emp_ev and l.cod=p.cod_ev
    where p.cod_ev is not null
  ),
  npcod0 as (
    select regexp_replace(np::text,'\D','','g') as np, empresa, btrim(cod_cliente) as cod, true as es_web
      from public."PPP_Web_Programacion" where np is not null
    union
    select regexp_replace(np::text,'\D','','g') as np, gv_empresa_de_np_texto(np::text) as empresa, btrim(cod) as cod, false
      from public."GV_PPP_Programacion_Diaria" where np is not null and cod is not null
  ),
  npcod as (
    select n.np, id.empresa, id.cod
      from npcod0 n
      cross join lateral public.gv_cuarentena_ident(n.empresa, n.cod, n.es_web) id
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
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.monto, l.limite,
           row_number() over (partition by p.emp_ev, p.cod_ev order by p.fecha_recep, p.order_id) as rn
    from ped p join lim l on l.empresa = p.emp_ev and l.cod = p.cod_ev
    where p.order_id is not null and p.cod_ev is not null
  ),
  walk as (
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.rn, p.monto, p.limite,
           (coalesce(b.usado,0) + p.monto > p.limite) as cuar,
           case when coalesce(b.usado,0) + p.monto > p.limite then coalesce(b.usado,0)
                else coalesce(b.usado,0) + p.monto end as usado,
           (coalesce(b.usado,0) + p.monto - p.limite) as exceso
    from pend p
    left join base b on b.empresa = p.emp_ev and b.cod = p.cod_ev
    where p.rn = 1
    union all
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.rn, p.monto, p.limite,
           (w.usado + p.monto > p.limite),
           case when w.usado + p.monto > p.limite then w.usado else w.usado + p.monto end,
           (w.usado + p.monto - p.limite)
    from walk w join pend p on p.emp_ev = w.emp_ev and p.cod_ev = w.cod_ev and p.rn = w.rn + 1
  )
  select order_id, empresa, round(exceso::numeric, 2) as exceso, round(limite::numeric, 2) as limite
  from walk where cuar;
$function$;

-- ── VERIFICACIÓN ─────────────────────────────────────────────────────────────────────
-- (a) los 4 súper que caían por estado / cliente nuevo ya no caen, y un cliente común igual
-- select * from public.gv_cuarentena_marcar_calc(jsonb_build_array(
--   jsonb_build_object('order_id','999001','empresa','chef','cod','1087'),   -- Carrefour, Suspendido
--   jsonb_build_object('order_id','999002','empresa','chef','cod','1093'),   -- Libertad, Suspendido
--   jsonb_build_object('order_id','999003','empresa','chef','cod','2261'),   -- Coto, Suspendido
--   jsonb_build_object('order_id','999004','empresa','lk','cod','4263'),     -- Gigot, cliente_nuevo
--   jsonb_build_object('order_id','999005','empresa','lk','cod','288'),      -- Torres y Liva
--   jsonb_build_object('order_id','999006','empresa','lk','cod','2533'),     -- Osa
--   jsonb_build_object('order_id','999007','empresa','lk','cod','862')));    -- Muller  → vacío = bien
-- (b) el centinela, vacío
-- select * from public.gv_excepcion_cuarentena_desincronizada;
