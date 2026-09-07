-- ⚠ v13.72: la función viva es la v2 (migración gv_excluidos_doble_lk_y_alerta_sin_eventos_v1372): lee `cod_alt` y
-- agrega el motivo 'en_produccion_lk' (pedido Chef que ISIS LK ya tiene, mismo CUIT y día). Ver §3.ax.
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
--                       como PRIMER motivo de exclusión (v12.94).
--   2026-09-05 noche  · dueño: "el lunes van a empezar a usar GV, no más PV". Con nadie en
--                       Producción, los 1340..1349 del mail del sábado quedaban HUÉRFANOS
--                       (excluidos por `enviado_a_isis` y sin nadie que los programe).
--                       Decisión: el mail del sábado se ignora y GV los programa desde la
--                       página. Interruptor `PPP_Web_Config.excluir_enviados_a_isis`
--                       (1 = regla de convivencia, 0 = no excluir) → hoy 0 (v13.15).
--
-- LA REGLA (v13.15): PENDIENTE = pedido de la página con fecha >= gestion_desde que
--                    Producción/ISIS no conozca. (Con `excluir_enviados_a_isis = 1`, además
--                    que no haya salido por el mail.)
--
-- Motivos que devuelve (un pedido puede traer más de uno):
--   enviado_a_isis     → enviado_a_compras = true, SÓLO con excluir_enviados_a_isis = 1.
--   anterior_al_cambio → fecha_recep < gestion_desde (piso, 2026-09-03).
--   en_produccion      → hay NP de ISIS de ese cliente con esa fecha de pedido en
--                        programación / facturación / entregados / entregas, y esa NP pasa
--                        la canilla del espejo (gv_espejo_corte, v12.90).
--
-- DÓNDE SE APLICA: la Edge Function gv-ppp-web-tandas-diarias (soloPendientes, v13/v14) y
-- "A Programar" (aprTraerPedidos) le pasan (empresa, order_id, cod, fecha_recep,
-- enviado_a_compras) por pedido, sobre los feeds CRUDOS de LK.
--
-- FALLA CERRADO: sin config gestion_desde se excluye todo.
--
-- MEDIDO al aplicar la v13.15 (sábado 05/09 noche, simulación sin escribir): LK pendientes
-- 1340..1351 → 0 excluidos; el lunes 00:01 arma 6 tandas de zona 1/2/3 (3,718 m³) y deja a
-- mano 1340 (Retira), 1341 (Martínez, zona 6) y 1349 (Padua, zona 5).
--
-- ROLLBACK: update public."PPP_Web_Config" set valor = 1 where clave = 'excluir_enviados_a_isis';
--           (la versión v12.94 sin interruptor está en git antes del commit de v13.15)
-- =============================================================================

insert into public."PPP_Web_Config" (clave, valor_texto)
select 'gestion_desde', '2026-09-03'
where not exists (select 1 from public."PPP_Web_Config" where clave = 'gestion_desde');

insert into public."PPP_Web_Config" (clave, valor, descripcion)
values ('excluir_enviados_a_isis', 0,
        'v13.15: 1 = un pedido que salió a ISIS por el mail (enviado_a_compras) no se programa en Gestión (regla de convivencia con Producción); 0 = se programa igual (desde el 2026-09-07 todos usan Gestión). Rollback: valor = 1.')
on conflict (clave) do nothing;

create or replace function public.gv_pedidos_web_excluidos(p_pedidos jsonb)
returns table(empresa text, order_id bigint, motivo text)
language sql
stable
set search_path to 'public'
as $function$
  with cfg as (
    select coalesce((select nullif(valor_texto,'')::date from public."PPP_Web_Config" where clave = 'gestion_desde'),
                    date '9999-12-31') as desde,
           coalesce((select valor from public."PPP_Web_Config" where clave = 'excluir_enviados_a_isis'), 1) <> 0 as excluir_enviados
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
    from ped d cross join cfg where d.enviado and cfg.excluir_enviados
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
$function$;

grant execute on function public.gv_pedidos_web_excluidos(jsonb) to anon, authenticated;
