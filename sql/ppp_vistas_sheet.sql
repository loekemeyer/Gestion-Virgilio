-- ppp_vistas_sheet.sql — vistas que alimentan el Sheet "PPP" (2 hojas), derivadas de las
-- tablas transaccionales que producen los eventos de la página Virgilio.
--
-- "Entregado" = NP facturada y cerrada (Facturacion_NP.cierre_id no nulo). Cuando una NP se
-- cierra, sale sola de "programación pendiente" y aparece en "pedidos entregados": el ajuste
-- es una condición en la vista, no un movimiento (event-sourced, como el stock).
--
-- security_invoker = true → respetan la RLS del que consulta; anon ya puede leer las tablas
-- base (PPP_Programacion_Diaria, Facturacion_NP, Facturacion_Cierres, Entregas_Virgilio).
-- Las lee el botón "⬇ Exportar Excel" de la app (index.html, pppExportExcel).
-- (El Apps Script ppp-a-excel.gs que también las leía se eliminó el 2026-07-30
--  por decisión del usuario, sin haberse deployado.)
-- (Aplicado como migración `vistas_ppp_sheet`; este archivo es la copia versionada.)

-- Hoja 1: Programación diaria — SOLO lo pendiente.
create or replace view public.vista_ppp_programacion_pendiente
with (security_invoker = true) as
select p.tanda, p.np, p.tipo, p.cod as cod_cliente, p.razon_social, p.m3,
       p.zona, p.barrio, p.direccion, p.op, p.fecha_recep, p.fecha_entrega,
       p.fecha_fc, p.observaciones
from public."PPP_Programacion_Diaria" p
where not exists (
  select 1 from public."Facturacion_NP" f
  where f.np = p.np and f.cierre_id is not null
);

-- Hoja 2: Pedidos entregados — NP facturadas y cerradas, con m³ y cajas reales.
--
-- ⚠ Este bloque estuvo DESACTUALIZADO respecto de la base hasta el 2026-09-12 (v16.33): le
--   faltaban `fecha_carga`, `fecha_ppp` y `fecha_salida_real`, que el front sí pide. Que el
--   archivo mienta no es cosmético — se tardó en encontrar un 500 justamente porque el `::date`
--   que lo causaba no estaba acá. Si se toca la vista en la base, se actualiza este bloque.
--
-- `nullif(btrim(...), '')` en `fecha_entrega`: la columna es TEXT y 16 filas tienen cadena
-- vacía. Un `::date` pelado tiraba la vista entera con `invalid input syntax for type date: ""`
-- y el panel Entregados quedaba vacío y callado. Ver sql/gv_fix_entregados_y_deadlock_v1633.sql.
create or replace view public.vista_ppp_pedidos_entregados
with (security_invoker = true) as
select f.np, f.tanda, f.cod_cliente, f.razon_social, f.m3,
       f.fecha_salida, c.fecha_cierre, c.fecha_reparto, f.facturado_at,
       coalesce(e.cajas_pedidas, 0)    as cajas_pedidas,
       coalesce(e.cajas_entregadas, 0) as cajas_entregadas,
       coalesce(e.cajas_falto, 0)      as cajas_falto,
       cc.fecha_carga,
       pp.fecha_ppp,
       coalesce(cc.fecha_carga, pp.fecha_ppp, f.fecha_salida, f.facturado_at::date) as fecha_salida_real
from public."Facturacion_NP" f
left join public."Facturacion_Cierres" c on c.id = f.cierre_id
left join lateral (
  select sum(cajas_pedidas) as cajas_pedidas,
         sum(cajas_entregadas) as cajas_entregadas,
         sum(cajas_falto) as cajas_falto
  from public."Entregas_Virgilio" ev where ev.np = f.np
) e on true
left join lateral (
  select max((r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as fecha_carga
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'CCN'
    and btrim(split_part(r.texto, '|', 1)) = regexp_replace(btrim(f.np), '\.0$', '')
) cc on true
left join lateral (
  select max(nullif(btrim(p.fecha_entrega), '')::date) as fecha_ppp
  from public."PPP_Programacion_Diaria" p
  where regexp_replace(btrim(p.np), '\.0$', '') = regexp_replace(btrim(f.np), '\.0$', '')
) pp on true
where f.cierre_id is not null;

grant select on public.vista_ppp_programacion_pendiente to anon, authenticated;
grant select on public.vista_ppp_pedidos_entregados     to anon, authenticated;

-- Índice de apoyo para el lateral (ev.np = f.np) — recomendación del auditor.
-- (Aplicado como migración `entregas_virgilio_np_idx`.)
create index if not exists entregas_virgilio_np_idx on public."Entregas_Virgilio" (np);
