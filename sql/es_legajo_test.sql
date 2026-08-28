-- ✅ APLICADO 2026-08-28 (migración `es_legajo_test_fn`) — FASE A.
-- ✅ FASE B (vistas): APLICADA 2026-08-28 — 7 vistas migradas a `NOT es_legajo_test(...)`.
--   Ver es_legajo_test_fase_b.sql para el detalle.
-- ✅ FASE B-front (index.html): APLICADA 2026-08-28 — 4 checks inline reemplazados por
--   esLegajoPrueba() (getActivityStatus, prodCompute, stock display, fetchMonitorEvents).
--   generar_reporte_agentes_v2.sql: 3 exclusiones migradas a es_legajo_test().
-- FASE C (UPDATE en Empleados.tipo): NO aplicar sin backup + permiso explícito del dueño.
--
-- Centraliza la detección de legajos de prueba/basura (0 y 1) que hoy está ad-hoc
-- en decenas de `legajo==='0'||legajo==='1'` en el front y en vistas SQL.
--
-- ⚠ NO USAR EN STOCK — legajo '0' es sentinel admin en Movimientos_Stock.
-- ⚠ NO AGREGAR STRICT — es_legajo_test(NULL) debe dar FALSE, no NULL.
-- ⚠ NO AGREGAR SET search_path — mata el inlining del planner.

create or replace function public.es_legajo_test(p_legajo text)
returns boolean
language sql
immutable
parallel safe
return coalesce(btrim(p_legajo), '') = any(array['0','1']);

comment on function public.es_legajo_test(text) is
$c$Devuelve TRUE si el legajo es de prueba/basura ('0' o '1').
⚠ NO USAR EN STOCK — legajo '0' es sentinel admin en Movimientos_Stock.
⚠ NO AGREGAR STRICT — es_legajo_test(NULL) debe dar FALSE, no NULL.
⚠ NO AGREGAR SET search_path — mata el inlining (proconfig != NULL).$c$;

grant execute on function public.es_legajo_test(text) to anon, authenticated, service_role;
