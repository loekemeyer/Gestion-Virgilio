-- =============================================================================
-- gv_valor_items_indices_v1868.sql — TRES ÍNDICES DE EXPRESIÓN: gv_ppp_web_valor_items 300× más rápida
-- 2026-09-15 (v18.68) · pedido de Luis · problema 314 · tarea Planify 3480
-- =============================================================================
-- SÍNTOMA. gv_cuarentena_limite (la Cuarentena de A Programar) tardaba 1,2–1,9 s de media y hasta
-- 7,7 s (pg_stat_statements, 821 llamadas/día), contra los 8 s de statement_timeout del rol:
-- 4 HTTP 500 el 15/09. gv_ppp_web_armar_pendientes, que también valoriza, 1,8 s de media.
--
-- LO QUE NO SIRVE (medido): `alter function … set statement_timeout = '30s'`. El timer del
-- statement se arma al empezar con el tope del ROL; cambiar la GUC adentro de la función no lo
-- re-arma. Prueba: rol con 2 s, función con SET 30 s y pg_sleep(4) → "canceling statement due to
-- statement timeout" a los 2 s. Así que no se tocó ningún timeout.
--
-- CAUSA. gv_ppp_web_valor_items, por CADA artículo, hacía un seq scan de GV_UxB (984 filas)
-- evaluando gv_cod_stock(cod) fila por fila, y los joins a precios_venta / precios_venta_chef
-- comparaban canon_cod(cod) sin índice. 26 ms por artículo; 340 ms para un pedido de 18 líneas.
-- Y gv_cuarentena_limite valoriza, además de los pendientes, TODAS las NP sin facturar de esos
-- clientes (CTE `base`): 40 NP → 8,3 s con todos los clientes con límite.
--
-- ARREGLO. Las tres funciones son IMMUTABLE y puras (regexp sobre el texto), así que se indexa la
-- expresión. Sin tocar ninguna función: el planner usa el índice solo.
--   antes: seq scan precios_venta + seq scan GV_UxB por artículo → 26,2 ms
--   después: index scan + bitmap index scan → 0,087 ms
-- cobranzas_precios_super es una VISTA (no se indexa); sólo entra para clientes de súper.
-- =============================================================================
create index if not exists gv_uxb_cod_stock_idx        on public."GV_UxB" (public.gv_cod_stock(cod)) where uxb > 0;
create index if not exists precios_venta_canon_idx      on public.precios_venta (public.canon_cod(cod));
create index if not exists precios_venta_chef_canon_idx on public.precios_venta_chef (public.canon_cod(cod));

-- Chequeo: tiene que salir "Bitmap Index Scan on gv_uxb_cod_stock_idx" e "Index Scan using precios_venta_canon_idx".
-- explain (analyze) select pv.precio_unit, (select max(g.uxb) from public."GV_UxB" g where public.gv_cod_stock(g.cod) = public.gv_cod_stock('505') and g.uxb > 0)
--   from public.precios_venta pv where public.canon_cod(pv.cod) = public.canon_cod('505');

-- ROLLBACK: drop index public.gv_uxb_cod_stock_idx, public.precios_venta_canon_idx, public.precios_venta_chef_canon_idx;
