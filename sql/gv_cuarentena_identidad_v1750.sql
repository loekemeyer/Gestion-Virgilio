-- =====================================================================================
-- v17.50 (Luis, 2026-09-14) — UNA sola identidad por pedido en Cuarentena, y los datos
-- del pedido resueltos en la lectura.
--
-- PREGUNTA DE LUIS: *"no está sacando la razón social de ese cliente, ¿por qué?"* (el
-- pedido 1426, cod LK 4210, salía en el Log de Cuarentena sin nombre).
--
-- RESPUESTA, y son DOS problemas con la misma raíz (problema 172 de
-- `github_repo_problemas`): la identidad del pedido y sus datos no eran confiables.
--
-- ── (a) El mismo pedido de ISIS entra con DOS claves distintas ───────────────────────
-- En "A Programar" una NP de ISIS sin tanda se **disfraza de pedido** para reusar el
-- tildado y los pasos: `order_id = "np" + np` (`np98587`, `index.html` ~línea 38202).
-- `gv_cuarentena_ya_programado`, en cambio, la llama `98587` (`coalesce(order_id, np)`).
-- Las dos formas terminan en las mismas tablas (`GV_Cuarentena_Log`, `_Liberados`,
-- `_Comentarios`) como si fueran pedidos distintos. Medido el 14/09: **6 pedidos
-- duplicados** en el log (98585…98590), y las NP 98585/98586 —aprobadas bajo `np9858x`—
-- figuraban **retenidas**, porque su evento `entro` había quedado bajo la otra forma.
-- Peor: una aprobación hecha desde una pantalla no la veía la otra, así que el pedido
-- volvía a caer en cuarentena.
--
-- `gv_cuarentena_clave()` normaliza (`np98587` → `98587`) y se usa en los cuatro lugares
-- donde esa clave se compara. Es seguro: un `order_id` de pedido web es SIEMPRE dígitos,
-- nunca `np####`, así que el prefijo sólo puede venir del disfraz de ISIS.
--
-- ── (b) La fila del log nacía ciega y no se completaba nunca ─────────────────────────
-- `GV_Cuarentena_Log` guardaba `np` / `cod` / `razon_social` **tal como se los mandaba el
-- front**. Si una llamada no los traía, la fila quedaba sin ellos para siempre: el log no
-- vuelve a escribir esa fila porque `gv_cuarentena_marcar` sólo inserta cuando hay novedad
-- (primera vez, re-entrada o cambio de motivos). Al 14/09 había 7 filas así, entre ellas
-- la 1426 que preguntó Luis.
--
-- El arreglo NO es pedirle al front que mande mejor los datos —eso deja las filas viejas
-- rotas y se vuelve a romper con cualquier otra entrada— sino **resolverlos en la lectura**,
-- en cascada y desde lo que ya está en la base:
--   cod          → el guardado, o el de la programación viva (web por `order_id` en
--                  `PPP_Web_Programacion`; ISIS por NP en `gv_ppp_programacion_diaria`)
--   razón social → la guardada, la de la programación viva, o la de `GV_Cuarentena_Fuente`
--                  — la planilla del ERP que puso al pedido en cuarentena, así que si está
--                  retenido por deuda o suspensión el nombre está sí o sí
--   NP           → la guardada, la de `PPP_Web_NP`, la clave si es de ISIS, y si el pedido
--                  web todavía no tiene NP, la etiqueta `web LK 1426` que muestra A Programar
--
-- MEDICIÓN (14/09, antes → después): 32 → **26 pedidos** en el log (los 6 duplicados
-- fusionados), **0 sin razón social** (eran 7), **0 sin NP**, **0 sin cod**. El 1426 pasó a
-- mostrar `web LK 1426 · LK 4210 · Garbarino Franco Tomas`. Y `gv_cuarentena_marcar_calc`
-- probada con las dos formas de una NP aprobada (`np98585` y `98585`): ninguna vuelve a caer
-- en cuarentena — antes la forma sin prefijo caía igual.
--
-- ⚠ Los writers NO se tocaron a propósito: la resolución vive en UN solo lugar (la lectura),
-- así arregla también las filas ya escritas y no hay dos copias de la misma cascada que se
-- puedan desincronizar.
--
-- ROLLBACK: `drop function public.gv_cuarentena_clave(text) cascade` NO — se lo llevaría
-- puesto a las cuatro. Volver una por una a `sql/gv_cuarentena_log_v1743.sql` (log),
-- `sql/gv_cuarentena_comentarios_v1715.sql` (comentarios) y, para `marcar_calc` /
-- `ya_programado` / `liberados`, reemplazar cada `public.gv_cuarentena_clave(X)` por `X`.
-- =====================================================================================

