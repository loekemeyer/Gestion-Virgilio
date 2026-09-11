-- v15.42 (2026-09-11) — las NP del formato nuevo ("LK 0003", "CH 0012") salían sin
-- Cod Cliente / Razón Social en Recepción Remitos (RR) y, mientras no estuvieran
-- facturadas, en la Cola de Impresión.
--
-- Causa: vista_control_remitos y vista_cola_impresion buscan el cliente sólo en
-- PPP_Programacion_Diaria / PPP_Entregados_Meta / Facturacion_NP, que son de ISIS.
-- Las NP web viven en PPP_Web_Programacion y se identifican por la etiqueta que
-- arma gv_ppp_web_np_label(empresa, np, np_idx).
--
-- Se AGREGAN dos vistas gv_* encima de las compartidas (no se tocan las viejas, que
-- quedan igual para Producción). Rollback: apuntar el front a las vistas viejas y
--   drop view public.gv_vista_control_remitos;
--   drop view public.gv_vista_cola_impresion;

create or replace view public.gv_vista_control_remitos
with (security_invoker = true) as
select
  v.np, v.tanda, v.first_load, v.last_ccn, v.lios, v.controlado, v.sin_salida,
  coalesce(nullif(btrim(v.cod_cliente), ''), w.cod_cliente, ev.cod_cliente, '') as cod_cliente,
  coalesce(nullif(btrim(v.rs), ''), w.razon_social, fn.razon_social, '')        as rs,
  v.vencido, v.clase, v.cajas
from public.vista_control_remitos v
-- (1) NP web: PPP_Web_Programacion, por la etiqueta ("LK 0003")
left join lateral (
  select btrim(coalesce(p.cod_cliente, '')) as cod_cliente,
         coalesce(p.razon_social, '')       as razon_social
  from public."PPP_Web_Programacion" p
  where public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) = btrim(v.np)
  order by p.actualizado_at desc nulls last, p.creado_at desc nulls last
  limit 1
) w on true
-- (2) v15.44 — NP de ISIS que ya no estan en PPP_Programacion_Diaria (ej. 98665, D50E,
--     facturada el 02/09): la razon social esta en Facturacion_NP...
left join lateral (
  select btrim(f.razon_social) as razon_social
  from public."Facturacion_NP" f
  where regexp_replace(btrim(f.np), '\.0+$', '') = btrim(v.np)
    and coalesce(btrim(f.razon_social), '') <> ''
  order by f.facturado_at desc nulls last
  limit 1
) fn on true
--     ...y el cod de cliente en Entregas_Virgilio.
left join lateral (
  select btrim(e.cod_cliente) as cod_cliente
  from public."Entregas_Virgilio" e
  where regexp_replace(btrim(e.np), '\.0+$', '') = btrim(v.np)
    and coalesce(btrim(e.cod_cliente), '') <> ''
  limit 1
) ev on true;

grant select on public.gv_vista_control_remitos to anon, authenticated, service_role;

create or replace view public.gv_vista_cola_impresion
with (security_invoker = true) as
select
  v.np, v.tanda, v.armado_ts,
  coalesce(nullif(btrim(v.razon_social), ''), w.razon_social, '') as razon_social,
  v.vencido, v.resumen, v.armador_leg, v.arts_fallback, v.faltantes_fallback
from public.vista_cola_impresion v
left join lateral (
  select coalesce(p.razon_social, '') as razon_social
  from public."PPP_Web_Programacion" p
  where public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) = btrim(v.np)
  order by p.actualizado_at desc nulls last, p.creado_at desc nulls last
  limit 1
) w on true;

grant select on public.gv_vista_cola_impresion to anon, authenticated, service_role;

-- prueba (antes: cod_cliente y rs vacíos en LK 0001 / LK 0003)
-- select np, tanda, cod_cliente, rs from public.gv_vista_control_remitos order by np;
