-- v23.15 (Luis, 2026-09-28): "fijate si puede volver a pasar" (LK 1506 pickeada que salió de la programación).
-- Barrido de las funciones que sacan una NP de la programación (tanda = null / desprogramada / delete):
--   gv_ppp_web_desprogramar, gv_ppp_isis_desprogramar  -> freno v23.10 (EP/TP/PKC/AP/TAP)
--   gv_ppp_np_desarmar, gv_ppp_pedido_a_programar       -> desarme: devuelve el stock antes (legítimo)
--   gv_pedido_anular, gv_ppp_np_cancelar (web)           -> ya frenaban con gv_ppp_tanda_tocada
--   gv_ppp_web_diferido_tarde, ppp_web_resync            -> ya saltean tanda empezada
--   gv_ppp_np_cancelar rama ISIS                          -> NO frenaba: se agrega (abajo)
-- Aplicado sobre la definición viva con marcador 'v23.11-freno' (idempotente) + fila en GV_Reglas_Centinela.
--
-- Centinela: select * from public.gv_pedido_pickeado_desprogramado;  -- vacía = todo bien
-- (NP fuera de la programación cuya tanda ya se pickeaba CUANDO se la sacó; LK 1475 no entra: E92A se
--  pickeó 33 min después de sacarla).
create or replace view public.gv_pedido_pickeado_desprogramado with (security_invoker = true) as
with ev as (select upper(btrim(split_part(texto,'|',1))) t, min(ts_cliente) desde
              from public."Registros_Produccion_Virgilio"
             where opcion in ('EP','TP','PKC','AP','TAP') and not public.es_legajo_test(legajo) group by 1)
select 'web'::text origen, public.gv_ppp_web_np_label(r.empresa,r.np,r.np_idx) np, r.tanda_previa, r.fecha_previa,
       r.creado_at sacado_at, r.por, ev.desde picking_desde
  from public."GV_PPP_Web_Retenido" r
  join ev on ev.t = upper(btrim(r.tanda_previa)) and ev.desde < r.creado_at
  join public."PPP_Web_Programacion" w on w.empresa=r.empresa and w.order_id=r.order_id and w.np_idx=r.np_idx
 where nullif(btrim(w.tanda),'') is null
union all
select 'isis', o.np, o.tanda_previa, null::date, null::timestamptz, null, ev.desde
  from public."GV_PPP_Prog_Override" o
  join ev on ev.t = upper(btrim(o.tanda_previa))
 where o.desprogramada
   and not exists (select 1 from public."Registros_Produccion_Virgilio" x where x.opcion in ('CCN','CRN') and split_part(x.texto,'|',1)=o.np);
revoke all on public.gv_pedido_pickeado_desprogramado from anon;
