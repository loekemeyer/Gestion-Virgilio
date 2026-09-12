-- v16.06 — UNA sola cascada de precios para toda la Facturación. APLICADO 2026-09-12.
--
-- QUÉ PASABA
--   La pantalla de Facturación valoriza con `vista_facturacion_neto_items` (vía las RPC
--   facturacion_neto_lote / facturacion_neto_detalle) y Conciliación con
--   `gv_vista_facturacion_neto_items`. Eran dos vistas distintas con dos cascadas de precio:
--   la gv_ NO miraba `GV_Precios_Cliente` (el precio pactado con el cliente) ni el precio de
--   la última factura, así que marcaba "sin precio" 391 líneas que la otra sí valoriza —
--   Cencosud 254, Aimetta (2460) 59, South Naz (2714) 41, Dorinka 22, Osa 3.
--   Resultado: un tablero decía que faltaban precios y el otro facturaba con ellos.
--   Problema 63 de github_repo_problemas.
--
-- QUÉ CAMBIA
--   `gv_vista_facturacion_neto_items` pasa a ser un PASAMANOS de la otra: mismas 15 columnas,
--   mismos tipos, mismo orden (verificado columna por columna antes de reemplazar).
--   `gv_vista_facturacion_neto` agrega sobre ella, así que hereda el cambio solo.
--
--   La definición vieja quedó guardada como vista: `gv_bkp_facneto_items_v1604`.

create or replace view public.gv_vista_facturacion_neto_items
with (security_invoker = true) as
  select np, cod_cliente, cod, cajas_ped, cajas_ent, cajas_falto, uxb, precio_lista, dto_vol,
         importe_ent, importe_ped, sin_precio, cod_canon, factor_web, es_super
    from public.vista_facturacion_neto_items;

------------------------------------------------------------------------------
-- MEDICIÓN (la consulta que lo prueba)
------------------------------------------------------------------------------
-- select count(*) nps, round(sum(neto)) neto_total, sum(items_sin_precio) items_sin_precio
--   from public.gv_vista_facturacion_neto;
--   ANTES:   903 NP · $1.245.479.863 · 391 items sin precio (46 NP afectadas)
--   DESPUÉS: 903 NP · $1.360.979.779 ·   0 items sin precio
--   La diferencia (+$115,5 M) es la plata de esas 391 líneas, que Conciliación contaba como
--   cero. La pantalla de Facturación ya las valorizaba: su total no cambió.
--
-- Conciliación sigue andando igual: gv_conciliacion_totales() → 59 ok, 7 diff, 1 sin_factura.
-- Osa (NP 98650) ahora se ve con su precio pactado en las dos vistas: 102E 1.530, 103 632,
-- 106E 1.956, 198E 802, todos con dto_vol 0,16 (antes la gv_ decía "sin precio" en tres y
-- $1.110 —la lista general de LK— en el 198E).

------------------------------------------------------------------------------
-- ROLLBACK
------------------------------------------------------------------------------
-- do $$ declare d text; begin
--   select pg_get_viewdef('public.gv_bkp_facneto_items_v1604'::regclass) into d;
--   execute 'create or replace view public.gv_vista_facturacion_neto_items with (security_invoker = true) as ' || d;
-- end $$;