-- ── 1) la normalización, en un solo lugar ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.gv_cuarentena_clave(p_clave text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case when p_clave ~ '^np[0-9]+$' then substring(p_clave from 3) else p_clave end;
$function$;

revoke all on function public.gv_cuarentena_clave(text) from public, anon;
grant execute on function public.gv_cuarentena_clave(text) to authenticated, service_role;

-- ── 2) el log: una fila por pedido, con los datos resueltos ──────────────────────────
CREATE OR REPLACE FUNCTION public.gv_cuarentena_log(p_dias integer DEFAULT 60)
 RETURNS TABLE(empresa text, clave text, np text, cod text, razon_social text, motivos text[], deuda numeric, entro_at timestamp with time zone, estado text, cerrado_at timestamp with time zone, persona text, por text, comentario text, com_persona text, com_por text, com_at timestamp with time zone, comentarios integer, eventos integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.50 (Luis, 2026-09-14: "no esta sacando la razon social de ese cliente, por que?").
  -- Dos arreglos, misma raiz -- la IDENTIDAD del pedido y sus datos no eran confiables:
  --
  -- (a) UNA sola clave. A Programar llama `np98587` al pedido de ISIS (order_id falso con el que
  --     se disfraza de pedido) y gv_cuarentena_ya_programado lo llama `98587`. El log los contaba
  --     como dos pedidos distintos: 6 duplicados, y las NP 98585/98586 -aprobadas bajo np9858x-
  --     figuraban RETENIDAS porque su evento `entro` habia quedado bajo la otra forma.
  --     gv_cuarentena_clave() las unifica, y las busquedas contra Comentarios aceptan las dos.
  --
  -- (b) cod, np y razon_social se RESUELVEN si la fila no los trae. Antes se guardaba lo que
  --     mandara el front y, si no los mandaba, la fila nacia ciega y no se completaba nunca
  --     (marcar solo escribe cuando hay novedad). Ahora, en la LECTURA y en cascada:
  --       cod          -> el guardado, o el de la programacion viva (web por order_id, ISIS por NP)
  --       razon social -> la guardada, la de la programacion viva, o la de GV_Cuarentena_Fuente
  --                       (la planilla del ERP que puso al pedido en cuarentena: si esta retenido
  --                       por deuda o suspension, el nombre esta si o si)
  --       NP           -> la guardada, la de PPP_Web_NP, la clave si es de ISIS, y si el pedido
  --                       web todavia no tiene NP, la etiqueta "web LK 1426" de A Programar
  with lg as (
    select l.*, public.gv_cuarentena_clave(l.clave) as k,
           (l.clave ~ '^np[0-9]+$') as es_isis
      from public."GV_Cuarentena_Log" l
  ),
  cm as (
    select c.*, public.gv_cuarentena_clave(c.order_id) as k
      from public."GV_Cuarentena_Comentarios" c
  ),
  base as (
    select g.empresa, g.k from lg g
     where g.at >= now() - make_interval(days => greatest(coalesce(p_dias, 60), 1))
    union
    -- un pedido comentado pero cuyo "entro" quedo fuera de la ventana tambien tiene que figurar
    select c.empresa, c.k from cm c
     where c.creado_at >= now() - make_interval(days => greatest(coalesce(p_dias, 60), 1))
  ),
  claves as (select distinct b.empresa, b.k from base b),
  det as (
    select k.empresa, k.k,
      (select g.np from lg g where g.empresa = k.empresa and g.k = k.k and g.np is not null
        order by g.at desc, g.id desc limit 1) as np,
      (select g.cod from lg g where g.empresa = k.empresa and g.k = k.k and g.cod is not null
        order by g.at desc, g.id desc limit 1) as cod,
      (select g.razon_social from lg g where g.empresa = k.empresa and g.k = k.k and g.razon_social is not null
        order by g.at desc, g.id desc limit 1) as razon_social,
      (select g.motivos from lg g where g.empresa = k.empresa and g.k = k.k and g.motivos is not null
        order by g.at desc, g.id desc limit 1) as motivos,
      (select g.deuda from lg g where g.empresa = k.empresa and g.k = k.k and g.deuda is not null
        order by g.at desc, g.id desc limit 1) as deuda,
      (select g.at from lg g where g.empresa = k.empresa and g.k = k.k and g.evento = 'entro'
        order by g.at desc, g.id desc limit 1) as entro_at,
      (select g.evento from lg g where g.empresa = k.empresa and g.k = k.k
        order by g.at desc, g.id desc limit 1) as ult_evento,
      (select g.at from lg g where g.empresa = k.empresa and g.k = k.k and g.evento in ('aprobado','devuelto')
        order by g.at desc, g.id desc limit 1) as cerrado_at,
      (select g.persona from lg g where g.empresa = k.empresa and g.k = k.k and g.evento in ('aprobado','devuelto')
        order by g.at desc, g.id desc limit 1) as persona,
      (select g.por from lg g where g.empresa = k.empresa and g.k = k.k and g.evento in ('aprobado','devuelto')
        order by g.at desc, g.id desc limit 1) as por,
      (select bool_or(g.es_isis) from lg g where g.empresa = k.empresa and g.k = k.k) as es_isis,
      (select c.texto from cm c where c.empresa = k.empresa and c.k = k.k
        order by c.creado_at desc, c.id desc limit 1) as comentario,
      (select c.persona from cm c where c.empresa = k.empresa and c.k = k.k
        order by c.creado_at desc, c.id desc limit 1) as com_persona,
      (select c.por from cm c where c.empresa = k.empresa and c.k = k.k
        order by c.creado_at desc, c.id desc limit 1) as com_por,
      (select c.creado_at from cm c where c.empresa = k.empresa and c.k = k.k
        order by c.creado_at desc, c.id desc limit 1) as com_at,
      (select count(*)::int from cm c where c.empresa = k.empresa and c.k = k.k) as comentarios,
      (select count(*)::int from lg g where g.empresa = k.empresa and g.k = k.k) as eventos
    from claves k
  ),
  res as (   -- cascada de resolucion: primero el cod, que es la llave del nombre
    select d.*,
      coalesce(d.cod,
        (select btrim(w.cod_cliente) from public."PPP_Web_Programacion" w
          where w.empresa = d.empresa and w.order_id::text = d.k
            and nullif(btrim(w.cod_cliente),'') is not null limit 1),
        (select btrim(p.cod) from public.gv_ppp_programacion_diaria p
          where btrim(p.np) = d.k and nullif(btrim(p.cod),'') is not null limit 1)) as cod_r,
      coalesce(d.razon_social,
        (select w.razon_social from public."PPP_Web_Programacion" w
          where w.empresa = d.empresa and w.order_id::text = d.k
            and nullif(btrim(w.razon_social),'') is not null limit 1),
        (select p.razon_social from public.gv_ppp_programacion_diaria p
          where btrim(p.np) = d.k and nullif(btrim(p.razon_social),'') is not null limit 1)) as rs_r
    from det d
  )
  select r.empresa, r.k,
         coalesce(r.np,
           (select public.gv_ppp_web_np_label(n.empresa, n.np, n.np_idx)
              from public."PPP_Web_NP" n
             where n.empresa = r.empresa and n.order_id::text = r.k limit 1),
           case when r.es_isis or r.k ~ '^[0-9]{5,}$' then r.k
                when r.k ~ '^[0-9]+$' then 'web ' || case when r.empresa = 'chef' then 'CH' else 'LK' end || ' ' || r.k
           end),
         r.cod_r,
         coalesce(r.rs_r,
           (select nullif(btrim(f.razon_social), '') from public."GV_Cuarentena_Fuente" f
             where f.empresa = r.empresa and f.cod = r.cod_r
               and nullif(btrim(f.razon_social),'') is not null
             order by f.cargado_at desc limit 1)),
         r.motivos, r.deuda, r.entro_at,
         case when r.ult_evento = 'aprobado' then 'aprobado'
              when r.ult_evento = 'devuelto' then 'devuelto'
              else 'retenido' end,
         case when r.ult_evento in ('aprobado','devuelto') then r.cerrado_at end,
         case when r.ult_evento in ('aprobado','devuelto') then r.persona end,
         case when r.ult_evento in ('aprobado','devuelto') then r.por end,
         r.comentario, r.com_persona, r.com_por, r.com_at,
         r.comentarios, r.eventos
    from res r
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by greatest(coalesce(r.cerrado_at, r.entro_at, r.com_at),
                     coalesce(r.com_at, r.cerrado_at, r.entro_at)) desc nulls last;
$function$;

-- ── 3) los comentarios, buscados por la clave normalizada ────────────────────────────
CREATE OR REPLACE FUNCTION public.gv_cuarentena_comentarios(p_empresa text, p_order_id text)
 RETURNS TABLE(id bigint, creado_at timestamp with time zone, persona text, por text, texto text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.38 (Luis, 2026-09-14): devuelve también `persona` — la identidad de quien dejó el
  -- comentario (Vivi / Marian / lo que escribieron en "Otro"), que es distinta del `por`
  -- (el mail de la sesión que lo tipeó) y es la que se busca al leer el log.
  -- v17.50: el mismo pedido de ISIS se llama `np98587` en A Programar y `98587` en el log, así
  -- que la búsqueda va por la clave NORMALIZADA. Sin esto, un comentario dejado desde una
  -- pantalla no aparecía en la otra: el 📖 mostraba un hilo distinto según de dónde se abriera.
  select c.id, c.creado_at, c.persona, c.por, c.texto
    from public."GV_Cuarentena_Comentarios" c
   where c.empresa = lower(p_empresa)
     and public.gv_cuarentena_clave(c.order_id) = public.gv_cuarentena_clave(nullif(btrim(p_order_id),''))
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by c.creado_at;
$function$;

-- ── 4) los liberados: devuelve LAS DOS formas de cada clave ──────────────────────────
-- El front matchea el pedido por su `order_id` (que para ISIS es `np98585`), así que una
-- aprobación hecha desde la tabla del log (clave `98585`) no la veía. Devolver las dos
-- formas lo arregla sin tocar el front; filas de más no molestan, es una lista de chequeo.
CREATE OR REPLACE FUNCTION public.gv_cuarentena_liberados()
 RETURNS TABLE(empresa text, order_id text, motivos text[])
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.empresa, f.forma, l.motivos
    from public."GV_Cuarentena_Liberados" l
    cross join lateral (
      select distinct x from unnest(array[
        l.order_id,
        case when l.order_id ~ '^np[0-9]+$' then substring(l.order_id from 3)
             when l.order_id ~ '^[0-9]+$'   then 'np' || l.order_id end]) x
       where x is not null) f(forma)
   where es_supervisor_virgilio() or gv_es_supervisor_o_servicio();
