-- =====================================================================================
-- gv_cuarentena_log v2 — v17.43 (Luis, 2026-09-14)
--
-- PEDIDO: *"fijate que muestre bien lo que pongan en el log de ahora en más"*.
--
-- QUÉ ESTABA MAL (problema 168 de `github_repo_problemas`): la v17.23 sacaba
-- `comentario` / `persona` / `por` de los eventos `aprobado` | `devuelto` de
-- `GV_Cuarentena_Log`. Pero los comentarios NO viven ahí: viven en
-- `GV_Cuarentena_Comentarios`, donde caen TODOS —los de una aprobación y los de una
-- devolución los escribe `gv_cuarentena_liberar` / `gv_cuarentena_devolver`, y los
-- sueltos los escribe `gv_cuarentena_comentar` desde el 📖—. Resultado: si alguien
-- comentaba un pedido que seguía RETENIDO, la fila del log mostraba "—" y lo único que
-- se movía era el contador del 📖. O sea que lo que la gente escribía no se veía sin
-- abrir el pop-up pedido por pedido, que es justo lo que el log venía a evitar.
--
-- QUÉ CAMBIA
--   · `comentario` pasa a ser el ÚLTIMO comentario del pedido, salga de donde salga.
--   · se agregan `com_persona` / `com_por` / `com_at` — quién lo escribió (Vivi, Marian
--     o lo que hayan puesto en "Otro"), con qué usuario y cuándo. Son datos DISTINTOS de
--     `persona` / `por` / `cerrado_at`, que siguen siendo los del CIERRE: un pedido lo
--     puede aprobar Vivi y comentarlo Marian media hora después.
--   · la ventana de `p_dias` ahora también entra por los comentarios (`union` en `base`):
--     un pedido viejo que alguien comenta hoy tiene que aparecer, y con el filtro sólo
--     sobre `GV_Cuarentena_Log.at` se caía de la lista.
--   · el orden pasa a ser por lo último que pasó (cierre, entrada o comentario).
--
-- ⚠ Cambia el TIPO DE RETORNO, así que es DROP + CREATE, no `create or replace`. El DROP
-- se lleva los grants: por eso el `revoke`/`grant` del final NO es decorativo. Los que
-- tenía: `authenticated` y `service_role` (nunca `anon` — es SECURITY DEFINER y el guard
-- de supervisor es lo único que la protege).
--
-- MEDIDO al aplicarla (14/09): 32 pedidos en 60 días, los mismos que antes (25 retenidos,
-- 7 aprobados), 3 con comentario. Y probada de verdad contra un pedido retenido real
-- dentro de una transacción que después se abortó: se insertó un comentario con
-- `gv_cuarentena_comentar(... 'Marian')` y la fila pasó a devolver
-- `comentario=[PRUEBA: ojo con este cliente] com_persona=Marian com_por=prueba@local
-- com_at=14/09 12:36 comentarios=1` — con la v17.23 esa misma fila devolvía todo en NULL.
-- Confirmado después que no quedó escrito nada (`GV_Cuarentena_Comentarios` siguió en 3).
--
-- ROLLBACK: volver a la definición de `sql/gv_cuarentena_log_v1723.sql` (mismo DROP +
-- CREATE + grants). El front de la v17.23 no leía `com_*`, así que es reversible sola.
-- =====================================================================================

drop function if exists public.gv_cuarentena_log(integer);

create function public.gv_cuarentena_log(p_dias integer default 60)
returns table(empresa text, clave text, np text, cod text, razon_social text, motivos text[],
              deuda numeric, entro_at timestamptz, estado text, cerrado_at timestamptz,
              persona text, por text, comentario text, com_persona text, com_por text,
              com_at timestamptz, comentarios integer, eventos integer)
language sql stable security definer set search_path to 'public'
as $function$
  -- v17.43 (Luis, 2026-09-14: "fijate que muestre bien lo que pongan en el log de ahora en mas").
  -- Cambio respecto de la v17.23: el COMENTARIO que se muestra ya no sale del evento de cierre
  -- sino de GV_Cuarentena_Comentarios, que es donde caen TODOS -- los de una aprobacion o una
  -- devolucion (gv_cuarentena_liberar / _devolver insertan ahi tambien) y los sueltos que alguien
  -- deja desde el 📖 sobre un pedido que sigue retenido. Con la version anterior ese ultimo caso
  -- no se veia: la fila mostraba "—" y solo se movia el contador del 📖.
  -- persona/por/cerrado_at siguen siendo los del CIERRE (quien aprobo o devolvio);
  -- com_persona/com_por/com_at son los del ultimo comentario, que puede ser otro y otro momento.
  with base as (
    select l.empresa, l.clave from public."GV_Cuarentena_Log" l
     where l.at >= now() - make_interval(days => greatest(coalesce(p_dias, 60), 1))
    union
    -- un pedido comentado pero cuyo "entro" quedo fuera de la ventana tambien tiene que figurar
    select c.empresa, c.order_id from public."GV_Cuarentena_Comentarios" c
     where c.creado_at >= now() - make_interval(days => greatest(coalesce(p_dias, 60), 1))
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
      (select c.texto from public."GV_Cuarentena_Comentarios" c
        where c.empresa = k.empresa and c.order_id = k.clave
        order by c.creado_at desc, c.id desc limit 1) as comentario,
      (select c.persona from public."GV_Cuarentena_Comentarios" c
        where c.empresa = k.empresa and c.order_id = k.clave
        order by c.creado_at desc, c.id desc limit 1) as com_persona,
      (select c.por from public."GV_Cuarentena_Comentarios" c
        where c.empresa = k.empresa and c.order_id = k.clave
        order by c.creado_at desc, c.id desc limit 1) as com_por,
      (select c.creado_at from public."GV_Cuarentena_Comentarios" c
        where c.empresa = k.empresa and c.order_id = k.clave
        order by c.creado_at desc, c.id desc limit 1) as com_at,
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
         d.comentario, d.com_persona, d.com_por, d.com_at,
         d.comentarios, d.eventos
    from det d
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by greatest(coalesce(d.cerrado_at, d.entro_at, d.com_at),
                     coalesce(d.com_at, d.cerrado_at, d.entro_at)) desc nulls last;
$function$;

-- el DROP se llevó los grants: sin estas dos líneas la RPC queda ejecutable por PUBLIC
-- (o sea por la anon key) y sin `authenticated` no la puede llamar el supervisor logueado.
revoke all on function public.gv_cuarentena_log(integer) from public, anon;
grant execute on function public.gv_cuarentena_log(integer) to authenticated, service_role;

-- verificación
select count(*) filter (where estado = 'retenido') retenidos,
       count(*) filter (where estado = 'aprobado') aprobados,
       count(*) filter (where comentario is not null) con_comentario,
       count(*) total
  from public.gv_cuarentena_log(60);
