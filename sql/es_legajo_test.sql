-- ✅ APLICADO 2026-08-28 (migración `es_legajo_test_fn`) — FASE A únicamente.
-- FASE B (vistas): pendiente — aplicar de a una (vista_tanda_status → vista_faltante_demanda
--   → vista_faltante_real → vista_correcciones_pedido_rich → vista_productividad_semanal
--   → vista_productividad_diaria → vista_faltantes_sin_completar).
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
