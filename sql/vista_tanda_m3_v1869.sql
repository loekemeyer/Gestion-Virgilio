-- =============================================================================
-- vista_tanda_m3_v1869.sql — LO VIVO MANDA SOBRE EL HISTÓRICO (código de tanda reusado)
-- 2026-09-15 (v18.69) · pedido de Luis · problema 316 · tarea Planify 3481
-- =============================================================================
-- D47B se entregó el 27/08 (1,962 m³ en GV_PPP_Entregados_Historico, la hoja congelada el 02/09) y
-- el override v16.03 reprogramó 98480/98481 REUSANDO ese código para el 16/09 (0,238 m³). La vista
-- hacía COALESCE(histórico, ISIS, web) y entregado = histórico is not null, así que Ocupación y la
-- productividad veían 1,962 m³ y "entregada" para una tanda de mañana. Única tanda afectada hoy
-- (medido: un solo código con histórico Y programación viva).
-- Cambio: m³ = ISIS vivo → web viva → histórico; entregado sólo si no hay nada vivo con ese código.
-- Columnas iguales (tanda, m3, entregado). security_invoker en el WITH + ALTER.
-- ROLLBACK: sql/backups/vista_tanda_m3_pre_v1869_20260915.sql
-- =============================================================================
create or replace view public.vista_tanda_m3
with (security_invoker = true) as
with ent as (
  select upper(btrim(m.tanda)) as tanda, sum(m.m3) as m3
  from "GV_PPP_Entregados_Historico" m
  where m.m3 > 0 and btrim(coalesce(m.tanda,'')) <> '' group by 1),
prog as (
  select upper(btrim(p_1.tanda)) as tanda, sum(p_1.m3) as m3
  from gv_ppp_programacion_diaria p_1
  where p_1.m3 > 0 and btrim(coalesce(p_1.tanda,'')) <> '' group by 1),
web as (
  select upper(btrim(w.tanda)) as tanda, sum(w.m3) as m3
  from "PPP_Web_Programacion" w
  where w.m3 > 0 and btrim(coalesce(w.tanda,'')) <> '' group by 1),
u as (select tanda from ent union select tanda from prog union select tanda from web)
-- v18.69: lo VIVO manda. Un código reusado (D47B: entregada el 27/08, reprogramada para el 16/09 por
-- override) tomaba el m³ del histórico y salía "entregado". Ahora: m³ = ISIS vivo, si no web viva, si
-- no histórico; entregado sólo si no hay nada vivo con ese código.
select u.tanda,
       round(coalesce(p.m3, b.m3, e.m3), 3) as m3,
       (e.m3 is not null and p.m3 is null and b.m3 is null) as entregado
from u
left join ent e on e.tanda = u.tanda
left join prog p on p.tanda = u.tanda
left join web b on b.tanda = u.tanda
where coalesce(p.m3, b.m3, e.m3) > 0;
alter view public.vista_tanda_m3 set (security_invoker = true);
-- Prueba: select * from public.vista_tanda_m3 where tanda='D47B';  → 0.238, entregado=false