$function$;

-- ── 5) y 6) los dos consumidores de la clave ─────────────────────────────────────────
-- `gv_cuarentena_marcar_calc` y `gv_cuarentena_ya_programado` se parchearon con el loop
-- mecánico (`pg_get_functiondef` → `replace()` → `execute`) porque el cambio es de UNA
-- condición en cada una; abajo va el `CREATE` COMPLETO resultante, que es lo que manda
-- (regla del CLAUDE.md: la definición viva va en el repo, no "aplicada en la base").
--   marcar_calc  : `lb.order_id = m.order_id`  → por clave normalizada
--   ya_programado: el join contra Liberados y el conteo de Comentarios, idem
-- Sin eso, un pedido de ISIS aprobado bajo una forma volvía a caer en cuarentena bajo la otra.

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
           where c.empresa = m.empresa and public.gv_cuarentena_clave(c.order_id) = public.gv_cuarentena_clave(m.clave))
  from marca m
  left join public."GV_Cuarentena_Liberados" lb
         on lb.empresa = m.empresa and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(m.clave)
  where array_length(m.motivos, 1) >= 1
    and lb.order_id is null   -- v17.23 (Luis): "si un cliente está aprobado, que salga de esa lista"
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;

-- ── verificación ─────────────────────────────────────────────────────────────────────
-- tiene que dar 0 sin razón social, 0 sin NP, 0 sin cod, y ningún pedido repetido
select count(*) total,
       count(*) filter (where razon_social is null) sin_rs,
       count(*) filter (where np is null) sin_np,
       count(*) filter (where cod is null) sin_cod,
       count(*) - count(distinct (empresa, clave)) repetidos
  from public.gv_cuarentena_log(60);

-- y que ninguna de las dos formas de una NP aprobada vuelva a caer en cuarentena
select * from public.gv_cuarentena_marcar_calc(jsonb_build_array(
  jsonb_build_object('order_id','np98585','empresa','lk','cod','4274'),
  jsonb_build_object('order_id','98585','empresa','lk','cod','4274')));   -- vacío = bien
