-- =============================================================================
-- gv_pedidos_web_excluidos.sql — LA REGLA DE "PENDIENTE PARA GESTIÓN"
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · objetos NUEVOS, prefijo gv_, sólo lectura
-- =============================================================================
-- HISTORIA
--   2026-09-04 tarde  · "pendiente = no enviado a compras" en los feeds de LK (v12.88).
--   2026-09-04 noche  · el dueño lo cambió a "desde gestion_desde, lo que Producción no
--                       tenga" (v12.89), para tomar también el limbo (enviado a ISIS pero
--                       que Producción no tenía) porque el mail de las 12:30 seguía prendido.
--   2026-09-05 sábado · el dueño decidió APAGAR el mail de las 12:30 de LK (cron 7 y 10 en
--                       kwkclwhmoygunqmlegrg, active=false a las 13:50 ART; el último envío
--                       fue ese mismo sábado a las 12:30 con los pedidos 1340..1349) y que
--                       Gestión arranque limpio: lo que YA salió a ISIS es de Producción,
--                       lo que no salió es de Gestión. Vuelve `enviado_a_compras`, ahora
--                       como PRIMER motivo de exclusión (v12.94). Chef sigue mandando su
--                       mail hasta que el dueño lo apague en su proyecto: mismo criterio.
--
-- LA REGLA (v12.94): PENDIENTE = pedido de la página que NO salió a ISIS por el mail,
--                    con fecha >= gestion_desde, y que Producción/ISIS no conozca.
--
-- Motivos que devuelve (un pedido puede traer más de uno):
--   enviado_a_isis     → enviado_a_compras = true: ya lo tiene ISIS → Producción.
--   anterior_al_cambio → fecha_recep < gestion_desde (piso, 2026-09-03).
--   en_produccion      → hay NP de ISIS de ese cliente con esa fecha de pedido en
--                        programación / facturación / entregados / entregas, y esa NP pasa
--                        la canilla del espejo (gv_espejo_corte, v12.90).
--
-- ¿Por qué no bastó con la fecha del lunes? Con el mail apagado el sábado a la tarde, un
-- pedido del sábado a las 12:49 (el 1350) o del domingo no sale por mail NUNCA: si Gestión
-- lo excluyera por fecha (< lunes), no lo tomaría nadie. Con `enviado_a_compras` el corte
-- es exacto: el último mail. Cero dobles, cero huérfanos.
--
-- DÓNDE SE APLICA: la Edge Function gv-ppp-web-tandas-diarias (soloPendientes, v13) y
-- "A Programar" (aprTraerPedidos) le pasan (empresa, order_id, cod, fecha_recep,
-- enviado_a_compras) por pedido, sobre los feeds CRUDOS de LK.
--
-- FALLA CERRADO: sin config gestion_desde se excluye todo.
--
-- MEDIDO al aplicar (sábado 13:55 ART): LK 212 pedidos → pendiente 1 (el 1350, 12:49) ·
-- Chef → 0 (el 217 salió por su mail el viernes).
--
-- ROLLBACK: la versión v12.89 (sin `enviado_a_isis`) está en git (commit 473cf7f);
--           delete from public."PPP_Web_Config" where clave = 'gestion_desde';
--           y en LK: select cron.alter_job(7, active := true); select cron.alter_job(10, active := true);
-- =============================================================================

insert into public."PPP_Web_Config" (clave, valor_texto)
select 'gestion_desde', '2026-09-03'
where not exists (select 1 from public."PPP_Web_Config" where clave = 'gestion_desde');

create or replace function public.gv_pedidos_web_excluidos(p_pedidos jsonb)
returns table(empresa text, order_id bigint, motivo text)
language sql stable security invoker set search_path = public as $$
  with cfg as (
    select coalesce((select nullif(valor_texto,'')::date from public."PPP_Web_Config" where clave = 'gestion_desde'),
                    date '9999-12-31') as desde
  ),
  corte as (select lk, chef from public.gv_espejo_corte()),
  ped as (
    select lower(coalesce(p->>'empresa','lk')) as empresa,
           (p->>'order_id')::bigint            as order_id,
           btrim(p->>'cod')                    as cod,
           (p->>'fecha_recep')::date           as fecha,
           coalesce((p->>'enviado_a_compras')::boolean, false) as enviado
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
  select d.empresa, d.order_id, 'enviado_a_isis'::text
    from ped d where d.enviado
  union
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

grant execute on function public.gv_pedidos_web_excluidos(jsonb) to anon, authenticated, service_role;
