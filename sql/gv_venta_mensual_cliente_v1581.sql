-- v15.81 — "¿quién me compró este mes?" en Stock y Compras (Abastecimiento).
--
-- Pedido del dueño (2026-09-11): "desde stock y compras, poder tocar en 1 mes y ver
-- quién me compró (solo los primeros 5 clientes de cada mes y un sexto con Resto)"
-- y, sobre la unidad: "3 cajas" → CAJAS, la misma de la tabla mes a mes.
--
-- Objeto NUEVO con prefijo gv_ (protocolo de base compartida: no se toca nada existente).
-- Es el hermano por CLIENTE de vista_venta_mensual, que agrupa (cod, mes) y pierde el
-- quién. El corte a 5 + "Resto" lo hace el front (abastClientesHtml): acá se devuelve el
-- detalle completo por cliente, que sirve igual para cualquier otro corte.
--
-- Razón social: Entregas_Virgilio sólo guarda cod_cliente, así que se resuelve en cascada
--   1) PPP_Entregados_Meta.rs   (la más reciente por cod)
--   2) PPP_Programacion_Diaria.razon_social
--   3) GV_Clientes_Direcciones.razon_social  (el padrón; sin este paso quedaban 8 clientes
--      sin nombre)
--   4) el cod pelado, para no mostrar nunca "(s/nombre)".
--
-- MEDICIÓN (no "no debería afectar"):
--   select (select count(*) from public.vista_venta_mensual) pares_viejo,
--          (select count(*) from (select distinct cod, mes from public.gv_venta_mensual_cliente) x) pares_nuevo,
--          (select count(*) from public.gv_venta_mensual_cliente) filas,
--          (select count(*) from public.gv_venta_mensual_cliente where razon_social ~ '^\d+$') sin_nombre,
--          (select count(*) from (
--             select v.cod from public.vista_venta_mensual v
--             join (select cod, mes, sum(cajas) cajas from public.gv_venta_mensual_cliente group by 1,2) c
--               on c.cod=v.cod and c.mes=v.mes where v.cajas <> c.cajas) d) difs;
--   → pares_viejo 845 · pares_nuevo 845 · filas 8.866 · sin_nombre 0 · difs 0.
--
-- ROLLBACK: drop view public.gv_venta_mensual_cliente;
--   (no lo lee nadie más que el detalle de Abastecimiento; Producción no la conoce.)

create or replace view public.gv_venta_mensual_cliente
with (security_invoker = true) as
with nombres as (
  select cod,
         rs,
         row_number() over (partition by cod order by updated_at desc nulls last) rn
    from public."PPP_Entregados_Meta"
   where coalesce(nullif(trim(rs), ''), '') <> ''
),
n as (select cod, rs from nombres where rn = 1)
select public.gv_cod_stock(e.cod_art)                                        as cod,
       to_char(date_trunc('month', e.fecha_salida::date), 'YYYY-MM')         as mes,
       e.cod_cliente                                                          as cod_cliente,
       coalesce(n.rs, p.razon_social, pad.razon_social, e.cod_cliente)        as razon_social,
       sum(coalesce(e.cajas_entregadas, 0))                                   as cajas,
       count(distinct e.np)                                                   as nps
  from public."Entregas_Virgilio" e
  left join n on n.cod = e.cod_cliente
  left join lateral (
        select d.razon_social
          from public."PPP_Programacion_Diaria" d
         where d.cod = e.cod_cliente
           and coalesce(nullif(trim(d.razon_social), ''), '') <> ''
         limit 1
  ) p on true
  left join lateral (
        select g.razon_social
          from public."GV_Clientes_Direcciones" g
         where g.cod = e.cod_cliente
           and coalesce(nullif(trim(g.razon_social), ''), '') <> ''
         order by g.actualizado_at desc nulls last, g.slot
         limit 1
  ) pad on true
 where e.fecha_salida ~ '^\d{4}-\d{2}-\d{2}'
   and coalesce(e.cajas_entregadas, 0) <> 0
 group by 1, 2, 3, 4;

comment on view public.gv_venta_mensual_cliente is
  'v15.81 — venta por ARTICULO + MES + CLIENTE en cajas, para el "quien me compro" del detalle de Abastecimiento. Hermano por cliente de vista_venta_mensual (mismo total, chequeado). Razon social: PPP_Entregados_Meta > PPP_Programacion_Diaria > GV_Clientes_Direcciones > el cod. security_invoker.';

grant select on public.gv_venta_mensual_cliente to anon, authenticated;
