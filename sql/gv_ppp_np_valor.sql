-- =============================================================================
-- gv_ppp_np_valor.sql — VALOR A LISTA DE CADA NP (2026-09-05, para la Programación nueva)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · vista NUEVA gv_, sólo lectura
-- =============================================================================
-- Para qué: el resumen por día / por camión de la solapa Programación (mockup v2) muestra
-- "$" además de pedidos y m³. Decisión del dueño: se calcula en el backend.
--
-- Cómo: Σ cajas × uxb × precio_unit por NP, SIN descuentos (es una estimación a lista).
--   · ISIS: líneas de gv_ppp_base_pedidos (canilla del espejo) × precios_venta (LK) o
--     precios_venta_chef (Chef). La empresa sale del prefijo de la NP: 4xxxx = Chef, resto LK.
--   · Web: líneas de PPP_Web_Base (la foto que pickea el operario; np_label "LK 1350") ×
--     precios por empresa.
--   lineas_sin_precio dice cuántas líneas no se pudieron valuar (precio faltante o 0).
--
-- Medido al crearla (05/09): 822 NP valuadas (181 de las 182 programadas), 46 con alguna
-- línea sin precio; total programado ≈ $334 M.
--
-- NO TOCA PRODUCCIÓN: sólo lee. ROLLBACK: drop view public.gv_ppp_np_valor;
-- =============================================================================

create or replace view public.gv_ppp_np_valor
with (security_invoker = true) as
with lin as (
  select regexp_replace(btrim(b.pedido), '\.0+$', '') as np,
         case when btrim(b.pedido) ~ '^4' then 'chef' else 'lk' end as empresa,
         b.articulo, coalesce(b.cajas, 0) as cajas
  from public.gv_ppp_base_pedidos b
  where b.articulo is not null and coalesce(b.cajas, 0) > 0
  union all
  select w.np_label, lower(w.empresa), w.articulo, coalesce(w.cajas, 0)
  from public."PPP_Web_Base" w
  where w.articulo is not null and coalesce(w.cajas, 0) > 0
),
pr as (
  select l.np, l.empresa, l.articulo, l.cajas,
         case when l.empresa = 'chef' then pc.uxb else pv.uxb end as uxb,
         case when l.empresa = 'chef' then pc.precio_unit else pv.precio_unit end as precio_unit
  from lin l
  left join public.precios_venta pv on l.empresa <> 'chef' and public.canon_cod(pv.cod) = public.canon_cod(l.articulo)
  left join public.precios_venta_chef pc on l.empresa = 'chef' and public.canon_cod(pc.cod) = public.canon_cod(l.articulo)
)
select np, empresa,
       round(sum(cajas * coalesce(uxb, 1) * coalesce(precio_unit, 0)), 0) as valor_lista,
       count(*) as lineas,
       count(*) filter (where precio_unit is null or precio_unit <= 0) as lineas_sin_precio,
       sum(cajas) as cajas
from pr
group by np, empresa;

revoke all on public.gv_ppp_np_valor from anon, authenticated;
grant select on public.gv_ppp_np_valor to anon, authenticated;
