-- =============================================================================
-- gv_espejo_corte.sql — LA CANILLA DEL ESPEJO DE ISIS, CERRADA PARA GESTIÓN (2026-09-05)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · objetos NUEVOS, prefijo gv_, sólo lectura
-- =============================================================================
-- LO QUE PIDIÓ EL DUEÑO: "una vez que ya esté todo en Gestión Virgilio, cerrá la
-- canilla para que no lleguen más desde el espejo del Excel".
--
-- LA CANILLA. El Apps Script de Google ("Carga PPP.gs", fuera del repo; el espejo
-- está en apps-script/sync-ppp-supabase.gs) pisa `PPP_Programacion_Diaria` y
-- `PPP_Base_Pedidos` con la service key cada vez que ISIS actualiza el Sheet, y el
-- cron `sync-ppp-entregados-meta` (jobid 27) baja "Pedidos Entregados" a
-- `PPP_Entregados_Meta`. Producción Virgilio lee ESAS MISMAS tablas y sigue viva, y
-- la regla del dueño sobre lo compartido es: se agrega, no se modifica. Así que la
-- canilla NO se cierra en Google ni en las tablas: se cierra EN LO QUE GESTIÓN LEE.
--
-- CÓMO. Corte por NP. ISIS numera en orden (LK 9xxxx, Chef 4xxxx). Al cerrar se
-- anota la última NP que había en el espejo (`espejo_np_corte_lk` / `_chef` en
-- `PPP_Web_Config`) y Gestión, en vez de las tablas, lee tres vistas que sólo
-- devuelven NP <= corte:
--   · gv_ppp_programacion_diaria   sobre PPP_Programacion_Diaria
--   · gv_ppp_base_pedidos          sobre PPP_Base_Pedidos
--   · gv_ppp_entregados_meta       sobre PPP_Entregados_Meta
-- Las NP abiertas de Producción siguen vivas en Gestión (y se purgan solas cuando
-- Producción las saca del Excel, como siempre). Lo que ISIS cargue DESPUÉS del corte
-- no entra más: esos pedidos entran a Gestión desde la página, por A Programar / el
-- job. Para eso `gv_pedidos_web_excluidos` deja de contar como "en Producción" una NP
-- posterior al corte (si no, el pedido desaparecía de las dos pantallas).
--
-- ABIERTA / CERRADA. Sin las dos filas de config (o con valor null) las vistas son
-- passthrough: la canilla está abierta y Gestión ve lo mismo que Producción. Con las
-- filas, cerrada. Todo reversible con un update, sin redeployar nada.
--
-- ⚠ MIENTRAS SIGA EL MAIL DE LAS 12:30 EN LK, un pedido nuevo de la página va a
-- existir en las dos apps: en Producción como NP de ISIS (> corte, Gestión no la ve)
-- y en Gestión como NP web. Lo aceptó el dueño el 2026-09-04; se resuelve apagando
-- `procesar-pedidos-web` en LK.
--
-- Etiquetas web ("LK 00001") y NP no numéricas pasan siempre: el corte es sólo
-- sobre lo que numeró ISIS.
--
-- MEDIDO al cerrar (2026-09-05): corte LK 98694 / Chef 44619 = el máximo de ese
-- momento → las vistas devuelven exactamente lo que había: 182 / 9.667 / 2.783.
--
-- ROLLBACK (abrir la canilla):
--   update public."PPP_Web_Config" set valor = null where clave like 'espejo_np_corte_%';
-- ROLLBACK total:
--   drop view public.gv_ppp_programacion_diaria, public.gv_ppp_base_pedidos, public.gv_ppp_entregados_meta;
--   drop function public.gv_espejo_np_pasa(text, bigint, bigint), public.gv_espejo_corte();
--   delete from public."PPP_Web_Config" where clave like 'espejo_np_corte_%';
--   (y la RPC gv_pedidos_web_excluidos vuelve a la versión de sql/gv_pedidos_web_excluidos.sql
--    sin el cruce con gv_espejo_corte)
-- =============================================================================

insert into public."PPP_Web_Config" (clave, valor, descripcion) values
  ('espejo_np_corte_lk',   98694, 'CANILLA DEL ESPEJO DE ISIS (LK). Ultima NP de ISIS que Gestion toma del espejo del Excel (PPP_Programacion_Diaria / Base / Entregados_Meta). Lo que ISIS numere despues de esto no entra a Gestion: entra desde la pagina. null = canilla abierta (Gestion ve lo mismo que Produccion). Cerrada el 2026-09-05.'),
  ('espejo_np_corte_chef', 44619, 'CANILLA DEL ESPEJO DE ISIS (Chef). Idem espejo_np_corte_lk para las NP 4xxxx.')
on conflict (clave) do nothing;

-- El corte vigente, una sola vez por consulta (las vistas hacen cross join con esto).
create or replace function public.gv_espejo_corte()
returns table(lk bigint, chef bigint)
language sql stable security invoker set search_path = public as $$
  select (select valor::bigint from public."PPP_Web_Config" where clave = 'espejo_np_corte_lk'),
         (select valor::bigint from public."PPP_Web_Config" where clave = 'espejo_np_corte_chef');
$$;

