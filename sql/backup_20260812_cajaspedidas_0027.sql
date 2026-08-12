-- ============================================================
-- BACKUP 2026-08-12 — antes de:
--   1) recrear v_cajas_pedidas (fix doble-resta facturado/entregado)
--   2) eliminar el codigo fantasma 0027 ("Caja Nº 1") de Movimientos_Stock e Insumos
-- Restore: ejecutar este archivo entero.
-- ============================================================

-- ---- (1) Vista v_cajas_pedidas ANTERIOR (buggy: restaba facturadas + entregadas por separado) ----
create or replace view public.v_cajas_pedidas as
 WITH base AS (
         SELECT "PPP_Base_Pedidos".articulo,
            sum("PPP_Base_Pedidos".cajas) AS cajas_base
           FROM "PPP_Base_Pedidos"
          GROUP BY "PPP_Base_Pedidos".articulo
        ), facturadas AS (
         SELECT "PPP_Base_Pedidos".articulo,
            sum("PPP_Base_Pedidos".cajas) AS cajas_fac
           FROM "PPP_Base_Pedidos"
          WHERE ("PPP_Base_Pedidos".pedido IN ( SELECT DISTINCT "Facturacion_NP".np FROM "Facturacion_NP"))
          GROUP BY "PPP_Base_Pedidos".articulo
        ), entregadas AS (
         SELECT "PPP_Base_Pedidos".articulo,
            sum("PPP_Base_Pedidos".cajas) AS cajas_ent
           FROM "PPP_Base_Pedidos"
          WHERE ("PPP_Base_Pedidos".pedido IN ( SELECT DISTINCT "PPP_Entregados_Meta".np FROM "PPP_Entregados_Meta"))
          GROUP BY "PPP_Base_Pedidos".articulo
        ), canceladas AS (
         SELECT "PPP_Base_Pedidos".articulo,
            sum("PPP_Base_Pedidos".cajas) AS cajas_can
           FROM "PPP_Base_Pedidos"
          WHERE ("PPP_Base_Pedidos".pedido IN ( SELECT DISTINCT "NP_Canceladas".np FROM "NP_Canceladas"))
          GROUP BY "PPP_Base_Pedidos".articulo
        )
 SELECT COALESCE(base.articulo, facturadas.articulo, entregadas.articulo, canceladas.articulo) AS articulo,
    COALESCE(base.cajas_base, 0::numeric) - COALESCE(facturadas.cajas_fac, 0::numeric) - COALESCE(entregadas.cajas_ent, 0::numeric) - COALESCE(canceladas.cajas_can, 0::numeric) AS cajas_pedidas
   FROM base
     FULL JOIN facturadas ON base.articulo = facturadas.articulo
     FULL JOIN entregadas ON base.articulo = entregadas.articulo
     FULL JOIN canceladas ON base.articulo = canceladas.articulo
  WHERE (COALESCE(base.cajas_base, 0::numeric) - COALESCE(facturadas.cajas_fac, 0::numeric) - COALESCE(entregadas.cajas_ent, 0::numeric) - COALESCE(canceladas.cajas_can, 0::numeric)) > 0::numeric;

-- ---- (2) Filas eliminadas de Movimientos_Stock (codigo 0027, netean 0) ----
INSERT INTO "Movimientos_Stock" (id, ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, unidad, client_id) VALUES
 (12836, '2026-07-23 16:25:10.44993-03', '0027', 'NUMERO 1', 'insumos', 80,  'recepcion_insumo', NULL,           '104', 'Paquetes', NULL),
 (15302, '2026-07-27 15:29:59.327848-03', '0027', 'NUMERO 1', 'insumos', -80, 'ajuste',           'ajuste manual', '0',  'Paquetes', NULL);

-- ---- (3) Fila eliminada de Insumos (catalogo) ----
INSERT INTO "Insumos" (id, cod, nombre, creado_por, creado, sector, categoria, ubicacion, orden, isis) VALUES
 (23, '0027', 'Caja Nº 1', '104', '2026-07-23T16:24:39.043781-03:00', 'Cajas', 'cajas', NULL, NULL, NULL);
