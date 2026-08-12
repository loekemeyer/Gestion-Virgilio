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

-- ============================================================
-- BACKUP 2026-08-12 (parte 2) — fantasmas "Caja Nº N" (codigo 00XX, delta 0, misma clase que 0027)
-- ============================================================
-- Movimientos_Stock (carga inicial delta 0):
INSERT INTO "Movimientos_Stock" (id, ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, unidad, client_id) VALUES
 (15336, '2026-07-27 15:38:26.859134-03', '0037', 'Caja Nº 2',  'insumos', 0, 'inicial', 'carga inicial', '0', 'Paquetes', NULL),
 (15338, '2026-07-27 15:38:26.859134-03', '0087', 'Caja Nº 10', 'insumos', 0, 'inicial', 'carga inicial', '0', 'Paquetes', NULL),
 (15340, '2026-07-27 15:38:26.859134-03', '0107', 'Caja Nº 13', 'insumos', 0, 'inicial', 'carga inicial', '0', 'Paquetes', NULL),
 (15342, '2026-07-27 15:38:26.859134-03', '0137', 'Caja Nº 27', 'insumos', 0, 'inicial', 'carga inicial', '0', 'Paquetes', NULL),
 (15343, '2026-07-27 15:38:26.859134-03', '0157', 'Caja Nº 29', 'insumos', 0, 'inicial', 'carga inicial', '0', 'Paquetes', NULL);
-- Insumos (catalogo):
INSERT INTO "Insumos" (id, cod, nombre, creado_por, creado, sector, categoria, ubicacion, orden, isis) VALUES
 (42, '0037', 'Caja Nº 2',  'sistema·7917', '2026-08-04T09:39:55.176199-03:00', NULL, 'cajas', NULL, NULL, NULL),
 (44, '0087', 'Caja Nº 10', 'sistema·7917', '2026-08-04T09:39:55.176199-03:00', NULL, 'cajas', NULL, NULL, NULL),
 (45, '0107', 'Caja Nº 13', 'sistema·7917', '2026-08-04T09:39:55.176199-03:00', NULL, 'cajas', NULL, NULL, NULL),
 (47, '0137', 'Caja Nº 27', 'sistema·7917', '2026-08-04T09:39:55.176199-03:00', NULL, 'cajas', NULL, NULL, NULL),
 (48, '0157', 'Caja Nº 29', 'sistema·7917', '2026-08-04T09:39:55.176199-03:00', NULL, 'cajas', NULL, NULL, NULL);
