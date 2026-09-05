-- =============================================================================
-- gv_pedido_web_estado_pagina.sql — EL ESTADO DE CADA PEDIDO WEB, PARA LA PÁGINA (idea 8743)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · vista NUEVA gv_, sólo lectura · 2026-09-05
-- =============================================================================
-- Dueño (2026-09-04): "cuando un pedido queda facturado debería mostrarlo en la página
-- y decir que ya no se puede modificar".
--
-- Un estado por PEDIDO (empresa, order_id), agregando sus bloques: el pedido está en el
-- estado del bloque MENOS avanzado (hasta que todos estén facturados no está facturado).
--   sin_programar → programado → en_picking → pickeado → en_armado → armado → facturado
--   → entregado (control de remito, CRN)
--
-- Sale de gv_ppp_web_estado (PPP_Web_Programacion + eventos EP/TP/AP/TAP + Facturacion_NP
-- por etiqueta) más los CRN. Sólo NP programadas en Gestión: un pedido que todavía está
-- en "A Programar" no aparece (la página lo muestra como "Recibido").
--
-- QUIÉN LA LEE: la página LK, por FDW. En el proyecto LK (kwkclwhmoygunqmlegrg):
--   import foreign schema public limit to (gv_pedido_web_estado_pagina)
--     from server virgilio_db into virgilio;
--   → RPC gv_estado_mis_pedidos(p_ids) (sólo los pedidos del usuario logueado) y
--     candado en edit_order_fast (facturado/entregado → no editable).
-- Para eso el rol lk_ppp_reader (el del FDW) recibió SELECT sobre PPP_Web_Programacion
-- (policy ppp_web_prog_lk_reader_sel), gv_ppp_web_estado y esta vista, y EXECUTE sobre
-- gv_ppp_web_np_label. Registros_Produccion_Virgilio y Facturacion_NP ya los leía.
--
-- NO TOCA PRODUCCIÓN. Sin escritura, sin trigger.
-- ROLLBACK: drop view public.gv_pedido_web_estado_pagina; drop policy
--   ppp_web_prog_lk_reader_sel on "PPP_Web_Programacion"; revoke select ... from lk_ppp_reader.
-- =============================================================================

grant select on public."PPP_Web_Programacion" to lk_ppp_reader;
drop policy if exists ppp_web_prog_lk_reader_sel on public."PPP_Web_Programacion";
create policy ppp_web_prog_lk_reader_sel on public."PPP_Web_Programacion" for select to lk_ppp_reader using (true);
grant execute on function public.gv_ppp_web_np_label(text, integer, integer) to lk_ppp_reader;
grant select on public.gv_ppp_web_estado to lk_ppp_reader;

create or replace view public.gv_pedido_web_estado_pagina
with (security_invoker = true) as
with crn as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np_label,
         min(r.ts_cliente) as entregado_at
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'CRN'
  group by 1
),
b as (
  select e.empresa, e.order_id, e.np_idx, e.np_label, e.tanda, e.fecha_entrega, e.estado, e.estado_desde,
         c.entregado_at,
         case when c.entregado_at is not null then 8
              when e.estado = 'facturado' then 7
              when e.estado = 'armado' then 6
              when e.estado = 'en_armado' then 5
              when e.estado = 'pickeado' then 4
              when e.estado = 'en_picking' then 3
              when e.estado = 'programado' then 2
              else 1 end as rango
  from public.gv_ppp_web_estado e
  left join crn c on c.np_label = e.np_label
)
select empresa, order_id,
       count(*)::int as bloques,
       (array['sin_programar','programado','en_picking','pickeado','en_armado','armado','facturado','entregado'])[min(rango)] as estado,
       min(rango) as rango,
       min(fecha_entrega) as fecha_entrega,
       min(tanda) as tanda,
       min(estado_desde) as estado_desde,
       max(entregado_at) filter (where min_rango_all = 8) as entregado_at,
       bool_and(rango >= 7) as facturado,
       bool_and(rango >= 8) as entregado
from (select b.*, min(rango) over (partition by empresa, order_id) as min_rango_all from b) x
group by empresa, order_id;

revoke all on public.gv_pedido_web_estado_pagina from anon, authenticated;
grant select on public.gv_pedido_web_estado_pagina to anon, authenticated, lk_ppp_reader;