-- ¿Esta NP pasa la canilla? Sólo frena NP numéricas de ISIS por encima del corte
-- de su empresa; etiquetas web, vacíos y cualquier otra cosa pasan.
create or replace function public.gv_espejo_np_pasa(p_np text, p_lk bigint, p_chef bigint)
returns boolean
language sql immutable parallel safe as $$
  select case
    when regexp_replace(btrim(coalesce(p_np, '')), '\.0+$', '') !~ '^\d{1,18}$' then true
    when p_np ~ '^\s*9' then p_lk   is null or regexp_replace(btrim(p_np), '\.0+$', '')::bigint <= p_lk
    when p_np ~ '^\s*4' then p_chef is null or regexp_replace(btrim(p_np), '\.0+$', '')::bigint <= p_chef
    else true
  end;
$$;

create or replace view public.gv_ppp_programacion_diaria
with (security_invoker = true) as
  select p.*
    from public."PPP_Programacion_Diaria" p
    cross join public.gv_espejo_corte() c
   where public.gv_espejo_np_pasa(p.np, c.lk, c.chef);

create or replace view public.gv_ppp_base_pedidos
with (security_invoker = true) as
  select b.*
    from public."PPP_Base_Pedidos" b
    cross join public.gv_espejo_corte() c
   where public.gv_espejo_np_pasa(b.pedido, c.lk, c.chef);

create or replace view public.gv_ppp_entregados_meta
with (security_invoker = true) as
  select m.*
    from public."PPP_Entregados_Meta" m
    cross join public.gv_espejo_corte() c
   where public.gv_espejo_np_pasa(m.np, c.lk, c.chef);

-- Sólo lectura: las vistas son "simple" y Postgres las dejaría actualizables.
revoke all on public.gv_ppp_programacion_diaria, public.gv_ppp_base_pedidos, public.gv_ppp_entregados_meta from anon, authenticated;
grant select on public.gv_ppp_programacion_diaria, public.gv_ppp_base_pedidos, public.gv_ppp_entregados_meta to anon, authenticated;
grant execute on function public.gv_espejo_corte() to anon, authenticated, service_role;
grant execute on function public.gv_espejo_np_pasa(text, bigint, bigint) to anon, authenticated, service_role;

-- La regla de pendiente respeta la canilla: una NP de ISIS posterior al corte no
-- cuenta como "en Producción" para Gestión (ese pedido entra desde la página).
create or replace function public.gv_pedidos_web_excluidos(p_pedidos jsonb)
returns table(empresa text, order_id bigint, motivo text)
language sql
stable
security invoker
set search_path = public
as $$
  -- PENDIENTE PARA GESTIÓN = pedido de la página con fecha >= gestion_desde que
  -- Producción/ISIS NO conozca. Esta función devuelve los EXCLUIDOS (lo que Gestión
  -- no toma) con el motivo; el que llama saca esos order_id de su lista.
  --   anterior_al_cambio → fecha_recep < PPP_Web_Config.gestion_desde (lo de antes es
  --                        de Producción, no entra nunca)
  --   en_produccion      → hay una NP de ISIS de ese cliente con esa fecha de pedido en
  --                        cualquiera de las cuatro tablas que Producción usa, y esa NP
  --                        es ANTERIOR AL CORTE DEL ESPEJO (gv_espejo_corte): lo que
  --                        ISIS numere después de cerrar la canilla no es de Producción
  --                        a los ojos de Gestión (2026-09-05).
  -- Si falta la config, se excluye TODO (falla cerrado): antes que duplicar, no tomar.
  with cfg as (
    select coalesce((select nullif(valor_texto,'')::date from public."PPP_Web_Config" where clave = 'gestion_desde'),
                    date '9999-12-31') as desde
  ),
  corte as (select lk, chef from public.gv_espejo_corte()),
  ped as (
    select lower(coalesce(p->>'empresa','lk')) as empresa,
           (p->>'order_id')::bigint            as order_id,
           btrim(p->>'cod')                    as cod,
           (p->>'fecha_recep')::date           as fecha
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) p
  ),
  np_prod as (
    select regexp_replace(btrim(x.np),'\.0+$','') as np, btrim(x.cod) as cod
    from (
      select np, cod         from public."PPP_Programacion_Diaria"
      union all select np, cod_cliente from public."Facturacion_NP"
      union all select np, cod         from public."PPP_Entregados_Meta"
      union all select np, cod_cliente from public."Entregas_Virgilio"
    ) x
    cross join corte c
    where x.np is not null and nullif(btrim(x.cod),'') is not null
      and public.gv_espejo_np_pasa(x.np, c.lk, c.chef)
  ),
  np_fecha as (
    select regexp_replace(btrim(pedido),'\.0+$','') as np, min(fecha::date) as fecha
    from public."PPP_Base_Pedidos" group by 1
  )
  select d.empresa, d.order_id, 'anterior_al_cambio'::text
    from ped d cross join cfg
   where d.fecha is null or d.fecha < cfg.desde
  union
  select d.empresa, d.order_id, 'en_produccion'::text
    from ped d
   where exists (
     select 1 from np_prod n join np_fecha f on f.np = n.np
      where n.cod = d.cod and f.fecha = d.fecha
        and ((d.empresa = 'lk' and n.np ~ '^9') or (d.empresa = 'chef' and n.np ~ '^4'))
   );
$$;
