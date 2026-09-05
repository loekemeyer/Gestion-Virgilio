-- =============================================================================
-- gv_pedidos_web_excluidos.sql — LA REGLA DE "PENDIENTE PARA GESTIÓN" (2026-09-04, noche)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · objetos NUEVOS, prefijo gv_, sólo lectura
-- =============================================================================
-- REGLA DEL DUEÑO: "de ahora en más Gestión no tiene que leer más [del espejo de ISIS],
-- salvo los pedidos que estén en la página LK que falten en la programación diaria /
-- A Programar". Precisada con números y elegida entre tres formas:
--
--   PENDIENTE = pedido de la página con fecha >= gestion_desde que Producción/ISIS
--               NO conozca.
--
-- Por qué "desde el día del cambio": "lo que Producción no tenga" a secas marcaba
-- 19 pedidos de LK, de los cuales 9 eran de hace tres semanas (clientes nuevos que
-- ISIS dio de alta con otro código, un cod "1" placeholder, fechas corridas un día
-- por la carga en ISIS). Con la fecha de corte quedan 10 (los 5 sin enviar + los 5
-- en limbo: enviados a ISIS pero que Producción todavía no tenía). Chef: 2.
--
-- Por qué NO "no enviado a compras" (la regla que estuvo unas horas en los feeds de
-- LK): dejaba afuera el limbo, y el dueño quiere que eso sea de Gestión.
--
-- DÓNDE SE APLICA: esta RPC devuelve los EXCLUIDOS con motivo, y la llaman
--   · la Edge Function gv-ppp-web-tandas-diarias (el job de las 00:01), y
--   · "A Programar" (aprTraerPedidos) en el front,
-- sobre lo que traen los feeds crudos de LK (gv_pedidos_web_np_lk / _chef, que
-- volvieron a NO filtrar nada). Una sola regla, en el backend de Virgilio.
--
-- "Producción lo conoce" = hay una NP de ISIS de ese cliente (cod) con esa fecha de
-- pedido en cualquiera de las cuatro tablas que Producción usa (programación,
-- facturación, entregados, entregas), tomando la fecha de la NP de PPP_Base_Pedidos.
-- Separado por empresa (9xxxx = LK, 4xxxx = Chef): el mismo cod es otro cliente en
-- cada una. Todo lectura sobre tablas que anon ya lee.
--
-- FALLA CERRADO: si falta la config gestion_desde, se excluye todo. Antes que
-- duplicar un pedido en el depósito, no tomar ninguno.
--
-- MEDIDO al crearla (30 días reales): LK 212 pedidos → 202 anteriores al cambio,
-- 193 en Producción, 10 pendientes · Chef 26 → 23 / 21 / 2.
--
-- ROLLBACK: drop function public.gv_pedidos_web_excluidos(jsonb);
--           delete from public."PPP_Web_Config" where clave = 'gestion_desde';
-- =============================================================================

insert into public."PPP_Web_Config" (clave, valor_texto)
select 'gestion_desde', '2026-09-03'
where not exists (select 1 from public."PPP_Web_Config" where clave = 'gestion_desde');

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
  --                        cualquiera de las cuatro tablas que Producción usa
  -- Si falta la config, se excluye TODO (falla cerrado): antes que duplicar, no tomar.
  with cfg as (
    select coalesce((select nullif(valor_texto,'')::date from public."PPP_Web_Config" where clave = 'gestion_desde'),
                    date '9999-12-31') as desde
  ),
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
    where x.np is not null and nullif(btrim(x.cod),'') is not null
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

grant execute on function public.gv_pedidos_web_excluidos(jsonb) to anon, authenticated, service_role;
