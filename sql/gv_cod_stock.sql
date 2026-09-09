-- =============================================================================
-- gv_cod_stock.sql — normalización ÚNICA del código para la proyección (ventas + compras)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · v14.54 (2026-09-09)
-- =============================================================================
-- Para qué: que ventas y compras (OCs) usen EXACTAMENTE la misma canonicalización de código.
-- La "L" (438EL) sólo dice "factura Chef, stock LK" → para stock/proyección SIEMPRE es el
-- código real (438E). Antes vista_venta_mensual y vista_stock_vs_pedidos.dem NO pelaban la L
-- → 439EL quedaba como SKU fantasma (demanda bajo 439EL, stock/producción bajo 439E) y
-- subcontaba la demanda real de 439E. Ahora las 3 vistas de proyección usan gv_cod_stock,
-- la MISMA normalización que ya hacía vista_generador_oc.
--
-- gv_cod_stock: upper/trim → saca "·celda" → saca sufijo empresa (LK/CH/LOKE) → saca ceros a
-- la izquierda → pela la L final ([0-9E]L$). IMMUTABLE.
--
-- Medido (09/09): 0 códigos con L en venta/recepción/stock_vs_pedidos/abastecimiento/generador_oc;
-- 439E consolidó lo que iba a 439EL. Vistas COMPARTIDAS (security_invoker=true preservado).
-- Backup de los defs viejos: sql/backups/proyeccion_views_20260909_pre_v1454.sql.
-- Anotado en docs/ROLLBACK-PRODUCCION.md. Rollback: correr ese backup + drop function gv_cod_stock.
-- =============================================================================
create or replace function public.gv_cod_stock(p text)
returns text language sql immutable
set search_path to 'public','pg_temp' as $fn$
  select regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(upper(btrim(coalesce(p,''))), '·.*$', ''),
             '\s+(LK|CH|LOKE)$', ''),
           '^0+(?=.)', ''),
         '([0-9E])L$', '\1');
$fn$;

-- vista_venta_mensual, vista_recepcion_mensual, vista_stock_vs_pedidos:
-- idénticas a antes salvo que el código se normaliza con public.gv_cod_stock(...).
-- (Cuerpo completo aplicado en la migración gv_cod_stock_normaliza_proyeccion_v1454;
--  el def viejo está en sql/backups/proyeccion_views_20260909_pre_v1454.sql.)
